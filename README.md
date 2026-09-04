# Vien

Vien is a Markdown editor for long stretches of attention.

No split preview. No busy dashboard. No productivity theater.
Just one continuous surface for writing, reading, revising, and exporting.

It is local-first, keyboard-fluent, and being shaped to feel especially at home on macOS.
Its tone comes from Ludwig Wandinger's [*Is Peace Wild?*](https://ludwigwandinger.bandcamp.com/album/is-peace-wild-2): spacious, nocturnal, restrained, and emotionally clear.

## Screenshots

![Vien writing surface](docs/screenshots/blank-surface.png)
![Vien about dialog](docs/screenshots/about.png)

## A Name From The Record

Vien takes its name from the track `Vien` on *Is Peace Wild?*.

That album never rushes to prove anything. It moves in low light, leaves room around each gesture, and lets tension stay gentle instead of turning it into noise. That felt like the right instinct for a writing tool.

So this project is not trying to look "efficient" at every second. It is trying to feel settled. Quiet, but not empty. Precise, but not cold. Something closer to a clear desk at night than a dashboard full of controls.

## What Lives Here

What Vien offers, without raising its voice:

- One continuous WYSIWYG Markdown surface
- CommonMark and GitHub Flavored Markdown support
- File tree, recent documents, quick open, and tabs
- Focus Mode, Typewriter Mode, and Source Code Mode
- Styled HTML and PDF export
- Import paths for common document formats
- macOS-native menu bar, Dock integration, recent files, and document edited state

## Why It Exists

Vien is being shaped for people who like calm writing software but still want a real desktop app: local files, native behavior, keyboard depth, and an interface that does not keep asking to be looked at.

Vien targets macOS. It keeps the open-source, file-first spirit of the editor lineage it came from without diluting its quality work across other desktop platforms.

When Vien opens, it goes straight to the page. No dashboard, no drop target, no staging area. Open a file through `File > Open…`, `Open Recent`, quick open, or a CLI path and keep moving.

## Start Quietly

```bash
git clone https://github.com/L0stInFades/vien.git
cd vien
pnpm install
pnpm run dev
```

Every direct package declaration follows npm's `latest` dist-tag. `pnpm-lock.yaml` keeps each reviewed build reproducible, while daily dependency updates advance that snapshot and run the macOS quality gates.

To package the macOS app:

```bash
pnpm run build
```

To build the macOS release artifacts directly:

```bash
pnpm run release:mac
```

## Project Status

Vien is an actively refined continuation of the MarkText foundation.

The work now is less about adding noise and more about removing roughness: better macOS behavior, better reliability, better pacing, and a stronger sense that the editor belongs on the desktop rather than inside a browser-shaped shell.

## Credits

- Built on the open-source foundation of [MarkText](https://github.com/marktext/marktext)
- Named in response to [Ludwig Wandinger](https://www.ludwigwandinger.com/) and [*Is Peace Wild?*](https://ludwigwandinger.bandcamp.com/album/is-peace-wild-2)

## License

[MIT](LICENSE)
