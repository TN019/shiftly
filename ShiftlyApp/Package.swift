// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShiftlyApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ShiftlyApp", targets: ["ShiftlyApp"]),
        .library(name: "ShiftlyKit", targets: ["ShiftlyKit"]),
    ],
    targets: [
        // Domain core: models, config/data file access, script runners.
        // Must stay free of SwiftUI/AppKit so the future CLI can reuse it.
        .target(
            name: "ShiftlyKit",
            path: "Sources/ShiftlyKit"
        ),
        .executableTarget(
            name: "ShiftlyApp",
            dependencies: ["ShiftlyKit"],
            path: "Sources/ShiftlyApp",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist (calendar permission strings) so the bare
                // executable can prompt for EventKit access on its own.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ShiftlyApp/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "ShiftlyKitTests",
            dependencies: ["ShiftlyKit"],
            path: "Tests/ShiftlyKitTests"
        ),
    ]
)
