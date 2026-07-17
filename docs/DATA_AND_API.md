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

## 3. `shiftly` CLI（M6，已实现——AI 的统一入口）

Swift executable target（`ShiftlyApp/Sources/shiftly`），复用 ShiftlyKit；
**输出恒为 JSON**（`--json` 兼容接受）；根目录解析与 App 一致
（`SHIFTLY_ROOT` → App 记忆目录 → 可执行文件向上查找）。
打包时随 Shiftly.app 分发：`dist/Shiftly.app/Contents/MacOS/shiftly-cli`
（在包内运行可用内置 Python 脚本，数据目录无需仓库检出）。

```
shiftly schedule show
shiftly schedule set --workdays MO,TU --from 2026-08-01 [--shift-type day] [--start HH:MM --end HH:MM]
shiftly swap add --from 2026-07-21 --to 2026-07-23 | list | remove <index>
shiftly leave add --start 2026-07-25 --end 2026-07-27 | list | remove <index>
shiftly shifts list --from 2026-07-01 --to 2026-07-31     # 引擎求解后的实际班次
shiftly pay report --month 2026-07                        # 工资明细（base_currency 计）
shiftly log append "今天……" [--date 2026-07-16] | show | path
shiftly report hours --period week|month
shiftly sync now [--window next_month]                    # 需已在 App 授权日历
```

约定：成功退出码 0 + JSON stdout；错误 `{"error": …}` 到 stderr + 非零退出码
（2=参数/配置问题，3=资源不存在或权限，1=其他）。写数据后日历不会自动更新，
需 `sync now` 或在 App 里 Sync。

## 4. Shiftly MCP server（M6，已实现）

`packages/mcp-server/`（node + zod，stdio），每个工具 = 一次 CLI 调用；
工具面共 11 个：get_schedule / set_schedule / list_shifts / add_swap /
add_leave / list_overrides / remove_override / pay_report / log_append /
log_read / sync_now。详见 packages/mcp-server/README.md。

注册示例（SHIFTLY_ROOT 指数据目录；CLI 路径缺省自动探测，也可用 SHIFTLY_CLI 指定）：

```bash
claude mcp add shiftly -e SHIFTLY_ROOT=/path/to/shiftly-data \
  -- node /绝对路径/shiftly/packages/mcp-server/index.js
```

## 5. AI 直接编辑文件的守则（M6 文档化前的临时约定）

- 改 `data/*.json` 前先读全文件，保留未知字段，写回保持 2 空格缩进；
- 日期一律 `YYYY-MM-DD`，时间 `HH:MM`（24h）；
- 改完数据后提示用户在 App 里 Sync（或调 `shiftly sync now`），否则日历不会更新；
- 不要手改 `sync_state.json` 与 `meta.json`（同步引擎的私有状态）。
