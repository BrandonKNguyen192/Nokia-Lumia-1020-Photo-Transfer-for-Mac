import Foundation
import Compression

// =============================================================================
// AdobeLookLUT — decode Adobe Camera Raw "Look" LUTs (crs:RGBTable) with NO
// Adobe code and NO Lightroom.
//
// A Cobalt / ACR "Look" .xmp stores its 3-D colour LUT as a proprietary blob:
//
//   crs:RGBTable="<MD5 key>"
//   crs:Table_<MD5 key>="<ASCII-85 (custom alphabet) + zlib payload>"
//
// Decoding pipeline (reverse-engineered from the public XMPconverter project and
// validated byte-for-byte against zlib here):
//
//   1. Pull the blob out of crs:Table_<key>="…".
//   2. Custom base-85 decode (Adobe's 85-char alphabet, little-endian groups of
//      5 chars -> 4 bytes; values wrap mod 2^32 exactly like the C++ original).
//   3. The first 4 decoded bytes are a little-endian uncompressed size; the rest
//      is a zlib stream. Strip the 2-byte zlib header + 4-byte Adler32 trailer
//      and inflate the raw DEFLATE with Apple's Compression framework.
//   4. The inflated block is a 16-byte header + N^3 int16 RGB *deltas*. Each
//      output channel = (delta + neutral-ramp[that channel's axis]) / 65535.
//
// The result is an ordinary 3-D LUT we apply ourselves via CoreImage, so the
// whole look can be rendered standalone — Lightroom is never needed.
// =============================================================================

public enum LookError: Error, CustomStringConvertible {
    case noRGBTable
    case noTableBlob(key: String)
    case shortPayload
    case inflateMismatch(produced: Int, expected: Int)
    case badHeader(channels: Int, divisions: Int)
    case cannotReadImage(String)
    case cannotRender(String)

    public var description: String {
        switch self {
        case .noRGBTable:                 return "Not an ACR Look profile (no crs:RGBTable)."
        case .noTableBlob(let k):         return "Profile is missing its crs:Table_\(k) LUT blob."
        case .shortPayload:               return "LUT payload is too short to be valid."
        case .inflateMismatch(let p, let e): return "zlib inflate produced \(p) bytes, expected \(e)."
        case .badHeader(let c, let d):    return "Unsupported LUT header (channels=\(c), divisions=\(d))."
        case .cannotReadImage(let p):     return "Could not read image: \(p)"
        case .cannotRender(let p):        return "Could not render output: \(p)"
        }
    }
}

public struct LookLUT {
    /// Display name parsed from the profile (crs:Name) or the file name.
    public let name: String
    /// Cube edge length (typically 32; ACR caps Looks at 32).
    public let divisions: Int
    /// Flat RGB outputs in [0,1], indexed `r + g*N + b*N*N` (red fastest — the
    /// standard .cube ordering). One SIMD3 per grid node.
    let rgb: [SIMD3<Float>]

    public var cubeDimension: Int { divisions }

    @inline(__always)
    func index(_ r: Int, _ g: Int, _ b: Int) -> Int {
        r + g * divisions + b * divisions * divisions
    }

    /// Trilinear sample of the LUT for an input colour in [0,1]. This is the
    /// ground-truth reference the GPU CIColorCube path is verified against.
    public func sample(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
        let n = divisions
        let f = Float(n - 1)
        func axis(_ v: Float) -> (Int, Int, Float) {
            let c = min(max(v, 0), 1) * f
            let lo = Int(c.rounded(.down))
            let loC = min(max(lo, 0), n - 1)
            let hiC = min(loC + 1, n - 1)
            return (loC, hiC, c - Float(loC))
        }
        let (r0, r1, tr) = axis(r)
        let (g0, g1, tg) = axis(g)
        let (b0, b1, tb) = axis(b)
        func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
        let c000 = rgb[index(r0, g0, b0)], c100 = rgb[index(r1, g0, b0)]
        let c010 = rgb[index(r0, g1, b0)], c110 = rgb[index(r1, g1, b0)]
        let c001 = rgb[index(r0, g0, b1)], c101 = rgb[index(r1, g0, b1)]
        let c011 = rgb[index(r0, g1, b1)], c111 = rgb[index(r1, g1, b1)]
        let c00 = lerp(c000, c100, tr), c10 = lerp(c010, c110, tr)
        let c01 = lerp(c001, c101, tr), c11 = lerp(c011, c111, tr)
        let c0 = lerp(c00, c10, tg), c1 = lerp(c01, c11, tg)
        return lerp(c0, c1, tb)
    }

    /// Cube data laid out for `CIColorCubeWithColorSpace`: N^3 RGBA float
    /// quadruplets, red varying fastest, then green, then blue (matches the
    /// decoded ordering — verified by the CLI `--selftest`). Alpha is 1.
    public func colorCubeRGBAData() -> Data {
        let n = divisions
        var floats = [Float]()
        floats.reserveCapacity(n * n * n * 4)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let c = rgb[index(r, g, b)]
                    floats.append(c.x); floats.append(c.y); floats.append(c.z); floats.append(1)
                }
            }
        }
        return floats.withUnsafeBytes { Data($0) }
    }
}

/// Namespace (caseless enum) of static decoding helpers.
public enum AdobeLookLUT {

    // Adobe's custom 85-symbol alphabet maps to this 96-entry lookup (indexed by
    // `char - 32`); entries > 85 mean "skip this character".
    private static let decodeTable: [UInt8] = [
        0xFF,0x44,0xFF,0x54,0x53,0x52,0xFF,0x49,0x4B,0x4C,0x46,0x41,0xFF,0x3F,0x3E,0x45,
        0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x40,0xFF,0xFF,0x42,0xFF,0x47,
        0x51,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,0x2C,0x2D,0x2E,0x2F,0x30,0x31,0x32,
        0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x4D,0xFF,0x4E,0x43,0xFF,
        0x48,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,
        0x19,0x1A,0x1B,0x1C,0x1D,0x1E,0x1F,0x20,0x21,0x22,0x23,0x4F,0x4A,0x50,0xFF,0xFF
    ]

    /// Decode a Look LUT from the raw text of an .xmp profile.
    public static func decode(xmpText: String, fallbackName: String) throws -> LookLUT {
        // crs:RGBTable="<key>"  then  crs:Table_<key>="<blob>"
        guard let key = firstCapture(#"crs:RGBTable="([0-9A-Fa-f]+)""#, in: xmpText) else {
            throw LookError.noRGBTable
        }
        let blobPattern = "crs:Table_" + NSRegularExpression.escapedPattern(for: key) + #"="([^"]*)""#
        guard let blob = firstCapture(blobPattern, in: xmpText) else {
            throw LookError.noTableBlob(key: key)
        }
        let name = firstCapture(#"<crs:Name>\s*<rdf:Alt>\s*<rdf:li xml:lang="x-default">([^<]*)<"#, in: xmpText)
            ?? fallbackName

        let decoded = base85Decode(blob)
        guard decoded.count > 4 else { throw LookError.shortPayload }

        let expected = Int(UInt32(decoded[0])
                         | UInt32(decoded[1]) << 8
                         | UInt32(decoded[2]) << 16
                         | UInt32(decoded[3]) << 24)
        let lut = try inflateZlib(decoded.subdata(in: 4..<decoded.count), expectedSize: expected)
        return try buildLUT(lut, name: name)
    }

    /// Convenience: decode straight from a profile file URL.
    public static func decode(xmpAt url: URL) throws -> LookLUT {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try decode(xmpText: text,
                          fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    // MARK: - base-85

    private static func base85Decode(_ s: String) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(s.count * 4 / 5 + 8)
        var phase = 0
        var value: UInt32 = 0
        for scalar in s.unicodeScalars {
            let o = scalar.value
            guard o >= 32, o <= 127 else { continue }
            let d = decodeTable[Int(o - 32)]
            guard d <= 85 else { continue }
            let dv = UInt32(d)
            phase += 1
            switch phase {
            case 1: value = dv
            case 2: value = value &+ dv &* 85
            case 3: value = value &+ dv &* 7225          // 85^2
            case 4: value = value &+ dv &* 614125        // 85^3
            case 5:
                value = value &+ dv &* 52200625          // 85^4 (wraps mod 2^32, like the C++)
                out.append(UInt8(value & 0xFF))
                out.append(UInt8((value >> 8) & 0xFF))
                out.append(UInt8((value >> 16) & 0xFF))
                out.append(UInt8((value >> 24) & 0xFF))
                phase = 0; value = 0
            default: break
            }
        }
        // Partial trailing group: n chars encode n-1 bytes (low bytes first).
        switch phase {
        case 4:
            out.append(UInt8(value & 0xFF)); out.append(UInt8((value >> 8) & 0xFF))
            out.append(UInt8((value >> 16) & 0xFF))
        case 3:
            out.append(UInt8(value & 0xFF)); out.append(UInt8((value >> 8) & 0xFF))
        case 2:
            out.append(UInt8(value & 0xFF))
        default: break
        }
        return Data(out)
    }

    // MARK: - zlib (raw DEFLATE via Compression)

    private static func inflateZlib(_ zlibStream: Data, expectedSize: Int) throws -> Data {
        // zlib = 2-byte header + raw DEFLATE + 4-byte Adler32. COMPRESSION_ZLIB
        // is raw DEFLATE, so strip the 6 wrapper bytes. No scratch buffer is
        // needed for the zlib codec.
        guard zlibStream.count > 6, expectedSize > 0 else { throw LookError.shortPayload }
        let rawLen = zlibStream.count - 6
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { dst.deallocate() }

        let produced = zlibStream.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int in
            let base = buf.bindMemory(to: UInt8.self).baseAddress!
            return compression_decode_buffer(dst, expectedSize, base + 2, rawLen,
                                             nil, COMPRESSION_ZLIB)
        }
        guard produced == expectedSize else {
            throw LookError.inflateMismatch(produced: produced, expected: expectedSize)
        }
        return Data(bytes: dst, count: produced)
    }

    // MARK: - LUT assembly

    private static func buildLUT(_ lut: Data, name: String) throws -> LookLUT {
        // Header (little-endian uint32 x4): [_, _, channels, divisions].
        guard lut.count >= 16 else { throw LookError.shortPayload }
        let channels = Int(lut[8])
        let n = Int(lut[12])
        guard channels == 3, n >= 2, n <= 64 else { throw LookError.badHeader(channels: channels, divisions: n) }
        let needed = 16 + n * n * n * 3 * 2
        guard lut.count >= needed else { throw LookError.shortPayload }

        // Neutral ramp the int16 deltas are relative to (rounded, per axis step).
        var ramp = [Int](repeating: 0, count: n)
        for idx in 0..<n { ramp[idx] = (idx * 0xFFFF + (n >> 1)) / (n - 1) }

        var rgb = [SIMD3<Float>](repeating: .zero, count: n * n * n)
        lut.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let p = raw.bindMemory(to: UInt8.self).baseAddress!
            for b in 0..<n {
                for g in 0..<n {
                    for r in 0..<n {
                        let off = 16 + (r + g * n + b * n * n) * 6
                        let dr = Int16(bitPattern: UInt16(p[off])     | UInt16(p[off + 1]) << 8)
                        let dg = Int16(bitPattern: UInt16(p[off + 2]) | UInt16(p[off + 3]) << 8)
                        let db = Int16(bitPattern: UInt16(p[off + 4]) | UInt16(p[off + 5]) << 8)
                        // (uint16)(delta + ramp) replicates the original wrap, then /65535.
                        let R = Float((Int(dr) + ramp[r]) & 0xFFFF) / 65535.0
                        let G = Float((Int(dg) + ramp[g]) & 0xFFFF) / 65535.0
                        let B = Float((Int(db) + ramp[b]) & 0xFFFF) / 65535.0
                        rgb[r + g * n + b * n * n] = SIMD3<Float>(R, G, B)
                    }
                }
            }
        }
        return LookLUT(name: name, divisions: n, rgb: rgb)
    }

    // MARK: - regex helper

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }
}
