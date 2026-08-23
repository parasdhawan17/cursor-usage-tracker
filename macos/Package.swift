// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CursorUsageMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CursorUsageMenuBar", targets: ["CursorUsageMenuBar"]),
    ],
    targets: [
        .executableTarget(
            name: "CursorUsageMenuBar",
            path: "Sources/CursorUsageMenuBar"
        ),
        .testTarget(
            name: "CursorUsageMenuBarTests",
            dependencies: ["CursorUsageMenuBar"],
            path: "Tests/CursorUsageMenuBarTests"
        ),
    ]
)
