// swift-tools-version: 6.2
import PackageDescription

// Vien — native macOS Markdown editor.
//
// Modules (each owns exactly one responsibility):
//   VienMarkdown  — pure Swift CommonMark/GFM(+extensions) parser, source-span AST, incremental reparse, HTML.
//   VienDiagrams  — Mermaid / KaTeX rendering through one hidden WebKit host, cached as images + SVG.
//   Vien          — AppKit document app (TextKit 2 editor, sidebar, settings, export).
//   vien-check    — spec ratchet + corpus + incremental + perf checks (no XCTest needed).

let strict: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
  name: "Vien",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "VienMarkdown", targets: ["VienMarkdown"]),
    .executable(name: "Vien", targets: ["Vien"]),
  ],
  targets: [
    .target(name: "VienMarkdown", swiftSettings: strict),
    .target(
      name: "VienDiagrams",
      swiftSettings: strict + [.defaultIsolation(MainActor.self)]
    ),
    .executableTarget(
      name: "Vien",
      dependencies: ["VienMarkdown", "VienDiagrams"],
      swiftSettings: strict + [.defaultIsolation(MainActor.self)]
    ),
    .executableTarget(
      name: "vien-check",
      dependencies: ["VienMarkdown"],
      path: "Tests/vien-check",
      swiftSettings: strict
    ),
  ]
)
