// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ImageForgeGUI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ImageForgeGUI",
            path: "Sources/ImageForgeGUI"
        ),
        .testTarget(
            name: "ImageForgeGUITests",
            dependencies: ["ImageForgeGUI"],
            path: "Tests/ImageForgeGUITests"
        ),
    ]
)
