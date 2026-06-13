// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "EnclaveSpike",
  platforms: [.macOS(.v13)],
  targets: [
    .executableTarget(name: "EnclaveSpike")
  ]
)
