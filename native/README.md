# Vien — native macOS build

A Swift-only rewrite of the Vien Markdown editor: no Electron, no WebKit, no JavaScript, no third-party
packages. Everything the editor shows is drawn by AppKit, Core Text and Core Graphics from the
Markdown source, and the source is never rewritten behind your back.

## Modules

| Module | Responsibility | Lines |
| --- | --- | ---: |
| `VienMarkdown` | CommonMark 0.31.2 + GFM parser with source spans on every node, incremental reparse, HTML renderer. Zero dependencies (no Foundation). | ~3.3k |
| `VienDiagrams` | Native Mermaid: parser (flowchart, sequence, pie, class, state), layered graph layout, Core Graphics + SVG canvases. | ~2.2k |
| `VienMath` | Native TeX math: parser, box layout driven by STIX Two Math's OpenType MATH table, Core Graphics + MathML. | ~1.4k |
| `Vien` | The document app: TextKit 2 editor, sidebar (files / outline / search), settings, export, print. | ~3.5k |

`vien-tool` (perf timings, PNG renders, parse dumps) and the swift-testing suites under `Tests/`
round it out. The Electron sources in the repository root are untouched reference material.

## How the editor works

* **Source is truth.** The text view holds the file's characters, byte for byte. Styling is applied
  lazily, paragraph by paragraph, through `NSTextContentStorageDelegate` as TextKit 2 lays out the
  viewport, so a 10 MB document costs nothing more per keystroke than a 1 KB one.
* **Incremental parsing.** `MarkdownDocument.replace` reparses only the top-level blocks around an
  edit and reuses the rest with lazily applied offset shifts (measured at 0.05 ms for 0.5 MB and
  ~2 ms for 15 MB per keystroke, release build).
* **Diagrams and math draw themselves.** A Mermaid fence or a `$$` block gets a custom
  `NSTextLayoutFragment` that reserves space and draws the rendered bitmap beneath the closing line;
  the text stays editable above it. Rendering is synchronous native code (5–20 ms per diagram,
  <2 ms per formula) with an in-memory cache.
* **macOS does the rest.** `NSDocument` provides autosave, versions, crash recovery, rename/move from
  the title bar and external-change detection; `NSWindow` tabbing, the system find bar, spell checking,
  Quick Look-style Open Recent, Dark Mode and the Help menu's command search come for free.

## Build, run, test

Requires macOS 15 and the latest Swift release toolchain (rolling policy: the newest toolchain on
swift.org is the supported one).

```sh
Scripts/update-toolchain.sh        # installs the newest release toolchain into ~/Library (no admin)
Scripts/run.sh path/to/file.md     # debug build + launch
Scripts/bundle.sh                  # release build → dist/Vien.app (ad-hoc signed)
Scripts/swift.sh test              # swift-testing suites (spec conformance, corpus, incremental, diagrams, math)
Scripts/swift.sh run vien-tool     # perf numbers + PNG renders in /tmp/vien-diagrams and /tmp/vien-math
```

Headless helpers used by scripts and CI:

```sh
dist/Vien.app/Contents/MacOS/Vien --export html in.md out.html
dist/Vien.app/Contents/MacOS/Vien --export pdf  in.md out.pdf
VIEN_QUIT_WHEN_READY=1 Vien file.md           # prints time-to-window and resident memory
VIEN_SNAPSHOT=/tmp/shot.png Vien file.md      # renders the window to a PNG and quits
```

## Conformance and performance (release, MacBook Air-class Intel, Swift 6.3.3)

| Check | Result |
| --- | --- |
| CommonMark 0.31.2 examples | 652 / 652 |
| GFM 0.29 examples | 28 / 28 |
| Lossless corpus | 35 / 35 fixtures byte-identical, spans cover every byte |
| Incremental vs full reparse | 2,160 random edits identical (36 documents × 60 edits) |
| Block parse | ~70 ms / MB |
| Keystroke reparse | 0.05 ms (0.5 MB) · 0.8 ms (5 MB) · 2.4 ms (15 MB) |
| HTML render | ~150 ms / MB |

## What is deliberately different from the Electron app

* One editing surface: styled source instead of a contenteditable WYSIWYG tree. Markers stay visible
  but recede; nothing is normalised on save.
* macOS conventions replace custom chrome: system fonts and colours, sidebar and toolbar, settings
  window, tabs, find bar, Open Recent, Help search instead of a command palette.
* Diagrams other than Mermaid (flowchart.js, js-sequence, PlantUML, Vega-Lite) are not rendered;
  their fences remain plain code blocks. Unsupported Mermaid kinds (gantt, ER, mindmap, …) show the
  parser's message instead of an image.
* Image upload services, Unsplash, the screenshot tool and the PlantUML web service are gone: they
  needed the network or external processes. Pandoc import/export stays (optional, detected at runtime).
