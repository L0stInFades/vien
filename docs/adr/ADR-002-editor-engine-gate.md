# ADR-002: Muya 加固 vs 更换编辑内核 — 决策闸门框架

- 状态：框架已接受；最终 go/no-go 悬而未决（按证据决策）
- 日期：2026-07-16
- 最晚决策时间：PLAN.md 第 18–20 周（Phase 3 结束）
- 复审日期：每个 timebox 结束时

## 上下文

Muya（`src/muya/lib/`）功能最丰富（表格、数学、图表、脚注、front matter、
可视操作），但其架构存在与 ADR-001 冲突的根性质：

- 可变 block tree + DOM-first 输入路径；
- 每次输入全量 `getMarkdown()` 序列化；
- 历史记录深拷贝整棵块树；
- Markdown exporter 归一化表格/列表/空白表示；
- `getBlock` 递归扫描、模块级计时器跨实例串扰。

直接重写编辑器风险极高（PLAN.md 风险表：大重写拖垮现有功能 = 中概率/极高
影响）。因此先隔离、后决策。

## 决策（框架）

1. 先建立 `EditorEngine` 适配层接口（PLAN.md §5.5），UI 停止直接依赖
   `ContentState`；
2. 给 Muya 四至八周量化改造窗口（两个 timebox）；
3. Phase 3 结束时只按下表证据决策，禁止感情式延期。

### Muya 继续条件（全部满足才继续）

- [ ] 支持语法"打开 → 显式保存不编辑"语料 100% 字节相同；
- [ ] 所有局部编辑用例的非目标 source span 100% 不变；
- [ ] 中/日/韩 IME、跨块 selection、撤销、表格关键矩阵全绿；
- [ ] 1 MB 输入 p95、10 MB 打开、内存指标达 §2.2 目标；
- [ ] 历史不再深拷贝全树；block lookup O(1)；输入不同步全量序列化；
- [ ] 正确性不依赖全局 suppress counter 或模块级跨实例 timer。

### 候选替代（若 Muya 失败）

| 候选 | 优势 | 主要风险 | 采用条件 |
| --- | --- | --- | --- |
| CM6 source-first + widgets/decorations | 文本事实来源、增量、大文档强 | 重做可视块交互/表格/selection 成本高 | 4 周 spike 证明关键交互可达 |
| ProseMirror/Lexical 语义编辑器 | selection/命令/生态成熟 | 语义模型倾向归一化，与 ADR-001 冲突 | 仅当 source-span 适配原型通过无损门槛 |

## 反例

- 若适配层本身导致不可接受的性能/复杂度开销，允许直接在 Muya 内部实现
  source-span（跳过适配层），但 UI 与 ContentState 解耦的边界不可放弃。

## 迁移路径（若更换内核）

Phase 4 前半段按 block/command 垂直切片迁移；旧内核只作受控 fallback；
禁止向两个内核同时加新功能；复用 parser fixtures、命令模型、UI 与主进程
服务。

## 回滚

适配层保证任一内核可整体替换；每个文件在新旧 engine 切换前创建 recovery
point（PLAN.md §9.3）。

## 指标

见"Muya 继续条件"清单；证据产物：无损金库报告、IME 矩阵、性能 trace、
spike 人天记录。
