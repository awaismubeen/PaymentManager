// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PaymentManager",
    platforms: [
        .macOS(.v12_0) // or your target version
    ],
    products: [
        .library(
            name: "PaymentManager",
            targets: ["PaymentManager"]
        ),
    ],
    targets: [
        .target(
            name: "PaymentManager",
            path: "Sources/PaymentManager"
        ),
    ]
)

