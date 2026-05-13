#!/usr/bin/env bash
set -euo pipefail

loaded="$(mktemp)"
trap 'rm -f "$loaded"' EXIT

find examples -type f -name '*.jai' ! -path '*/raylib/extras/*.jai' | sort | while IFS= read -r src; do
    dir="$(dirname "$src")"
    sed -n 's/.*#load "\([^"]*\.jai\)".*/\1/p' "$src" | while IFS= read -r load; do
        case "$load" in
            /*) printf '%s\n' "$load" ;;
            *) printf '%s/%s\n' "$dir" "$load" ;;
        esac
    done
done | sort -u > "$loaded"

find examples -type f -name '*.jai' ! -path '*/raylib/extras/*.jai' | sort | while IFS= read -r src; do
    if grep -qx "$src" "$loaded" && ! grep -q '^[[:space:]]*main[[:space:]]*::' "$src"; then
        continue
    fi
    printf '%s\n' "$src"
done
