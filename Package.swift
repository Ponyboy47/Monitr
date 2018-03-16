// swift-tools-version:4.0

import PackageDescription

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/IBM-Swift/BlueSignals.git", .upToNextMajor(from: "0.9.50")),
    .package(url: "https://github.com/Ponyboy47/CLI.git", .upToNextMinor(from: "2.1.0")),
    .package(url: "https://github.com/Ponyboy47/Cron-Swift.git", .upToNextMajor(from: "2.1.0")),
    .package(url: "https://github.com/Ponyboy47/Downpour.git", .upToNextMinor(from: "0.5.0")),
    .package(url: "https://github.com/Ponyboy47/PathKit.git", .upToNextMajor(from: "0.9.0")),
    .package(url: "https://github.com/kareman/SwiftShell.git", .upToNextMinor(from: "4.0.0")),
    .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMinor(from: "1.4.0")),
    .package(url: "https://github.com/Ponyboy47/LockSmith.git", .upToNextMinor(from: "0.2.0"))
]
var namedDependencies: [Target.Dependency] = ["Signals", "CLI", "Cron", "Downpour", "PathKit", "SwiftShell", "SwiftyBeaver", "LockSmith"]

#if os(Linux)
dependencies.append(.package(url: "https://github.com/Ponyboy47/inotify.git", .upToNextMinor(from: "0.4.3")))
namedDependencies.append("Inotify")
#endif

let package = Package(
    name: "Plex-Monitr",
    products: [
        .executable(
            name: "monitr",
            targets: ["monitr"])
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "monitr",
            dependencies: namedDependencies)
    ]
)
