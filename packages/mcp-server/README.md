# @shiftly/mcp-server

把 `shiftly` CLI 封装成 MCP 工具：AI 会话可直接查排班、换班、请假、读写工作日志、出工资报告、触发日历同步。

## 工具

| 工具 | 说明 |
|------|------|
| `get_schedule` | 排班配置：默认时间、规则时间线、班次类型 |
| `set_schedule` | 新增/更新一条规则（同日覆盖、异日追加，历史保留） |
| `list_shifts` | 引擎求解后的实际班次（from/to 区间） |
| `add_swap` | 换班（from_date → to_date） |
| `add_leave` | 请假（start_date ~ end_date） |
| `list_overrides` | 全部换班/请假记录（带 index） |
| `remove_override` | 按 kind + index 删除一条换班/请假 |
| `list_holidays` | 列出全部公共假期 |
| `add_holiday` | 新增公共假期（该日不排班） |
| `remove_holiday` | 删除某天的公共假期 |
| `pay_report` | 某月工资明细与合计 |
| `log_append` | 追加带时间戳的工作日志 |
| `log_read` | 读取某天日志全文 |
| `routine_show` | 一键上班流程步骤列表 |
| `routine_run` | 执行一键上班流程（已勾选步骤） |
| `sync_now` | 日历双向同步（需已在 App 授权） |

写操作只落数据文件；日历更新需 `sync_now` 或在 App 里 Sync。

## 配置

1. 安装依赖（一次性）：

   ```bash
   cd packages/mcp-server && npm install
   ```

2. 注册到 Claude Code：

   ```bash
   claude mcp add shiftly \
     -e SHIFTLY_ROOT=/path/to/your/shiftly-data \
     -- node /绝对路径/shiftly/packages/mcp-server/index.js
   ```

环境变量：

- `SHIFTLY_ROOT`（必填）— 数据目录（包含 `data/` 的文件夹）
- `SHIFTLY_CLI`（可选）— shiftly 二进制路径；缺省依次探测
  `/Applications/Shiftly.app/Contents/MacOS/shiftly-cli` → 仓库 `dist/` → `.build/`

## 说明

- 纯 ESM 零构建，仅两个依赖（MCP SDK + zod）
- 错误原样透传 CLI 的结构化信息（如"pay not configured"、非法日期）
- `sync_now` 的日历权限属于 CLI 二进制的宿主；先在 Shiftly App 里完成一次授权
