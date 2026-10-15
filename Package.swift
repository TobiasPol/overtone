// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Overtone",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "Overtone", targets: ["Overtone"]),
    ],
    targets: [
        // Real-time audio code lives in C so the IO thread never touches ARC, locks or allocation.
        .target(
            name: "OvertoneDSP",
            path: "src/OvertoneDSP",
            cSettings: [.define("OT_ENABLE_ASSERTS", .when(configuration: .debug))],
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
            ]
        ),
        .executableTarget(
            name: "Overtone",
            dependencies: ["OvertoneDSP"],
            path: "src/Overtone",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreAudioKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "OvertoneDSPTests",
            dependencies: ["OvertoneDSP"],
            path: "tests/OvertoneDSPTests"
        ),
        .testTarget(
            name: "OvertoneTests",
            dependencies: ["Overtone", "OvertoneDSP"],
            path: "tests/OvertoneTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
