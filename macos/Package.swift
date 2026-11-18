// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeskBot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DeskBotCore", targets: ["DeskBotCore"]),
        .executable(name: "DeskBot", targets: ["DeskBot"]),
    ],
    targets: [
        // Платформоос хамааралгүй логик — AppKit/SwiftUI импортлохгүй.
        .target(name: "DeskBotCore"),
        .executableTarget(name: "DeskBot", dependencies: ["DeskBotCore"]),
        // XCTest нь Command Line Tools-д байхгүй тул swift-testing (import Testing) ашиглана.
        .testTarget(name: "DeskBotCoreTests", dependencies: ["DeskBotCore"]),
    ]
)
