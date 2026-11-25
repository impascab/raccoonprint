import AppKit
import SwiftUI
// Test build only (-D SELFTEST). Drives the real Model and window.
@MainActor enum SelfTest {
    static let out = ProcessInfo.processInfo.environment["PP_OUT"]!, m = Model.shared
    static var bad = 0
    static func ck(_ n: String, _ c: Bool, _ extra: String = "") { print(c ? "ok  " : "FAIL", n, extra); if !c { bad += 1 } }
    static func nap(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
    static func idle(_ t: Double) async -> Bool { let e = Date().addingTimeInterval(t); while m.busy && Date() < e { await nap(0.1) }; return !m.busy }
    static func shot(_ n: String) async {
        await nap(0.7)
        guard let v = NSApp.windows.first(where: { $0.isVisible && $0.title == "RaccoonPrint" })?.contentView, let r = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { print("FAIL no window"); bad += 1; return }
        v.cacheDisplay(in: v.bounds, to: r); try? r.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(n).png"))
    }
    /// The whole window with its title bar, for the README.
    static func frameShot(_ n: String) async {
        await nap(1.2)
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.title == "RaccoonPrint" }) else { print("FAIL no window"); return }
        for _ in 0..<15 { // needs to be the active window, or its buttons are grey
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); await nap(0.8)
            if NSApp.isActive && w.isKeyWindow { break }
        }
        if !(NSApp.isActive && w.isKeyWindow) { print("FAIL", n, "not active") }
        typealias F = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let f = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"), let i = unsafeBitCast(f, to: F.self)(.null, 8, UInt32(w.windowNumber), 1 | 8)?.takeRetainedValue(), i.width > 100 {
            try? NSBitmapImageRep(cgImage: i).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(n)-own.png")); print("own", n, i.width, i.height)
        } else { print("own-window capture not available") }
        if let v = w.contentView?.superview, let r = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: r); try? r.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(n)-frame.png")); print("frame", n, r.pixelsWide, r.pixelsHigh)
        }
    }
    static func dims() -> String { m.preview.map { "\($0.width)x\($0.height)" } ?? "none" }
    static func pixels() -> [UInt8] { (m.preview?.dataProvider?.data as Data?).map { [UInt8]($0) } ?? [] }
    static func dark() -> Int { pixels().filter { $0 < 128 }.count }
    static func run() async {
        setbuf(stdout, nil); await nap(2)
        if CommandLine.arguments.contains("--shots") {
            for w in NSApp.windows where w.title == "RaccoonPrint" { w.setContentSize(NSSize(width: 480, height: 640)) }
            m.theme = .light; m.brightness = 0; m.trim = false; m.darkness = 1; m.copies = 1
            m.add([URL(fileURLWithPath: out + "/raccoon.png")]); await nap(1.5); m.status = "Ready"; await frameShot("w-warm"); await nap(1); await frameShot("w-light")
            m.tab = .text; m.text = "Hello\nraccoon"; m.size = 2; m.bold = true; m.align = .left; m.textTurns = 1; m.status = "Ready"; await nap(1); await frameShot("w-text")
            m.tab = .files; m.theme = .dark; await nap(1); m.status = "Ready"; await frameShot("w-dark"); exit(0)
        }
        if CommandLine.arguments.contains("--nopaper") {
            m.tab = .text; m.text = "no paper"; m.size = 0; m.copies = 2; await nap(0.5)
            m.check(); ck("check says out of paper", await idle(40) && m.status.contains("out of paper"), m.status)
            m.printAll(); ck("print refused", await idle(40) && m.status.hasPrefix("Out of paper") && m.status.contains("0 of 2"), m.status)
            ck("nothing was sent", !Log.shared.lines.suffix(8).contains { $0.text.contains("Sent strip") || $0.text.contains("Printing 1") })
            ck("can try again", m.canPrint); await m.settle(); ck("link closed", !m.linkBusy)
            print("FAILURES", bad); print(Log.shared.lines.suffix(9).map(\.text).joined(separator: "\n")); exit(0)
        }
        if CommandLine.arguments.contains("--off") {
            m.tab = .files; m.add([URL(fileURLWithPath: out + "/test.png")]); await nap(1); m.copies = 1
            var t = uptime(), worst = 0.0, last = uptime()
            let beat = Task { while !Task.isCancelled { await nap(0.05); worst = max(worst, uptime() - last); last = uptime() } }
            m.printAll(); ck("print with printer off ends", await idle(70), String(format: "%.1fs: %@", uptime() - t, m.status)); ck("clear error", m.status.contains("Can't reach the printer") && m.canPrint)
            t = uptime(); m.check(); ck("check with printer off ends", await idle(70) && m.status.contains("Can't reach"), String(format: "%.1fs", uptime() - t))
            t = uptime(); m.printAll(); await nap(2); m.cancel(); ck("cancel with printer off", await idle(20) && m.status == "Cancelled.", String(format: "%.1fs after start", uptime() - t))
            beat.cancel(); ck("window stayed responsive", worst < 1, String(format: "longest pause %.2fs", worst)); ck("nothing left open", !m.linkBusy)
            print("FAILURES", bad); print(Log.shared.lines.suffix(16).map(\.text).joined(separator: "\n")); exit(0)
        }
        if CommandLine.arguments.contains("--theme-check") { ck("theme remembered", m.theme == .dark && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua); exit(Int32(bad)) }
        for w in NSApp.windows where w.title == "RaccoonPrint" { w.setContentSize(NSSize(width: 480, height: 640)) }
        m.brightness = 0; m.trim = false; m.darkness = 1
        await shot("1-empty"); ck("print disabled when empty", !m.canPrint)
        m.add([URL(fileURLWithPath: out + "/test.png")]); await nap(1)
        ck("load", m.items.count == 1 && dims() == "384x160", dims()); await shot("2-file")
        let p0 = pixels(); m.rotate(); await nap(1); ck("rotate 90", dims() == "384x922", dims()); await shot("3-rotated")
        m.rotate(); await nap(1); ck("rotate 180", dims() == "384x160" && pixels() != p0); m.rotate(); m.rotate(); await nap(1); ck("rotate 360 = original", pixels() == p0)
        m.add(["photo.jpg", "doc.pdf", "land.heic", "bad.png"].map { URL(fileURLWithPath: out + "/" + $0) }); await nap(2)
        ck("several files, bad one rejected", m.items.count == 4 && m.status.contains("bad.png"), m.status)
        m.add([URL(string: "https://example.com/a.png")!]); ck("web link refused", m.items.count == 4 && m.status.contains("Only files"))
        m.selected = m.items[1].id; await nap(1); let ph = pixels(), d0 = dark(); await shot("4-photo")
        ck("shading kept", d0 > 0 && ph.contains { $0 < 128 }); ck("old Text setting removed", UserDefaults.standard.object(forKey: "mode") == nil)
        m.brightness = 0.6; await nap(1); let d1 = dark(); m.brightness = -0.6; await nap(1); ck("brightness", d1 < d0 && dark() > d0, "\(dark())>\(d0)>\(d1)"); m.brightness = 0
        m.selected = m.items[2].id; await nap(1); let h = dims(); m.trim = true; await nap(1); ck("trim on PDF", dims() != h, "\(h)->\(dims())"); m.trim = false
        let st1 = pixels(); m.darkness = 2; await nap(1); ck("strength changes the preview", pixels() != st1); m.darkness = 1; await nap(1)
        ck("settings saved", UserDefaults.standard.object(forKey: "darkness") as? Int == 1)
        m.remove(); ck("remove", m.items.count == 3)
        // Paste: keep and restore the user's clipboard.
        let pb = NSPasteboard.general
        let saved = (pb.pasteboardItems ?? []).map { it -> NSPasteboardItem in let n = NSPasteboardItem(); for t in it.types { if let d = it.data(forType: t) { n.setData(d, forType: t) } }; return n }
        pb.clearContents(); pb.writeObjects([NSImage(contentsOfFile: out + "/test.png")!]); m.paste(); await nap(0.5)
        ck("paste image", m.items.last?.name == "Pasted image"); pb.clearContents(); if !saved.isEmpty { pb.writeObjects(saved) }
        let before = m.items.count
        // Text tab
        m.tab = .text; await nap(0.5); ck("empty text can't print", !m.canPrint)
        m.text = "RaccoonPrint test\nÉté déjà 😀"; m.size = 1; m.bold = true; m.align = .center; await nap(1)
        ck("text preview", m.preview != nil && m.canPrint, dims()); await shot("5-text")
        let c = pixels(); m.align = .right; await nap(1); ck("alignment", pixels() != c); m.align = .center
        let h1 = m.preview?.height ?? 0; m.size = 3; await nap(1); ck("text size", (m.preview?.height ?? 0) > h1, dims()); m.size = 1; m.bold = false; await nap(1); ck("bold", pixels() != c); m.bold = true; await nap(1)
        m.text = "Hello raccoon\nsideways"; m.size = 2; m.textTurns = 1; m.status = "Ready"; await nap(1)
        ck("sideways text", m.preview?.width == 384 && (m.preview?.height ?? 0) > 300, dims()); await shot("8-sideways"); m.textTurns = 0
        if CommandLine.arguments.contains("--print") {
            if !CommandLine.arguments.contains("--short") { print("--- PRINT 1: typed text"); m.copies = 1; m.printAll(); await nap(0.3); ck("busy while printing", m.busy && !m.canPrint)
            ck("finished", await idle(90)); ck("text printed", m.status.hasPrefix("Done"), m.status); await shot("6-printed") }
            print("--- PRINT 2: rotated image, several blocks")
            m.tab = .files; m.items = []; m.add([URL(fileURLWithPath: out + "/tall.png")]); await nap(1); m.rotate(); m.rotate(); m.rotate(); await nap(1)
            m.printAll(); await nap(6); await shot("7-printing"); m.add([URL(fileURLWithPath: out + "/photo.jpg")]); ck("add refused while busy", m.items.count == 1)
            ck("finished", await idle(150)); ck("rotated printed", m.status.hasPrefix("Done"), m.status)
            print("--- PRINT 3: cancel a long print"); await nap(5)
            m.printAll(); let e = Date().addingTimeInterval(40); while (m.progress ?? 0) <= 0 && Date() < e { await nap(0.05) }
            m.cancel(); ck("finished", await idle(60)); ck("cancelled", m.status.hasPrefix("Cancelled"), m.status)
            print("--- PRINT 4: 2 copies after a cancel"); await nap(5)
            m.items = []; m.add([URL(fileURLWithPath: out + "/test.png")]); await nap(1); m.copies = 2; await nap(1); m.printAll(); ck("finished", await idle(120)); ck("2 copies", m.status.hasPrefix("Done"), m.status); m.copies = 1
            print("--- cancel while connecting"); await nap(3); m.printAll(); await nap(0.15); m.cancel(); ck("finished", await idle(40)); ck("cancelled early", m.status.hasPrefix("Cancelled"), m.status)
            print("--- check printer"); await nap(3); m.check(); ck("finished", await idle(60)); ck("status", m.status.contains("battery"), m.status)
        }
        ck("no file names in log", !Log.shared.text.contains("photo.jpg") && !Log.shared.text.contains("bad.png"))
        m.add([URL(fileURLWithPath: out + "/two.pdf")]); ck("print blocked while loading", m.loading > 0 && !m.canPrint); await nap(1); ck("page notice", m.status.contains("page 1 of 2"), m.status)
        m.add([URL(fileURLWithPath: out + "/huge.png")]); await nap(1); ck("over 100 MP refused", m.status.contains("too large"), m.status)
        if CommandLine.arguments.contains("--modal") {
            // Opened from the run loop, like the quit alert, not from inside a Task (which would block the main queue).
            m.check(); var during: Bool?; let t0 = uptime()
            RunLoop.main.perform { MainActor.assumeIsolated {
                let w = NSPanel(contentRect: NSRect(x: 300, y: 300, width: 260, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
                w.title = "RaccoonPrint test, closes by itself"
                let t = Timer(timeInterval: 9, repeats: false) { _ in MainActor.assumeIsolated { during = !m.busy; NSApp.stopModal() } }
                RunLoop.main.add(t, forMode: .common); NSApp.runModal(for: w); w.orderOut(nil)
            } }
            while during == nil && uptime() - t0 < 20 { await nap(0.2) }
            ck("Bluetooth works while an alert is open", during == true, "\(m.status) after \(Int(uptime() - t0)) s"); _ = await idle(60)
        }
        if CommandLine.arguments.contains("--link") {
            func count(_ x: String) -> Int { Log.shared.lines.filter { $0.text.contains(x) }.count }
            let z0 = count("Connection closed")
            m.check(); ck("first check", await idle(30) && m.status.contains("battery"), m.status)
            let r0 = count("Using the open connection"), c0 = count(" Connected")
            var t = uptime(); m.check(); ck("second check reuses the link", await idle(30) && m.status.contains("battery") && count("Using the open connection") == r0 + 1 && count(" Connected") == c0, String(format: "%.1fs", uptime() - t))
            let e = uptime() + 36; while count("Connection closed") == z0 && uptime() < e { await nap(0.2) }
            ck("idle link closes", count("Connection closed") == z0 + 1 && !m.linkBusy)
            t = uptime(); m.check(); await nap(0.3); m.cancel(); ck("cancel while connecting", await idle(15) && m.status == "Cancelled.", String(format: "%@ %.1fs", m.status, uptime() - t))
            t = uptime(); m.check(); ck("connects right after a cancel", await idle(30) && m.status.contains("battery"), String(format: "%.1fs", uptime() - t))
            m.willSleep(); m.check(); ck("check right after sleep close", await idle(30) && m.status.contains("battery"), m.status)
            t = uptime(); await m.settle(); ck("quit path closes the link", !m.linkBusy, String(format: "%.1fs", uptime() - t))
            ck("no failed attempts", !Log.shared.lines.suffix(40).contains { $0.text.contains("Attempt ") })
        }
        if CommandLine.arguments.contains("--final") {
            await m.settle(); m.trim = false; m.brightness = 0; m.copies = 1; m.darkness = 1
            print("--- long image"); m.tab = .files; m.items = []; m.add([URL(fileURLWithPath: out + "/long.png")]); await nap(1.5)
            m.printAll(); await nap(1); ck("close button off while printing", NSApp.windows.first { $0.title == "RaccoonPrint" }?.standardWindowButton(.closeButton)?.isEnabled == false)
            ck("long finished", await idle(150) && m.status.hasPrefix("Done"), m.status)
            ck("close button back", NSApp.windows.first { $0.title == "RaccoonPrint" }?.standardWindowButton(.closeButton)?.isEnabled == true)
            print("--- sideways text, straight after"); m.tab = .text; m.text = "Raccoon 123"; m.size = 2; m.bold = true; m.align = .left; m.textTurns = 1; await nap(1)
            m.printAll(); ck("sideways finished", await idle(90) && m.status.hasPrefix("Done"), m.status); m.textTurns = 0
            print("--- cancel while connecting"); await m.settle(); m.printAll(); await nap(0.8); let t = uptime(); m.cancel(); ck("cancel while connecting", await idle(15) && m.status == "Cancelled.", String(format: "%.1fs", uptime() - t))
            print("--- quit mid-print"); m.tab = .files; m.items = []; m.add([URL(fileURLWithPath: out + "/short.png")]); await nap(1); m.printAll()
            let e = uptime() + 30; while (m.progress ?? 0) <= 0.15 && uptime() < e { await nap(0.05) }
            print("FAILURES before quit", bad)
            RunLoop.main.perform { MainActor.assumeIsolated {
                let t = Timer(timeInterval: 0.5, repeats: false) { _ in MainActor.assumeIsolated {
                    func find(_ v: NSView?) -> NSButton? { guard let v else { return nil }; if let b = v as? NSButton, b.title == "Stop and Quit" { return b }; for s in v.subviews { if let b = find(s) { return b } }; return nil }
                    if let b = find(NSApp.modalWindow?.contentView) { print("ok   quit question shown"); b.performClick(nil) } else { print("FAIL quit question missing"); exit(3) }
                } }
                RunLoop.main.add(t, forMode: .common); NSApp.terminate(nil)
            } }
            await nap(60); print("FAIL app did not quit"); exit(4)
        }
        m.text = ""; m.tab = .files; m.items = [m.items[0]]; m.selected = m.items[0].id; m.status = "Ready"; m.theme = .dark; await nap(0.6); ck("dark theme", NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua && UserDefaults.standard.string(forKey: "theme") == "Dark"); await shot("9-dark")
        m.theme = .light; await nap(0.6); ck("light theme", NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua); await shot("10-light")
        m.theme = .dark; ck("typed text not in log", !Log.shared.text.contains("déjà")); _ = before
        print("FAILURES", bad); print(Log.shared.lines.suffix(45).map(\.text).joined(separator: "\n")); exit(0)
    }
}
