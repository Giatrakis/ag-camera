// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ag-camera",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(
            name: "AGCamera",
            targets: ["AGCamera"]
        )
    ],
    targets: [
        .target(
            name: "AGCamera",
            dependencies: [],
            path: "Sources/AGCamera",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "AGCameraTests",
            dependencies: ["AGCamera"],
            path: "Tests/AGCameraTests"
        )
    ]
)
