// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PinyinMatcher",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PinyinMatcher", targets: ["PinyinMatcher"]),
    ],
    targets: [
        .target(name: "PinyinMatcher"),
        .testTarget(name: "PinyinMatcherTests", dependencies: ["PinyinMatcher"]),
    ]
)
