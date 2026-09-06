# Contributing

Vien is small on purpose. A change is welcome when it makes the editor calmer, faster or more
correct, and when it arrives with the evidence.

## Before you open a pull request

1. `Scripts/swift.sh test` passes (spec conformance, lossless corpus, incremental parsing,
   diagrams, math, highlighting).
2. `Scripts/bundle.sh` builds `dist/Vien.app` and the app opens a document.
3. Anything visible comes with a screenshot from the harness (`VIEN_SCRIPT=… snap:`), and anything
   about speed comes with numbers from `time` or `vien-tool`.
4. No new dependencies. Everything Vien draws, it draws itself.

## Ground rules

- The user's text is never rewritten to style it.
- Work in the viewport; a document's length must not show up in a keystroke or a page down.
- Prefer one clear type to three clever ones; delete before you add.

Commit as `area(native): what changed`, with why in the body.
