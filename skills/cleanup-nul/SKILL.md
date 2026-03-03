---
name: cleanup-nul
description: Find and delete 'nul' files accidentally created by tools on Windows. Use when cleaning up spurious nul files from a directory tree.
license: MIT
compatibility: Works on Windows, macOS, and Linux. Primarily useful on Windows where nul files are problematic.
metadata:
  author: chenxizhang
  version: "1.0"
---

# Cleanup NUL Files

Find and remove `nul` files that are accidentally created by some tools (like Claude Code) on Windows.

## Background

On Windows, `nul` is a reserved device name (like `/dev/null` on Unix). Some tools may accidentally create actual files named `nul`, which can cause issues. This skill helps locate and remove them.

## Usage

```bash
bash scripts/cleanup.sh [path]
```

## Options

- `--dry-run`: Show files that would be deleted without actually deleting
- `path`: Directory to scan (default: current directory)

## Examples

```bash
# Preview what would be deleted
bash scripts/cleanup.sh --dry-run /c/work

# Actually delete the files
bash scripts/cleanup.sh /c/work

# Clean current directory
bash scripts/cleanup.sh
```

## Output

```
Scanning for 'nul' files in /c/work...

Found 3 nul files:
  /c/work/nul
  /c/work/project-a/nul
  /c/work/project-b/src/nul

Delete these files? [y/N]: y

Deleted: /c/work/nul
Deleted: /c/work/project-a/nul
Deleted: /c/work/project-b/src/nul

Done. Removed 3 files.
```
