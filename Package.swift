// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PaymentManager",
    platforms: [
        .macOS(.v10_13) // or your target version
    ],
    products: [
        .library(
            name: "AMPlaceholder",
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

