# Vien — CLAUDE.md

Vien is a native macOS Markdown editor: Swift only, AppKit + Core Text + Core Graphics, no
Electron, no WebKit, no JavaScript, no third-party packages. `README.md` is the single source of
facts (modules, how the editor works, numbers); this file keeps the working conventions.

## Commands

```sh
Scripts/update-toolchain.sh   # newest Swift release toolchain into ~/Library (rolling policy)
Scripts/run.sh file.md        # debug build + launch
Scripts/bundle.sh             # release build → dist/Vien.app (fails instead of shipping a stale binary)
Scripts/swift.sh test         # every suite; must pass before a commit
Scripts/swift.sh run vien-tool
```

Verify visually with the harness instead of guessing: `VIEN_SCRIPT="…§snap:/tmp/a.png§quit"
dist/Vien.app/Contents/MacOS/Vien -sourceMode 0 file.md` (steps in `README.md`), then look at
the PNG. `time` after `pagedown` prints layout/styling/draw; `VIEN_TRACE=1` prints timings.

## Conventions

- Latest Swift release toolchain, strict upcoming features on every target; the app target has
  default `MainActor` isolation, so anything TextKit or Core Graphics touches off the main actor
  (fragments, paragraphs, grids) is `nonisolated`.
- Source is truth: never rewrite the user's text to style it. Styling is per line, through the
  `NSTextContentStorageDelegate`, and never enumerates TextKit elements outside the viewport.
- Good code first, then the least of it: one type per responsibility, small data instead of
  branches, comments say why. No dependencies, ever.
- `Tests/Fixtures/corpus` is byte-exact data (`* -text`); never "format" it.
- Commit messages: `area(native): what changed`, with the reason in the body. The harness gets a
  step when a behaviour needs verifying, not a debug print.

## History

The Electron/MarkText lineage is archived on `archive/electron` (tag `electron-final`); nothing
from it is built or shipped any more.
