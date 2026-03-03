---
name: git-sync-all
description: Recursively find all git repositories in the current directory and pull latest changes from remote. Use when syncing multiple projects across machines or after switching computers.
license: MIT
compatibility: Requires git. Works on Windows, macOS, and Linux.
metadata:
  author: chenxizhang
  version: "1.0"
---

# Git Sync All

Synchronize all git repositories under the current working directory by pulling latest changes from their remotes.

## When to Use

- After switching to a different computer
- When you need to update multiple projects at once
- To ensure all local repositories are up to date with remotes

## Usage

Run the sync script from the parent directory containing your projects:

```bash
bash scripts/sync.sh
```

## Options

- `--dry-run`: Show which repositories would be synced without actually pulling
- `--depth N`: Maximum directory depth to search (default: 3)

Example:

```bash
bash scripts/sync.sh --dry-run
bash scripts/sync.sh --depth 5
```

## Output

The script provides a summary including:

- **Synced**: Repositories successfully updated
- **Already up to date**: Repositories with no new changes
- **Skipped**: Repositories without remotes configured
- **Failed**: Repositories with errors (conflicts, network issues, etc.)

## Handling Failures

If a repository fails to sync (e.g., due to merge conflicts), the script will:
1. Report the error
2. Continue with remaining repositories
3. List all failed repositories at the end

You must manually resolve conflicts in failed repositories.

## Example Output

```
Scanning for git repositories...

[1/5] project-a
      ✓ Synced (3 commits pulled)

[2/5] project-b
      ✓ Already up to date

[3/5] project-c
      ✗ Failed: merge conflict in src/main.py

[4/5] project-d
      - Skipped: no remote configured

[5/5] project-e
      ✓ Synced (1 commit pulled)

=== Summary ===
Synced:     2
Up to date: 1
Skipped:    1
Failed:     1

Failed repositories:
  - project-c: merge conflict in src/main.py
```
