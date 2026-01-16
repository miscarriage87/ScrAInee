// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scrainee",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Scrainee", targets: ["Scrainee"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        // Explizite transitive Dependencies für WhisperKit (Swift 6 Kompatibilität)
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "0.1.12")
    ],
    targets: [
        .executableTarget(
            name: "Scrainee",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Scrainee",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ScraineeTests",
            dependencies: [
                "Scrainee",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/ScraineeTests",
            exclude: [
                "Fixtures"
            ]
        )
    ]
)
