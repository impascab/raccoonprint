import AppKit
import CoreText

enum TextAlign: String, CaseIterable { case left, center, right }

enum TextRender {
    static let sizes: [(String, CGFloat)] = [("Small", 22), ("Medium", 32), ("Large", 48), ("Very large", 76)]

    static func render(_ text: String, size: CGFloat, bold: Bool, align: TextAlign, turns: Int = 0) throws -> Bitmap {
        if turns % 2 == 1 { return rotated(try lengthwise(text, size: size, bold: bold, align: align), turns) }
        let t = text.trimmingCharacters(in: .newlines)
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EncodeError(msg: "Type some text to print") }
        let st = NSMutableParagraphStyle(); st.lineBreakMode = .byWordWrapping
        st.alignment = align == .left ? .left : align == .center ? .center : .right
        let s = NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : .medium), .paragraphStyle: st, .foregroundColor: NSColor.black])
        let fs = CTFramesetterCreateWithAttributedString(s)
        let m = 4, w = Encoder.width, tw = CGFloat(w - 2 * m)
        let need = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(), nil, CGSize(width: tw, height: .greatestFiniteMagnitude), nil)
        let h = Int(need.height.rounded(.up)) + 2 * m + Int(size / 4)
        guard h <= Encoder.maxRows else { throw EncodeError(msg: "Text is too long to print") }
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw EncodeError(msg: "Out of memory") }
        c.setFillColor(gray: 1, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let f = CTFramesetterCreateFrame(fs, CFRange(), CGPath(rect: CGRect(x: CGFloat(m), y: 0, width: tw, height: CGFloat(h - m)), transform: nil), nil)
        guard CTFrameGetVisibleStringRange(f).length >= s.length else { throw EncodeError(msg: "Text doesn't fit") }
        CTFrameDraw(f, c)
        let emoji = t.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
        return rotated(Encoder.toBits(c.data!.assumingMemoryBound(to: UInt8.self), w, h, emoji ? .photo : .text), turns)
    }

    /// Writes along the paper: lines don't wrap, and shrink if together they are taller than the paper is wide.
    private static func lengthwise(_ text: String, size: CGFloat, bold: Bool, align: TextAlign) throws -> Bitmap {
        let t = text.trimmingCharacters(in: .newlines)
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EncodeError(msg: "Type some text to print") }
        let m = 4, paper = Encoder.width, avail = CGFloat(paper - 2 * m)
        let st = NSMutableParagraphStyle(); st.lineBreakMode = .byClipping
        st.alignment = align == .left ? .left : align == .center ? .center : .right
        var pt = size
        while true {
            let s = NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: pt, weight: bold ? .bold : .medium), .paragraphStyle: st, .foregroundColor: NSColor.black])
            let lines = t.components(separatedBy: .newlines).map { l in
                CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: l, attributes: s.attributes(at: 0, effectiveRange: nil))), nil, nil, nil) }
            let len = CGFloat(lines.max() ?? 0).rounded(.up) + 4
            guard len + CGFloat(2 * m) <= CGFloat(Encoder.maxRows) else { throw EncodeError(msg: "Text is too long to print") }
            let fs = CTFramesetterCreateWithAttributedString(s)
            let need = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(), nil, CGSize(width: len, height: .greatestFiniteMagnitude), nil)
            if need.height > avail && pt > 6 { pt = max(6, min(pt - 1, (pt * avail / need.height).rounded(.down))); continue }
            guard need.height <= avail else { throw EncodeError(msg: "Too many lines for sideways text") }
            let w = Int(len) + 2 * m, boxH = min(avail, need.height + 4)
            guard let c = CGContext(data: nil, width: w, height: paper, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw EncodeError(msg: "Out of memory") }
            c.setFillColor(gray: 1, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: paper))
            let f = CTFramesetterCreateFrame(fs, CFRange(), CGPath(rect: CGRect(x: CGFloat(m), y: (CGFloat(paper) - boxH) / 2, width: len, height: boxH), transform: nil), nil)
            guard CTFrameGetVisibleStringRange(f).length >= s.length else { throw EncodeError(msg: "Text doesn't fit") }
            CTFrameDraw(f, c)
            let emoji = t.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
            return Encoder.toBits(c.data!.assumingMemoryBound(to: UInt8.self), w, paper, emoji ? .photo : .text)
        }
    }

    /// Quarter turns clockwise.
    static func rotated(_ b: Bitmap, _ turns: Int) -> Bitmap {
        var r = b
        for _ in 0..<((turns % 4 + 4) % 4) {
            let w = r.height, h = r.width; var o = [UInt8](repeating: 255, count: w * h)
            for y in 0..<r.height { for x in 0..<r.width { o[x * w + (w - 1 - y)] = r.px[y * r.width + x] } }
            r = Bitmap(width: w, height: h, px: o)
        }
        return r
    }
}
