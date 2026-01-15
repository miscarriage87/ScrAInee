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
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2")
    ],
    targets: [
        .executableTarget(
            name: "Scrainee",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeychainAccess", package: "KeychainAccess")
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
