// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PaymentManager",
    platforms: [
        .macOS(.v13), // or your target version
        .iOS(.v15)
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

