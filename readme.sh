#!/usr/bin/env bash
set -euo pipefail

README="README.md"

MERGED_DIR="merged"
SUBMITTED_DIR="submitted"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

count_patches() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        echo 0
        return
    fi

    find "$dir" -maxdepth 1 -type f -name '*.patch' | wc -l | tr -d ' '
}

extract_subject() {
    local file="$1"
    local subject

    subject="$(
        grep -m1 '^Subject:' "$file" \
            | sed -E 's/^Subject:[[:space:]]*//' \
            | sed -E 's/^\[[^]]+\][[:space:]]*//' \
            | sed -E 's/[[:space:]]+/ /g' \
            || true
    )"

    if [[ -n "$subject" ]]; then
        echo "$subject"
    else
        basename "$file" .patch
    fi
}

extract_version() {
    local file="$1"
    local subject

    subject="$(grep -m1 '^Subject:' "$file" || true)"

    if [[ "$subject" =~ \[PATCH[[:space:]]+v([0-9]+) ]]; then
        echo "v${BASH_REMATCH[1]}"
    else
        echo "v1"
    fi
}

extract_date() {
    local file="$1"
    local date_line

    date_line="$(
        grep -m1 '^Date:' "$file" \
            | sed -E 's/^Date:[[:space:]]*//' \
            || true
    )"

    if [[ -z "$date_line" ]]; then
        echo "-"
        return
    fi

    date -d "$date_line" '+%Y-%m-%d' 2>/dev/null || echo "-"
}

extract_subsystem() {
    local file="$1"
    local path

    path="$(
        grep -m1 '^diff --git ' "$file" \
            | awk '{print $3}' \
            | sed -E 's|^a/||' \
            || true
    )"

    if [[ -z "$path" ]]; then
        echo "-"
        return
    fi

    case "$path" in
        arch/arm64/*) echo "arch/arm64" ;;
        arch/x86/*) echo "arch/x86" ;;
        arch/*) echo "arch" ;;

        drivers/gpu/*) echo "drivers/gpu" ;;
        drivers/media/*) echo "drivers/media" ;;
        drivers/net/*) echo "drivers/net" ;;
        drivers/*) echo "drivers" ;;

        fs/ext4/*) echo "fs/ext4" ;;
        fs/*) echo "fs" ;;

        net/*) echo "net" ;;
        mm/*) echo "mm" ;;
        kernel/*) echo "kernel" ;;
        include/*) echo "include" ;;
        tools/*) echo "tools" ;;
        Documentation/*) echo "Documentation" ;;

        *) echo "$(echo "$path" | cut -d/ -f1)" ;;
    esac
}

extract_discussion() {
    local file="$1"
    local subject
    local query
    local encoded_query

    subject="$(extract_subject "$file")"

    if [[ -z "$subject" ]]; then
        echo "-"
        return
    fi

    query="s:\"$subject\""

    encoded_query="$(
        python3 -c '
import sys
import urllib.parse

print(urllib.parse.quote_plus(sys.argv[1]))
' "$query"
    )"

    echo "[search](https://lore.kernel.org/all/?q=$encoded_query)"
}

escape_md() {
    sed -E \
        -e 's/\\/\\\\/g' \
        -e 's/\|/\\|/g' \
        -e 's/_/\\_/g' \
        -e 's/\*/\\*/g' \
        -e 's/`/\\`/g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g'
}

extract_sort_time() {
    local file="$1"
    local date_line

    date_line="$(
        grep -m1 '^Date:' "$file" \
            | sed -E 's/^Date:[[:space:]]*//' \
            || true
    )"

    if [[ -z "$date_line" ]]; then
        echo 0
        return
    fi

    date -d "$date_line" '+%s' 2>/dev/null || echo 0
}

extract_version_num() {
    local file="$1"
    local version

    version="$(extract_version "$file")"
    echo "$version" | sed -E 's/^v//'
}

make_table() {
    local dir="$1"

    echo "| Patch | Subsystem | Version | Date | Discussion |"
    echo "|-------|-----------|---------|------|------------|"

    if [[ ! -d "$dir" ]]; then
        return
    fi

    shopt -s nullglob
    local files=("$dir"/*.patch)
    shopt -u nullglob

    for file in "${files[@]}"; do
        local subject subsystem version version_num patch_date discussion sort_time

        subject="$(extract_subject "$file" | escape_md)"
        subsystem="$(extract_subsystem "$file" | escape_md)"
        version="$(extract_version "$file")"
        version_num="$(extract_version_num "$file")"
        patch_date="$(extract_date "$file")"
        discussion="$(extract_discussion "$file")"
        sort_time="$(extract_sort_time "$file")"

        echo "$sort_time|$version_num| $subject | $subsystem | $version | $patch_date | $discussion |"
    done | sort -t'|' -k1,1nr -k2,2nr | cut -d'|' -f3-
}

merged_count="$(count_patches "$MERGED_DIR")"
submitted_count="$(count_patches "$SUBMITTED_DIR")"

cat > "$tmp" <<EOF
# Linux Patches

Patch collections of Linux

## Summary

- **Merged**: $merged_count
- **Submitted**: $submitted_count

## Merged

$(make_table "$MERGED_DIR")

## Submitted

$(make_table "$SUBMITTED_DIR")
EOF

mv "$tmp" "$README"

echo "Updated $README"