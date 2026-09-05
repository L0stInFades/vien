# Vien — native macOS build

A Swift-only rewrite of the Vien Markdown editor: no Electron, no WebKit, no JavaScript, no third-party
packages. Everything the editor shows is drawn by AppKit, Core Text and Core Graphics from the
Markdown source, and the source is never rewritten behind your back.

## Modules

| Module | Responsibility | Lines |
| --- | --- | ---: |
| `VienMarkdown` | CommonMark 0.31.2 + GFM parser with source spans on every node, incremental reparse, HTML renderer. Zero dependencies (no Foundation). | ~3.5k (+4k generated entity/emoji tables) |
| `VienDiagrams` | Native Mermaid: parser (flowchart, sequence, pie, class, state), layered graph layout, Core Graphics + SVG canvases. | ~2.2k |
| `VienMath` | Native TeX math: parser, box layout driven by STIX Two Math's OpenType MATH table, Core Graphics + MathML. | ~1.4k |
| `Vien` | The document app: TextKit 2 editor, sidebar (files / outline / search), settings, export, print. | ~4.4k |

`vien-tool` (perf timings, PNG renders, parse dumps) and the swift-testing suites under `Tests/`
round it out. The Electron sources in the repository root are untouched reference material.

## How the editor works

* **Source is truth.** The text view holds the file's characters, byte for byte. Styling is applied
  lazily, paragraph by paragraph, through `NSTextContentStorageDelegate` as TextKit 2 lays out the
  viewport, so a 10 MB document costs nothing more per keystroke than a 1 KB one.
* **Incremental parsing.** `MarkdownDocument.replace` reparses only the top-level blocks around an
  edit and reuses the rest with lazily applied offset shifts; the line table shifts lazily too
  (0.02 ms per keystroke at 0.5 MB, 0.14 ms at 5 MB, release build).
* **TextKit 2 on a short leash.** TextKit caches every paragraph element it has ever created and
  rewrites the range of each one after the caret on every keystroke, so reading through a long
  document would make typing slower and slower (440 ms per keystroke after paging through 15 MB in
  a plain `NSTextView`). Vien never enumerates elements outside the viewport, and once scrolling has
  created a couple of thousand elements it drops them again with a whole-document attribute
  invalidation, anchored so the view does not move. Typing stays at ~2 ms whatever has been read.
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
VIEN_SCRIPT="type:- a§enter§type:b§dump§quit" Vien file.md   # drives the editor like keystrokes
# steps: type: enter tab backtab backspace select:a,b goto:phrase end bold heading:n bullets quote
#        table undo wait:ms pagedown:n recycle snap:path stats dump selection time quit
```

## Conformance and performance (release build, 2020 Intel MacBook, Swift 6.3.3)

| Check | Result |
| --- | --- |
| CommonMark 0.31.2 examples | 652 / 652 |
| GFM 0.29 examples | 28 / 28 |
| Lossless corpus | 35 / 35 fixtures byte-identical, spans cover every byte |
| Incremental vs full reparse | 2,160 random edits identical (36 documents × 60 edits) |
| Block parse | ~70 ms / MB |
| Keystroke reparse (parser only) | 0.02 ms (0.5 MB) · 0.14 ms (5 MB) |
| Keystroke in the editor (insert, reparse, relayout) | 2 ms (0.6 MB) · 3 ms (5 MB) · 4 ms (15 MB), unchanged after reading the whole document |
| HTML render | ~150 ms / MB |
| App bundle | 2.4 MB |
| Launch to editable window | 0.35 s (1 KB file) · 0.42 s (0.6 MB) · 0.57 s (5.3 MB) · 0.96 s (15 MB) |
| Resident memory after opening | 50 MB (1 KB) · 62 MB (0.6 MB) · 125 MB (5.3 MB) · 259 MB (15 MB) |
| Mermaid render | 5–20 ms per diagram · TeX formula < 2 ms |

Only the paragraphs on screen are styled, at launch and ever after (127 at launch whatever the file
size); everything else is built as it scrolls into view, which is what keeps the numbers flat as
documents grow.

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
