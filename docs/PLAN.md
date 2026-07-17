# Shiftly 总体方案（v2 规划）

> 状态：**已全部完成**（2026-07-17，v0.7.0，31/31 张卡，PR #1–#28）。
> 本文保留为架构决策与路线图的历史记录；当前数据/接口契约见
> [DATA_AND_API.md](DATA_AND_API.md)，同步设计见 [SYNC_DESIGN.md](SYNC_DESIGN.md)。
> 任务卡在 mingri 的 **Shiftly** 项目（project_id `16cfcb5f-28c4-4658-a4d8-78299fb5ae24`）。

## 愿景

**Shiftly**（由 Shifty 更名）是一个本地优先的 macOS 原生工具，把三件事合为一体：

1. **排班** —— 周期规则 + 换班 + 请假，与 Apple Calendar **双向**同步；
2. **工资** —— 按实际班次计算工资（时薪/加班/夜班/节假日），图表可视化；
3. **工作日志** —— 每日 Markdown 日志，存放在用户指定目录，可在外部编辑器打开。

明确不做（当前阶段）：网站部署、多用户、云端存储、GitHub 自动化。

## 核心原则

- **本地文件是唯一真相源**：配置与业务数据是 `data/` 下的 JSON，日志是用户目录下的 Markdown。不引入数据库，保证 AI / 脚本 / 人都能直接读写。
- **逻辑只写一份**：所有领域逻辑（排班求解、工资计算、日志路径规则）在 **ShiftlyKit**（Swift 包）里实现一次，GUI 与 CLI 都是它的壳。这是对旧版最大教训的修正——Shifty 的排班算法在 Python 和两段 AppleScript 内嵌字符串里重复了三份。
- **轻启动**：双击 `Shiftly.app` 即用，任何日常操作都不需要终端。终端/CLI 只服务于 AI 和自动化。

## 目标架构

```
Shiftly.app (SwiftUI GUI)          shiftly CLI (--json)         Shiftly MCP server (stdio)
        │                                │                            │（薄封装，调 CLI）
        └──────────────┬─────────────────┴────────────────────────────┘
                       ▼
                  ShiftlyKit（领域核心，Swift Package）
        排班引擎 · 工资引擎 · 日志管理 · EventKit 同步引擎 · 存储层
                       │
        ┌──────────────┼────────────────────┐
        ▼              ▼                    ▼
   data/*.json    Apple Calendar      ~/…/ShiftlyLogs/*.md
  （配置+业务）   （EventKit 双向）     （用户指定目录）
```

被替代的旧组件：`scripts/sync.applescript`（AppleScript + 内嵌 Python）→ EventKit 同步引擎；
`scripts/*.py` → ShiftlyKit + `shiftly` CLI。过渡期内 AppleScript 菜单保留为备用入口。

## 关键技术决策

| 决策 | 理由 |
|------|------|
| EventKit 替代 AppleScript 写日历 | 双向同步的前提；快一个数量级；系统标准权限弹窗；结构化字段替代 `[SF_SYNC]` 文本标记 |
| 数据保持 JSON 文件（不用 SQLite/CoreData） | AI 友好（需求 6 的基础）；diff/备份/手改容易；数据量级（个人排班）完全够用 |
| CLI 用 Swift（同包 target）而非 Python | 复用 ShiftlyKit，杜绝逻辑双写；Python 脚本在 M6 完成后退役 |
| MCP server 用 node 薄封装调 CLI | 与 mingri 的 `packages/mcp-server` 模式一致，零构建、易维护 |
| 增量 upsert 而非"清空重建"同步 | 旧版每次同步全清重建 O(N×M)，回读（双向）也要求保留事件身份 |

## 路线图（与 mingri 里程碑一一对应）

| 里程碑 | 版本 | 内容 | 依赖 |
|--------|------|------|------|
| **M1 基座重构与更名** | v0.2 | 更名 Shiftly、拆分 main.swift、建 ShiftlyKit、修 4 个已知 bug、消除逻辑三重复制、补测试 | — |
| **M2 EventKit 双向同步与轻启动** | v0.3 | EventKit 读写引擎、sync_state 映射、回读（移动=换班/删除=休/新增=单次班）、.app 打包、后台定时同步 | M1 |
| **M3 UI/UX 改版与日历视图** | v0.4 | 侧边栏五区（今日/日历/工资/日志/设置）、月历视图、规则时间线、MenuBarExtra、通知、本地化 | M2 |
| **M4 工资计算与可视化** | v0.5 | pay.json 薪资模型、计算引擎（加班/夜班/跨午夜）、Swift Charts、工资单导出 | M1（引擎）/ M3（图表页） |
| **M5 工作日志** | v0.6 | 指定目录 Markdown 日志、快记+预览、Finder/外部编辑器打开、日历联动、搜索 | M3 |
| **M6 AI 友好接口** | v0.7 | `shiftly` CLI（全量 CRUD，`--json`）、MCP server、schema 文档、FSEvents 文件监听 | M1–M5 |

实施顺序建议：M1 → M2 是硬依赖链（先止血再换引擎）；M4 的计算引擎可与 M3 并行；M6 收尾。

## 旧版已知问题（M1 要解决的）

1. 排班算法三处重复（`schedule_core.py` + `sync.applescript` 两段内嵌 Python）。
2. `parseDateTime` 月底翻转 bug（29/30/31 号运行同步会写错月份）。
3. UI 保存排班会覆盖 `rules` 数组，摧毁 effective_from 历史。
4. Swift `Config` 保存丢弃未知字段；`SwapItem.id` 每次访问变化。
5. AppleScript 把对话框输入拼进 Python 源码执行（注入面）。
6. 同步失败时 meta.json 永远不会记录 error。
7. `clearSyncEvents` 遍历日历全部事件，历史导入后同步极慢。

## 相关文档

- [SYNC_DESIGN.md](SYNC_DESIGN.md) —— 双向同步详细设计（M2）
- [DATA_AND_API.md](DATA_AND_API.md) —— 数据 schema 与 AI 接口设计（M6，含现状 schema）
- 根目录 `CLAUDE.md` —— 会话快速上下文
