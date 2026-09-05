# Build Instructions

Clone the repository:

```
git clone https://github.com/L0stInFades/vien.git
cd vien
```

### Prerequisites

Before you start developing, set up the following:

- Current Node.js LTS
- `pnpm`
- Python `>=v3.6` for node-gyp
- Xcode Command Line Tools
- macOS 14 or newer for the same baseline used by CI

Vien targets macOS only. Historical Linux and Windows code may remain in the tree, but those platforms are not build, test, or release contracts.

### Install and build

1. Install dependencies: `pnpm install`
2. Start development mode: `pnpm run dev`
3. Build renderer and main bundles only: `pnpm run electron:build`
4. Build packaged binaries for your current OS: `pnpm run build`

Packaged artifacts are written to `build/`.

### macOS release build

Vien currently ships macOS release artifacts through the main release flow.

```sh
pnpm run release:mac
```

The resulting `.dmg` and `.zip` files are written to `build/`.

### Important scripts

```sh
pnpm run <script>
```

| Script              | Description                                 |
| ------------------- | ------------------------------------------- |
| `dev`               | Start Vien in development mode              |
| `electron:build`    | Build the Electron app without packaging    |
| `build`             | Build and package the macOS app              |
| `release:mac`       | Build macOS release artifacts only          |
| `deps:update`       | Refresh every package to its latest release |
| `unit`              | Run unit tests                              |
| `test:specs`        | Run offline CommonMark/GFM known-difference ratchets |
| `e2e`               | Run Playwright Electron end-to-end tests    |
| `lint`              | Run Biome against `src/`                    |
| `validate-licenses` | Validate third-party license metadata       |

For more scripts please see `package.json`.
