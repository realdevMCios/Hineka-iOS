// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hineka",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "HinekaUI",
            targets: ["HinekaUI"]
        )
    ],
    targets: [
        .target(
            name: "HinekaUI",
            path: "App",
            exclude: [
                "Hineka/HinekaApp.swift",
                "Hineka/README.md",
                "Library/README.md",
                "Wallet/README.md"
            ]
        )
    ]
)
