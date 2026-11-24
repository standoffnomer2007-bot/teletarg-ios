// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeleTarg",
    defaultLocalization: "ru",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TeleTargCore",
            targets: ["TeleTargCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/Swiftgram/TDLibKit.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "TeleTargCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "TDLibKit", package: "TDLibKit")
            ],
            path: "Sources/TeleTarg/Core",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
