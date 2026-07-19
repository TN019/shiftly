# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report privately through GitHub's **"Report a vulnerability"** button under the
repository's **Security** tab
([Security Advisories](https://github.com/TN019/shiftly/security/advisories/new)).
Include what you found, how to reproduce it, and the potential impact. You'll get a
response as soon as reasonably possible.

## Scope

Shiftly runs entirely on your own Mac and makes no network calls of its own. The
relevant security surface is local:

- **Apple Calendar access** via EventKit (events Shiftly reads and writes),
- **local data files** it reads and writes, and
- the **schedule/pay scripts** it runs as subprocesses.

Reports about calendar-data handling, file handling, or subprocess/script execution
are especially welcome. The optional MCP server (`packages/mcp-server`) exposes Shiftly
data to local AI tooling — issues there are in scope too.

## Supported versions

Fixes land on `main` and in the latest release. There is no long-term support branch.
