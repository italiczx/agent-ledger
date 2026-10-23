// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentLedger",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentLedger", targets: ["AgentLedger"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .target(
            name: "AgentLedgerCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "AgentLedger",
            dependencies: [
                "AgentLedgerCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(
            name: "AgentLedgerCoreTests",
            dependencies: ["AgentLedgerCore"]
        ),
    ]
)
