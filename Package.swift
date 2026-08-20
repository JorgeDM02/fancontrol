// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FanControl",       targets: ["FanControlApp"]),
        .executable(name: "FanControlHelper", targets: ["FanControlHelper"]),
    ],
    targets: [
        // ---- C shim: IOKit SMC access ----
        .target(
            name: "SMCShim",
            path: "Sources/SMCShim",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),

        // ---- Shared Swift library ----
        .target(
            name: "FanControlCore",
            dependencies: ["SMCShim"],
            path: "Sources/FanControlCore"
        ),

        // ---- SwiftUI GUI app ----
        .executableTarget(
            name: "FanControlApp",
            dependencies: ["FanControlCore"],
            path: "Sources/FanControlApp",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/FanControlApp/Resources/Info.plist",
                ])
            ]
        ),

        // ---- Privileged helper daemon ----
        .executableTarget(
            name: "FanControlHelper",
            dependencies: ["FanControlCore"],
            path: "Sources/FanControlHelper",
            exclude: ["Resources"]
        ),

        // ---- Tests ----
        .testTarget(
            name: "FanControlCoreTests",
            dependencies: ["FanControlCore"],
            path: "Tests/FanControlCoreTests"
        ),
    ]
)