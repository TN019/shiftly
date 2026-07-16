# Apple Calendar 双向同步设计（M2）

> 目标：Shiftly 与 Apple Calendar 的 **Shifts** 日历双向保持一致。
> 用户在日历里拖动/删除/新建班次事件，Shiftly 能理解并回写到自己的数据；
> Shiftly 里的规则/换班/请假变更，也增量地反映到日历。

## 1. 技术底座

- **EventKit**（`EKEventStore`），macOS 14+ 需要 Full Access
  （`NSCalendarsFullAccessUsageDescription`），macOS 13 走旧权限。
- 事件身份：使用 `eventIdentifier` + 本地映射表，不再依赖旧版的
  `[SF_SYNC]` notes 文本标记（迁移期兼容识别旧标记，见 §6）。

## 2. 同步状态存储 `data/sync_state.json`

```jsonc
{
  "version": 1,
  "calendar_id": "EKCalendar identifier",
  "last_sync_at": "2026-07-16T10:00:00+08:00",
  "entries": [
    {
      "date": "2026-07-18",            // 班次归属日（跨午夜按开始时间算）
      "kind": "rule|swap|manual",       // 班次来源
      "event_id": "EK eventIdentifier",
      "fingerprint": "sha256(start|end|title)"  // 上次写入/看到的内容指纹
    }
  ]
}
```

`fingerprint` 用来区分"我上次写的样子"和"现在日历里的样子"，是检测用户改动的依据。

## 3. 同步流程（单次 Sync 的五步）

1. **计算期望态**：ShiftlyKit 由 rules + swaps + leave 求出窗口内的计划班次集合 `P`。
2. **读取日历态**：取 Shifts 日历窗口内全部事件 `E`（一次谓词查询，不遍历全日历）。
3. **三方 diff**（期望态 `P` × 日历态 `E` × 映射表 `S`）：

   | 情况 | 判定 | 动作 |
   |------|------|------|
   | P 有，S 无 | Shiftly 新增班次 | 创建事件，写入映射 |
   | P 有，S 有，E 中事件与 fingerprint 一致但与 P 不同 | Shiftly 侧修改（如改了上下班时间） | 更新事件 |
   | P 有，S 有，E 中事件与 fingerprint 不一致 | **用户在日历改了事件** | 回读：生成换班/时间覆盖记录（§4） |
   | P 有，S 有，E 中事件不存在 | **用户在日历删了事件** | 回读：生成当日请假/停班记录 |
   | P 无，S 有，E 一致 | Shiftly 侧取消班次（请假等） | 删除事件，清映射 |
   | E 有，S 无，且事件可识别为班次格式 | **用户在日历手动新建** | 回读：生成 `kind=manual` 单次班次 |

4. **应用回读**：把第 3 步产生的回读变更写入 `data/`（swaps/leave/manual_shifts），
   然后**重算期望态并二次校验**（一轮内收敛，避免震荡）。
5. **写报告**：变更摘要存 `data/meta.json`（含 error 状态——旧版只会写 success），
   UI 展示"本次同步：新建 2、回读换班 1、删除 0"，回读条目可单条撤销。

## 4. 回读语义（Calendar → Shiftly 的翻译规则)

- **事件被移动到另一天** → `swaps.json` 追加 `{from_date, to_date}`。
- **事件当天时间被修改** → 当日时间覆盖记录（新增 `overrides` 数据，仅当日生效，不改全局默认时间）。
- **事件被删除** → `leave.json` 追加单日请假（UI 上区分显示为"日历侧移除"）。
- **手动新建事件**（在 Shifts 日历内）→ 单次班次记录，参与工资计算与工作历史。
- 识别不了的事件（其他 app 写入、格式不符）：忽略并在报告中列出，绝不删除非 Shiftly 管理的事件。

## 5. 冲突策略

同一班次在两侧同时被改（Shiftly 改了规则、日历里也拖动了事件）：

- **默认：日历侧胜出**（一次性事实调整以日历为准），规则仍然是未来班次的生成源；
- 特例：Shiftly 取消班次（请假）而用户同时改动了事件 → 事件保留为单次班（用户塑造成什么样就是什么样）；
- 状态丢失/旧标记认领时无法判断谁改的 → **计划侧胜出**（确定性重建，绝不重复建事件）；
- 报告中标注回读项，允许用户单条撤销（即改判为"以 Shiftly 为准"，撤销后重新同步回写日历）。

理由：日历是用户日常触点，拖一下事件是最自然的"我换班了"表达。

### 报告与撤销（已实现）

- `data/last_sync_report.json` —— 最近一次同步摘要：时间、状态（success/error + 原因）、
  新建/更新/删除计数、回读数、被跳过的外部事件标题、是否收敛；
- `data/readback_log.json` —— 回读日志（追加式，保留最近 50 条，带 undone 标记），
  UI 的 Sync Report 卡片按此渲染撤销列表；
- **撤销语义**：删除该回读在数据文件里创建的那条记录（swap/override/单日 leave/manual），
  标记 undone，随后再跑一次同步——计划恢复原状并回写日历（事件可能重建，identifier 允许改变）；
- 两个文件均为引擎私有状态，不面向用户编辑。

## 6. 迁移与兼容

- 首次以 EventKit 同步时：扫描窗口内含 `[SF_SYNC]` 标记的旧事件，
  按日期认领进映射表（不重建，保持事件不闪烁），之后不再写该标记。
- `History.csv` 一次性导入逻辑保留（marker 文件 `data/meta.history_imported`）。
- launchd 定时任务改为调 `shiftly sync`（CLI），或由常驻 app 的内部 Timer 承担。

## 7. 边界情况清单（测试必须覆盖）

- 跨午夜班次（end < start，+1 天）归属日判定；
- 用户把事件移出同步窗口 / 移进窗口；
- 同一天既有换班又有请假；
- 月底运行（旧版 parseDateTime 翻转 bug 的回归用例）；
- 日历被整体删除 / 更名（重建 + 全量重写，映射作废）；
- 全天事件、重复事件（Shiftly 不生成，回读时忽略并报告）。
