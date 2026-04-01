// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShiftFlowApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ShiftFlowApp", targets: ["ShiftFlowApp"])
    ],
    targets: [
        .executableTarget(
            name: "ShiftFlowApp",
            path: "Sources"
        )
    ]
)
