# Contributing to Shiftly

Thanks for your interest in Shiftly! Bug reports, fixes, features, and docs are welcome.

> 中文读者：贡献前请阅读下方「Contribution terms」一节。为保证再许可条款在法律上明确，该节以英文为准。

## Project layout

- `ShiftlyApp/` — the native macOS app (Swift Package: `ShiftlyKit` domain core + `ShiftlyApp` / `shiftly` executables + tests)
- `scripts/` — the Python schedule/pay engine the app drives
- `packages/mcp-server/` — the MCP server (Node)

## Getting started

```bash
git clone https://github.com/TN019/shiftly.git && cd shiftly

# Swift core (needs Xcode 16+ for the Testing framework)
cd ShiftlyApp && swift test && cd ..

# Python engine (stdlib only)
python scripts/test_schedule_core.py
```

See [docs/SETUP.md](docs/SETUP.md) for building and running the app. Keep the test
suites green and add tests for behavior you change; `ShiftlyKit` stays free of
SwiftUI/AppKit so the core and CLI can reuse it.

## Reporting bugs

Open an issue with what you did, what you expected, what happened, and your macOS version.

## Contribution terms (please read)

Shiftly is released under the **PolyForm Noncommercial License 1.0.0** — free for
noncommercial use; commercial use requires a separate license from the author.

By submitting a contribution (a pull request, patch, or any other material) to this
project, you represent and agree that:

1. **You have the right to submit it.** The contribution is your own original work, or
   you otherwise have the right to submit it under these terms.

2. **License to the project and its users.** You license your contribution under the
   project's current license (PolyForm Noncommercial 1.0.0) to the project and to
   everyone who receives it.

3. **Relicensing grant to the author.** You additionally grant the project's author /
   maintainer a perpetual, worldwide, non-exclusive, royalty-free, irrevocable right to
   use, reproduce, modify, prepare derivative works of, sublicense, and **relicense**
   your contribution under any license terms — including **commercial or proprietary**
   terms — as part of this project or any derivative of it, without further notice,
   permission, or compensation.

This keeps the source available today while preserving the author's ability to offer
Shiftly (or a derivative) commercially in the future. If you do not agree to these
terms, please do not submit a contribution.

> These terms are a plain-language license grant, not legal advice. For anything
> significant, consult a lawyer.
