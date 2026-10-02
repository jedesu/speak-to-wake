// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PinyinMatcher", targets: ["PinyinMatcher"]),
        .library(name: "WakeCore", targets: ["WakeCore"]),
    ],
    targets: [
        .target(name: "PinyinMatcher"),
        .target(name: "WakeCore"),
        .testTarget(name: "PinyinMatcherTests", dependencies: ["PinyinMatcher"]),
        .testTarget(name: "WakeCoreTests", dependencies: ["WakeCore"]),
    ]
)
