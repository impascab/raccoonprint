import Foundation
@main struct F { static func main() {
 for p in CommandLine.arguments.dropFirst() { print("START", p); fflush(stdout); let u = URL(fileURLWithPath: p)
  _ = Encoder.pages(u)
  if let i = try? Encoder.load(u) { for t in 0..<2 { if let b = try? Encoder.render(i, mode: .photo, turns: t, brightness: -0.5, trim: t == 0), b.height <= 3000 { _ = Encoder.strips(b); _ = Encoder.preview(b, strength: 2) } } }
  if let d = try? Data(contentsOf: u) { _ = try? Encoder.load(data: d); _ = batteryLevel(d); _ = cleanReply(String(decoding: d.prefix(5000), as: UTF8.self)); for t in 0..<4 { _ = try? TextRender.render(String(decoding: d.prefix(300), as: UTF8.self), size: 32, bold: false, align: .left, turns: t) } }
  print("END", p); fflush(stdout) } } }
