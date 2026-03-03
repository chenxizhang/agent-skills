#!/usr/bin/env bash
#
# Recursively sync all git repositories by pulling from remotes.
# Cross-platform compatible: Windows (Git Bash), macOS, Linux.
#

set -euo pipefail

# Default values
DRY_RUN=false
MAX_DEPTH=3
ROOT_PATH="."

# Counters
SYNCED=0
UP_TO_DATE=0
SKIPPED=0
FAILED=0
declare -a FAILED_REPOS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --depth)
            MAX_DEPTH="$2"
            shift 2
            ;;
        *)
            ROOT_PATH="$1"
            shift
            ;;
    esac
done

# Resolve absolute path
ROOT_PATH=$(cd "$ROOT_PATH" && pwd)

echo "Scanning for git repositories in $ROOT_PATH..."
if [ "$DRY_RUN" = true ]; then
    echo "(Dry run mode - no changes will be made)"
fi

# Find all git repositories
mapfile -t REPOS < <(find "$ROOT_PATH" -maxdepth "$MAX_DEPTH" -type d -name ".git" 2>/dev/null | sed 's/\/.git$//' | sort)

TOTAL=${#REPOS[@]}

if [ "$TOTAL" -eq 0 ]; then
    echo ""
    echo "No git repositories found."
    exit 0
fi

echo "Found $TOTAL git repositories."

# Process each repository
INDEX=0
for REPO in "${REPOS[@]}"; do
    ((INDEX++)) || true
    REPO_NAME=$(basename "$REPO")

    echo ""
    echo "[$INDEX/$TOTAL] $REPO_NAME"

    # Check for remote
    REMOTES=$(git -C "$REPO" remote 2>/dev/null || echo "")
    if [ -z "$REMOTES" ]; then
        echo "      - Skipped: no remote configured"
        ((SKIPPED++)) || true
        continue
    fi

    # Dry run check
    if [ "$DRY_RUN" = true ]; then
        echo "      ✓ Would sync"
        ((SYNCED++)) || true
        continue
    fi

    # Perform git pull
    PULL_OUTPUT=$(git -C "$REPO" pull --ff-only 2>&1) || {
        ERROR_MSG=$(echo "$PULL_OUTPUT" | head -n 1)
        echo "      ✗ Failed: $ERROR_MSG"
        ((FAILED++)) || true
        FAILED_REPOS+=("$REPO_NAME: $ERROR_MSG")
        continue
    }

    if echo "$PULL_OUTPUT" | grep -qE "(Already up to date|Already up-to-date)"; then
        echo "      ✓ Already up to date"
        ((UP_TO_DATE++)) || true
    else
        CHANGES=$(echo "$PULL_OUTPUT" | grep -E "(files? changed|insertions?|deletions?)" | head -n 1 || echo "pulled latest changes")
        echo "      ✓ Synced: $CHANGES"
        ((SYNCED++)) || true
    fi
done

# Print summary
echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Synced:       $SYNCED"
echo "Up to date:   $UP_TO_DATE"
echo "Skipped:      $SKIPPED"
echo "Failed:       $FAILED"

if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "Failed repositories:"
    for REPO_ERR in "${FAILED_REPOS[@]}"; do
        echo "  - $REPO_ERR"
    done
    exit 1
fi

exit 0
