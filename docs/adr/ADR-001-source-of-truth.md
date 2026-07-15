# ADR-001: Source Markdown 文本是唯一内容事实来源

- 状态：已接受
- 日期：2026-07-16
- 决策者：架构（本 ADR 由 PLAN.md §4.2/§5.4 固化）
- 复审日期：Phase 3 引擎闸门评审时（PLAN.md 第 18–20 周）

## 上下文

当前系统同时存在四种"事实来源"，它们通过全量导入/导出、异步事件和 suppress
标志保持"差不多一致"：

1. 磁盘上的 Markdown 字节；
2. renderer store 中的字符串（`src/renderer/store/editor.js`）；
3. Muya 的可变 block tree（`src/muya/lib/contentState/index.ts`）;
4. contenteditable DOM。

已观测到的后果：

- `setMarkdown()` → `getMarkdown()` 回环不是身份变换（表格、列表 marker、
  空白被归一化），需要 `_suppressDirtyCount` 全局计数器抑制加载后的伪修改；
- 输入路径每次变更全量序列化整个文档（性能 + 竞态风险）；
- 未编辑的源片段可能被改写，违背"Markdown 可信"的产品承诺。

## 候选方案

| 候选 | 描述 | 结论 |
| --- | --- | --- |
| A. 语义树为事实来源 | block tree 是权威，Markdown 是导出格式 | 拒绝：天然倾向格式归一化，无法保证未编辑字节不变 |
| B. DOM 为事实来源 | contenteditable 内容权威 | 拒绝：DOM 无法表达全部 Markdown 语法差异，且不可靠 |
| C. **源文本缓冲区为事实来源** | UTF 文本 buffer 权威；parser 生成带 source span 的投影；可视命令产生 source transaction | **接受** |

## 决策

1. **源文本缓冲区（source buffer）是唯一内容事实来源**；
2. `DocumentSession`（revision 状态机）是状态事实来源；
3. 磁盘版本（`DiskVersion`）由主进程持有；
4. 语义树和 DOM 只是可重建投影，不得持久化内容；
5. 可视编辑命令必须产生 source transaction（区间替换），未命中区间的字节
   原样保留；
6. source 模式与 visual 模式编辑同一 buffer，共享 undo/redo 和 revision。

## 反例（什么情况下此决策是错的）

- 若无损语料证明 source-span 投影在支持语法上无法达到 100% 字节保持，且
  性能开销超出 §2.2 预算 — 那么问题在实现而非架构；不存在推翻本决策而能
  同时满足"未编辑字节不变"承诺的候选。

## 迁移路径

1. Phase 2：`DocumentSession` reducer 从 `editor.js` 抽出（SAFE-001）；
2. Phase 3：`EditorEngine` 接口 + `MuyaAdapter`（CORE-001），无损金库
   （CORE-002），block id 索引（CORE-003），transaction history（CORE-004）；
3. Muya 通过/不通过 §5.5 闸门 → ADR-002 记录后续。

## 回滚

Phase 3 结束前旧路径（全量 get/setMarkdown）保持可用；适配层允许按 flag
切回。回滚代价：放弃无损承诺，重新接受归一化。

## 指标

- 未编辑保存 100% byte-identical（金库语料）；
- 局部编辑无旁观 source diff；
- 1 MB 文档输入 p95 ≤ 50 ms（§2.2）。
