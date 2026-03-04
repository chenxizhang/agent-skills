---
name: cleanup-nul
description: Find and delete 'nul' files accidentally created by tools on Windows. Use when cleaning up spurious nul files from a directory tree.
license: MIT
metadata:
  author: chenxizhang
  version: "2.0"
---

# Cleanup NUL Files

Find and remove `nul` files that are accidentally created by some tools (like Claude Code) on Windows.

## Background

On Windows, `nul` is a reserved device name (like `/dev/null` on Unix). Some tools may accidentally create actual files named `nul`, which can cause issues. This skill helps locate and remove them.

## Execution Strategy

**Do NOT use any scripts. Execute all commands directly through the agent's shell/tool capabilities.**

### Phase 1: Environment Detection

Detect the current runtime environment before doing anything:

- **Operating System**: Windows, macOS, or Linux
- **Shell**: PowerShell, cmd, bash, zsh, etc.
- **Target path**: User-specified or default to current working directory

### Phase 2: Find NUL Files

Use the appropriate command for the detected environment:

| Environment | Command |
|-------------|---------|
| PowerShell (Windows) | `Get-ChildItem -Path <target> -Recurse -Filter "nul" -File -ErrorAction SilentlyContinue` |
| bash/zsh (macOS/Linux) | `find <target> -name "nul" -type f 2>/dev/null` |
| cmd (Windows) | `dir /s /b <target>\nul` |

### Phase 3: Report and Clean

1. List all found `nul` files with their full paths
2. Report the total count
3. **Ask the user for confirmation before deleting**
4. Delete files using the appropriate command for the environment:
   - PowerShell: `Remove-Item -Path <file> -Force`
   - bash/zsh: `rm -f <file>`
   - If standard deletion fails on Windows (reserved name), try: `Remove-Item -LiteralPath "\\?\<full-path>" -Force`
5. Report results (deleted count, any failures)

## Notes

- Always confirm with the user before deleting any files
- This is a simple task — no parallelism needed unless scanning multiple large directory trees
- If scanning multiple separate root paths, those scans CAN be parallelized
