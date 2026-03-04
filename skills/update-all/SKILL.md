---
name: update-all
description: Update all system packages and tools in parallel — winget (Windows), Windows Update (Windows), npm globals, agent skills, and apt (Linux). Each update category runs as an independent parallel task, with winget packages also upgraded in parallel internally. Use when you want to bring everything up to date quickly.
license: MIT
metadata:
  author: chenxizhang
  version: "3.0"
---

# Update All

Update all system packages and developer tools in parallel — bringing everything up to date in one command.

## Update Tasks

| Task | When to Run | Execution Mode |
|------|-------------|----------------|
| **winget upgrade** | Windows only | ✅ Each package upgraded in parallel |
| **Windows Update** | Windows only | Serial (scan → download → install → monitor) |
| **npm update -g** | If Node.js is installed | Single command |
| **npx skills update** | If Node.js is installed | Check global & project-level |
| **sudo apt update → sudo apt upgrade -y** | Linux only | ⚠️ Serial (update first, then upgrade) |

**All tasks are completely independent and MUST run in parallel. However, some tasks have internal serial steps (apt, Windows Update) — those internal steps must run in order.**

## Strict Execution Flow

**Do NOT use any scripts. Do NOT skip or merge phases. Execute each phase in order.**

⛔ **ABSOLUTELY FORBIDDEN on all platforms:**
- Do NOT create temporary script files (`.ps1`, `.sh`, `.bat`, `.cmd`, or any other script file)
- Do NOT use `Out-File`, `Set-Content`, `>`, or any file-writing mechanism to create scripts
- ALL commands must be run directly via the agent's tool calls (powershell, write_powershell, bash, etc.)
- If you find yourself wanting to create a script, STOP — run the commands directly instead

---

### Agent Capability Reference

Different agents have different shell models. **You MUST use the correct strategy for your agent.**

| Agent | Shell | Persistent Session? | Tools Available |
|-------|-------|---------------------|-----------------|
| **GitHub Copilot CLI** | PowerShell (native) | ✅ Yes — `powershell` tool with `mode: "async"`, `write_powershell`, `read_powershell`, `stop_powershell` | Full interactive session support |
| **Claude Code** | Bash (even on Windows via Git Bash/WSL) | ❌ No — each `Bash` tool call is a one-shot command | One-shot commands only, no interactive sessions |
| **Cursor / Other** | Varies | Check agent docs | Adapt accordingly |

### Calling PowerShell from Bash (Claude Code on Windows)

When the agent's shell is bash (e.g., Claude Code), use these patterns to call PowerShell commands:

**Simple command — use single quotes to avoid bash interpolation:**
```bash
pwsh -NoProfile -Command 'Get-Command winget -ErrorAction SilentlyContinue'
```

**Command with PowerShell variables — use single quotes (bash won't expand `$`):**
```bash
pwsh -NoProfile -Command '$m = Get-Module -ListAvailable PSWindowsUpdate; if ($m) { "v$($m.Version)" } else { "not installed" }'
```

**Multi-line complex command — use quoted heredoc:**
```bash
pwsh -NoProfile -Command "$(cat <<'PWSH'
$packages = @("pkg1", "pkg2", "pkg3")
$jobs = $packages | ForEach-Object {
    Start-Job -ScriptBlock { param($id); winget upgrade --id $id --silent --accept-package-agreements --accept-source-agreements 2>&1 } -ArgumentList $_
}
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
PWSH
)"
```

⚠️ **Key rule**: Always use **single quotes** around PowerShell code in bash, or use a **heredoc with `<<'PWSH'`** (quoted delimiter prevents bash expansion). NEVER use double quotes with `$` — bash will try to expand PowerShell variables and break the command.

### Recommended Timeouts

| Command | Timeout |
|---------|---------|
| Environment detection (Phase 1) | 30s |
| `winget upgrade` (list packages) | 60s |
| Single `winget upgrade --id <pkg>` | 120s |
| `npm update -g` | 120s |
| `npx skills update -g -y` (global) | 120s |
| `npx skills update -y` (project) | 120s |
| Windows Update scan (`Get-WindowsUpdate`) | 120s |
| Windows Update install (`Install-WindowsUpdate`) | 600s (10 min) |
| `sudo apt update` | 60s |
| `sudo apt upgrade` | 300s (5 min) |

For GitHub Copilot CLI: use `initial_wait` parameter on `powershell` tool calls.
For Claude Code: use `timeout` parameter on Bash tool calls (in milliseconds: multiply seconds × 1000).

---

### Phase 1: Environment Detection (MANDATORY — must display results before proceeding)

Detect and **explicitly display** the following before doing anything else.

**Prefer bash-native commands where possible** — only invoke `pwsh` when genuinely needed (e.g., PSWindowsUpdate check). This reduces escaping issues and errors.

| Detection | Bash / Shell-native | Only if pwsh needed |
|-----------|---------------------|---------------------|
| OS version | `uname -s` / `cat /etc/os-release` | `pwsh -NoProfile -Command '[System.Environment]::OSVersion'` (for detailed Windows version) |
| Shell | `echo $SHELL` or `$PSVersionTable` | — |
| winget | `which winget` or `winget --version` | — |
| node/npm | `node --version` / `npm --version` | — |
| apt | `which apt` | — |
| sudo | `which sudo` / `sudo config` | — |
| PSWindowsUpdate | — | `pwsh -NoProfile -Command 'Get-Module -ListAvailable PSWindowsUpdate'` |

1. **Operating System**: `uname -s` (all platforms), or `winget --version` to confirm Windows
2. **Shell environment**: Note which shell you are running in (PowerShell, bash, zsh)
3. **Agent identity**: Identify which agent is running (Claude Code, GitHub Copilot CLI, Cursor, etc.)
4. **Available tools** — use simple commands:
   - `winget`: `winget --version 2>/dev/null` or `which winget`
   - `node`/`npm`: `node --version 2>/dev/null` / `npm --version 2>/dev/null`
   - `apt`: `which apt 2>/dev/null`
   - `PSWindowsUpdate` module (Windows only): `pwsh -NoProfile -Command 'Get-Module -ListAvailable PSWindowsUpdate'`
5. **sudo status** (Windows only, required for winget and Windows Update):
   - Check if sudo exists: `which sudo` or `sudo --version 2>/dev/null`
   - Check sudo mode: `sudo config`
   - **If sudo is not installed or not in Inline/normal mode**: Auto-fix IMMEDIATELY — do NOT stop and ask the user:
     1. Run `sudo sudo config --enable normal` — this may trigger a one-time UAC confirmation
     2. Re-check: `sudo config` — verify mode is now `Inline` or `normal`
     3. If auto-fix succeeded, proceed normally — do NOT re-prompt the user
     4. If auto-fix failed (e.g., user declined UAC, or command not found), THEN display a warning and skip elevated tasks (winget, Windows Update). Other tasks (npm, skills) can still proceed.
   - ⛔ **Do NOT stop execution to ask the user** whether to fix sudo. Just fix it. Only skip if the fix itself fails.
6. **sudo status** (Linux only, required for apt):
   - Check if sudo credentials are already cached (no password needed): `sudo -n true 2>/dev/null`
   - If exit code 0 → credentials cached, proceed normally
   - If exit code non-zero → password will be required. The agent should:
     1. Inform the user that sudo will prompt for their password
     2. Run `sudo -v` as the **first** sudo command — this prompts for the password and caches credentials (typically 15 minutes)
     3. After `sudo -v` succeeds, all subsequent `sudo` commands will reuse the cached credentials without re-prompting
     4. If `sudo -v` fails (wrong password, user cancelled), skip apt tasks and report the failure

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
  PSWindowsUpdate: ✅ v2.2.1.5 installed

Applicable update tasks:
  1. winget upgrade (parallel per package)
  2. Windows Update (scan → install → monitor)
  3. npm update -g
  4. npx skills update (global + project)
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
  sudo:    ✅ available (credentials cached / password will be needed)

Applicable update tasks:
  1. sudo apt update → sudo apt upgrade -y (serial)
  2. npm update -g
  3. npx skills update (global + project)
```

**CRITICAL: If on Windows and sudo is missing or not in Inline/normal mode, auto-fix with `sudo sudo config --enable normal` immediately — do NOT ask the user. Only if auto-fix fails should you skip winget and Windows Update tasks. Other tasks (npm, skills) can always proceed.**

---

### Phase 2: Plan (generate environment-specific parallel execution plan)

Based on Phase 1 results, build the task list and parallel strategy.

#### Task Definitions

**Task A: winget upgrade (Windows only, requires elevation)**

1. Run `winget upgrade --accept-source-agreements --disable-interactivity` (no elevation) to list all upgradable packages
   - The `--disable-interactivity` flag suppresses spinner characters (`- \ |`) that make output hard to parse
2. Parse the output to extract package IDs — look for the table header with `Name`, `Id`, `Version`, `Available` columns, then extract the `Id` value from each row
3. If no packages to upgrade, skip
4. Upgrade **each package individually in parallel** (see Parallel Strategy for agent-specific approach)
5. Collect results per package

⚠️ **CRITICAL — per-package parallel upgrade rules:**
- **DO**: `sudo winget upgrade --id <specific-package-id> --silent --accept-package-agreements --accept-source-agreements --disable-interactivity` for EACH package, run in parallel
- **DO NOT**: `winget upgrade --all` or `sudo winget upgrade --all` — this runs serially and defeats the purpose of parallelism
- Each package upgrade is independent — run them ALL in parallel, never sequentially
- **Exception**: If only 1 package needs upgrading, you may use `sudo winget upgrade --id <pkg> ...` directly (no need for parallel infrastructure)

**Task B: npm update -g (if Node.js installed)**

Single command:
- Windows PowerShell: `npm update -g 2>&1`
- bash/zsh: `npm update -g 2>&1`

**Task C: npx skills update (if Node.js installed)**

Run both global and project-level updates:
1. Check if global skills exist: `npx skills list -g 2>&1`
   - If global skills found: `npx skills update -g -y 2>&1`
   - If no global skills: skip global update, report "No global skills installed"
2. Check if project-level skills exist (look for `skills-lock.json` in the current directory or common project dirs):
   - If found: `npx skills update -y 2>&1` (without `-g`)
   - If not found: skip project update

**Task D: sudo apt update → sudo apt upgrade (Linux only, MUST be serial)**

⚠️ **These two commands MUST run serially, NOT combined with `&&` in a single shell call.** Run them as two separate sequential commands so the agent can observe and report each step independently.

0. **Pre-cache sudo credentials** (if not already cached from Phase 1):
   Run `sudo -v` first — this prompts for the password once and caches credentials for subsequent `sudo` calls (typically 15 minutes). This ensures `apt update` and `apt upgrade` won't each prompt for the password separately.
1. Run `sudo apt update -y 2>&1` — refresh package index
   - Wait for completion, capture and display output
   - If this fails, STOP — do not proceed to upgrade
2. Run `sudo apt upgrade -y 2>&1` — upgrade all packages
   - Wait for completion, capture and display output
   - Report number of upgraded, newly installed, held back packages

This serial approach allows the agent to:
- Detect and report failures at each step
- Show the user what's being updated before upgrading
- Avoid running upgrade with a stale or broken package index

**Task E: Windows Update (Windows only, requires elevation)**

Uses PSWindowsUpdate to scan, install, and monitor Windows Update. Runs serially (scan → install → reboot check). See Parallel Strategy for how elevation is handled per agent.

**WU Steps (run inside an elevated context):**

1. Ensure PSWindowsUpdate module:
   ```powershell
   if (-not (Get-Module -ListAvailable PSWindowsUpdate)) { Install-Module -Name PSWindowsUpdate -Force }; Import-Module PSWindowsUpdate
   ```
2. Scan: `Get-WindowsUpdate` — if no updates, report "up to date" and skip
3. Install: `Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose` — **never auto-reboot**
4. Check reboot: `Get-WURebootStatus` — inform user if reboot needed

⚠️ Windows Update can take a long time (minutes to hours) — use generous timeouts and poll for progress.

#### Parallel Strategy

Windows sudo caches credentials **per console session**. This determines how many UAC prompts the user sees:

| Agent | Shell Model | sudo Behavior |
|-------|-------------|---------------|
| **GitHub Copilot CLI** | Persistent shell session | ✅ Cached — one UAC prompt for all `sudo` calls |
| **Claude Code** | New process per command | ❌ Not cached — one UAC prompt per `sudo` call |
| **Other agents** | Varies | Test with two `sudo` calls to determine behavior |

---

**Strategy for GitHub Copilot CLI: parallel tool calls (one UAC prompt total)**

sudo credential caching means all `sudo` calls share one UAC prompt. Use the agent's native parallel tool calls:

```
parallel:
  Task A: multiple parallel `sudo winget upgrade --id <pkg> ...` tool calls
  Task B: npm update -g
  Task C: npx skills update (global + project)
  Task E: sequential sudo calls for WU (scan → install → reboot check)
```

All tasks run in parallel. Each `sudo` reuses the cached credential. **One UAC prompt for everything.**

---

**Strategy for Claude Code: ONE elevated command combining all elevated tasks (one UAC prompt total)**

Since Claude Code spawns a new process per Bash tool call and has NO persistent shell sessions (no `write_powershell`, `read_powershell`, or `stop_powershell` — those are Copilot CLI only), you MUST combine all elevated work into a single `sudo pwsh -Command` call.

Use the heredoc pattern to build a single PowerShell command that:
1. Runs winget upgrades in parallel via `Start-Job`
2. Runs Windows Update serially (scan → install → reboot check)

```
parallel (launch all at once):
  Track 1: sudo pwsh -NoProfile -Command "$(cat <<'PWSH'
    # --- winget parallel upgrades ---
    $packages = @("<pkg1>", "<pkg2>", "<pkg3>")
    $jobs = $packages | ForEach-Object {
        Start-Job -ScriptBlock {
            param($id)
            winget upgrade --id $id --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
        } -ArgumentList $_
    }
    $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job

    # --- Windows Update (serial) ---
    if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
        Install-Module -Name PSWindowsUpdate -Force
    }
    Import-Module PSWindowsUpdate
    $updates = Get-WindowsUpdate
    if (-not $updates) { Write-Output "No Windows Updates available"; return }
    Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose
    Get-WURebootStatus
  PWSH
  )"
  Track 2: npm update -g 2>&1
  Track 3: npx skills update -g -y 2>&1 && npx skills update -y 2>&1
```

**Key points:**
- ONE `sudo pwsh` call = ONE UAC prompt for both winget and Windows Update
- winget packages run in parallel via `Start-Job` inside that single command
- Windows Update runs serially after winget completes (same elevated process)
- npm and skills updates run in parallel OUTSIDE the elevated command (they don't need elevation)
- Use a generous timeout (600s / 600000ms) for Track 1 since Windows Update can be slow
- Do NOT use `write_powershell` or `read_powershell` — Claude Code does not have these tools

**Display the plan before executing**, e.g. (GitHub Copilot CLI):
```
Plan: 4 parallel update tasks (one UAC prompt via sudo caching)
  Task A: winget upgrade — 5 packages (parallel sudo calls)
  Task B: npm update -g
  Task C: npx skills update (global + project)
  Task E: Windows Update — scan → install → monitor
```

Or (Claude Code):
```
Plan: 3 parallel tracks (one UAC prompt via shared elevated session)
  Elevated session: winget (5 packages via Jobs) + Windows Update (serial)
  Task B: npm update -g (parallel, no elevation)
  Task C: npx skills update — global + project (parallel, no elevation)
```

---

### Phase 3: Execute (all tasks in parallel)

**Launch ALL applicable tasks simultaneously. NEVER run them sequentially.**

**GitHub Copilot CLI execution:**

For Task A (winget):
1. Run `winget upgrade --accept-source-agreements --disable-interactivity` to discover packages
2. Parse package IDs from the table output (the ID column)
3. For **each** package, launch a **separate** parallel tool call: `sudo winget upgrade --id <pkg> --silent --accept-package-agreements --accept-source-agreements --disable-interactivity`
4. ⚠️ Do NOT use `winget upgrade --all` — it runs serially. Each package MUST be a separate parallel call.
5. Collect all results

For Task E (Windows Update):
1. `sudo pwsh -NoProfile -Command "Import-Module PSWindowsUpdate; Get-WindowsUpdate"` — scan
2. If updates exist: `sudo pwsh -NoProfile -Command "Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose"`
3. `sudo pwsh -NoProfile -Command "Import-Module PSWindowsUpdate; Get-WURebootStatus"` — check reboot
4. All sudo calls reuse cached credential — no additional UAC prompts
5. ⚠️ Do NOT combine scan + install into one command. Run them as separate steps so the agent can observe each result.

For Tasks B, C: run the single command and capture output.

**Claude Code execution:**

1. First, build the winget package list: `winget upgrade --accept-source-agreements --disable-interactivity` (no sudo needed for listing)
2. Parse package IDs from the output
3. Launch ALL tracks in parallel:
   - **Track 1 (elevated, one UAC prompt):** Build and run a single `sudo pwsh -NoProfile -Command "$(cat <<'PWSH' ... PWSH)"` that contains:
     - winget `Start-Job` blocks for each package (parallel)
     - `Wait-Job | Receive-Job` to collect winget results
     - PSWindowsUpdate import, scan, install, reboot check (serial)
   - **Track 2:** `npm update -g 2>&1` (no elevation)
   - **Track 3:** `npx skills update -g -y 2>&1` then `npx skills update -y 2>&1` (no elevation)
4. Set timeout for Track 1 to at least 600s (600000ms) — Windows Update can be very slow
5. Collect and display results from all tracks

⚠️ **Do NOT use `write_powershell`, `read_powershell`, or `stop_powershell`** — these are GitHub Copilot CLI tools and do NOT exist in Claude Code. Use bash one-shot commands only.

**Linux execution (all agents):**

For Task D (apt):
1. Run `sudo apt update -y 2>&1` and wait for completion
2. Check exit code — if non-zero, report failure and STOP (do not run upgrade)
3. Run `sudo apt upgrade -y 2>&1` and wait for completion
4. Parse output for summary (X upgraded, Y newly installed, Z held back)

For Tasks B, C: run in parallel alongside Task D.

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

── Windows Update ──────────────────────────────────
  [✓] KB5034441 — Security Update (45 MB)
  [✓] KB5034123 — .NET Runtime Update (12 MB)
  [⚠] Reboot required to complete installation
  Succeeded: 2 / Failed: 0

── npm update -g ───────────────────────────────────
  [✓] Updated 3 packages

── npx skills update ───────────────────────────────
  [✓] All skills up to date

── apt update ──────────────────────────────────────
  [✓] Package index refreshed (42 packages can be upgraded)

── apt upgrade ─────────────────────────────────────
  [✓] 42 packages upgraded, 0 newly installed, 0 held back

================================================================================
Total tasks: 5 | Succeeded: 4 | Partial: 1 (winget had 1 failure)
⚠️ Reboot required for Windows Update
================================================================================
```

#### Environment-Specific Recommendations

Provide recommendations **ONLY for the detected environment**:

**Windows:**
- If winget packages failed, suggest retrying individually: `sudo winget upgrade --id <pkg> --silent --accept-package-agreements --accept-source-agreements --disable-interactivity`
- If a package failed due to "in use", suggest closing the application first
- If npm update -g reports `EPERM` errors on `.exe` files (e.g., `workiq.exe`, `azmcp.exe`), this means those packages are currently running. Inform the user: "npm update succeeded but could not replace some executables that are in use. Close the related applications and retry, or ignore — the update itself was applied."
- If sudo was not in Inline mode, remind: `sudo sudo config --enable normal`
- If Windows Update requires reboot, inform: "Please restart your computer to complete the update installation. You can do this when convenient."
- If Windows Update failed to install some updates, suggest: "Try running Windows Update again after a reboot, or check Windows Update settings in Settings → Windows Update"
- If PSWindowsUpdate module installation failed, suggest: "Run PowerShell as Administrator and try: `Install-Module -Name PSWindowsUpdate -Force`"
- Never suggest `chmod`, `apt`, or other Linux/macOS commands

**Linux:**
- If `apt update` failed, suggest checking network connectivity and sources list: `cat /etc/apt/sources.list`
- If `apt upgrade` failed, suggest `sudo apt --fix-broken install`
- If packages were held back, inform the user and suggest `sudo apt full-upgrade` if they want to force them
- If npm update failed with permission errors, suggest checking npm prefix: `npm config get prefix`
- Never suggest `winget`, `sudo config`, or other Windows commands

**macOS:**
- Note that this skill does not include Homebrew updates (yet) — user can run `brew update && brew upgrade` separately
- Never suggest `winget`, `apt`, or other Windows/Linux commands

---

## Notes

- **NEVER create script files** (`.ps1`, `.sh`, `.bat`, `.cmd`) — run all commands directly via agent tool calls
- **NEVER use `winget upgrade --all`** — always upgrade each package individually by `--id` for parallelism
- **NEVER combine Windows Update steps** (scan + install + reboot check) into a single command — run each step separately so the agent can observe and react
- The sudo requirement on Windows is specifically for winget and Windows Update — npm and skills updates typically don't need elevation
- If sudo is missing or wrong mode on Windows, try `sudo sudo config --enable normal` before giving up
- If only some tasks are applicable (e.g., no Node.js installed), run only the applicable ones
- The user may request to run only specific tasks (e.g., "just update winget") — honor that and skip others
- winget's table output format may vary by locale — the agent should parse it adaptively (look for the `Id` column header and the separator line of dashes). Always use `--disable-interactivity` to suppress spinner characters that interfere with parsing.
- Windows Update can take a very long time — always use generous timeouts (300+ seconds) and poll for completion
- Windows Update will NEVER trigger an automatic reboot — the agent must inform the user and let them decide
- On Linux, `apt update` and `apt upgrade` are intentionally separate commands (not combined with `&&`) for better observability and error handling
- If `PSWindowsUpdate` module is not available and cannot be installed, skip Windows Update and inform the user
