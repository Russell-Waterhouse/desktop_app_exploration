#!/usr/bin/env bash
# Combine the per-stack performance metrics CSVs into one
# CSV at the repo root. Run it from anywhere; it cds to its
# own directory (the repo root) first, like build_all_linux.sh.
#
# Input, in this order (the order the stacks appear in
# todo.md):
#   rust-egui/performance_metrics.csv
#   cpp-gtk4/performance_metrics.csv
#   odin-gtk/performance_metrics.csv
#   zig-gobject/performance_metrics.csv
#   electron-react/performance_metrics.csv
# Each is produced by that stack's profile_performance_linux.sh
# (one row per run, header written only if the file has no
# content, so repeated runs accumulate rows).
#
# Output (default: performance_metrics_all.csv in this
# folder): one header row, then every data row from every
# input file, in the order above, with each file's rows in
# their original order. The output is overwritten on every
# run, not appended to, so re-running it after a new
# profiling run gives the current combined data without
# duplicating old rows.
#
# The header of every input file must match the first
# file's header exactly (after stripping a trailing
# carriage return, so a CRLF file combines cleanly with
# LF files); a mismatch fails the script rather than
# silently combining unlike columns. Output lines are
# always LF-terminated. A missing or empty input file is
# warned about and skipped; if no data rows are found at
# all, the script fails and writes no output file.
#
# Usage:
#   ./combine_performance_metrics_linux.sh [--output FILE]
#
#   --output FILE   Combined CSV. Default:
#                   performance_metrics_all.csv in this folder.
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

OUTPUT="performance_metrics_all.csv"

usage() {
    echo "Usage: $0 [--output FILE]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --output)
            OUTPUT="$2"; shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            echo "Unexpected argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

STACKS=(
    "rust-egui"
    "cpp-gtk4"
    "odin-gtk"
    "zig-gobject"
    "electron-react"
)

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

header=""
rows=0
for stack in "${STACKS[@]}"; do
    input="$stack/performance_metrics.csv"
    if [ ! -s "$input" ]; then
        echo "Warning: $input missing or empty, skipping." >&2
        continue
    fi
    file_header="$(head -n 1 "$input")"
    file_header="${file_header%$'\r'}"
    if [ -z "$header" ]; then
        header="$file_header"
        echo "$header" > "$tmp"
    elif [ "$file_header" != "$header" ]; then
        echo "Error: $input header does not match the first file's header." >&2
        echo "  expected: $header" >&2
        echo "  found:    $file_header" >&2
        exit 1
    fi
    # Data rows only: skip the header, skip blank lines,
    # strip a trailing carriage return (CRLF input).
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [ -n "$line" ]; then
            echo "$line" >> "$tmp"
            rows=$(( rows + 1 ))
        fi
    done < <(tail -n +2 "$input")
done

if [ "$rows" -eq 0 ]; then
    echo "Error: no data rows found in any per-stack performance_metrics.csv." >&2
    exit 1
fi

mv "$tmp" "$OUTPUT"
trap - EXIT
echo "Wrote $rows row(s) to $OUTPUT"
