// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hineka",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .library(
            name: "HinekaUI",
            targets: ["HinekaUI"]
        ),
        .library(
            name: "HinekaJavaRuntime",
            targets: ["HinekaJavaRuntime"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "OpenJDK",
            path: ".runtime-build/OpenJDK.xcframework"
        ),
        .target(
            name: "HinekaJavaRuntimeBridge",
            dependencies: ["OpenJDK"],
            path: "App/Runtime/Bridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "HinekaJavaRuntime",
            dependencies: ["HinekaJavaRuntimeBridge"],
            path: "App/Runtime/Swift",
            resources: [
                .copy("Resources/lib"),
                .copy("Resources/HinekaRuntimeSmokeTest.jar"),
                .copy("Resources/openjdk-runtime-manifest.txt")
            ]
        ),
        .target(
            name: "HinekaUI",
            dependencies: ["HinekaJavaRuntime"],
            path: "App",
            exclude: [
                "Hineka/HinekaApp.swift",
                "Hineka/README.md",
                "Library/README.md",
                "Wallet/README.md",
                "Runtime"
            ]
        )
    ]
)
