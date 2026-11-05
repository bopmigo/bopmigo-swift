// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bopmigo",
    platforms: [.iOS(.v16)],
    products: [.library(name: "Bopmigo", targets: ["Bopmigo"])],
    targets: [.target(name: "Bopmigo", path: "Sources/Bopmigo")]
)
