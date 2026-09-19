// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "szElectricityMeter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "szElectricityMeter", targets: ["szElectricityMeter"]), .executable(name: "MeterCoreChecks", targets: ["MeterCoreChecks"])],
    targets: [
        .target(name: "MeterCore"),
        .executableTarget(name: "szElectricityMeter", dependencies: ["MeterCore"]),
        .executableTarget(name: "MeterCoreChecks", dependencies: ["MeterCore"], path: "Tests/MeterCoreTests")
    ]
)
