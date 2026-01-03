// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIChatSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "AIChatSDK",
            targets: ["AIChatSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "AIChatSDK",
            dependencies: [
                "Alamofire",
                "Starscream",
            ],
            path: "Sources"),
        .testTarget(
            name: "AIChatSDKTests",
            dependencies: ["AIChatSDK"],
            path: "Tests"),
    ],
    swiftLanguageVersions: [.v5]
)
