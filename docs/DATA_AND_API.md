# 数据 Schema 与 AI 接口设计

> 面向两类读者：实现 M4–M6 的开发会话，以及未来直接对数据做 CRUD 的 AI。
> 原则：**本地文件是唯一真相源**，所有文件人类可读、AI 可直接编辑；
> App 通过 FSEvents 监听变更自动刷新（M6）。

## 1. 现状数据（v1，`data/`，已在用）

| 文件 | 内容 |
|------|------|
| `config.json` | `config_version`(=1)、`calendar_name`、`event_title`、`default_start_time`/`default_end_time`（HH:MM）、`rules[]`、`setup_completed`、可选 `history_csv` |
| `swaps.json` | `[{"from_date": "YYYY-MM-DD", "to_date": "YYYY-MM-DD"}]` |
| `leave.json` | `[{"start_date": "YYYY-MM-DD", "end_date": "YYYY-MM-DD"}]` |
| `meta.json` | `{"last_sync_at", "last_sync_status"}` |
| `config.example.json` | 新装模板（唯一入库的 data 文件，其余被 .gitignore） |

`rules[]` 元素：`{"effective_from": "YYYY-MM-DD", "workdays": ["MO","TU",...]}`。
对某一天生效的规则 = effective_from ≤ 当天 的**最后**一条（按 effective_from 排序）。

## 2. 目标数据（v2，随 M2–M6 引入，`config_version: 2`）

新增/演进：

```jsonc
// config.json v2（已实现）：shift_types 叠加在默认时间之上（v1 依旧可读）
// 时间优先级：单日 override > 规则的 shift_type 时间 > default_start/end_time
"config_version": 2,
"shift_types": [
  { "id": "day",   "label": "白班", "start": "10:00", "end": "18:30" },
  { "id": "night", "label": "夜班", "start": "22:00", "end": "06:00" }  // 跨午夜（end ≤ start 进次日）
],
"rules": [ { "effective_from": "...", "workdays": [...], "shift_type": "day" } ]
// rules[].shift_type 缺省 = 用默认时间；planner.py shifts 输出
// "YYYY-MM-DD|rule或swap|shift_type"，换入日取当日生效规则的类型
```

```jsonc
// pay.json（M4，已实现）：casual 平率薪资模型（2026-07-17 与用户确认最简方案）
// 金额一律以 base_currency 记账；display_rates 是手工维护的显示换算（不联网）。
// 工时按真实起止计（跨午夜足额），班次归属开始日；
// 时薪取 effective_from ≤ 班次日期 的最新一段，早于首段的班次计 0 并在 UI 标记。
{
  "version": 1,
  "base_currency": "AUD",
  "rates": [ { "effective_from": "2026-01-01", "hourly": 32.5 } ],
  "display_rates": { "CNY": 4.7, "USD": 0.66 }
  // 预留扩展位（本期不实现）：overtime / allowances
}
```

```jsonc
// manual_shifts.json（M2 回读产物，已实现）：单次班次（非规则生成）
[ { "date": "2026-07-20", "start": "12:00", "end": "20:00", "source": "calendar" } ]

// overrides.json（M2 回读产物，已实现）：单日时间覆盖（用户在日历改了当天时间）
[ { "date": "2026-07-21", "start": "12:00", "end": "20:00" } ]

// sync_state.json（M2，已实现）：事件映射，见 docs/SYNC_DESIGN.md §2；
// 引擎私有状态，勿手改（连同 meta.json）
```

注：日历侧删除事件会回读为 leave.json 中的单日请假（start_date == end_date）。
meta.json 增加可选字段 `last_sync_error`（同步失败时记录原因）。

**工作日志（M5）**：不在 `data/` 内，存于用户指定目录（默认 `~/Documents/ShiftlyLogs`），
路径记入 `config.json` 的 `log_dir`（App 端用 security-scoped bookmark 持久授权）。
布局 `YYYY/YYYY-MM-DD.md`，frontmatter：

```markdown
---
date: 2026-07-16
shift: day
hours: 8.5
tags: []
---
（正文，自由 Markdown）
```

## 3. `shiftly` CLI（M6，AI 的统一入口）

Swift executable target，复用 ShiftlyKit；**所有子命令支持 `--json`**；
根目录用 `SHIFTLY_ROOT`（兼容读 `SHIFTY_ROOT`/`SHIFTFLOW_ROOT`）。

```
shiftly schedule show / set --workdays MO,TU --from 2026-08-01 --shift-type day
shiftly swap add --from 2026-07-21 --to 2026-07-23 / list / remove <n>
shiftly leave add --start 2026-07-25 --end 2026-07-27 / list / remove <n>
shiftly shifts list --from 2026-07-01 --to 2026-07-31     # 求解后的实际班次
shiftly pay report --month 2026-07                        # 工资分项明细
shiftly log append "今天……" [--date 2026-07-16] / show / path
shiftly sync now [--window month|next_month]
shiftly report hours --period week|month
```

约定：读操作退出码 0 + JSON stdout；写操作成功输出写入后的对象；错误 JSON 到 stderr + 非零退出码。

## 4. Shiftly MCP server（M6）

`packages/mcp-server/`（node + zod，参照 mingri 同名包的模式），stdio 传输，
每个工具 = 一次 CLI 调用：

| 工具 | 封装 |
|------|------|
| `get_schedule` / `set_schedule` | `shiftly schedule …` |
| `list_shifts` | `shiftly shifts list …` |
| `add_swap` / `add_leave` / `remove_override` | `shiftly swap/leave …` |
| `pay_report` | `shiftly pay report …` |
| `log_append` / `log_read` | `shiftly log …` |
| `sync_now` | `shiftly sync now` |

注册示例：

```bash
claude mcp add shiftly -e SHIFTLY_ROOT=/Users/tn/dev/local/shifty \
  -- node /Users/tn/dev/local/shifty/packages/mcp-server/index.js
```

## 5. AI 直接编辑文件的守则（M6 文档化前的临时约定）

- 改 `data/*.json` 前先读全文件，保留未知字段，写回保持 2 空格缩进；
- 日期一律 `YYYY-MM-DD`，时间 `HH:MM`（24h）；
- 改完数据后提示用户在 App 里 Sync（或调 `shiftly sync now`），否则日历不会更新；
- 不要手改 `sync_state.json` 与 `meta.json`（同步引擎的私有状态）。
