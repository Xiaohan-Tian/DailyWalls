// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DailyWalls",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DailyWalls",
            path: "Sources/DailyWalls",
            exclude: [
                "Resources/AppIcon.png"
            ],
            resources: [
                .copy("Resources/menubar_icon.png")
            ]
        )
    ]
)
