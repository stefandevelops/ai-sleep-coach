// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SleepCoachAnalysis",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15)
    ],
    products: [
        .library(name: "SleepCoachAnalysis", targets: ["SleepCoachAnalysis"])
    ],
    targets: [
        .target(
            name: "SleepCoachAnalysis",
            path: "Sources/SleepCoachAnalysis"
        ),
        .testTarget(
            name: "SleepCoachAnalysisTests",
            dependencies: ["SleepCoachAnalysis"],
            path: "Tests/SleepCoachAnalysisTests"
        )
    ]
)
