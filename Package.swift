// swift-tools-version: 6.3
import PackageDescription

// Vien — native macOS Markdown editor.
//
// Modules (each owns exactly one responsibility):
//   VienMarkdown  — pure Swift CommonMark/GFM(+extensions) parser, source-span AST, incremental reparse, HTML.
//   VienDiagrams  — native Mermaid: parser, layered graph layout, Core Graphics + SVG rendering.
//   VienMath      — native TeX math: parser, box layout with the system math font, Core Text + MathML.
//   VienCode      — syntax highlighting for fenced code: one-pass tokenizer over small language tables.
//   Vien          — AppKit document app (TextKit 2 editor, sidebar, settings, export).
//   vien-tool     — perf timings, diagram PNG rendering and parse-tree dumps for manual inspection.
//   Tests/        — swift-testing suites (spec conformance, corpus, incremental parsing, diagrams, math).

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
    .target(name: "VienDiagrams", swiftSettings: strict),
    .target(name: "VienMath", swiftSettings: strict),
    .target(name: "VienCode", swiftSettings: strict),
    .executableTarget(
      name: "Vien",
      dependencies: ["VienMarkdown", "VienDiagrams", "VienMath", "VienCode"],
      swiftSettings: strict + [.defaultIsolation(MainActor.self)]
    ),
    .executableTarget(
      name: "vien-tool",
      dependencies: ["VienMarkdown", "VienDiagrams", "VienMath"],
      path: "Tests/vien-tool",
      swiftSettings: strict
    ),
    .testTarget(name: "VienMarkdownTests", dependencies: ["VienMarkdown"], swiftSettings: strict),
    .testTarget(name: "VienDiagramsTests", dependencies: ["VienDiagrams"], swiftSettings: strict),
    .testTarget(name: "VienMathTests", dependencies: ["VienMath"], swiftSettings: strict),
    .testTarget(name: "VienCodeTests", dependencies: ["VienCode"], swiftSettings: strict),
  ]
)
