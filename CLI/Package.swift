// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cookey",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "cookey", targets: ["CLI"]),
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [
        .package(path: "../Packages/CryptoBox"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/dagronf/QRCode.git", from: "13.0.0")
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "CryptoBox", package: "CryptoBox"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "QRCode", package: "QRCode")
            ],
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "CLI",
            dependencies: ["Core"],
            path: "Sources/CLI"
        )
    ]
)
