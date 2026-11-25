import Foundation

struct LogLine: Identifiable { let id = UUID(); let text: String; let error: Bool }

@MainActor
final class Log: ObservableObject {
    static let shared = Log(file: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/RaccoonPrint.log"))
    static let cap = 500
    @Published private(set) var lines: [LogLine] = []
    private let file: URL
    private let df: DateFormatter = { let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.dateFormat = "yyyy-MM-dd HH:mm:ss"; return d }()

    init(file: URL) {
        self.file = file
        if let s = try? String(contentsOf: file, encoding: .utf8) {
            lines = s.split(separator: "\n").suffix(Log.cap).map { LogLine(text: String($0), error: $0.contains(" ERROR ")) }
        }
    }
    /// Never pass typed text or pasted content here.
    func add(_ s: String, error: Bool = false) {
        let clean = String(s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").prefix(400))
        lines.append(LogLine(text: "\(df.string(from: Date())) \(error ? "ERROR " : "")\(clean)", error: error))
        if lines.count > Log.cap { lines.removeFirst(lines.count - Log.cap) }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (text + "\n").write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    var text: String { lines.map(\.text).joined(separator: "\n") }
    func clear() { lines = []; try? FileManager.default.removeItem(at: file) }
}
