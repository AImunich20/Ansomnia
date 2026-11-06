// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Ansomnia",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        .executableTarget(
            name: "Ansomnia",
            path: "Sources/Ansomnia",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Test-only C target. Its constructor points ANSOMNIA_HOME at a temp
        // directory when the test bundle loads, before any test can log.
        .target(
            name: "AnsomniaTestHome",
            path: "Tests/AnsomniaTestHome"
        ),
        .testTarget(
            name: "AnsomniaTests",
            dependencies: ["Ansomnia", "AnsomniaTestHome"],
            path: "Tests/AnsomniaTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
