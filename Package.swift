// swift-tools-version: 6.2
import Foundation
import PackageDescription

// Use a sibling MenuBarKit checkout when present (monorepo-style development),
// otherwise resolve it from GitHub. SwiftPM caches the evaluated manifest, so
// after adding or removing the sibling run `swift package reset` once.
let useLocalMenuBarKit = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/../MenuBarKit/Package.swift"
)

let package = Package(
    name: "DisplayAnchor",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    dependencies: [
        useLocalMenuBarKit
            ? .package(path: "../MenuBarKit")
            : .package(url: "https://github.com/gabriarceus/MenuBarKit.git", from: "1.2.0"),
        // Binary XCFramework: `build.sh` embeds it into the bundle, since a
        // hand-assembled .app gets none of Xcode's copy-frameworks phase.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "DisplayAnchor",
            dependencies: [
                "MenuBarKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DisplayAnchorTests",
            dependencies: ["DisplayAnchor"]
        ),
    ]
)
