import Foundation

/// Seconds that don't count while the Mac sleeps and don't jump when the clock changes.
func uptime() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
/// Text from the printer, safe to show and log: printable ASCII, short.
func cleanReply(_ s: String) -> String { String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.value >= 32 && $0.value < 127 })).prefix(40).description }
/// The answer to the battery query: 0, then 0...100. Looks at the end, so a late "OK" doesn't hide it.
func batteryLevel(_ d: Data) -> Int? { let r = [UInt8](d.suffix(2)); return r.count == 2 && r[0] == 0 && r[1] <= 100 ? Int(r[1]) : nil }
struct UserCancelled: Error {}
struct PrintError: LocalizedError { let msg: String; var errorDescription: String? { msg } }

@MainActor protocol Transport: AnyObject {
    var rx: Data { get set }
    func send(_ x: Data) async throws
}

struct Job { let name: String; let strips: [Data]; let rows: Int }
enum Outcome: Equatable { case printed, cancelled(finished: Int), alreadySent, unconfirmed(finished: Int), noPaper(finished: Int, started: Bool) }

@MainActor
struct Sender {
    var timeScale = 1.0 // tests run faster
    var log: (String, Bool) -> Void = { _, _ in }
    var progress: (Double) -> Void = { _ in }
    var cancelled: () -> Bool = { false }

    /// Returns early when `done` is true or the user cancels.
    private func wait(_ s: Double, cancellable: Bool = true, until done: () -> Bool = { false }) async {
        let end = uptime() + s * timeScale
        while uptime() < end && !done() && !(cancellable && cancelled()) { try? await Task.sleep(nanoseconds: UInt64(50_000_000 * min(1, timeScale * 2))) }
    }
    static let reset = Data([0x10, 0xff, 0xfe, 0x01] + [UInt8](repeating: 0, count: 12))
    static let firmwareQuery = Data([0x10, 0xff, 0x20, 0xf1])
    /// Status flags (A6, firmware V1.11): 00 with paper, 04 and 06 without. So 04 means no paper; 02 is unknown.
    static let statusQuery = Data([0x10, 0xff, 0x40])
    static func noPaper(_ reply: Data) -> Bool { guard let v = reply.last, v < 0x10 else { return false }; return v & 0x04 != 0 }

    /// Only a clear "no paper" counts. No answer or an unknown one never blocks printing.
    private func outOfPaper(_ t: Transport) async throws -> Bool {
        t.rx = Data()
        try await t.send(Sender.statusQuery)
        await wait(2, cancellable: false) { !t.rx.isEmpty }
        if let v = t.rx.last, v != 0, v != 4 { log("Unknown printer status \(String(format: "%02x", v))", false) }
        return Sender.noPaper(t.rx)
    }
    static let query = Data([0x10, 0xff, 0x50, 0xf1]) // battery

    /// The printer handles commands in order, so an answer means it has taken in everything sent before.
    /// It does not prove the paper came out.
    private func answered(_ t: Transport, within s: Double, cancellable: Bool) async throws -> Bool {
        t.rx = Data()
        try await t.send(Sender.query)
        await wait(s, cancellable: cancellable) { batteryLevel(t.rx) != nil }
        return batteryLevel(t.rx) != nil
    }
    /// Seconds to keep the link open while the last rows print.
    static func drainTime(_ strip: Data) -> Double {
        min(7, max(3, 2 + Double(max(0, strip.count - Encoder.headerBytes) / Encoder.rowBytes) / 60))
    }
    private func drain(_ strip: Data) async { await wait(Sender.drainTime(strip), cancellable: false) }
    private func advise(_ e: Error, _ j: Int, _ n: Int) -> PrintError {
        PrintError(msg: "\(e.localizedDescription) \(j) of \(n) finished. Turn the printer off and on before printing again.")
    }
    /// After a cancel: feed, make sure the printer took everything, and let it finish.
    private func endCancelled(_ t: Transport, _ strip: Data, _ j: Int, _ n: Int) async throws -> Outcome {
        do {
            try await t.send(Sender.feed)
            guard try await answered(t, within: 20, cancellable: false) else { return .unconfirmed(finished: j) }
        } catch { throw advise(error, j, n) }
        await drain(strip)
        return .cancelled(finished: j)
    }
    static let slice = 48 * 50 // 50 rows
    static let feed = Data([0x1b, 0x4a, 0x60])

    /// The printer always gets every row it was promised. After a cancel, the rest of the strip is sent as white.
    func run(_ jobs: [Job], darkness: Int, on t: Transport) async throws -> Outcome {
        let total = max(1, jobs.reduce(0) { $0 + $1.strips.reduce(0) { $0 + $1.count } }); var sent = 0
        if cancelled() { return .cancelled(finished: 0) }
        t.rx = Data()
        try await t.send(Data([0x10, 0xff, 0x10, 0x00, UInt8(max(0, min(2, darkness)))]))
        // "OK" only acknowledges the darkness command. Wait for it so it isn't mistaken for a later answer.
        await wait(2) { t.rx.range(of: Data("OK".utf8)) != nil }
        for (j, job) in jobs.enumerated() {
            if try await outOfPaper(t) { log("Out of paper", true); return .noPaper(finished: j, started: false) }
            log("Printing \(j + 1) of \(jobs.count): \(job.name), \(job.rows) rows", false)
            for (k, strip) in job.strips.enumerated() {
                if cancelled() {
                    return k > 0 ? try await endCancelled(t, job.strips[k - 1], j, jobs.count) : .cancelled(finished: j)
                }
                var at = 0, white = false
                do {
                    while at < strip.count {
                        let n = min(at == 0 ? Encoder.headerBytes + Sender.slice : Sender.slice, strip.count - at)
                        if at > 0 && !white && cancelled() { white = true; log("Cancelling: feeding blank paper to the end of this strip", false) }
                        try await t.send(white ? Data(count: n) : strip.subdata(in: at..<at + n))
                        at += n; sent += n; progress(Double(sent) / Double(total))
                    }
                } catch {
                    throw advise(error, j, jobs.count)
                }
                log("Sent strip \(k + 1) of \(job.strips.count)\(white ? " (cancelled part is blank)" : "")", false)
                if white { return try await endCancelled(t, strip, j, jobs.count) }
                if k < job.strips.count - 1 {
                    // Cool the head, then make sure the printer caught up.
                    await wait(1.5)
                    if !cancelled() {
                        var good = false
                        do { good = try await answered(t, within: 30, cancellable: true) } catch {
                            throw advise(error, j, jobs.count)
                        }
                        if !good && !cancelled() { log("Printer didn't answer after strip \(k + 1)", true); return .unconfirmed(finished: j) }
                    }
                }
            }
            do { try await t.send(Sender.feed) } catch {
                throw PrintError(msg: "\(error.localizedDescription) The paper may not have advanced. \(j) of \(jobs.count) confirmed.")
            }
            let good = (try? await answered(t, within: 20, cancellable: false)) ?? false
            log(good ? "Printer answered after the last row" : "Printer didn't answer after the last row", !good)
            if !good { return .unconfirmed(finished: j) }
            if (try? await outOfPaper(t)) == true { log("Out of paper during the print", true); return .noPaper(finished: j, started: true) }
            // After the last job the caller keeps the link open instead, so the window is free sooner.
            if j < jobs.count - 1 {
                if let last = job.strips.last { await drain(last) }
                await wait(min(20, max(3, Double(job.rows) / 100)))
                if cancelled() { return .cancelled(finished: j + 1) }
            }
        }
        return cancelled() ? .alreadySent : .printed
    }
}
