# Shiftly — 会话快速上下文

## 这是什么

**Shiftly**（旧名 Shifty，已更名）：本地优先的 macOS 排班工具，正在扩展为
**排班 + 工资计算可视化 + Markdown 工作日志** 三合一应用，与 Apple Calendar 双向同步。
不做网站部署；日常使用零终端（双击 .app）。

## Git / PR 约定

- 仓库：`TN019/shiftly`（原 shifty，GitHub 已改名）。feature 分支开发，push + 建 PR 都允许，
  **但绝不执行 PR 合并**——合并永远留给用户。
- commit：一句话，`feat:/fix:/chore:/refactor:/docs:/test:` 前缀（参考 git log 既有格式）；
  author/committer 用默认 git 身份（用户本人），消息末尾加
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer。
- PR 描述：**背景 / 改动 / 验证** 三段；PR 归 Claude（保留 Generated with Claude Code 页脚），
  不写用户为 co-author。
- **GitHub 上的一切文字（PR 描述、评论）只做客观描述**：不出现"你/我"等对话措辞、
  不写承诺（"下次会…""合并后我会…"）；未自动化的验证写成「未自动化验证项」小节，
  内容为中性的操作步骤与预期。
- 代码质量：自测后再交；无法自测的（如真实日历交互）在 PR 里写清让用户测什么、怎么测、预期效果。
- 拿不准的事先问用户，不要擅自决定。

## 先读这些

1. [docs/PLAN.md](docs/PLAN.md) —— 总体方案、目标架构、M1–M6 路线图、已知 bug 清单
2. [docs/SYNC_DESIGN.md](docs/SYNC_DESIGN.md) —— 日历双向同步设计（M2）
3. [docs/DATA_AND_API.md](docs/DATA_AND_API.md) —— 数据 schema、`shiftly` CLI 与 MCP 设计（M6）

## 任务管理（mingri）

任务卡在用户自建的 mingri 看板（https://mingri.vercel.app）：

- 项目：**Shiftly**，project_id `16cfcb5f-28c4-4658-a4d8-78299fb5ae24`
- 里程碑 M1–M6 已建，31 张任务卡按里程碑归档（2026-07-16 建）
- 访问方式：本项目已注册 `mingri` MCP（工具：list_projects / list_tasks / create_task /
  update_task / complete_task…）；若 MCP 不可用，REST API 为
  `https://mingri.vercel.app/api/v1`，Bearer key 见 `~/.claude.json` 中本项目的 mcpServers 配置
- **做完一张卡的事就把卡标记 done**（update_task status=done）

## 当前代码布局（v1，重构前）

```
ShiftlyApp/Sources/ShiftlyKit/           领域核心（无 SwiftUI/AppKit）：Models、Paths、
                                         ConfigLogic、DataStore、ScriptRunners
ShiftlyApp/Sources/ShiftlyApp/           App：AppMain、AppModel、ContentView、
                                         OverridesViews、HistoryViews
ShiftlyApp/Tests/ShiftlyKitTests/        Swift Testing（import Testing，非 XCTest——
                                         本机只有 CLT，跑法见 scripts/test.sh）
scripts/schedule_core.py                 排班核心（Python，规则+换班+请假求解）
scripts/planner.py                       AppleScript 唯一的 Python 入口（CLI）
scripts/sync.applescript                 现行同步引擎（AppleScript，M2 用 EventKit 替代）
scripts/main.applescript                 AppleScript 菜单入口
scripts/{report,work_history,apply_setup,needs_setup}.py   辅助脚本
scripts/test.sh                          一键跑全部测试（python + applescript + swift）
data/                                    JSON 数据（整目录 gitignore，schema 见 DATA_AND_API.md）
launchd/com.shiftly.sync.plist           定时同步模板
```

## 常用命令

```bash
cd ShiftlyApp && swift run               # 跑 GUI（开发）
scripts/build_app.sh                     # 打包 dist/Shiftly.app（双击启动）
scripts/test.sh                          # 全部测试（--fast 跳过 swift）
osascript scripts/sync.applescript       # 手动同步（旧链路）
```

根目录解析：环境变量 `SHIFTLY_ROOT`（旧名 `SHIFTY_ROOT`/`SHIFTFLOW_ROOT` 兼容），
否则从可执行文件/脚本位置向上找 `data/config.json`。

## 约定与坑

- 排班逻辑目前在 3 处重复（schedule_core.py + sync.applescript 两段内嵌 Python），
  M1 会收敛到一份——在那之前改排班语义必须三处同步改；
- `sync.applescript` 的 `parseDateTime` 有月底翻转 bug（M1 卡）；
- Swift 保存 config 会丢未知字段、UI 保存会覆盖 rules 历史（均为 M1 卡）——
  测试时别用真实 config.json；
- 日历事件靠 notes 里的 `[SF_SYNC]` 标记识别（M2 后改为 eventIdentifier 映射）；
- 用户主语言中文，回复用中文。
