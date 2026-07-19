<div align="center">

<img src="assets/icon.png" width="128" alt="Shiftly 图标" />

# Shiftly

**排班、工资、工作日志——都住进你的 Apple 日历。**

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](docs/SETUP.md)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](docs/SETUP.md)
[![License](https://img.shields.io/badge/license-PolyForm%20NC-lightgrey)](LICENSE)
[![Release](https://img.shields.io/badge/release-v0.7.0-brightgreen)](https://github.com/TN019/shiftly/releases)

[English](README.md) · [简体中文](README.zh-Hans.md)

</div>

---

Shiftly 是一款为上班倒班的人做的 macOS 原生应用。设置一次每周排班，它会把班次写进专属的
Apple 日历并**双向**保持同步，替你算好工资，还给每个工作日配一页 Markdown 日志。
一切都在你的 Mac 上，存在你自己的文件里。

## ✨ 它能做什么

### 📅 双向的日历同步

排班写进 Apple 日历——日历里的改动也会回来。**把班拖到另一天**，Shiftly 记为换班；
**删掉一个班**，就是当天休息；**手动新建一个**，算作加班。每次同步做了什么都有报告，
每条改动都能一键撤销。

### 🖥 原生桌面组件，一键开始一天

真正的 WidgetKit 桌面组件（小方格 / 横向中格）把接下来的班摆在桌面上，
还带三个按钮：**Start Work** 一键跑完你的上班流程——打开钉钉、微信、网站、
在工作目录开好终端，全程不弹主窗口；**Meeting** 直达录音页；**QNotes**
直接弹出笔记编辑窗。流程步骤在设置里随意勾选。

### 🎙 会自己出转录的会议

一键把会议录进按时间戳命名的文件夹，再让 [Scripto](https://github.com/TN019/scripto)
在本机完成转录和翻译——不上云、无界面、各一个按钮。录音可以直接在 Shiftly
里回放，转录随播放逐句高亮，点任意一句即可跳到对应时间。

### 🗓 一眼看清整个月

月视图用不同颜色区分规则班、换班、单次班、请假和公共假期。点任意日期即可换班、
请假、或打开那天的日志。节假日可从任一订阅日历一键导入——假期自动不排班。
规则带着历史——下月起换新排班，过去的记录分毫不动。日历里已经躺着几个月的
上班记录？按真实工时一键导入成历史。

### 💰 挣了多少，清清楚楚

设好时薪（调薪各有生效日期）和每班的无薪休息，Shiftly 把上过的班换算成钱：
近 12 个月柱状图、本年累计、逐班明细、CSV / Markdown 工资单导出。显示币种可在 **AUD / CNY / USD**
间切换，汇率由你手工维护——绝不联网获取。

### 📝 每个工作日一页日志

每个班一个 Markdown 日志，外加独立的快速笔记，各自存在你指定的文件夹里。
在 Shiftly 里就能编辑和预览（GitHub 风格），一键跳到 VS Code 也行。
休息日写的复盘自动记进上一个工作日，所有内容都能全文搜索。

### 🔔 常驻菜单栏

下一班时间和倒计时抬眼可见，一键同步，班前提醒（提前量可调），定时自动同步，
登录时或工作日定点自动启动。关掉窗口，Shiftly 继续干活。

### 🤖 为 AI 时代而生

Shiftly 的一切数据都是人类可读的 JSON 和 Markdown，并有
[成文的契约文档](docs/DATA_AND_API.md)。自带 JSON 输出的命令行工具，配套的
[MCP server](packages/mcp-server/) 让 Claude 这样的 AI 助手能用自然语言管理你的排班：
「把周三的班换到周五，然后同步日历。」

### 🔒 本地优先，隐私为本

没有账号，没有服务器，没有数据统计。首次设置在你选的文件夹下自动铺好一切——
数据、日志、笔记、会议录音各归其位，之后任何一处都能整体迁移（文件由 Shiftly
搬好，原地不留）。想备份、想同步、想 grep、想带走，都随你；一键重置只抹掉
Shiftly 自己创建的内容，别的一概不动。

## 🚀 开始使用

```bash
git clone https://github.com/TN019/shiftly.git && cd shiftly
scripts/build_app.sh && cp -R dist/Shiftly.app /Applications/
```

然后只需三步：

1. **打开 Shiftly**，选一个文件夹存数据（任何空文件夹都行）
2. **设置每周排班**——哪几天上班、几点到几点
3. **点「立即同步」**，允许日历访问

班次已经躺在 Apple 日历里了。此后无论在哪边改，两边都保持一致。

## 📚 更多文档

| | |
|---|---|
| [安装与技术参考](docs/SETUP.md) | 安装细节、定时同步、迁移说明 |
| [数据与接口参考](docs/DATA_AND_API.md) | 文件 schema、CLI、MCP——脚本与 AI 的契约 |
| [同步设计](docs/SYNC_DESIGN.md) | 双向同步的底层原理 |
| [项目历程](docs/PLAN.md) | 造出这一切的 v2 路线图 |

## 许可证

[PolyForm Noncommercial 1.0.0](LICENSE)——个人及其他非商业用途免费；
商业使用需向作者另行取得授权。

> Required Notice: Copyright (c) 2026 Blake Liu (https://github.com/TN019/shiftly)
