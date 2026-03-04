---
name: update-all
description: Update all system packages and tools in parallel — winget (Windows), npm globals, agent skills, and apt (Linux). Each update category runs as an independent parallel task, with winget packages also upgraded in parallel internally. Use when you want to bring everything up to date quickly.
license: MIT
metadata:
  author: chenxizhang
  version: "1.0"
---

# Update All

Update all system packages and developer tools in parallel — bringing everything up to date in one command.

## Update Tasks

| Task | When to Run | Internal Parallelism |
|------|-------------|---------------------|
| **winget upgrade** | Windows only | ✅ Each package upgraded in parallel |
| **npm update -g** | If Node.js is installed | Single command |
| **npx skills update -g -y** | If Node.js is installed | Single command |
| **sudo apt update && sudo apt upgrade -y** | Linux only | Single command |

**All tasks are completely independent and MUST run in parallel.**

## Strict Execution Flow

**Do NOT use any scripts. Do NOT skip or merge phases. Execute each phase in order.**

---

### Phase 1: Environment Detection (MANDATORY — must display results before proceeding)

Detect and **explicitly display** the following before doing anything else:

1. **Operating System**:
   - Windows: `[System.Environment]::OSVersion` or `$env:OS`
   - macOS/Linux: `uname -s` and `cat /etc/os-release 2>/dev/null | head -3`
2. **Shell environment**:
   - PowerShell: `$PSVersionTable.PSVersion`
   - bash/zsh: `echo $SHELL`
3. **Agent identity**: Identify which agent is running (Claude Code, GitHub Copilot CLI, Cursor, etc.)
4. **Available tools** — check which of the following are installed:
   - `winget`: `Get-Command winget -ErrorAction SilentlyContinue` (Windows)
   - `node`/`npm`: `Get-Command node -ErrorAction SilentlyContinue` or `which node`
   - `apt`: `which apt` (Linux)
5. **sudo status** (Windows only, required for winget):
   - Check if sudo exists: `Get-Command sudo -ErrorAction SilentlyContinue`
   - Check sudo mode: `sudo config`
   - **If sudo is not installed**: ⛔ STOP winget updates. Tell user to enable sudo in **Settings → System → For Developers → Enable sudo**
   - **If sudo mode is NOT `Inline`/`normal`**: ⛔ STOP winget updates. Tell user to run: `sudo sudo config --enable normal` (this requires a one-time UAC confirmation to switch to inline mode)

**Display the detection results clearly**, for example:
```
Environment Detection:
  OS:      Windows 11 Pro (10.0.22631)
  Shell:   PowerShell 7.4
  Agent:   GitHub Copilot CLI
  winget:  ✅ available
  node:    ✅ v22.0.0
  npm:     ✅ v10.8.0
  apt:     ❌ not available (Windows)
  sudo:    ✅ v1.0.1, Inline mode

Applicable update tasks:
  1. winget upgrade (parallel per package)
  2. npm update -g
  3. npx skills update -g -y
```

Another example (Linux):
```
Environment Detection:
  OS:      Ubuntu 24.04 LTS
  Shell:   bash 5.2
  Agent:   Claude Code
  winget:  ❌ not available (Linux)
  node:    ✅ v22.0.0
  npm:     ✅ v10.8.0
  apt:     ✅ available
  sudo:    ✅ available (Linux native)

Applicable update tasks:
  1. sudo apt update && sudo apt upgrade -y
  2. npm update -g
  3. npx skills update -g -y
```

**CRITICAL: If on Windows and sudo is missing or not in Inline/normal mode, do NOT proceed with winget updates. Display a clear warning and instructions. Other tasks (npm, skills) can still proceed.**

---

### Phase 2: Plan (generate environment-specific parallel execution plan)

Based on Phase 1 results, build the task list and parallel strategy.

#### Task Definitions

**Task A: winget upgrade (Windows only, requires sudo in Inline mode)**

1. Run `winget upgrade` (no elevation) to list all upgradable packages
2. Parse the output to extract package IDs
3. If no packages to upgrade, skip
4. For EACH package, run in parallel: `sudo winget upgrade --id <package-id> --silent --accept-package-agreements --accept-source-agreements`
5. Collect results per package

⚠️ **Internal parallelism is CRITICAL**: each package upgrade is independent — run them ALL in parallel using agent's parallel tool calls, not sequentially.

**Task B: npm update -g (if Node.js installed)**

Single command:
- Windows PowerShell: `npm update -g 2>&1`
- bash/zsh: `npm update -g 2>&1`

**Task C: npx skills update -g -y (if Node.js installed)**

Single command:
- All platforms: `npx skills update -g -y 2>&1`

**Task D: sudo apt update + upgrade (Linux only)**

Single command:
- `sudo apt update -y && sudo apt upgrade -y 2>&1`

#### Parallel Strategy

Based on the detected **agent identity**:

| Agent | Strategy |
|-------|----------|
| **GitHub Copilot CLI** | Launch Tasks A/B/C/D as parallel tool calls or sub-agents (task tool). For Task A's internal parallelism, use parallel tool calls for each winget package. |
| **Claude Code** | Use Agent Teams to dispatch each task as a sub-agent. Task A's sub-agent internally parallelizes per-package upgrades. |
| **Other agents** | Use whatever parallel execution mechanism is available. |

**Display the plan before executing**, e.g.:
```
Plan: 3 parallel update tasks
  Task A: winget upgrade — 5 packages (parallel per package)
  Task B: npm update -g
  Task C: npx skills update -g -y
  Strategy: 3 parallel sub-agents + Task A fans out 5 parallel winget calls
```

---

### Phase 3: Execute (all tasks in parallel)

**Launch ALL applicable tasks simultaneously. NEVER run them sequentially.**

For Task A (winget), the execution flow within the sub-agent:
1. Run `winget upgrade` to discover packages
2. Parse package IDs from the table output (the ID column)
3. For each package, launch a parallel tool call: `sudo winget upgrade --id <pkg> --silent --accept-package-agreements --accept-source-agreements`
4. Collect all results

For Tasks B, C, D: run the single command and capture output.

---

### Phase 4: Report & Recommendations

#### Summary Report

```
================================================================================
                           UPDATE ALL — SUMMARY
================================================================================
Timestamp: <time>
System:    <OS>
Agent:     <agent>

── winget upgrade ──────────────────────────────────
  [✓] Git.Git (2.52.0 → 2.53.0)
  [✓] Microsoft.VisualStudioCode (1.95 → 1.96)
  [✗] SomeApp.Failed — installer error (exit code 1)
  Succeeded: 2 / Failed: 1

── npm update -g ───────────────────────────────────
  [✓] Updated 3 packages

── npx skills update -g -y ─────────────────────────
  [✓] All skills up to date

── apt upgrade (Linux only) ────────────────────────
  (not applicable — Windows)

================================================================================
Total tasks: 3 | Succeeded: 2 | Partial: 1 (winget had 1 failure)
================================================================================
```

#### Environment-Specific Recommendations

Provide recommendations **ONLY for the detected environment**:

**Windows:**
- If winget packages failed, suggest retrying individually: `sudo winget upgrade --id <pkg> --silent --accept-package-agreements --accept-source-agreements`
- If a package failed due to "in use", suggest closing the application first
- If sudo was not in Inline mode, remind: `sudo sudo config --enable normal`
- Never suggest `chmod`, `apt`, or other Linux/macOS commands

**Linux:**
- If apt upgrade failed, suggest `sudo apt --fix-broken install`
- If npm update failed with permission errors, suggest checking npm prefix: `npm config get prefix`
- Never suggest `winget`, `sudo config`, or other Windows commands

**macOS:**
- Note that this skill does not include Homebrew updates (yet) — user can run `brew update && brew upgrade` separately
- Never suggest `winget`, `apt`, or other Windows/Linux commands

---

## Notes

- The sudo requirement on Windows is specifically for winget — npm and skills updates typically don't need elevation
- If only some tasks are applicable (e.g., no Node.js installed), run only the applicable ones
- The user may request to run only specific tasks (e.g., "just update winget") — honor that and skip others
- winget's table output format may vary by locale — the agent should parse it adaptively (look for the `Id` column header and the separator line of dashes)
