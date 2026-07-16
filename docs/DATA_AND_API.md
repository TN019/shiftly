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
// config.json 演进：shift_types 取代单一默认时间（向后兼容读 v1）
"shift_types": [
  { "id": "day",   "label": "白班", "start": "10:00", "end": "18:30" },
  { "id": "night", "label": "夜班", "start": "22:00", "end": "06:00" }  // 跨午夜
],
"rules": [ { "effective_from": "...", "workdays": [...], "shift_type": "day" } ]
```

```jsonc
// pay.json（M4，新文件）：薪资模型，全部字段 effective_from 分段
{
  "version": 1,
  "currency": "AUD",
  "rates": [ { "effective_from": "2026-01-01", "hourly": 32.5 } ],
  "overtime": { "daily_after_hours": 8, "multiplier": 1.5 },
  "allowances": [
    { "kind": "night", "applies_to_shift_type": "night", "per_hour": 4.0 },
    { "kind": "holiday", "dates": ["2026-12-25"], "multiplier": 2.0 }
  ]
}
```

```jsonc
// manual_shifts.json（M2 回读产物）：单次班次（非规则生成）
[ { "date": "2026-07-20", "shift_type": "day", "start": "12:00", "end": "20:00", "source": "calendar" } ]

// sync_state.json（M2）：事件映射，见 docs/SYNC_DESIGN.md §2
```

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
