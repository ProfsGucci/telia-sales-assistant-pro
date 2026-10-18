// swift-tools-version:5.9
// Root package used for Linux-side unit testing of the platform-neutral Core target.
// The iOS app builds from the Xcode project (TeliaSalesAssistantPro.xcodeproj);
// this Package.swift compiles the exact same Core sources for `swift test`.
import PackageDescription

let package = Package(
    name: "TeliaCore",
    targets: [
        .target(
            name: "TeliaCore",
            path: "TeliaSalesAssistantPro/Core"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["TeliaCore"],
            path: "Tests/CoreTests"
        ),
    ]
)
