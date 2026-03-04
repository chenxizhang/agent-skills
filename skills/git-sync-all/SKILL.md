---
name: git-sync-all
description: Recursively find all git repositories and pull latest changes from remote IN PARALLEL. Use when syncing multiple projects across machines or after switching computers.
license: MIT
metadata:
  author: chenxizhang
  version: "2.0"
---

# Git Sync All

Synchronize all git repositories under the current working directory by pulling latest changes from their remotes — **using maximum parallelism**.

## When to Use

- After switching to a different computer
- When you need to update multiple projects at once
- To ensure all local repositories are up to date with remotes

## Execution Strategy

**Do NOT use any scripts. Execute all commands directly through the agent's shell/tool capabilities.**

### Phase 1: Environment Detection

Detect the current runtime environment:

- **Operating System**: Windows, macOS, or Linux
- **Shell**: PowerShell, bash, zsh, etc.
- **Git**: Verify `git --version` is available
- **Target path**: User-specified or default to current working directory
- **Search depth**: User-specified or default to 3 levels

### Phase 2: Discover Repositories

Find all git repositories under the target directory:

| Environment | Command |
|-------------|---------|
| PowerShell | `Get-ChildItem -Path <target> -Recurse -Directory -Filter ".git" -Depth <N> -ErrorAction SilentlyContinue \| Select -ExpandProperty Parent \| Select -ExpandProperty FullName` |
| bash/zsh | `find <target> -maxdepth <N> -type d -name ".git" -exec dirname {} \;` |

Report: "Found X git repositories."

### Phase 3: Parallel Sync ⚡

**THIS IS THE CRITICAL STEP — SYNC ALL REPOS IN PARALLEL, NOT SEQUENTIALLY!**

Each repository sync is completely independent. Use the agent's maximum parallel execution capabilities:

- **GitHub Copilot CLI**: Make multiple parallel tool calls — run `git -C <repo> pull --ff-only` for ALL repos simultaneously in one batch of tool calls. Use sub-agents (task tool with agent_type "task") for batches if needed.
- **Claude Code**: Use Agent Teams / sub-agents — launch one sub-agent per batch of repositories for concurrent pulling.
- **Other agents**: Use whatever parallel/concurrent execution mechanism is available.

**Per-repository sync logic:**
1. Check if a remote is configured: `git -C <repo> remote`
2. If no remote → classify as "Skipped"
3. If remote exists → run `git -C <repo> pull --ff-only`
4. Classify result:
   - Output contains "Already up to date" → "Up to date"
   - Pull succeeded → "Synced"
   - Pull failed → "Failed" (capture error message)

### Phase 4: Summary Report

After all parallel syncs complete, compile and display:

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

## Error Handling

- If a repo fails (e.g., merge conflict), report the error and continue with others
- Use `--ff-only` to avoid creating merge commits — if fast-forward is not possible, report it as a failure
- List all failed repos at the end for manual resolution

## Parallelism Guidelines

| Repo Count | Strategy |
|------------|----------|
| 1–5 | Run all in parallel in a single batch |
| 6–20 | Run all in parallel — most agents handle this fine |
| 20+ | Batch into groups of ~10, run each batch in parallel |

The whole point of this skill is speed through parallelism. **Never sync repos one by one.**
