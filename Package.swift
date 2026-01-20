// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PaymentManager",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "PaymentManager",
            targets: ["PaymentManager"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/marmelroy/Localize-Swift.git",
            from: "3.0.0"
        )
    ],
    targets: [
        .target(
            name: "PaymentManager",
            dependencies: [
                .product(name: "Localize_Swift", package: "Localize-Swift")
            ],
            path: "Sources/PaymentManager"
        ),
    ]
)

