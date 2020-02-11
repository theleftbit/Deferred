// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Deferred",
    products: [
        .library(name: "Deferred", type: .dynamic, targets: [ "Deferred", "Task" ])
    ],
    targets: [
        .target(name: "Atomics"),
        .target(
            name: "Deferred",
            dependencies: [ "Atomics" ]),
        .testTarget(
            name: "DeferredTests",
            dependencies: [ "Deferred" ],
            exclude: [ "Tests/AllTestsCommon.swift" ]),
        .target(
            name: "Task",
            dependencies: [ "Deferred" ]),
        .testTarget(
            name: "TaskTests",
            dependencies: [ "Deferred", "Task" ],
            exclude: [ "Tests/AllTestsCommon.swift" ])
    ]
)
