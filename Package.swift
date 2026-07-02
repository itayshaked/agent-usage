// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentUsage",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AgentUsage",
            path: "Sources/AgentUsage",
            resources: [.copy("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
