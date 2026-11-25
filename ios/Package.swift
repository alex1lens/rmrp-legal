// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RMRPLegal",
    platforms: [.iOS(.v17)],
    products: [.library(name: "RMRPLegal", targets: ["RMRPLegal"])],
    targets: [.target(name: "RMRPLegal", resources: [.copy("Registry.json"), .copy("articles.json"), .copy("Supplemental.json")])]
)
