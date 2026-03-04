---
name: git-sync-all
description: Recursively find all git repositories and pull latest changes from remote IN PARALLEL. Use when syncing multiple projects across machines or after switching computers.
license: MIT
metadata:
  author: chenxizhang
  version: "3.0"
---

# Git Sync All

Synchronize all git repositories under the current working directory by pulling latest changes from their remotes — **using maximum parallelism**.

## When to Use

- After switching to a different computer
- When you need to update multiple projects at once
- To ensure all local repositories are up to date with remotes

## Strict Execution Flow

**Do NOT use any scripts. Do NOT skip or merge phases. Execute each phase in order.**

---

### Phase 1: Environment Detection (MANDATORY — must display results before proceeding)

Detect and **explicitly display** the following before doing anything else:

1. **Operating System**: Run a command to detect the OS.
   - Windows: `[System.Environment]::OSVersion` or `$env:OS`
   - macOS/Linux: `uname -s`
2. **Shell environment**: Identify the current shell.
   - PowerShell: `$PSVersionTable.PSVersion`
   - bash/zsh: `echo $SHELL` and `echo $BASH_VERSION` or `echo $ZSH_VERSION`
3. **Agent identity**: Identify which agent is running this skill (Claude Code, GitHub Copilot CLI, Cursor, etc.) based on the agent's own context/identity.
4. **Git availability**: Run `git --version` to verify git is installed.

**Display the detection results clearly**, for example:
```
Environment Detection:
  OS:    Windows 11 (10.0.22631)
  Shell: PowerShell 7.4
  Agent: GitHub Copilot CLI
  Git:   git version 2.44.0.windows.1
```

**All subsequent phases MUST use ONLY commands appropriate for the detected OS and shell. Never mix platform commands.**

---

### Phase 2: Plan (discover repos and generate environment-specific steps)

#### Step 1: Discover Repositories

Use the appropriate command for the detected environment. **NOTE: `.git` directories are hidden — commands must handle hidden files/directories.**

**For PowerShell (Windows):**
```powershell
Get-ChildItem -Path <target> -Recurse -Directory -Hidden -Filter ".git" -Depth <N> -ErrorAction SilentlyContinue | ForEach-Object { $_.Parent.FullName }
```
⚠️ **CRITICAL**: The `-Hidden` flag (or `-Force`) is REQUIRED because `.git` is a hidden directory on Windows. Without it, most or all repositories will be missed.

**For bash/zsh (macOS/Linux):**
```bash
find <target> -maxdepth <N> -type d -name ".git" 2>/dev/null | sed 's/\/.git$//'
```

**For Git Bash on Windows:**
```bash
find <target> -maxdepth <N> -type d -name ".git" 2>/dev/null | sed 's/\/.git$//'
```

Default target: current working directory. Default depth: 3 levels.

Display: "Found X git repositories." followed by the list.

#### Step 2: Generate Parallel Execution Plan

Based on the detected **agent identity**, plan the parallel strategy:

| Agent | Parallel Strategy |
|-------|------------------|
| **GitHub Copilot CLI** | Use multiple parallel tool calls (powershell tool) to run `git pull` for all repos simultaneously. For large batches (20+), use sub-agents via the `task` tool. |
| **Claude Code** | Use Agent Teams / TodoWrite+TodoRead pattern to dispatch sub-agents, one per batch of repos. |
| **Other agents** | Use whatever parallel/concurrent execution mechanism is available. |

**Display the plan** before executing, e.g.:
```
Plan: Sync 12 repositories in parallel
  Strategy: 12 parallel tool calls (GitHub Copilot CLI)
  Command per repo: git -C <path> pull --ff-only
```

---

### Phase 3: Execute (parallel sync)

**SYNC ALL REPOS IN PARALLEL, NOT SEQUENTIALLY!**

For each repository, run in parallel:
1. Check if a remote is configured: `git -C <repo> remote`
2. If no remote → classify as "Skipped"
3. If remote exists → run `git -C <repo> pull --ff-only`
4. Classify result:
   - Output contains "Already up to date" → "Up to date"
   - Pull succeeded with changes → "Synced"
   - Pull failed → "Failed" (capture error message)

**Never sync repos one by one. The whole point of this skill is parallelism.**

---

### Phase 4: Report & Recommendations

#### Summary Report

```
=== Git Sync Summary ===
Total:        N repositories
Synced:       X
Up to date:   Y
Skipped:      Z (no remote)
Failed:       W

Failed repositories:
  - repo-name: error message
```

#### Environment-Specific Recommendations

Provide recommendations **ONLY for the detected environment**:

- **Windows PowerShell**: If repos failed due to path length, suggest enabling long paths: `git config --system core.longpaths true`. Suggest `git config --global credential.helper manager` for credential management.
- **macOS/Linux bash**: If repos failed due to permissions, suggest `chmod` or SSH key setup. Suggest `git config --global credential.helper osxkeychain` (macOS) or `git config --global credential.helper store` (Linux).
- **NEVER recommend commands from a different platform** (e.g., do NOT suggest `chmod` on Windows, do NOT suggest `credential.helper manager` on Linux).
