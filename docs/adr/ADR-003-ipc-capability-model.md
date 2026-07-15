# ADR-003: 版本化能力（Capability）IPC 模型

- 状态：已接受
- 日期：2026-07-16
- 复审日期：Phase 1 结束（PLAN.md 第 6 周）

## 上下文

当前 preload（`src/main/preload.ts`）暴露通用 `ipc.send/invoke/on` + 较宽的
shell/clipboard 能力；主进程 handler 多数缺少 payload schema、sender 验证
和能力级授权。编辑器处理原始 HTML、外部图片和图表，renderer 必须被当作
不可信内容的宿主。通用 IPC 意味着任何 renderer 侧妥协都可放大为任意文件
读写或进程执行。

Phase 0 现状：renderer Node stubs 已改为抛结构化 `CapabilityUnavailable`
（BASE-002），能力清单见 `docs/capability-inventory.md`。

## 候选方案

| 候选 | 描述 | 结论 |
| --- | --- | --- |
| A. 保持通用 `ipc.invoke(channel, ...args)` | 现状 | 拒绝：无 schema、无最小权限、攻击面宽 |
| B. tRPC/zod 等框架整体引入 | 类型安全 RPC 框架 | 拒绝（暂时）：依赖面大，Electron IPC 语义（sender、window 身份）仍需自建；可在 contracts 层内部选用轻量校验器 |
| C. **窄能力方法 + 运行时 schema 校验 + 版本化 contracts** | preload 每能力一个窄方法；`src/common/contracts` 定义请求/响应 schema、错误码、API version、取消协议 | **接受** |

## 决策

1. `src/common/contracts/` 是 renderer ↔ preload ↔ main 的唯一接口事实来源：
   - 每个能力（documents、workspace、search、assets、export、shell、watch、
     recovery）一个 contract 模块；
   - 请求/响应均有运行时校验（手写轻量 validator 或后续引入 zod —
     实现细节可换，schema-first 原则不可换）；
   - 每个请求携带 `requestId`；流式/长任务有取消语义；
   - contracts 版本化：破坏性变更递增 version，preload 与 main 校验兼容。
2. preload 只装配窄方法（如 `api.workspace.rename(...)`），**不暴露**通用
   `send/invoke/on`；事件订阅返回显式 unsubscribe。
3. main 每个 handler 校验：sender（窗口身份）、session/path capability、
   payload schema；路径经规范化与根目录约束。
4. renderer 禁止 import `electron`、`fs`、`child_process`（build rule 强制）。
5. 错误以结构化错误码返回（含 `CapabilityUnavailable`、`ValidationFailed`、
   `PathDenied`、`Conflict` 等），不吞异常、不把失败呈现为成功。

## 反例

- 若窄方法数量爆炸到不可维护（>100 个），允许在 contracts 层内引入按域分组
  的 method registry，但"每方法有 schema + 版本 + sender 校验"不可放弃。

## 迁移路径

1. Phase 1：BOUNDARY-001 建 contracts 骨架 + 校验器；WORKSPACE-001/
   SEARCH-001/ASSET-001/EXPORT-001 逐能力迁移；
2. 迁移完成的能力从旧通用通道移除；Phase 1 结束时 preload 删除通用
   `ipc.send/invoke/on` 暴露；
3. 渐进期允许旧通道与新能力 API 并存，但新代码只准用能力 API。

## 回滚

各能力迁移独立可回滚（保留旧 handler 一个里程碑）；整体回滚等于放弃
Electron 安全清单达标，不可接受（数据安全项无例外）。

## 指标

- preload 通用 IPC 暴露：0（Phase 1 退出条件）；
- 恶意路径、symlink escape、伪造 sender、超大 payload 测试全部被拒；
- renderer bundle 无特权模块 import（build rule + CI 断言）。
