import Foundation
import IOBluetooth

struct PrinterInfo { let name: String, firmware: String, battery: Int?; var noPaper = false }

@MainActor
final class Printer: NSObject, @preconcurrency IOBluetoothRFCOMMChannelDelegate, Transport {
    var log: (String, Bool) -> Void = { _, _ in }
    var cancelled: () -> Bool = { false }
    var rx = Data()
    private var dev: IOBluetoothDevice?, ch: IOBluetoothRFCOMMChannel?
    private var opened: IOReturn?, wrote: IOReturn?, closed = false, failed = false
    private var pending: UnsafeMutableRawPointer? // the write we are waiting for; buffers are freed in the completion
    private var linkDown = false
    /// Tests set this to 1 to measure first attempts.
    var maxAttempts = 3
    private(set) var attempts = 0

    @objc func rfcommChannelOpenComplete(_ c: IOBluetoothRFCOMMChannel!, status: IOReturn) { opened = status }
    @objc func rfcommChannelClosed(_ c: IOBluetoothRFCOMMChannel!) { closed = true }
    @objc func rfcommChannelData(_ c: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) { if n > 0, rx.count + n <= 4096 { rx.append(Data(bytes: p, count: n)) } } // replies are tiny; ignore floods
    @objc func rfcommChannelWriteComplete(_ c: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status: IOReturn) {
        guard let r = refcon else { return }
        if r == pending { wrote = status; pending = nil }
        r.deallocate()
    }
    @objc func linkClosed(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) { linkDown = true; n.unregister() }

    private func wait(_ s: Double, _ cond: () -> Bool) async {
        let end = uptime() + s
        while !cond() && uptime() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
    }
    private func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    private func tryOpen(_ d: IOBluetoothDevice, _ id: BluetoothRFCOMMChannelID, _ timeout: Double) async -> Bool {
        opened = nil; closed = false; failed = false; var c: IOBluetoothRFCOMMChannel?
        let r = d.openRFCOMMChannelAsync(&c, withChannelID: id, delegate: self)
        ch = c
        if r == kIOReturnSuccess { await wait(timeout) { opened != nil || cancelled() } }
        if opened == kIOReturnSuccess { return true }
        let why = r != kIOReturnSuccess ? String(format: "error %08x", r) : opened.map { String(format: "error %08x", $0) } ?? "no reply"
        if !cancelled() { log("Attempt \(attempts) of \(maxAttempts) failed: \(why)", true) }
        return false
    }

    private func checkCancel() async throws { if cancelled() { await close(); throw UserCancelled() } }

    func connect() async throws -> PrinterInfo {
        try await checkCancel()
        let all = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard let d = all.first(where: { ($0.name ?? "").lowercased().hasPrefix("peripage") }) else {
            throw PrintError(msg: "No paired PeriPage found. Pair it in System Settings > Bluetooth, and allow Bluetooth for RaccoonPrint in Privacy & Security.")
        }
        dev = d
        log("Connecting to \(cleanReply(d.name ?? "PeriPage"))", false)
        var id: BluetoothRFCOMMChannelID = 1
        for r in (d.services as? [IOBluetoothSDPServiceRecord]) ?? [] {
            var c: BluetoothRFCOMMChannelID = 0
            if r.getRFCOMMChannelID(&c) == kIOReturnSuccess { id = c; break }
        }
        // Reopening while the last link is still going down gets no answer, so start from a fully closed one.
        if d.isConnected() { await close(); dev = d }
        attempts = 0
        var ok = false
        while !ok && attempts < maxAttempts {
            attempts += 1; onAttempt(attempts)
            ok = await tryOpen(d, id, 6) // longer than Bluetooth's own 5 s page timeout
            try await checkCancel()
            if !ok { await close(); dev = d }
        }
        guard ok else {
            log("Connection failed", true); await close()
            throw PrintError(msg: "Can't reach the printer. Turn it off and on, keep it close, and disconnect it from your phone. If that fails, turn Bluetooth off and on.")
        }
        log("Connected", false)
        return try await identify(d)
    }

    /// True if an open link still answers, so it can be used again.
    func recheck() async -> PrinterInfo? {
        guard let i = info, ch != nil, !closed, !failed else { return nil }
        rx = Data()
        guard (try? await send(Sender.query)) != nil else { return nil }
        await wait(2) { closed || batteryLevel(rx) != nil }
        guard let b = batteryLevel(rx) else { return nil }
        var n = PrinterInfo(name: i.name, firmware: i.firmware, battery: b)
        rx = Data()
        if (try? await send(Sender.statusQuery)) != nil { await wait(1) { closed || !rx.isEmpty }; n.noPaper = Sender.noPaper(rx) }
        info = n
        return info
    }
    private var info: PrinterInfo?
    var onAttempt: (Int) -> Void = { _ in }

    private func identify(_ d: IOBluetoothDevice) async throws -> PrinterInfo {
        do { return try await identifyOnce(d) } catch { await close(); throw error }
    }
    private func identifyOnce(_ d: IOBluetoothDevice) async throws -> PrinterInfo {
        try await send(Sender.reset)
        await pause(0.4)
        // Never ask for everything at once (10 ff 70 f1): it makes the next print start about 5 mm too far right.
        guard let fw = try await ask(Sender.firmwareQuery, { $0.count >= 4 }) else { throw PrintError(msg: "The printer connected but didn't answer. Turn it off and on, then try again.") }
        try await checkCancel()
        let firmware = cleanReply(String(decoding: fw, as: UTF8.self))
        guard firmware.contains("203dpi") else { throw PrintError(msg: "This printer reports \(firmware). RaccoonPrint only supports the 203 dpi A6.") }
        let battery = try await ask(Sender.query, { batteryLevel($0) != nil }).flatMap(batteryLevel)
        try await checkCancel()
        let name = cleanReply(d.name ?? "PeriPage")
        log("Printer \(name), \(firmware), battery \(battery.map(String.init) ?? "unknown")", false)
        var i = PrinterInfo(name: name, firmware: firmware, battery: battery)
        i.noPaper = try await ask(Sender.statusQuery, { !$0.isEmpty }).map(Sender.noPaper) ?? false
        info = i
        return i
    }

    private func ask(_ q: Data, _ ok: (Data) -> Bool) async throws -> Data? {
        rx = Data(); try await send(q)
        await wait(4) { closed || ok(rx) }
        await pause(0.2)
        return ok(rx) ? rx : nil
    }

    func send(_ x: Data) async throws {
        guard let c = ch, !closed, !failed else { throw PrintError(msg: "The printer disconnected.") }
        let mtu = max(20, min(Int(c.getMTU()), 256)); var i = 0
        let bytes = [UInt8](x)
        while i < bytes.count {
            let n = min(mtu, bytes.count - i)
            let b = UnsafeMutableRawPointer.allocate(byteCount: n, alignment: 1)
            bytes.withUnsafeBytes { b.copyMemory(from: $0.baseAddress! + i, byteCount: n) }
            wrote = nil; pending = b
            // An immediate error means nothing was sent, so the same piece can be tried again.
            var r = c.writeAsync(b, length: UInt16(n), refcon: b); let giveUp = uptime() + 3
            while r != kIOReturnSuccess && !closed && uptime() < giveUp { await pause(0.1); r = c.writeAsync(b, length: UInt16(n), refcon: b) }
            guard r == kIOReturnSuccess else { pending = nil; b.deallocate(); failed = true; throw PrintError(msg: "The printer stopped accepting data.") }
            // The printer may pause for a while (hot head); keep waiting while the link is open.
            await wait(60) { wrote != nil || closed }
            guard let w = wrote else { pending = nil; failed = true; throw PrintError(msg: closed ? "The printer disconnected." : "The printer stopped responding.") }
            guard w == kIOReturnSuccess else { failed = true; throw PrintError(msg: "Sending to the printer failed.") }
            i += n
            await pause(0.02)
        }
    }

    /// Closes the whole link and waits until macOS says it is down. Measured: reopening right after closing only the
    /// channel, or about 2 s later while macOS drops the idle link, gets no answer.
    func close() async {
        info = nil
        if let c = ch {
            c.close(); if opened == kIOReturnSuccess { await wait(2) { closed } } // a channel that never opened has nothing to confirm
            c.setDelegate(nil); ch = nil
        }
        guard let d = dev else { return }
        dev = nil
        guard d.isConnected() else { return }
        linkDown = false
        let note = d.register(forDisconnectNotification: self, selector: #selector(linkClosed(_:device:)))
        d.closeConnection()
        await wait(5) { linkDown }
        if !linkDown { note?.unregister(); log("The old link didn't confirm closing", true) }
    }
}
