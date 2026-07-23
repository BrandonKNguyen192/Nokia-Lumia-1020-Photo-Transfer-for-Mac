import Foundation
import CoreImage
import CoreGraphics
import LookKit

// =============================================================================
// lumia-look — standalone CLI that applies a Cobalt / ACR "Look" .xmp to JPEG or
// DNG files using the same LookKit the app uses. Lets lumia-transfer.sh (and any
// terminal workflow) grade photos with zero Adobe software.
//
//   lumia-look --profile P.xmp --input photo.jpg --output graded.jpg
//   lumia-look --profile P.xmp --input-dir RAW/ --output-dir GRADED/ --format jpg
//   lumia-look --selftest --profile P.xmp        # verify GPU LUT vs reference
// =============================================================================

struct Options {
    var profile: String = ""
    var input: String = ""
    var output: String = ""
    var inputDir: String = ""
    var outputDir: String = ""
    var format: String = "jpg"
    var quality: Double = 0.95
    var selftest = false
}

func usage() {
    print("""
    lumia-look — apply an ACR/Cobalt Look (.xmp) to photos without Lightroom.

    USAGE:
      lumia-look --profile LOOK.xmp --input IN.jpg --output OUT.jpg
      lumia-look --profile LOOK.xmp --input-dir DIR --output-dir DIR [--format jpg|tiff|png]
      lumia-look --selftest --profile LOOK.xmp

    OPTIONS:
      --profile PATH     Look profile (.xmp) — required
      --input PATH       single image to grade (JPEG or DNG)
      --output PATH      output path (default: <input>_look.<format>)
      --input-dir DIR    grade every image in DIR
      --output-dir DIR   where graded files go (default: <input-dir>/Processed)
      --format FMT       jpg | tiff | png (default jpg)
      --quality Q        JPEG quality 0..1 (default 0.95)
      --selftest         verify the GPU color-cube against the reference LUT
    """)
}

// --- arg parsing -------------------------------------------------------------
var opts = Options()
var args = Array(CommandLine.arguments.dropFirst())
var i = 0
func nextValue(_ flag: String) -> String? {
    guard i + 1 < args.count else {
        FileHandle.standardError.write(Data("Missing value for \(flag)\n".utf8)); return nil
    }
    i += 1; return args[i]
}
while i < args.count {
    let a = args[i]
    switch a {
    case "--profile":    if let v = nextValue(a) { opts.profile = v }
    case "--input":      if let v = nextValue(a) { opts.input = v }
    case "--output":     if let v = nextValue(a) { opts.output = v }
    case "--input-dir":  if let v = nextValue(a) { opts.inputDir = v }
    case "--output-dir": if let v = nextValue(a) { opts.outputDir = v }
    case "--format":     if let v = nextValue(a) { opts.format = v.lowercased() }
    case "--quality":    if let v = nextValue(a) { opts.quality = Double(v) ?? 0.95 }
    case "--selftest":   opts.selftest = true
    case "--help", "-h": usage(); exit(0)
    default:
        FileHandle.standardError.write(Data("Unknown argument: \(a)\n".utf8)); usage(); exit(2)
    }
    i += 1
}

func outputFormat() -> LookOutputFormat {
    switch opts.format {
    case "tif", "tiff": return .tiff
    case "png":         return .png
    default:            return .jpeg(quality: opts.quality)
    }
}

let imageExts: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "dng", "nef", "arw", "cr2", "orf"]

guard !opts.profile.isEmpty else { usage(); exit(2) }
let profileURL = URL(fileURLWithPath: (opts.profile as NSString).expandingTildeInPath)
guard FileManager.default.fileExists(atPath: profileURL.path) else {
    FileHandle.standardError.write(Data("Profile not found: \(profileURL.path)\n".utf8)); exit(1)
}

// --- decode the look once ----------------------------------------------------
let lut: LookLUT
do {
    lut = try AdobeLookLUT.decode(xmpAt: profileURL)
} catch {
    FileHandle.standardError.write(Data("Failed to decode profile: \(error)\n".utf8)); exit(1)
}
print("Loaded look: \(lut.name)  (\(lut.divisions)×\(lut.divisions)×\(lut.divisions) cube)")

// --- selftest ----------------------------------------------------------------
if opts.selftest {
    let ok = runSelfTest(lut: lut)
    exit(ok ? 0 : 1)
}

// --- single or batch ---------------------------------------------------------
let processor = LookProcessor()

if !opts.input.isEmpty {
    let inURL = URL(fileURLWithPath: (opts.input as NSString).expandingTildeInPath)
    let outURL: URL
    if !opts.output.isEmpty {
        outURL = URL(fileURLWithPath: (opts.output as NSString).expandingTildeInPath)
    } else {
        let base = inURL.deletingPathExtension().lastPathComponent
        outURL = inURL.deletingLastPathComponent()
            .appendingPathComponent("\(base)_look.\(outputFormat().fileExtension)")
    }
    do {
        _ = try processor.apply(lut: lut, to: inURL, outputURL: outURL, format: outputFormat())
        print("✓ \(inURL.lastPathComponent) → \(outURL.path)")
    } catch {
        FileHandle.standardError.write(Data("✗ \(inURL.lastPathComponent): \(error)\n".utf8)); exit(1)
    }
    exit(0)
}

if !opts.inputDir.isEmpty {
    let inDir = URL(fileURLWithPath: (opts.inputDir as NSString).expandingTildeInPath)
    let outDir = opts.outputDir.isEmpty
        ? inDir.appendingPathComponent("Processed", isDirectory: true)
        : URL(fileURLWithPath: (opts.outputDir as NSString).expandingTildeInPath)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let files = (try? FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)) ?? []
    let images = files.filter { imageExts.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !images.isEmpty else {
        FileHandle.standardError.write(Data("No images in \(inDir.path)\n".utf8)); exit(1)
    }
    var done = 0, failed = 0
    for (idx, img) in images.enumerated() {
        let base = img.deletingPathExtension().lastPathComponent
        let outURL = outDir.appendingPathComponent("\(base).\(outputFormat().fileExtension)")
        do {
            _ = try processor.apply(lut: lut, to: img, outputURL: outURL, format: outputFormat())
            done += 1
            print("[\(idx + 1)/\(images.count)] ✓ \(img.lastPathComponent)")
        } catch {
            failed += 1
            FileHandle.standardError.write(Data("[\(idx + 1)/\(images.count)] ✗ \(img.lastPathComponent): \(error)\n".utf8))
        }
    }
    print("Done: \(done) graded, \(failed) failed → \(outDir.path)")
    exit(failed == 0 ? 0 : 1)
}

usage()
exit(2)

// =============================================================================
// Self-test: prove the GPU CIColorCube path matches the reference trilinear LUT.
// We feed a strip of known sRGB colours through both and compare the pixels. If
// the cube's axis order were wrong, asymmetric colours would diverge by large
// amounts (tens of 8-bit levels); a correct order stays within 8-bit rounding.
// =============================================================================
func runSelfTest(lut: LookLUT) -> Bool {
    print("Self-test: comparing GPU CIColorCube vs reference trilinear…")
    var testColors: [SIMD3<Float>] = [
        SIMD3(0, 0, 0), SIMD3(1, 1, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1),
        SIMD3(1, 1, 0), SIMD3(0, 1, 1), SIMD3(1, 0, 1), SIMD3(0.5, 0.5, 0.5),
        SIMD3(0.18, 0.18, 0.18), SIMD3(0.9, 0.75, 0.6), SIMD3(0.4, 0.6, 0.85),
        SIMD3(0.25, 0.5, 0.25), SIMD3(0.7, 0.2, 0.3), SIMD3(0.05, 0.4, 0.6),
    ]
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<17 {
        testColors.append(SIMD3(Float.random(in: 0...1, using: &rng),
                                Float.random(in: 0...1, using: &rng),
                                Float.random(in: 0...1, using: &rng)))
    }

    let n = testColors.count
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    let bpr = n * 4
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    // 1×n 8-bit sRGB strip holding the exact test colours.
    let inData = UnsafeMutableRawPointer.allocate(byteCount: bpr, alignment: 16)
    defer { inData.deallocate() }
    guard let inCtx = CGContext(data: inData, width: n, height: 1, bitsPerComponent: 8,
                                bytesPerRow: bpr, space: srgb, bitmapInfo: bitmapInfo) else {
        print("  ✗ could not create input CGContext"); return false
    }
    let inPx = inData.assumingMemoryBound(to: UInt8.self)
    for k in 0..<n {
        let c = testColors[k]
        inPx[k*4 + 0] = UInt8((c.x * 255).rounded())
        inPx[k*4 + 1] = UInt8((c.y * 255).rounded())
        inPx[k*4 + 2] = UInt8((c.z * 255).rounded())
        inPx[k*4 + 3] = 255
    }
    _ = inCtx
    guard let inCG = inCtx.makeImage() else { print("  ✗ input makeImage failed"); return false }
    let input = CIImage(cgImage: inCG)

    let processor = LookProcessor()
    guard let graded = processor.apply(lut: lut, to: input) else {
        print("  ✗ color cube produced no output"); return false
    }

    let context = CIContext(options: [.outputColorSpace: srgb])
    let bounds = CGRect(x: 0, y: 0, width: n, height: 1)
    guard let outCG = context.createCGImage(graded, from: bounds) else {
        print("  ✗ createCGImage failed"); return false
    }
    let outData = UnsafeMutableRawPointer.allocate(byteCount: bpr, alignment: 16)
    defer { outData.deallocate() }
    guard let outCtx = CGContext(data: outData, width: n, height: 1, bitsPerComponent: 8,
                                 bytesPerRow: bpr, space: srgb, bitmapInfo: bitmapInfo) else {
        print("  ✗ could not create output CGContext"); return false
    }
    outCtx.draw(outCG, in: bounds)
    let outPx = outData.assumingMemoryBound(to: UInt8.self)

    var maxErr: Float = 0
    var worst = (idx: -1, got: SIMD3<Float>.zero, want: SIMD3<Float>.zero)
    for k in 0..<n {
        let got = SIMD3<Float>(Float(outPx[k*4]) / 255,
                               Float(outPx[k*4 + 1]) / 255,
                               Float(outPx[k*4 + 2]) / 255)
        let c = testColors[k]
        // Compare against the LUT sampled at the *8-bit-quantized* input the GPU
        // actually saw; a steep LUT slope otherwise amplifies the +/-0.002 input
        // quantization into a misleading output delta.
        let cq = SIMD3<Float>(Float(UInt8((c.x * 255).rounded())) / 255,
                              Float(UInt8((c.y * 255).rounded())) / 255,
                              Float(UInt8((c.z * 255).rounded())) / 255)
        let want = lut.sample(cq.x, cq.y, cq.z)
        let err = max(max(abs(got.x - want.x), abs(got.y - want.y)), abs(got.z - want.z))
        if err > maxErr { maxErr = err; worst = (k, got, want) }
    }
    print(String(format: "  tested %d colours, max channel error = %.5f (8-bit quantum ≈ 0.004)", n, maxErr))
    if maxErr > 0.02 {
        print(String(format: "  ✗ MISMATCH at colour %d: GPU=(%.4f,%.4f,%.4f) ref=(%.4f,%.4f,%.4f)",
                     worst.idx, worst.got.x, worst.got.y, worst.got.z,
                     worst.want.x, worst.want.y, worst.want.z))
        print("  → cube axis order or colour-space wiring is wrong.")
        return false
    }
    print("  ✓ GPU color cube matches the reference LUT (axis order verified).")
    return true
}
