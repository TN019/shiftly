// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShiftlyApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ShiftlyApp", targets: ["ShiftlyApp"])
    ],
    targets: [
        .executableTarget(
            name: "ShiftlyApp",
            path: "Sources"
        )
    ]
)
