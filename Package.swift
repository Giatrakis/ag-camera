// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ag-camera",
    platforms: [
        .iOS(.v18)
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
        )
    ]
)
