// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "MusicDossier",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MusicDossierKit",
            targets: ["MusicDossierKit"]
        ),
        .executable(
            name: "MusicDossierApp",
            targets: ["MusicDossierApp"]
        ),
        .executable(
            name: "MusicDossierSmokeTests",
            targets: ["MusicDossierSmokeTests"]
        ),
    ],
    targets: [
        .target(
            name: "MusicDossierKit",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "MusicDossierApp",
            dependencies: ["MusicDossierKit"]
        ),
        .executableTarget(
            name: "MusicDossierSmokeTests",
            dependencies: ["MusicDossierKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
