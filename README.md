<div align="center">

<img src="assets/icon.png" width="128" alt="Shiftly icon" />

# Shiftly

**Your shifts, your pay, your work journal — living right inside Apple Calendar.**

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](docs/SETUP.md)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](docs/SETUP.md)
[![License](https://img.shields.io/badge/license-PolyForm%20NC-lightgrey)](LICENSE)
[![Release](https://img.shields.io/badge/release-v0.7.0-brightgreen)](https://github.com/TN019/shiftly/releases)

[English](README.md) · [简体中文](README.zh-Hans.md)

</div>

---

Shiftly is a native macOS app for anyone who works shifts. Set your weekly
pattern once — Shiftly writes it into a dedicated Apple Calendar, keeps it in
sync **both ways**, works out your pay, and gives every workday a Markdown
journal page. All of it on your Mac, in plain files you own.

## ✨ What it does

### 📅 Calendar sync that goes both ways

Your schedule lands in Apple Calendar — and Apple Calendar talks back.
**Drag a shift to another day** and Shiftly records it as a swap. **Delete
one** and it becomes a day off. **Create one** and it counts as an extra
shift. Every change is listed in a sync report, and any of them can be
undone with one click.

### 🗓 See your month at a glance

A month view shows regular shifts, swapped days, one-off shifts and leave in
different colors. Click any day to swap it, take leave, or open that day's
journal. Rules keep their history — change your pattern from next month, and
past records stay exactly as they were.

### 💰 Know what you've earned

Set your hourly rate (raises keep their effective dates) and Shiftly turns
worked shifts into money: a monthly chart of the last 12 months, year-to-date
totals, per-shift breakdowns, and payslip export to CSV or Markdown. Flip the
display between **AUD / CNY / USD** with your own exchange rates — nothing is
ever fetched from the internet.

### 📝 A journal page for every workday

One Markdown file per day, stored in a folder *you* choose, openable in any
editor. Jot a quick timestamped note from the app, search everything later,
and jump to any day's page straight from the calendar.

### 🔔 Lives in your menu bar

Next shift and countdown at a glance, one-click sync, pre-shift reminders
(configurable lead time), auto-sync on a schedule, launch at login. Close the
window — Shiftly keeps working.

### 🤖 Built for the AI era

Everything Shiftly knows lives in human-readable JSON and Markdown, with a
[documented contract](docs/DATA_AND_API.md). A bundled CLI speaks JSON, and an
[MCP server](packages/mcp-server/) lets AI assistants like Claude manage your
schedule in natural language: *"move Wednesday's shift to Friday and sync the
calendar."*

### 🔒 Local-first, private by design

No account. No server. No analytics. Your schedule, pay and journals are
plain files in a folder you picked — back them up, sync them, grep them,
take them anywhere.

## 🚀 Get started

```bash
git clone https://github.com/TN019/shiftly.git && cd shiftly
scripts/build_app.sh && cp -R dist/Shiftly.app /Applications/
```

Then it's three steps:

1. **Open Shiftly** and pick a folder for your data (any empty folder works)
2. **Set your weekly pattern** — which days, what hours
3. **Press Sync Now** and allow calendar access

Your shifts are in Apple Calendar. From here on, editing either side keeps
both in sync.

## 📚 Learn more

| | |
|---|---|
| [Setup & technical reference](docs/SETUP.md) | Install details, scheduled sync, migration |
| [Data & interface reference](docs/DATA_AND_API.md) | File schemas, CLI, MCP — the contract for scripts & AI |
| [Sync design](docs/SYNC_DESIGN.md) | How two-way sync works under the hood |
| [Project history](docs/PLAN.md) | The v2 roadmap that built all of this |

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free for personal and other
noncommercial use; commercial use requires a separate license from the author.

> Required Notice: Copyright (c) 2026 Blake Liu (https://github.com/TN019/shiftly)
