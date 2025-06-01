// swift-tools-version:6.0

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "FlooidPersistence",
    platforms: [.iOS(.v16), .macOS(.v10_15)],
    products: [
        .library(
            name: "FlooidCoreData",
            targets: ["FlooidCoreData"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "509.0.0"),
    ],
    targets: [
        .target(
            name: "FlooidCoreData",
            dependencies: [
                "FlooidCoreDataMacros",
            ],
            path: "CoreDataProvider"
        ),
        .macro(
            name: "FlooidCoreDataMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Macros"
        ),
    ],
    swiftLanguageVersions: [.v6]
)
