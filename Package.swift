// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProxyToggle",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ProxyToggle",
            path: "Sources/ProxyToggle",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
