# ADR-004: Native Swift implementation (experimental branch)

- Status: experimental (branch `experimental/swift-native`)
- Date: 2026-09-06

## Context

PLAN.md diagnoses the Electron app's core risks: four competing sources of truth (disk bytes,
renderer string, Muya block tree, contenteditable DOM), full serialisation on every input, and a
7 MB renderer bundle whose diagram and math libraries dominate start-up. The product north star is
"quiet, local-first, lossless, instantly responsive" on macOS only.

## Decision

Rebuild the application as a pure Swift macOS app under `native/`, with these constraints:

1. **Pure Swift, latest toolchain, no dependencies.** No JavaScript, WebKit or third-party packages.
   The supported toolchain is the newest release on swift.org (`Scripts/update-toolchain.sh`).
2. **Source-authoritative editor.** One `NSTextStorage` holds the file's characters; a hand-written
   CommonMark/GFM parser (`VienMarkdown`) maintains a block tree with byte-exact spans and reparses
   incrementally. Styling is a lazy projection (TextKit 2 paragraph delegate); nothing is normalised.
3. **Native rendering for everything.** Mermaid diagrams (`VienDiagrams`) and TeX math (`VienMath`)
   are parsed, laid out and drawn with Core Graphics/Core Text; exports emit SVG and MathML.
4. **macOS conventions over custom chrome.** NSDocument (autosave, versions, recovery, rename,
   conflicts), window tabs, sidebar split view, settings window, system find bar and spell checking,
   Dark Mode, Help-menu command search.

5. **WYSIWYG by folding, not by rewriting.** The editor stays a styled-source editor; markup
   outside the paragraph being edited is hidden with a hairline transparent font and tables and
   images are drawn by custom layout fragments. The text is never transformed, so undo, find,
   selection and the file on disk all see the same characters.
6. **Distribution without third parties.** Updates use GitHub Releases plus a checksum and a
   code-signature/Team ID check implemented with CryptoKit and the Security framework; no Sparkle,
   no update server.

## Consequences

- Start-up, memory and per-keystroke cost are bounded by AppKit and the incremental parser, not by a
  web runtime; see `native/README.md` for measured numbers and `swift test` for conformance.
- Feature parity is deliberate, not literal: WYSIWYG block manipulation becomes source commands;
  non-Mermaid diagram libraries and network image services are dropped (see README).
- The Electron code stays in the repository for reference until the native build reaches the
  PLAN.md exit criteria; PLAN.md remains the single roadmap.
