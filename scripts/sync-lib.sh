#!/usr/bin/env bash
# sync-lib.sh — copy canonical fleet-lib files into each skill's lib/ directory
# Resolves paths relative to the repo root (parent of this script's directory).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CANONICAL="$REPO_ROOT/_canonical/fleet-lib"

# ---------------------------------------------------------------------------
# Manifest: skill → space-separated list of required lib files
# ---------------------------------------------------------------------------
declare -A MANIFEST
MANIFEST["dag-fleet"]="logging.sh tools.sh worker-spawn.sh registry.sh dag.sh dag-viz.py reset.sh"
MANIFEST["worktree-fleet"]="logging.sh tools.sh worker-spawn.sh registry.sh"
MANIFEST["iterative-fleet"]="logging.sh tools.sh worker-spawn.sh registry.sh dag.sh"
MANIFEST["autoresearch-fleet"]="logging.sh tools.sh worker-spawn.sh registry.sh"

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
total_copied=0
total_identical=0
total_removed=0

# ---------------------------------------------------------------------------
# Process each skill
# ---------------------------------------------------------------------------
for skill in "${!MANIFEST[@]}"; do
    lib_dir="$REPO_ROOT/skills/$skill/lib"
    mkdir -p "$lib_dir"

    # Build a set of required files for this skill
    required_files=()
    IFS=' ' read -ra required_files <<< "${MANIFEST[$skill]}"

    echo "--- $skill ---"

    # Copy required files
    for file in "${required_files[@]}"; do
        src="$CANONICAL/$file"
        dst="$lib_dir/$file"

        if [[ ! -f "$src" ]]; then
            echo "  [ERROR] canonical source missing: $src" >&2
            continue
        fi

        if [[ -f "$dst" ]] && sha256sum -b "$src" "$dst" 2>/dev/null | awk '{print $1}' | sort -u | wc -l | grep -q '^1$'; then
            echo "  [identical] $file"
            (( total_identical++ )) || true
        else
            cp "$src" "$dst"
            echo "  [copied]    $file"
            (( total_copied++ )) || true
        fi
    done

    # Remove stale files (files in lib/ that are NOT in the manifest for this skill)
    while IFS= read -r -d '' existing; do
        basename_existing="$(basename "$existing")"
        found=0
        for req in "${required_files[@]}"; do
            if [[ "$basename_existing" == "$req" ]]; then
                found=1
                break
            fi
        done
        if [[ "$found" -eq 0 ]]; then
            rm "$existing"
            echo "  [removed]   $basename_existing (stale)"
            (( total_removed++ )) || true
        fi
    done < <(find "$lib_dir" -maxdepth 1 -type f -print0)

    echo ""
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================="
echo "Sync complete"
echo "  Files copied/updated : $total_copied"
echo "  Files already identical: $total_identical"
echo "  Stale files removed  : $total_removed"
echo "============================="
