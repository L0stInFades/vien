# Vien — CLAUDE.md

Vien 是 MarkText 的现代化 fork：安静、本地优先、无损、即时响应的 Markdown
阅读编辑器。

**唯一路线图：[PLAN.md](PLAN.md)**（Typora 级执行计划：里程碑、硬性指标、
阶段退出条件、风险登记）。本文件只保留开发约定与事实入口，不复制计划内容
——避免双重路线图（PLAN.md §16 维护规则）。

## 事实来源（不要在本文件里复制数字）

| 事实 | 来源 |
| --- | --- |
| 路线图 / 阶段 / 退出条件 | [PLAN.md](PLAN.md) |
| 架构决策 | [docs/adr/](docs/adr/)（ADR-001 source of truth、ADR-002 engine gate、ADR-003 IPC capability model） |
| renderer Node 能力清单与迁移状态 | [docs/capability-inventory.md](docs/capability-inventory.md) |
| 无损基线 | [test/corpus/known-lossy.json](test/corpus/known-lossy.json)（棘轮测试 `test/unit/specs/corpus-roundtrip.spec.js`） |
| 测试数量 / 通过状态 | 运行 `pnpm run verify`（CI 同源） |
| 原生 Swift 实验分支 | [native/README.md](native/README.md)（`experimental/swift-native`，`native/Scripts/swift.sh test`） |

## 技术栈（当前）

Electron / electron-vite / Vite / Vue + Element Plus 均跟随 npm `latest` · Vuex 与
Pinia 并存（迁移中，见 PLAN.md）· Muya 编辑内核（`src/muya/`，TypeScript）·
CodeMirror 6（源码模式）· Vitest + Playwright + CommonMark/GFM specs ·
Biome · pnpm `latest`。所有直接包声明都写 `latest`，唯一可复现快照是
`pnpm-lock.yaml`，由 Dependabot 每日推进。

## 常用命令

```bash
pnpm run dev            # electron-vite dev（HMR）
pnpm run verify         # latest policy + lint + typecheck + unit + specs + build
pnpm run deps:update    # 将 lockfile 推进到当前全部 latest
pnpm run unit           # Vitest
pnpm run test:specs     # 离线 CommonMark/GFM 已知差异棘轮
pnpm run e2e            # 构建后跑 Playwright Electron E2E
pnpm run lint:fix       # Biome 自动修复
pnpm run electron:build # 生产构建（dist/electron/）
```

## 开发约定

- 新文件优先 `.ts` / `<script setup lang="ts">`；Biome 格式化；`tsc --noEmit` 零错误。
- IPC channel 命名：`mt::<module>-<action>`（如 `mt::window-close`）。
- 所有 `window.api` 调用必须在方法体内（非模块顶层）——preload 未就绪时会崩溃：

  ```js
  // ✅ 在回调/方法内
  handleCloseClick () {
    if (window.api) window.api.window.close()
  }
  // ❌ 模块顶层
  window.api.ipc.on('mt::some-event', handler)
  ```

- renderer 禁止 import `fs`、`fs/promises`、`fs-extra`、`child_process`、
  `zlib`、`electron`、`vscode-ripgrep` —— 对应 stub 会抛结构化
  `CapabilityUnavailableError`（`src/common/errors/capabilityUnavailable.ts`）。
  能力一律走 `window.api` / 主进程服务，见能力清单。
- 语料 fixtures（`test/corpus/`）是字节精确数据：`-text` gitattributes 保护，
  勿手工"格式化"。
- 每个变更的 Definition of Done 见 PLAN.md §9.2；代码里的 TODO 必须关联
  PLAN.md 工作流/issue。

## CI

- PR/push：`.github/workflows/build.yml` — 全部质量门禁与 Electron E2E 都在
  macOS 上运行；Vien 不以 Linux/Windows 为交付目标。
- Release：`.github/workflows/release.yml` — tag 触发，签名 macOS 构建。
- 本地与 CI 使用 pnpm `latest` / Node 22+；包声明禁止固定版本，锁文件负责复现。

## 历史迁移记录（已完成，简要）

Phase 0-8 旧 SEA 迁移（2026-02 至 2026-04）：TypeScript 基础设施、
`src/common` + `src/muya/lib` 全量 TS 化（148 文件，tsc 零错误）、IPC 安全
加固（contextBridge + `window.api`，`contextIsolation: true`）、Electron
18→34、Karma→Vitest、Webpack→electron-vite。详情见 git 历史与
`docs/adr/`。后续工作全部以 [PLAN.md](PLAN.md) 为准。
