#!/usr/bin/env bash
#
# Find and delete 'nul' files accidentally created on Windows.
# Cross-platform compatible.
#

set -euo pipefail

DRY_RUN=false
ROOT_PATH="."

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            ROOT_PATH="$1"
            shift
            ;;
    esac
done

# Resolve absolute path
ROOT_PATH=$(cd "$ROOT_PATH" && pwd)

echo "Scanning for 'nul' files in $ROOT_PATH..."

# Find all nul files
mapfile -t NUL_FILES < <(find "$ROOT_PATH" -name "nul" -type f 2>/dev/null || true)

COUNT=${#NUL_FILES[@]}

if [ "$COUNT" -eq 0 ]; then
    echo "No 'nul' files found."
    exit 0
fi

echo ""
echo "Found $COUNT nul file(s):"
for FILE in "${NUL_FILES[@]}"; do
    echo "  $FILE"
done

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "(Dry run mode - no files deleted)"
    exit 0
fi

echo ""
read -p "Delete these files? [y/N]: " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

DELETED=0
for FILE in "${NUL_FILES[@]}"; do
    if rm -f "$FILE" 2>/dev/null; then
        echo "Deleted: $FILE"
        ((DELETED++)) || true
    else
        echo "Failed to delete: $FILE"
    fi
done

echo ""
echo "Done. Removed $DELETED file(s)."
