// swift-tools-version:5.9
import PackageDescription

// The app's game logic, kept free of UI so it can be unit tested on its own.
let package = Package(
    name: "PokerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PokerCore", targets: ["PokerCore"])],
    targets: [
        .target(name: "PokerCore"),
        .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
    ]
)
