#!/usr/bin/env node
// Shiftly MCP Server: wraps the `shiftly` CLI as semantic MCP tools so AI
// sessions can CRUD the schedule, overrides, pay and work logs directly.
//
// Environment:
//   SHIFTLY_ROOT — data folder (required; the folder containing data/)
//   SHIFTLY_CLI  — path to the shiftly binary (optional; common install
//                  locations are probed when unset)

import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const ROOT = process.env.SHIFTLY_ROOT;
if (!ROOT) {
  console.error("SHIFTLY_ROOT must point to the Shiftly data folder.");
  process.exit(1);
}

const CLI_CANDIDATES = [
  process.env.SHIFTLY_CLI,
  "/Applications/Shiftly.app/Contents/MacOS/shiftly-cli",
  new URL("../../dist/Shiftly.app/Contents/MacOS/shiftly-cli", import.meta.url).pathname,
  new URL("../../ShiftlyApp/.build/release/shiftly", import.meta.url).pathname,
  new URL("../../ShiftlyApp/.build/debug/shiftly", import.meta.url).pathname,
].filter(Boolean);

const CLI = CLI_CANDIDATES.find((p) => existsSync(p));
if (!CLI) {
  console.error(
    "shiftly CLI not found. Set SHIFTLY_CLI or install Shiftly.app " +
      "(scripts/build_app.sh puts the CLI at Contents/MacOS/shiftly-cli).",
  );
  process.exit(1);
}

function cli(args) {
  return new Promise((resolve, reject) => {
    execFile(
      CLI,
      args,
      { env: { ...process.env, SHIFTLY_ROOT: ROOT }, timeout: 60_000 },
      (error, stdout, stderr) => {
        if (error) {
          try {
            reject(new Error(JSON.parse(stderr).error));
          } catch {
            reject(new Error(stderr.trim() || String(error)));
          }
          return;
        }
        try {
          resolve(JSON.parse(stdout));
        } catch {
          resolve(stdout.trim());
        }
      },
    );
  });
}

function textResult(data) {
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

const DATE = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "YYYY-MM-DD");
const HHMM = z.string().regex(/^\d{1,2}:\d{2}$/, "HH:MM");
const WORKDAY = z.enum(["MO", "TU", "WE", "TH", "FR", "SA", "SU"]);

const server = new McpServer({ name: "shiftly", version: "0.1.0" });

server.registerTool(
  "get_schedule",
  {
    description: "当前排班配置：默认时间、规则时间线（effective_from + workdays + 班次类型）、班次类型列表",
    inputSchema: {},
  },
  async () => textResult(await cli(["schedule", "show"])),
);

server.registerTool(
  "set_schedule",
  {
    description: "新增/更新一条排班规则（同 effective_from 覆盖，否则追加；历史规则保留）",
    inputSchema: {
      workdays: z.array(WORKDAY).min(1).describe("工作日列表，如 [\"MO\",\"TU\"]"),
      effective_from: DATE.describe("生效日期"),
      shift_type: z.string().optional().describe("班次类型 id（可选，缺省用默认时间）"),
      start: HHMM.optional().describe("同时更新默认开始时间（可选）"),
      end: HHMM.optional().describe("同时更新默认结束时间（可选）"),
    },
  },
  async ({ workdays, effective_from, shift_type, start, end }) => {
    const args = ["schedule", "set", "--workdays", workdays.join(","), "--from", effective_from];
    if (shift_type) args.push("--shift-type", shift_type);
    if (start) args.push("--start", start);
    if (end) args.push("--end", end);
    return textResult(await cli(args));
  },
);

server.registerTool(
  "list_shifts",
  {
    description: "排班引擎求解后的实际班次（含换班/请假/改时/单次班的影响）",
    inputSchema: {
      from: DATE.describe("起始日期"),
      to: DATE.describe("结束日期"),
    },
  },
  async ({ from, to }) => textResult(await cli(["shifts", "list", "--from", from, "--to", to])),
);

server.registerTool(
  "add_swap",
  {
    description: "换班：把 from_date 的班移到 to_date（写入后需 sync_now 才会更新日历）",
    inputSchema: {
      from_date: DATE,
      to_date: DATE,
    },
  },
  async ({ from_date, to_date }) =>
    textResult(await cli(["swap", "add", "--from", from_date, "--to", to_date])),
);

server.registerTool(
  "add_leave",
  {
    description: "请假：start_date 到 end_date（含双端；写入后需 sync_now）",
    inputSchema: {
      start_date: DATE,
      end_date: DATE,
    },
  },
  async ({ start_date, end_date }) =>
    textResult(await cli(["leave", "add", "--start", start_date, "--end", end_date])),
);

server.registerTool(
  "list_overrides",
  {
    description: "列出全部换班与请假记录（带 index，供 remove_override 使用）",
    inputSchema: {},
  },
  async () => {
    const [swaps, leave] = await Promise.all([cli(["swap", "list"]), cli(["leave", "list"])]);
    return textResult({ ...swaps, ...leave });
  },
);

server.registerTool(
  "remove_override",
  {
    description: "删除一条换班或请假记录（index 来自 list_overrides）",
    inputSchema: {
      kind: z.enum(["swap", "leave"]),
      index: z.number().int().min(0),
    },
  },
  async ({ kind, index }) => textResult(await cli([kind, "remove", String(index)])),
);

server.registerTool(
  "pay_report",
  {
    description: "某月工资明细与合计（记账货币计；需先在 App 配置 pay）",
    inputSchema: {
      month: z.string().regex(/^\d{4}-\d{2}$/, "YYYY-MM").describe("月份，如 2026-07"),
    },
  },
  async ({ month }) => textResult(await cli(["pay", "report", "--month", month])),
);

server.registerTool(
  "log_append",
  {
    description: "追加一条带时间戳的工作日志（文件缺失自动按当日班次建档）",
    inputSchema: {
      text: z.string().min(1).describe("日志内容"),
      date: DATE.optional().describe("日期（缺省今天）"),
    },
  },
  async ({ text, date }) => {
    const args = ["log", "append", text];
    if (date) args.push("--date", date);
    return textResult(await cli(args));
  },
);

server.registerTool(
  "log_read",
  {
    description: "读取某天的工作日志全文（不存在时报错）",
    inputSchema: {
      date: DATE.optional().describe("日期（缺省今天）"),
    },
  },
  async ({ date }) => {
    const args = ["log", "show"];
    if (date) args.push("--date", date);
    return textResult(await cli(args));
  },
);

server.registerTool(
  "routine_show",
  {
    description: "查看一键上班流程的步骤列表（kind/value/args/enabled）",
    inputSchema: {},
  },
  async () => textResult(await cli(["routine", "show"])),
);

server.registerTool(
  "routine_run",
  {
    description: "执行一键上班流程（打开已勾选的 App/网站/目录/命令；sync 步骤需另行调用 sync_now）",
    inputSchema: {},
  },
  async () => textResult(await cli(["routine", "run"])),
);

server.registerTool(
  "sync_now",
  {
    description: "执行一次日历双向同步（需已在 Shiftly App 授权日历权限）",
    inputSchema: {
      window: z.enum(["month", "next_month"]).optional().describe("同步窗口（缺省本月剩余）"),
    },
  },
  async ({ window }) => {
    const args = ["sync", "now"];
    if (window) args.push("--window", window);
    return textResult(await cli(args));
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
