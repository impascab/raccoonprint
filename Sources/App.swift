import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Item: Identifiable { let id = UUID(); let name: String; let image: CGImage; var turns = 0 }
enum Theme: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"
    @MainActor func apply() { NSApp?.appearance = self == .system ? nil : NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
}
enum Tab: String, CaseIterable { case files = "Files", text = "Text" }

struct PreviewKey: Hashable {
    var tab: Tab, id: UUID?, turns: Int, brightness: Double, trim: Bool
    var text: String, size: Int, bold: Bool, align: TextAlign, textTurns: Int, strength: Int
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()
    private let d = UserDefaults.standard
    let log = Log.shared
    @Published var tab: Tab = .files
    @Published var items: [Item] = []
    @Published var selected: UUID?
    @Published var theme: Theme { didSet { d.set(theme.rawValue, forKey: "theme"); theme.apply() } }
    @Published var darkness: Int { didSet { d.set(darkness, forKey: "darkness") } }
    @Published var brightness: Double { didSet { d.set(brightness, forKey: "brightness") } }
    @Published var trim: Bool { didSet { d.set(trim, forKey: "trim") } }
    @Published var text = ""
    @Published var size = 1
    @Published var bold = false
    @Published var align: TextAlign = .left
    @Published var textTurns = 0
    @Published var copies = 1
    @Published var status = "Ready"
    @Published var busy = false
    @Published var printing = false
    @Published var progress: Double?
    @Published var preview: CGImage?
    @Published var previewError: String?
    var stop = false
    private var slept = false
    /// Lid closed or Sleep chosen: the link will probably drop. If it survives, the print is cancelled cleanly on wake.
    func willSleep() { if printing { slept = true; log.add("Mac going to sleep while printing", error: true); cancel() } else { releaseHeld() } }

    init() {
        theme = Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        darkness = (d.object(forKey: "darkness") as? Int).map { max(0, min(2, $0)) } ?? 1
        brightness = max(-1, min(1, d.double(forKey: "brightness")))
        trim = d.bool(forKey: "trim")
    }

    var index: Int? { items.firstIndex { $0.id == selected } }
    var key: PreviewKey { PreviewKey(tab: tab, id: selected, turns: index.map { items[$0].turns } ?? 0, brightness: brightness, trim: trim, text: tab == .text ? text : "", size: size, bold: bold, align: align, textTurns: textTurns, strength: darkness) }
    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canPrint: Bool { !busy && loading == 0 && (tab == .files ? !items.isEmpty : hasText) }

    func fail(_ s: String) { status = s; log.add(s, error: true) }

    static let maxItems = 50
    @Published var loading = 0
    private var added = 0

    func add(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { status = "Only files can be dropped here."; return }
        guard !busy else { status = "Busy: add files when printing is done."; return }
        tab = .files; loading += 1
        Task {
            defer { loading -= 1 }
            for u in files {
                let kind = u.pathExtension.lowercased()
                guard items.count < Model.maxItems else { fail("The list is full (\(Model.maxItems) files)."); break }
                added += 1; let n = added
                do {
                    let (img, pages) = try await Task.detached { (try Encoder.load(u), Encoder.pages(u)) }.value
                    let i = Item(name: u.lastPathComponent, image: img)
                    items.append(i); selected = i.id; log.add("Added file \(n) (\(kind))")
                    if pages > 1 { status = "Only page 1 of \(pages) was added from \(u.lastPathComponent)."; log.add("File \(n): only page 1 of \(pages) added") }
                } catch {
                    status = "\(u.lastPathComponent): \(error.localizedDescription)" // names stay on screen, not in the log
                    log.add("File \(n) (\(kind)) rejected: \(error.localizedDescription)", error: true)
                }
            }
        }
    }
    func paste() {
        guard !busy else { status = "Busy: paste when printing is done."; return }
        let p = NSPasteboard.general
        if let u = p.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !u.isEmpty { add(u); return }
        let kinds: [NSPasteboard.PasteboardType] = [.png, .tiff] + [UTType.jpeg, .heic, .gif].map { NSPasteboard.PasteboardType($0.identifier) }
        guard let data = kinds.lazy.compactMap({ p.data(forType: $0) }).first else { status = "Nothing to paste: copy an image or file first."; return }
        guard items.count < Model.maxItems else { fail("The list is full (\(Model.maxItems) files)."); return }
        loading += 1
        Task {
            defer { loading -= 1 }
            do {
                let i = Item(name: "Pasted image", image: try await Task.detached { try Encoder.load(data: data) }.value)
                items.append(i); selected = i.id; log.add("Added pasted image")
            } catch { fail(error.localizedDescription) }
        }
    }
    func choose() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.allowedContentTypes = [.image, .pdf]
        if p.runModal() == .OK { add(p.urls) }
    }
    func remove() { guard let i = index else { return }; items.remove(at: i); selected = items.isEmpty ? nil : items[min(i, items.count - 1)].id }
    func rotate() { if let i = index { items[i].turns = (items[i].turns + 1) % 4 } }

    private var rendering = false
    func refresh(_ k: PreviewKey) async {
        try? await Task.sleep(nanoseconds: 80_000_000)
        if Task.isCancelled { return }
        while rendering { try? await Task.sleep(nanoseconds: 20_000_000); if Task.isCancelled { return } } // one render at a time
        rendering = true; defer { rendering = false }
        let img = index.map { items[$0].image }
        if k.tab == .files ? img == nil : !hasText { preview = nil; previewError = nil; return }
        let r = await Task.detached { () -> Result<CGImage?, Error> in
            Result {
                let b = k.tab == .text
                    ? try TextRender.render(k.text, size: TextRender.sizes[k.size].1, bold: k.bold, align: k.align, turns: k.textTurns)
                    : try Encoder.render(img!, mode: .photo, turns: k.turns, brightness: k.brightness, trim: k.trim)
                return Encoder.preview(b, strength: k.strength)
            }
        }.value
        if Task.isCancelled { return }
        switch r {
        case .success(let i): preview = i; previewError = nil
        case .failure(let e): preview = nil; previewError = e.localizedDescription
        }
    }

    private func describe(_ p: PrinterInfo) -> String {
        guard let b = p.battery else { return p.name }
        return "\(p.name), battery \(b)%" + (b < 15 ? " (low, charge it)" : "") + (p.noPaper ? ", out of paper" : "")
    }
    private func makePrinter() -> Printer {
        let p = Printer()
        p.log = { [log] s, e in log.add(s, error: e) }
        p.cancelled = { [weak self] in self?.stop ?? false }
        return p
    }
    // The link stays open for a while after a job and is reused, so prints in a row don't reconnect.
    static let idleSeconds = 30.0
    private var held: Printer?, drainUntil = 0.0, idle: Task<Void, Never>?, closing: Task<Void, Never>?
    var linkBusy: Bool { held != nil || closing != nil }

    private func acquire() async throws -> (Printer, PrinterInfo) {
        if let p = held {
            held = nil; idle?.cancel(); idle = nil
            if uptime() < drainUntil { status = "Finishing previous print…" }
            while uptime() < drainUntil {
                if stop { hold(p, max(0, drainUntil - uptime())); throw UserCancelled() }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if let i = await p.recheck() { log.add("Using the open connection"); return (p, i) }
            log.add("The open connection stopped answering", error: true)
            await p.close()
        }
        await closing?.value
        if stop { throw UserCancelled() }
        status = "Connecting…"
        let p = makePrinter()
        p.onAttempt = { [weak self] n in if n > 1 { self?.status = "Connecting (attempt \(n) of 3)…" } }
        return (p, try await p.connect())
    }
    private func hold(_ p: Printer, _ drain: Double) {
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Finishing print")
        held = p; drainUntil = uptime() + drain
        idle = Task {
            try? await Task.sleep(nanoseconds: UInt64(drain * 1e9)); ProcessInfo.processInfo.endActivity(activity)
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: UInt64(Model.idleSeconds * 1e9))
            if Task.isCancelled { return }
            releaseHeld()
        }
    }
    private func releaseHeld() {
        guard let p = held else { return }
        held = nil; idle?.cancel(); idle = nil
        closing = Task { await p.close(); log.add("Connection closed"); closing = nil }
    }
    /// For quitting: let the last rows print, then close the link.
    func settle() async {
        while busy { try? await Task.sleep(nanoseconds: 100_000_000) }
        while held != nil && uptime() < drainUntil { try? await Task.sleep(nanoseconds: 50_000_000) }
        releaseHeld(); await closing?.value
    }
    private func finish() { progress = nil; busy = false; printing = false; stop = false; setClose(true) }
    private func setClose(_ on: Bool) { for w in NSApp.windows { w.standardWindowButton(.closeButton)?.isEnabled = on } }

    func cancel() { stop = true; status = printing && progress != nil ? "Cancelling: feeding blank paper…" : "Cancelling…"; log.add("Cancel requested") }

    func check() {
        guard !busy else { return }
        busy = true; stop = false; status = "Connecting…"
        Task {
            do { let (p, i) = try await acquire(); status = describe(i); hold(p, 0) }
            catch is UserCancelled { status = "Cancelled."; log.add("Cancelled") } catch { fail(error.localizedDescription) }
            finish()
        }
    }

    func printAll() {
        guard canPrint else { return }
        busy = true; printing = true; stop = false; slept = false; status = "Preparing…"; progress = nil; setClose(false)
        let k = key, list = items, n = copies, dark = darkness
        Task {
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Printing")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            var link: Printer?
            do {
                let jobs = try await Task.detached { () throws -> [Job] in
                    if k.tab == .text {
                        let b = try TextRender.render(k.text, size: TextRender.sizes[k.size].1, bold: k.bold, align: k.align, turns: k.textTurns)
                        return Array(repeating: Job(name: "Text", strips: Encoder.strips(b), rows: b.height), count: n)
                    }
                    return try list.enumerated().flatMap { x -> [Job] in
                        let (k2, it) = x
                        let b = try Encoder.render(it.image, mode: .photo, turns: it.turns, brightness: k.brightness, trim: k.trim)
                        return Array(repeating: Job(name: "file \(k2 + 1)", strips: Encoder.strips(b), rows: b.height), count: n)
                    }
                }.value
                if stop { throw UserCancelled() }
                let rows = jobs.reduce(0) { $0 + $1.rows }
                if rows > 3000 {
                    let a = NSAlert(); a.messageText = "Print about \(rows / 80) cm of paper?"
                    a.informativeText = "Long prints can heat up the printer."
                    a.addButton(withTitle: "Print"); a.addButton(withTitle: "Cancel")
                    if a.runModal() != .alertFirstButtonReturn { status = "Cancelled."; finish(); return }
                }
                let (pr, pi) = try await acquire()
                link = pr
                let info = describe(pi)
                status = "Printing on \(info)"; progress = 0
                let s = Sender(log: { [log] t, e in log.add(t, error: e) }, progress: { self.progress = $0 }, cancelled: { self.stop })
                var keep = false
                switch try await s.run(jobs, darkness: dark, on: pr) {
                case .printed: keep = true; status = "Done. \(info)"; log.add("Finished")
                case .alreadySent: keep = true; status = "Too late to cancel: it was already sent."; log.add("Cancel came after everything was sent")
                case .cancelled(let f): status = "Cancelled. \(f) of \(jobs.count) printed."; log.add(status)
                case .noPaper(let f, let started): fail(started
                    ? "The printer ran out of paper. The last print may be incomplete. \(f) of \(jobs.count) finished. Load paper, close the lid and print again."
                    : "Out of paper. Load paper, close the lid and print again. \(f) of \(jobs.count) printed.")
                case .unconfirmed(let f): fail("The printer stopped answering, so printing stopped. \(f) of \(jobs.count) finished. Check the paper, then turn the printer off and on.")
                }
                if keep, let last = jobs.last?.strips.last { hold(pr, Sender.drainTime(last)); finish(); return }
            } catch is UserCancelled { status = "Cancelled."; log.add("Cancelled") } catch { fail((slept ? "The Mac went to sleep while printing. " : "") + error.localizedDescription) }
            await link?.close(); finish()
        }
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        Model.shared.theme.apply()
        Log.shared.add("RaccoonPrint \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "") started")
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Model.shared.willSleep() }
        }
        #if SELFTEST
        Task { await SelfTest.run() }
        #endif
        // Cmd+V adds images on the Files tab; the Text tab keeps normal text paste.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.modifierFlags.intersection([.command, .shift, .option, .control]) == .command, e.charactersIgnoringModifiers == "v",
                  NSApp.modalWindow == nil, Model.shared.tab == .files, !(NSApp.keyWindow is NSPanel) else { return e }
            Model.shared.paste(); return nil
        }
    }
    private func quitWhenIdle() -> NSApplication.TerminateReply {
        Task {
            await Model.shared.settle()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func application(_ a: NSApplication, open urls: [URL]) { Model.shared.add(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        if !Model.shared.printing {
            guard Model.shared.linkBusy else { return .terminateNow }
            return quitWhenIdle()
        }
        let a = NSAlert(); a.messageText = "Stop printing and quit?"
        a.informativeText = "RaccoonPrint will first feed blank paper to the end of the current strip (up to about 12 cm)."
        a.addButton(withTitle: "Keep Printing"); a.addButton(withTitle: "Stop and Quit")
        guard a.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        if Model.shared.printing { Model.shared.cancel() }
        return quitWhenIdle()
    }
}

struct LogView: View {
    @ObservedObject var log = Log.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollViewReader { r in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.lines) { l in
                            Text(l.text).font(.system(size: 11, design: .monospaced)).foregroundStyle(l.error ? Color.red : Color.primary)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).id(l.id)
                        }
                    }.padding(6)
                }
                .frame(height: 120).background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 6))
                .onAppear { if let l = log.lines.last { r.scrollTo(l.id) } }
                .onChange(of: log.lines.last?.id) { _, id in if let id { r.scrollTo(id) } }
            }
            HStack {
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(log.text, forType: .string) }
                Button("Clear") { log.clear() }
            }.controlSize(.small).disabled(log.lines.isEmpty)
        }
    }
}

struct ContentView: View {
    @ObservedObject var m = Model.shared
    @State private var over = false
    @State private var showLog = false

    private var previewBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .underPageBackgroundColor))
            RoundedRectangle(cornerRadius: 10).strokeBorder(over ? Color.accentColor : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: m.preview == nil ? [6] : []))
            if let p = m.preview {
                ScrollView { Image(decorative: p, scale: 1).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 384).frame(maxWidth: .infinity) }.padding(8)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: m.previewError == nil ? "printer" : "exclamationmark.triangle").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(m.previewError ?? (m.tab == .files ? "Drop or paste images or PDFs here" : "Your text preview appears here")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding()
            }
        }
        .frame(minHeight: m.tab == .files ? 240 : 150)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Picker("", selection: $m.tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
                HStack {
                    Spacer()
                    Menu {
                        Picker("Theme", selection: $m.theme) { ForEach(Theme.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.inline).labelsHidden()
                    } label: { Image(systemName: "circle.lefthalf.filled") }
                    .menuIndicator(.hidden).fixedSize().help("Theme").accessibilityLabel("Theme")
                }
            }
            if m.tab == .text {
                TextEditor(text: $m.text).font(.system(size: 14)).frame(minHeight: 80, maxHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.4)))
                    .accessibilityLabel("Text to print")
                HStack {
                    Picker("Size", selection: $m.size) { ForEach(TextRender.sizes.indices, id: \.self) { Text(TextRender.sizes[$0].0).tag($0) } }.fixedSize()
                    Toggle("Bold", isOn: $m.bold)
                    Button { m.textTurns = (m.textTurns + 1) % 4 } label: { Image(systemName: "rotate.right") }.help("Rotate: sideways writes along the paper").accessibilityLabel("Rotate text")
                    Spacer()
                    Picker("", selection: $m.align) {
                        ForEach(TextAlign.allCases, id: \.self) { Image(systemName: "text.align\($0.rawValue)").accessibilityLabel($0.rawValue) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            previewBox
            if m.tab == .files {
                HStack {
                    Button("Choose files…") { m.choose() }.disabled(m.busy)
                    if !m.items.isEmpty {
                        Picker("", selection: $m.selected) { ForEach(m.items) { Text($0.name).tag(Optional($0.id)) } }.labelsHidden()
                        Button { m.rotate() } label: { Image(systemName: "rotate.right") }.help("Rotate").accessibilityLabel("Rotate")
                        Button { m.remove() } label: { Image(systemName: "trash") }.help("Remove from list").accessibilityLabel("Remove from list")
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Toggle("Trim white edges", isOn: $m.trim)
                    Spacer(minLength: 0)
                }
                HStack {
                    Text("Brightness")
                    Slider(value: $m.brightness, in: -1...1)
                    Button("Reset") { m.brightness = 0 }.disabled(m.brightness == 0)
                }
            }
            HStack {
                Picker("Print strength", selection: $m.darkness) { Text("Light").tag(0); Text("Normal").tag(1); Text("Dark").tag(2) }.fixedSize().help("Changes the printer's heat. The preview is approximate.")
                Spacer()
                Stepper("Copies: \(m.copies)", value: $m.copies, in: 1...20)
            }
            HStack {
                Button("Check printer") { m.check() }.disabled(m.busy)
                Spacer()
                if m.busy { Button("Cancel") { m.cancel() } }
                Button(m.tab == .files && m.items.count > 1 ? "Print all (\(m.items.count))" : "Print") { m.printAll() }
                    .keyboardShortcut("p").buttonStyle(.borderedProminent).disabled(!m.canPrint)
            }
            if let p = m.progress { ProgressView(value: p) }
            HStack {
                if m.busy && m.progress == nil { ProgressView().controlSize(.small) }
                Text(m.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0)
            }
            DisclosureGroup("Log", isExpanded: $showLog) { LogView() }
        }
        .padding(16).frame(minWidth: 460)
        .dropDestination(for: URL.self) { u, _ in
            guard !m.busy, u.contains(where: \.isFileURL) else { m.add(u); return false }
            m.add(u); return true
        } isTargeted: { over = $0 }
        .task(id: m.key) { await m.refresh(m.key) }
    }
}

struct ThemeMenu: View {
    @ObservedObject var m = Model.shared
    var body: some View { Picker("Theme", selection: $m.theme) { ForEach(Theme.allCases, id: \.self) { Text($0.rawValue) } } }
}

@main
struct RaccoonPrintApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var d
    var body: some Scene {
        Window("RaccoonPrint", id: "main") { ContentView() }.windowResizability(.contentMinSize).defaultSize(width: 480, height: 620)
            .commands { CommandGroup(before: .toolbar) { ThemeMenu() } }
    }
}
