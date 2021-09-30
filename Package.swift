// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PublicCalendar",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13)],
    products: [
        .library(
            name: "PublicCalendar",
            targets: ["PublicCalendar"]),
    ],
    dependencies: [
        .package(name: "AutomatedFetcher", url: "https://github.com/helsingborg-stad/spm-automated-fetcher", from: "0.1.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.3.2"),
    ],
    targets: [
        .target(
            name: "PublicCalendar",
            dependencies: ["SwiftSoup","AutomatedFetcher"]),
        .testTarget(
            name: "PublicCalendarTests",
            dependencies: ["PublicCalendar"]),
    ]
)
