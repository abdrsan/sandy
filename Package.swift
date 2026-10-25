// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sandy",
    // macOS 15 for Translation.framework, which the translate tab runs on.
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "SandyMobileCore", targets: ["SandyMobileCore"]),
        .executable(name: "Sandy", targets: ["Sandy"]),
        // Хелпер мониторинга AI-сессий. bundle.sh кладёт его в
        // Sandy.app/Contents/Helpers/sandy-agent; см. docs/agent-bridge.md.
        .executable(name: "sandy-agent", targets: ["SandyAgentBridge"])
    ],
    targets: [
        .target(name: "SandyMobileCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "SandyMobileCoreTests", dependencies: ["SandyMobileCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "Sandy",
            dependencies: ["SandyMobileCore"],
            path: "Sources/Sandy",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Разбор событий Claude Code и Codex без UI и без AppKit: всё, что
        // можно проверить на фикстурах, живёт здесь.
        .target(
            name: "AgentBridgeCore",
            path: "Sources/AgentBridgeCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SandyAgentBridge",
            dependencies: ["AgentBridgeCore", "SandyMobileCore"],
            path: "Sources/SandyAgentBridge",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Только чистые сторы — разбор файла, дедупликация, порядок. Панель
        // сюда не входит и не должна: вырез, наведение и раскладка рельса
        // проверяются глазами, а тест на них врал бы чаще, чем ловил (#65).
        .testTarget(
            name: "SandyTests",
            dependencies: ["Sandy"],
            path: "Tests/SandyTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AgentBridgeCoreTests",
            dependencies: ["AgentBridgeCore"],
            path: "Tests/AgentBridgeCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
