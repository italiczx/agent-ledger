// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentLedger",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentLedger", targets: ["AgentLedger"])
    ],
    targets: [
        .target(
            name: "AgentLedgerCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "AgentLedger",
            dependencies: ["AgentLedgerCore"]
        ),
        .testTarget(
            name: "AgentLedgerCoreTests",
            dependencies: ["AgentLedgerCore"]
        ),
    ]
)
