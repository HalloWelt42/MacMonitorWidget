// swift-tools-version: 6.0
import PackageDescription

// SwiftPM baut nur das Menüleisten-Programm (Shared + App) für den schnellen
// --dump/--snapshot-Pfad. Das Schreibtisch-Widget wird über XcodeGen gebaut, weil
// SwiftPM keine App-Erweiterung (.appex) bündeln kann.
let package = Package(
    name: "MacMonitorWidget",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacMonitorWidget",
            path: "Sources",
            exclude: ["Widget", "App/Info.plist", "App/App.entitlements"],
            sources: ["Shared", "App"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
