// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HabitusWin",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HabitusWin", targets: ["HabitusWin"])
    ],
    targets: [
        .executableTarget(
            name: "HabitusWin",
            path: "Sources/HabitusWin"
        )
    ],
    swiftLanguageVersions: [.v5]
)
