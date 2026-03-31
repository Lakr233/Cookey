// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CryptoBox",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "CryptoBox", targets: ["CryptoBox"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "CryptoBox",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
    ]
)
