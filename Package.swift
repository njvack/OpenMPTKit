// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenMPTKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "OpenMPTKit", targets: ["OpenMPTKit"]),
        .executable(name: "mptinfo", targets: ["mptinfo"]),
        .executable(name: "mptplay", targets: ["mptplay"]),
    ],
    targets: [
        .target(
            name: "Clibopenmpt",
            path: "Sources/Clibopenmpt",
            exclude: [
                "soundlib/plugins/dmo",
                "libopenmpt/xmp-openmpt",
                "libopenmpt/in_openmpt",
                "libopenmpt/plugin-common",
                "libopenmpt/libopenmpt_test",
                "libopenmpt/libopenmpt_version.rc",
                "libopenmpt/libopenmpt_version.mk",
                "libopenmpt/libopenmpt.pc.in",
                "libopenmpt/Doxyfile",
                "libopenmpt/.clang-format",
                "libopenmpt/bindings",
            ],
            sources: [
                "common",
                "src/openmpt/base",
                "src/openmpt/logging",
                "src/openmpt/random",
                "src/openmpt/fileformat_base",
                "src/openmpt/soundbase",
                "src/openmpt/soundfile_data",
                "soundlib",
                "soundlib/plugins",
                "sounddsp",
                "libopenmpt",
            ],
            publicHeadersPath: "swift",
            cxxSettings: [
                .define("LIBOPENMPT_BUILD"),
                .headerSearchPath("."),
                .headerSearchPath("common"),
                .headerSearchPath("src"),
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "OpenMPTKit",
            dependencies: ["Clibopenmpt"],
            path: "Sources/OpenMPTKit"
        ),
        .executableTarget(
            name: "mptinfo",
            dependencies: ["OpenMPTKit"],
            path: "Sources/mptinfo"
        ),
        .executableTarget(
            name: "mptplay",
            dependencies: ["OpenMPTKit"],
            path: "Sources/mptplay"
        ),
        .testTarget(
            name: "OpenMPTKitTests",
            dependencies: ["OpenMPTKit"],
            path: "Tests/OpenMPTKitTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
