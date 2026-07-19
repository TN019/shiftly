# Shiftly — 会话快速上下文

## 这是什么

**Shiftly**（旧名 Shifty）：本地优先的 macOS **排班 + 工资 + Markdown 工作日志**
三合一应用，与 Apple Calendar 双向同步（EventKit，回读+撤销）。
不做网站部署；日常使用零终端（双击 .app，登录自启 + 自动同步）。
**v2 规划（M1–M6，31 张卡）已于 2026-07-17 全部完成（v0.7.0）；v0.8 开发中：
一键上班 routine、历史导入、公共假期、无薪休息、日志/笔记体系（应用内编辑器）、
Meetings（录音 + Scripto 转录）、原生 WidgetKit 组件（深链按钮）、标准存储布局。**

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

1. [docs/DATA_AND_API.md](docs/DATA_AND_API.md) —— 数据 schema、CLI 与 MCP 的权威契约
2. [docs/SYNC_DESIGN.md](docs/SYNC_DESIGN.md) —— 日历双向同步设计
3. [docs/SETUP.md](docs/SETUP.md) —— 安装/launchd/迁移等技术参考（README 已产品化，
   分 [README.md](README.md) 英文 / [README.zh-Hans.md](README.zh-Hans.md) 中文）
4. [docs/PLAN.md](docs/PLAN.md) —— v2 路线图归档

## 任务管理（mingri）

任务卡在用户自建的 mingri 看板（https://mingri.vercel.app）：

- 项目：**Shiftly**，project_id `16cfcb5f-28c4-4658-a4d8-78299fb5ae24`
- 里程碑 M1–M6 已建，31 张任务卡按里程碑归档（2026-07-16 建）
- 访问方式：本项目已注册 `mingri` MCP（工具：list_projects / list_tasks / create_task /
  update_task / complete_task…）；若 MCP 不可用，REST API 为
  `https://mingri.vercel.app/api/v1`，Bearer key 见 `~/.claude.json` 中本项目的 mcpServers 配置
- **做完一张卡的事就把卡标记 done**（update_task status=done）

## 代码布局

```
ShiftlyApp/Sources/ShiftlyKit/           领域核心（无 UI 依赖）：模型、同步引擎
                                         （SyncEngine/Coordinator/EKCalendarStore）、
                                         工资（PayEngine）、日志与笔记（WorkLogStore）、
                                         会议（Meetings/SRT）、导入（HistoryImporter）、
                                         存储（StorageLayout/DataReset）、Routine、
                                         FolderWatcher、DataStore/ConfigLogic
ShiftlyApp/Sources/ShiftlyApp/           GUI：七区导航（今日/排班/日历/工资/日志/
                                         会议/设置）、月历、规则管理、菜单栏、通知、
                                         应用内 Markdown 编辑窗、会议播放窗
ShiftlyApp/Widgets/                      WidgetKit 组件源（build_app.sh 用 swiftc
                                         打进 PlugIns/ShiftlyWidgets.appex；入口
                                         必须 -e _NSExtensionMain + sandbox 签名）
ShiftlyApp/Sources/shiftly/              CLI（JSON 输出，AI/脚本入口）
ShiftlyApp/Tests/ShiftlyKitTests/        Swift Testing（74 用例；本机只有 CLT，
                                         跑法见 scripts/test.sh）
ShiftlyApp/Localization/zh-Hans.lproj/   中文翻译（英文键即兜底）
packages/mcp-server/                     Shiftly MCP server（node，封装 CLI）
scripts/schedule_core.py + planner.py    排班求解唯一真相源（Python）+ CLI 面
scripts/main.applescript                 AppleScript 菜单（备用入口）
scripts/{build_app,test}.sh              打包 dist/Shiftly.app / 一键全测试
data/                                    JSON 数据（gitignore，schema 见 DATA_AND_API.md）
launchd/com.shiftly.sync.plist           无人值守定时同步模板（调 Shiftly --sync）
```

## 常用命令

```bash
cd ShiftlyApp && swift run               # 跑 GUI（开发）
scripts/build_app.sh                     # 打包 dist/Shiftly.app（双击启动）
scripts/test.sh                          # 全部测试（--fast 跳过 swift）
dist/Shiftly.app/Contents/MacOS/Shiftly --sync   # 无头同步（launchd/菜单同款入口）
```

根目录解析：环境变量 `SHIFTLY_ROOT`（旧名 `SHIFTY_ROOT`/`SHIFTFLOW_ROOT` 兼容），
否则从可执行文件/脚本位置向上找 `data/config.json`。

## 约定与坑

- 排班求解算法唯一真相源是 schedule_core.py（planner.py 是它的 CLI 面）；
  Swift 侧只叠加 manual_shifts / overrides，不复制算法；
- 数据契约以 docs/DATA_AND_API.md 为准（改代码须同步改文档）；
- 测试时别用真实 config.json / 真实日历（造临时根目录 + calendar_name 用测试名）；
- 本机只有 CLT（无 Xcode/XCTest）：Swift 测试用 `import Testing`，跑法见 scripts/test.sh；
  UserNotifications / SMAppService 仅在打包后的 .app 内生效；
- 包内 CLI 叫 shiftly-cli（大小写不敏感文件系统会与主程序 Shiftly 撞名）；
- 用户主语言中文，回复用中文。
