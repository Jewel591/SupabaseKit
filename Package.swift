// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SupabaseKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "SupabaseKit",
            targets: ["SupabaseKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.5.1"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0"),
    ],
    targets: [
        .target(
            name: "SupabaseKit",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS", condition: .when(platforms: [.iOS])),
            ]
        ),
    ]
)
