import Foundation
import CoreGraphics
import ImageIO

enum Mode: String, CaseIterable { case photo = "Photo", text = "Text" }
struct EncodeError: LocalizedError { let msg: String; var errorDescription: String? { msg } }

/// 1 byte per pixel: 0 black, 255 white.
struct Bitmap { let width: Int, height: Int; var px: [UInt8] }

enum Encoder {
    static let width = 384, rowBytes = 48, maxRows = 20_000

    static func load(_ url: URL) throws -> CGImage {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = CGPDFDocument(url as CFURL) else { throw EncodeError(msg: "Can't read this PDF") }
            guard doc.isUnlocked else { throw EncodeError(msg: "This PDF is password-protected") }
            guard let page = doc.page(at: 1) else { throw EncodeError(msg: "Can't read this PDF") }
            var box = page.getBoxRect(.cropBox)
            if page.rotationAngle % 180 != 0 { box = CGRect(x: 0, y: 0, width: box.height, height: box.width) }
            guard box.width > 1, box.height > 1 else { throw EncodeError(msg: "Empty PDF page") }
            let s = min(1200 / box.width, 6000 / box.height)
            let w = max(1, Int(box.width * s)), h = max(1, Int(box.height * s))
            guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw EncodeError(msg: "Can't draw PDF") }
            c.setFillColor(.white); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.scaleBy(x: s, y: s)
            c.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: box.size), rotate: 0, preserveAspectRatio: true))
            c.drawPDFPage(page)
            guard let i = c.makeImage() else { throw EncodeError(msg: "Can't draw PDF") }
            return i
        }
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw EncodeError(msg: "Can't read this file") }
        return try load(s)
    }

    static func load(data: Data) throws -> CGImage {
        guard let s = CGImageSourceCreateWithData(data as CFData, nil) else { throw EncodeError(msg: "Can't read this image") }
        return try load(s)
    }

    /// Pages in a PDF or TIFF, 1 for anything else.
    static func pages(_ url: URL) -> Int {
        switch url.pathExtension.lowercased() {
        case "pdf": return CGPDFDocument(url as CFURL)?.numberOfPages ?? 1
        case "tif", "tiff": return CGImageSourceCreateWithURL(url as CFURL, nil).map(CGImageSourceGetCount) ?? 1
        default: return 1
        }
    }

    private static func load(_ s: CGImageSource) throws -> CGImage {
        // Keep the short side near 800 px: plenty for 384 dots, without holding huge photos in memory.
        var limit = 6000
        if let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
           let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int, min(w, h) > 0 {
            guard Double(w) * Double(h) <= 100_000_000 else { throw EncodeError(msg: "Image is too large (over 100 megapixels)") }
            let long = max(w, h), short = min(w, h)
            limit = short <= 800 ? min(long, 20_000) : min(20_000, Int(800.0 * Double(long) / Double(short)))
        }
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: limit]
        guard let i = CGImageSourceCreateThumbnailAtIndex(s, 0, o as CFDictionary) else { throw EncodeError(msg: "Can't read this file") }
        return i
    }

    /// White space kept around a trimmed image, so nothing sits on the paper's edge.
    static let trimMargin = 6

    /// Crops the empty border: transparent pixels if the image has any, otherwise white ones. A blank image is returned unchanged.
    static func trimmed(_ img: CGImage) -> CGImage {
        let w = img.width, h = img.height
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        var clear = false
        for i in 0..<w * h where p[i * 4 + 3] < 128 { clear = true; break }
        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for y in 0..<h { for x in 0..<w {
            let q = p + (y * w + x) * 4
            let used = clear ? q[3] > 8 : min(q[0], q[1], q[2]) < 250
            if used { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = y }
        } }
        guard x1 >= 0 else { return img }
        return img.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)) ?? img
    }

    /// brightness -1...1, 0 = unchanged.
    static func render(_ source: CGImage, mode: Mode, turns: Int, brightness: Double = 0, trim: Bool = false) throws -> Bitmap {
        let img = trim ? trimmed(source) : source
        let side = turns % 2 == 1
        let iw = CGFloat(side ? img.height : img.width), ih = CGFloat(side ? img.width : img.height)
        let m = trim ? trimMargin : 0
        let w = width, h = max(1, Int((ih * CGFloat(w - 2 * m) / iw).rounded())) + 2 * m
        guard h <= maxRows else { throw EncodeError(msg: "Image is too long to print") }
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw EncodeError(msg: "Out of memory") }
        c.setFillColor(gray: 1, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.interpolationQuality = .high
        c.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        c.rotate(by: -CGFloat(turns) * .pi / 2)
        let dw = CGFloat((side ? h : w) - 2 * m), dh = CGFloat((side ? w : h) - 2 * m)
        c.draw(img, in: CGRect(x: -dw / 2, y: -dh / 2, width: dw, height: dh))
        let g = c.data!.assumingMemoryBound(to: UInt8.self)
        if brightness != 0 {
            let e = pow(2.0, -brightness * 1.5)
            let lut = (0...255).map { UInt8((255 * pow(Double($0) / 255, e)).rounded()) }
            for i in 0..<w * h { g[i] = lut[Int(g[i])] }
        }
        return toBits(g, w, h, mode)
    }

    static func toBits(_ g: UnsafeMutablePointer<UInt8>, _ w: Int, _ h: Int, _ mode: Mode) -> Bitmap {
        var out = [UInt8](repeating: 255, count: w * h)
        if mode == .text {
            for i in 0..<w * h { out[i] = g[i] < 128 ? 0 : 255 }
        } else { // Floyd-Steinberg
            var cur = [Float](repeating: 0, count: w + 2), nxt = cur
            for y in 0..<h {
                for x in 0..<w {
                    let v = Float(g[y * w + x]) + cur[x + 1]
                    let n: Float = v < 128 ? 0 : 255
                    out[y * w + x] = UInt8(n)
                    let e = v - n
                    cur[x + 2] += e * 7 / 16; nxt[x] += e * 3 / 16; nxt[x + 1] += e * 5 / 16; nxt[x + 2] += e / 16
                }
                cur = nxt; nxt = [Float](repeating: 0, count: w + 2)
            }
        }
        return Bitmap(width: w, height: h, px: out)
    }

    /// Rows per continuous strip (about 12.5 cm).
    static let stripRows = 1000
    static let headerBytes = 24

    /// One Data per strip: reset, raster header with a 16-bit row count, rows. Joins between rasters
    /// were suspected of shifting the print; those tests were later found unreliable (see CHANGELOG).
    static func strips(_ b: Bitmap) -> [Data] {
        stride(from: 0, to: b.height, by: stripRows).map { start in
            let n = min(stripRows, b.height - start)
            var d = Data([0x10, 0xff, 0xfe, 0x01] + [UInt8](repeating: 0, count: 12) + [0x1d, 0x76, 0x30, 0, UInt8(rowBytes), 0, UInt8(n & 255), UInt8(n >> 8)])
            for y in start..<start + n {
                for xb in 0..<rowBytes {
                    var v: UInt8 = 0
                    for k in 0..<8 where b.px[y * b.width + xb * 8 + k] == 0 { v |= 0x80 >> UInt8(k) }
                    d.append(v)
                }
            }
            return d
        }
    }

    /// How a print looks on paper, roughly, fitted to a photo of a calibration strip (Light, Normal, Dark).
    /// Isolated dots print weaker, and heat fills in the gaps between dense dots.
    /// Display only; print data never uses this.
    static let solid: [Float] = [80, 72, 72], alone: [Float] = [0.2, 0.4, 0.6], fill: [Float] = [108, 192, 192]

    static func preview(_ b: Bitmap, strength: Int) -> CGImage? {
        let w = b.width, h = b.height, k = max(0, min(2, strength))
        // Greys by neighbour count, in half steps 0...12 (6 = all eight neighbours black, diagonals count half).
        let ink: Float = solid[k], weak: Float = alone[k], heat: Float = fill[k]
        var black = [UInt8](), white = [UInt8]()
        for i in 0...12 {
            let part: Float = Float(i) / 12
            let cover: Float = weak + (1 - weak) * part
            black.append(UInt8(255 - (255 - ink) * cover))
            let spread: Float = heat * powf(part, 2.5)
            white.append(UInt8(max(ink, 255 - spread)))
        }
        var o = [UInt8](repeating: 255, count: w * h)
        b.px.withUnsafeBufferPointer { px in
            for y in 0..<h { for x in 0..<w {
                var n = 0
                for yy in max(0, y - 1)...min(h - 1, y + 1) { for xx in max(0, x - 1)...min(w - 1, x + 1) where px[yy * w + xx] == 0 && (xx != x || yy != y) {
                    n += xx == x || yy == y ? 2 : 1
                } }
                o[y * w + x] = px[y * w + x] == 0 ? black[n] : white[n]
            } }
        }
        guard let p = CGDataProvider(data: Data(o) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
