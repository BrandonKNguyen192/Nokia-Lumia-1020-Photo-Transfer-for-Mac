import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// =============================================================================
// LookProcessor — apply a decoded LookLUT to a real image (JPEG *or* DNG) and
// write a developed output, entirely with macOS frameworks. No Lightroom.
//
// Colour pipeline:
//   input (JPEG, or a DNG rendered by the system RAW decoder — often tagged
//          Display P3 or another wide/linear space)
//     -> bakeToWorkingSpace(): rasterise ONCE into our working colour space
//        (sRGB by default) so the pixels the cube sees are guaranteed to be in
//        the same encoded space the Look was authored in. This is the critical
//        step: a DNG's CIImage is NOT sRGB, and feeding it straight to the cube
//        samples the LUT at the wrong coordinates (gross colour cast). Baking
//        first adds no extra RAW decode — the rasterisation is the same one the
//        encoder performs — it just pins the colour space.
//     -> CIColorCubeWithColorSpace applies the 3-D LUT on the GPU
//     -> written back out as JPEG / TIFF / PNG.
//
// The original file is never touched; callers write to a separate output path.
// =============================================================================

public enum LookOutputFormat: Equatable {
    case jpeg(quality: Double)
    case tiff
    case png

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .tiff: return "tif"
        case .png:  return "png"
        }
    }
}

public struct LookProcessor {

    /// The colour space the LUT is evaluated in. sRGB matches how these Looks
    /// are authored (display-referred film simulations), and keeps results
    /// consistent regardless of whether the source is a phone JPEG or a freshly
    /// rendered DNG (which the system decoder typically hands us in Display P3).
    public var workingSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public init() {}

    /// Apply `lut` to the image at `inputURL`, writing the graded result to
    /// `outputURL` in the requested format. Returns the output URL on success.
    @discardableResult
    public func apply(lut: LookLUT,
                      to inputURL: URL,
                      outputURL: URL,
                      format: LookOutputFormat) throws -> URL {
        // .applyOrientationProperty honours EXIF orientation so phone portraits
        // don't come out sideways. CIImage is lazy; nothing renders yet.
        guard let input = CIImage(contentsOf: inputURL,
                                  options: [.applyOrientationProperty: true]) else {
            throw LookError.cannotReadImage(inputURL.lastPathComponent)
        }
        guard let graded = grade(input, lut: lut) else {
            throw LookError.cannotRender(outputURL.lastPathComponent)
        }
        let context = CIContext(options: [.workingColorSpace: workingSpace,
                                          .outputColorSpace: workingSpace])
        try write(graded, with: context, to: outputURL, format: format)
        return outputURL
    }

    /// Apply the LUT to an in-memory CIImage (used by the self-test and by
    /// callers that already have a rendered image).
    public func apply(lut: LookLUT, to image: CIImage) -> CIImage? {
        grade(image, lut: lut)
    }

    // MARK: - core

    private func grade(_ image: CIImage, lut: LookLUT) -> CIImage? {
        let src = bakeToWorkingSpace(image)
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = src
        filter.cubeDimension = Float(lut.divisions)
        filter.cubeData = lut.colorCubeRGBAData()
        filter.colorSpace = workingSpace
        return filter.outputImage
    }

    /// Rasterise `image` into `workingSpace` so the cube always samples
    /// coordinates in the encoded space the Look expects. 16-bit sRGB keeps
    /// gradients smooth even when the source is a high-bit-depth RAW. If the
    /// image is already in the working space this is effectively a colour-managed
    /// no-op (just a gamut/transfer confirmation), and crucially it never adds a
    /// second RAW decode — the encoder would rasterise here regardless.
    private func bakeToWorkingSpace(_ image: CIImage) -> CIImage {
        let ctx = CIContext(options: [.workingColorSpace: workingSpace,
                                      .outputColorSpace: workingSpace])
        guard let cg = ctx.createCGImage(image, from: image.extent,
                                         format: .RGBA16, colorSpace: workingSpace) else {
            return image
        }
        return CIImage(cgImage: cg)
    }

    // MARK: - writing

    private func write(_ image: CIImage, with context: CIContext,
                       to url: URL, format: LookOutputFormat) throws {
        let extent = image.extent
        switch format {
        case .jpeg(let quality):
            let opts: [CIImageRepresentationOption: Any] =
                [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
            guard (try? context.writeJPEGRepresentation(of: image, to: url,
                                                        colorSpace: workingSpace,
                                                        options: opts)) != nil else {
                throw LookError.cannotRender(url.lastPathComponent)
            }
        case .tiff:
            guard let cg = context.createCGImage(image, from: extent) else {
                throw LookError.cannotRender(url.lastPathComponent)
            }
            try writeCG(cg, to: url, type: UTType.tiff)
        case .png:
            guard let cg = context.createCGImage(image, from: extent) else {
                throw LookError.cannotRender(url.lastPathComponent)
            }
            try writeCG(cg, to: url, type: UTType.png)
        }
    }

    private func writeCG(_ cg: CGImage, to url: URL, type: UTType) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw LookError.cannotRender(url.lastPathComponent) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw LookError.cannotRender(url.lastPathComponent) }
    }
}
