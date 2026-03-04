---
name: cleanup-nul
description: Find and delete 'nul' files accidentally created by tools on Windows. Use when cleaning up spurious nul files from a directory tree.
license: MIT
metadata:
  author: chenxizhang
  version: "3.0"
---

# Cleanup NUL Files

Find and remove `nul` files that are accidentally created by some tools (like Claude Code) on Windows.

## Background

On Windows, `nul` is a reserved device name (like `/dev/null` on Unix). Some tools may accidentally create actual files named `nul`, which can cause issues. This skill helps locate and remove them.

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

**Display the detection results clearly**, for example:
```
Environment Detection:
  OS:    Windows 11 (10.0.22631)
  Shell: PowerShell 7.4
  Agent: GitHub Copilot CLI
```

**All subsequent phases MUST use ONLY commands appropriate for the detected OS and shell. Never mix platform commands.**

---

### Phase 2: Plan (generate environment-specific steps)

Based on Phase 1 results, generate the concrete execution plan:

**For PowerShell (Windows):**
- Find: `Get-ChildItem -Path <target> -Recurse -Filter "nul" -File -Force -ErrorAction SilentlyContinue`
- Delete: `Remove-Item -LiteralPath <file> -Force` (use `\\?\<full-path>` prefix if deletion fails due to reserved name)

**For bash/zsh (macOS/Linux):**
- Find: `find <target> -name "nul" -type f 2>/dev/null`
- Delete: `rm -f <file>`

**For Git Bash on Windows:**
- Find: `find <target> -name "nul" -type f 2>/dev/null`
- Delete: `rm -f <file>` (if fails, note that PowerShell may be needed for reserved name handling)

Target path: user-specified or default to current working directory.

If scanning multiple separate root paths, plan them as parallel operations.

---

### Phase 3: Execute

1. Run the find command from the plan
2. List all found `nul` files with their full paths
3. Report the total count
4. **Ask the user for confirmation before deleting**
5. Delete the confirmed files
6. Report results (deleted count, any failures)

---

### Phase 4: Report & Recommendations

Summarize what was done and provide **environment-specific** recommendations:

- **Windows PowerShell**: Recommend checking IDE/tool settings that may create `nul` files. Suggest using `Remove-Item -LiteralPath "\\?\..."` for stubborn files.
- **macOS/Linux bash**: Note that `nul` files are uncommon on Unix — check if Windows-origin tools created them.
- **NEVER recommend commands from a different platform** (e.g., do NOT suggest `chmod` on Windows, do NOT suggest `Get-Acl` on Linux).
