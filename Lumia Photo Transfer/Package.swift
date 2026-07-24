// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LumiaPhotoTransfer",
    platforms: [.macOS(.v13)],
    targets: [
        // Standalone Adobe "Look" LUT decoder + CoreImage renderer. Shared by the
        // app and the lumia-look CLI so both grade photos with zero Adobe software.
        .target(
            name: "LookKit",
            path: "Sources/LookKit"
        ),
        .executableTarget(
            name: "LumiaPhotoTransfer",
            dependencies: ["LookKit"],
            path: "Sources",
            exclude: ["LookKit", "lumia-look"]
        ),
        .executableTarget(
            name: "lumia-look",
            dependencies: ["LookKit"],
            path: "Sources/lumia-look"
        ),
    ]
)
