# Shiftly 数据与接口权威参考

> 读者：直接对 Shiftly 数据做 CRUD 的 AI 会话、脚本与开发者。
> 只读这一份文档即可安全操作；发生冲突时以本文档为准（代码变更须同步更新此处）。

## 0. 总览

- **本地文件是唯一真相源**。数据根目录（下称 `<root>`）= 环境变量 `SHIFTLY_ROOT`
  →（App 记忆的目录）→ 从可执行文件向上找 `data/config.json`。
- 三种操作方式，**推荐顺序**：① MCP 工具（会话内已注册 `shiftly` server 时）
  ② `shiftly` CLI ③ 直接编辑文件（遵守 §5 守则）。
- **写数据不会自动更新 Apple Calendar**：改完调 `sync_now` / `shiftly sync now`，
  或让用户在 App 里点 Sync。
- 日期一律 `YYYY-MM-DD`；时间 `HH:MM`（24 小时制）；跨午夜班次 end ≤ start 表示次日结束。

| 文件（相对 `<root>`） | 谁可以写 | 作用 |
|---|---|---|
| `data/config.json` | 人 / AI / App | 排班规则、班次类型、日历名、日志目录 |
| `data/swaps.json` | 人 / AI / App / 同步回读 | 换班记录 |
| `data/leave.json` | 人 / AI / App / 同步回读 | 请假区间 |
| `data/overrides.json` | 同步回读（AI 可删条目=撤销） | 单日时间覆盖 |
| `data/manual_shifts.json` | 同步回读（AI 可删条目=撤销） | 日历里手建的单次班 |
| `data/pay.json` | 人 / AI / App | 薪资模型 |
| `data/meta.json` | **只读**（同步引擎写） | 最近同步状态 |
| `data/sync_state.json` | **禁止手改**（引擎私有） | 事件映射 |
| `data/last_sync_report.json` | **禁止手改**（引擎私有） | 最近同步报告 |
| `data/readback_log.json` | **禁止手改**（引擎私有） | 回读日志（App 内撤销用） |
| `<log_dir>/YYYY/YYYY-MM-DD.md` | 人 / AI / App | 工作日志（见 §2） |

## 1. 数据文件 Schema

### 1.1 config.json（config_version 2；v1 无 shift_types/log_dir 亦可读）

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["calendar_name", "event_title", "default_start_time", "default_end_time", "rules"],
  "properties": {
    "config_version": { "type": "integer", "enum": [1, 2] },
    "calendar_name":  { "type": "string", "minLength": 1 },
    "event_title":    { "type": "string", "minLength": 1 },
    "default_start_time": { "type": "string", "pattern": "^\\d{1,2}:\\d{2}$" },
    "default_end_time":   { "type": "string", "pattern": "^\\d{1,2}:\\d{2}$" },
    "setup_completed": { "type": "boolean" },
    "history_csv":    { "type": "string" },
    "log_dir":        { "type": "string" },
    "rules": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["effective_from", "workdays"],
        "properties": {
          "effective_from": { "type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$" },
          "workdays": { "type": "array", "items": { "enum": ["MO","TU","WE","TH","FR","SA","SU"] } },
          "shift_type": { "type": "string" }
        }
      }
    },
    "shift_types": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "label", "start", "end"],
        "properties": {
          "id":    { "type": "string", "minLength": 1 },
          "label": { "type": "string", "minLength": 1 },
          "start": { "type": "string", "pattern": "^\\d{1,2}:\\d{2}$" },
          "end":   { "type": "string", "pattern": "^\\d{1,2}:\\d{2}$" }
        }
      }
    }
  }
}
```

语义：

- 某天生效的规则 = `effective_from ≤ 当天` 的**最后**一条（按日期排序）。
  **改排班永远是追加/同日替换，绝不清除历史规则**（历史规则保证过去的工作记录正确）。
- 某天的班次时间：`overrides.json` 的单日覆盖 > 规则 `shift_type` 对应类型的时间 > 默认时间。
- `shift_types[].end ≤ start` 表示跨午夜（次日结束）；写入 shift_types 时把
  `config_version` 提到 2。
- `log_dir` 缺省 `~/Documents/ShiftlyLogs`。

示例：

```json
{
  "config_version": 2,
  "calendar_name": "Shifts",
  "event_title": "Work Schedule",
  "default_start_time": "10:00",
  "default_end_time": "18:30",
  "setup_completed": true,
  "log_dir": "/Users/me/Documents/ShiftlyLogs",
  "shift_types": [
    { "id": "day", "label": "白班", "start": "09:00", "end": "17:00" },
    { "id": "night", "label": "夜班", "start": "22:00", "end": "06:00" }
  ],
  "rules": [
    { "effective_from": "2026-07-01", "workdays": ["MO", "TU"], "shift_type": "day" },
    { "effective_from": "2026-08-01", "workdays": ["WE", "FR"], "shift_type": "night" }
  ]
}
```

### 1.2 swaps.json / leave.json

```json
{ "type": "array", "items": { "type": "object",
  "required": ["from_date", "to_date"],
  "properties": { "from_date": { "pattern": "^\\d{4}-\\d{2}-\\d{2}$" },
                  "to_date":   { "pattern": "^\\d{4}-\\d{2}-\\d{2}$" } } } }
```

```json
{ "type": "array", "items": { "type": "object",
  "required": ["start_date", "end_date"],
  "properties": { "start_date": { "pattern": "^\\d{4}-\\d{2}-\\d{2}$" },
                  "end_date":   { "pattern": "^\\d{4}-\\d{2}-\\d{2}$" } } } }
```

语义：换班把 `from_date` 的班移到 `to_date`（按顺序应用，可链式）；请假区间含双端，
**请假在换班之后应用**（换入请假日的班会被吞掉）。日历侧删除事件会回读为单日请假
（start_date == end_date）。

### 1.3 overrides.json（单日时间覆盖）与 manual_shifts.json（单次班）

```json
{ "type": "array", "items": { "type": "object",
  "required": ["date", "start", "end"],
  "properties": { "date": { "pattern": "^\\d{4}-\\d{2}-\\d{2}$" },
                  "start": { "pattern": "^\\d{1,2}:\\d{2}$" },
                  "end":   { "pattern": "^\\d{1,2}:\\d{2}$" } } } }
```

```json
{ "type": "array", "items": { "type": "object",
  "required": ["date", "start", "end", "source"],
  "properties": { "date": { "pattern": "^\\d{4}-\\d{2}-\\d{2}$" },
                  "start": { "pattern": "^\\d{1,2}:\\d{2}$" },
                  "end":   { "pattern": "^\\d{1,2}:\\d{2}$" },
                  "source": { "type": "string" } } } }
```

两者主要由**日历回读**产生（用户在 Apple Calendar 改时/新建）。AI 通常不新增；
删除某条目 = 撤销该回读（App 的 Sync Report 卡片有同款按钮）。每日期至多一条。

### 1.4 pay.json（casual 平率薪资模型）

```json
{
  "type": "object",
  "required": ["version", "base_currency", "rates"],
  "properties": {
    "version": { "type": "integer", "enum": [1] },
    "base_currency": { "type": "string", "minLength": 3, "maxLength": 3 },
    "rates": {
      "type": "array", "minItems": 1,
      "items": { "type": "object", "required": ["effective_from", "hourly"],
        "properties": { "effective_from": { "pattern": "^\\d{4}-\\d{2}-\\d{2}$" },
                        "hourly": { "type": "number", "exclusiveMinimum": 0 } } }
    },
    "display_rates": { "type": "object", "additionalProperties": { "type": "number" } }
  }
}
```

语义：金额一律 `base_currency` 记账；班次适用费率 = `effective_from ≤ 班次日期` 的最新段；
早于首段的班次计 0（App 标橙提示）。`display_rates` 是手工维护的显示换算乘数
（1 base = N 显示币），**本地维护，永不联网获取**。调薪 = 追加一段，勿改历史段。
工时按真实起止（跨午夜足额），班次归属开始日。示例：

```json
{
  "version": 1,
  "base_currency": "AUD",
  "rates": [ { "effective_from": "2026-01-01", "hourly": 32.5 } ],
  "display_rates": { "CNY": 4.7, "USD": 0.66 }
}
```

### 1.5 meta.json（只读）

`{ "last_sync_at": ISO8601, "last_sync_status": "success"|"error", "last_sync_error": string? }`
——由同步引擎写入，用于判断最近一次同步是否成功。

### 1.6 引擎私有文件（禁止手改）

- `sync_state.json`：班次 ↔ 日历事件的映射与指纹。手改会导致重复建事件或误删。
  文件损坏/丢失时引擎自动降级重认领。
- `last_sync_report.json` / `readback_log.json`：同步报告与回读日志（App 内撤销依据）。

## 2. 工作日志

- 位置：`config.log_dir`（缺省 `~/Documents/ShiftlyLogs`），布局 `YYYY/YYYY-MM-DD.md`。
- 新文件自动带 frontmatter；**已存在的文件 Shiftly 只追加、绝不重建**：

```markdown
---
date: 2026-07-17
shift: day        # 规则班次类型 id；无班次 = none；日历手建 = manual
hours: 8.5        # 当日计划工时；无班次 = 0
tags: []
---

- 12:30 快记条目（`- HH:MM 内容` 为快记约定格式，正文其余部分自由）
```

- 正文是自由 Markdown，任何编辑器可改；App 的搜索会命中 frontmatter 与正文。

## 3. `shiftly` CLI 参考

二进制：随 App 打包在 `/Applications/Shiftly.app/Contents/MacOS/shiftly-cli`
（或仓库 `ShiftlyApp/.build/*/shiftly`）。输出恒为 JSON（`--json` 兼容接受）。
错误 `{"error": "…"}` 到 stderr；退出码：0 成功 / 2 参数或配置问题 / 3 资源不存在或权限 / 1 其他。
环境：`SHIFTLY_ROOT` 指数据目录（不设则用 App 记忆目录/向上查找）。

| 命令 | 参数 | 输出（成功） |
|---|---|---|
| `schedule show` | — | `{default_start_time, default_end_time, rules[], shift_types[]}` |
| `schedule set` | `--workdays MO,TU --from D [--shift-type id] [--start HH:MM --end HH:MM]` | `{rules[]}`（upsert 后全量） |
| `swap add` | `--from D --to D` | `{swaps[]}` |
| `swap list` | — | `{swaps[{index,…}]}` |
| `swap remove` | `<index>` | `{swaps[]}` |
| `leave add / list / remove` | `--start D --end D` / — / `<index>` | `{leave[…]}` |
| `shifts list` | `--from D --to D` | `{shifts[{date,kind,start,end,hours}]}` |
| `pay report` | `--month YYYY-MM` | `{month,currency,total_hours,total_amount,has_unrated_shifts,items[]}` |
| `log append` | `"text" [--date D]` | `{date,path}` |
| `log show` | `[--date D]` | `{date,content}` |
| `log path` | `[--date D]` | `{date,path,exists}` |
| `report hours` | `--period week\|month` | `{period,from,to,shift_count,total_hours,shifts[]}` |
| `sync now` | `[--window next_month]` | `{created,updated,deleted,readbacks,converged}`（需已在 App 授权日历） |

示例：

```bash
export SHIFTLY_ROOT=/path/to/shiftly-data
shiftly-cli shifts list --from 2026-07-01 --to 2026-07-31
shiftly-cli swap add --from 2026-07-22 --to 2026-07-24
shiftly-cli sync now
```

## 4. Shiftly MCP server

`packages/mcp-server/`（node + zod，stdio），每个工具 = 一次 CLI 调用；
工具面共 11 个：get_schedule / set_schedule / list_shifts / add_swap /
add_leave / list_overrides / remove_override / pay_report / log_append /
log_read / sync_now。详见 packages/mcp-server/README.md。

注册示例（SHIFTLY_ROOT 指数据目录；CLI 路径缺省自动探测，也可用 SHIFTLY_CLI 指定）：

```bash
claude mcp add shiftly -e SHIFTLY_ROOT=/path/to/shiftly-data \
  -- node /绝对路径/shiftly/packages/mcp-server/index.js
```

## 5. AI 直接编辑文件守则

1. **优先用 MCP / CLI**——它们校验输入并保证格式；直接改文件是兜底手段。
2. 改前**读全文件**；写回时**保留所有未知字段**（顶层与嵌套都算），2 空格缩进。
3. 只改 §0 表中标注可写的文件；`sync_state.json` 等私有文件一律不碰。
4. `config.rules` 只允许追加或同日替换，**不得删除历史规则**（未来日期的规则可删）。
5. `pay.rates` 只追加新段，不改动历史段。
6. 写完提醒（或代为执行）同步：`shiftly-cli sync now` / MCP `sync_now`，
   否则日历不会更新；App 开着时界面可能需要点 Refresh 才反映外部改动。
7. 日志文件：可自由编辑正文；保留 frontmatter 块；快记条目用 `- HH:MM 内容` 格式追加。
