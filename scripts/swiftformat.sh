#!/usr/bin/env bash
# Runs SwiftFormat with this repo's configs named explicitly, so it formats the same files in an
# agent worktree as in the main checkout. Used by lefthook and the Makefile's format targets.
#
# SwiftFormat also applies every .swiftformat above its input, past the repo root. Agent worktrees
# live under the main checkout's .claude/worktrees/, and that checkout's .swiftformat excludes
# .claude, so plain `swiftformat` skips every file in a worktree ("0 files formatted, N skipped").
# `--config` stops that upward search, but it also drops the nested .swiftformat files, so each
# file gets the root config plus every nested config on its path, outermost first (later ones
# override earlier ones).
#
# Usage: scripts/swiftformat.sh [--lint] [file ...]
#   Files are relative to the repo root. With none, every tracked or untracked, not-ignored Swift
#   file. SWIFTFORMAT overrides the binary (the tests' stub).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
SWIFTFORMAT="${SWIFTFORMAT:-swiftformat}"

lint=()
if [[ "${1:-}" == "--lint" ]]; then
    lint=(--lint)
    shift
fi

files=()
if [[ $# -gt 0 ]]; then
    files=("$@")
else
    while IFS= read -r file; do
        [[ -f "${file}" ]] && files+=("${file}")
    done < <(git ls-files --cached --others --exclude-standard -- '*.swift')
fi
if [[ ${#files[@]} -eq 0 ]]; then
    echo "swiftformat.sh: no Swift files"
    exit 0
fi

# Directories holding a nested .swiftformat. Sorted, so a parent comes before its children.
nested=()
while IFS= read -r config; do
    nested+=("$(dirname "${config}")")
done < <(git ls-files -- '*/.swiftformat' | sort)

# Each file's group is the deepest nested-config directory above it ("" for the root alone).
groups=()
for file in "${files[@]}"; do
    group=""
    for dir in ${nested[@]+"${nested[@]}"}; do
        if [[ "${file}" == "${dir}/"* && ${#dir} -gt ${#group} ]]; then
            group="${dir}"
        fi
    done
    groups+=("${group}")
done

status=0
for group in "" ${nested[@]+"${nested[@]}"}; do
    members=()
    for i in "${!files[@]}"; do
        [[ "${groups[$i]}" == "${group}" ]] && members+=("${files[$i]}")
    done
    [[ ${#members[@]} -eq 0 ]] && continue

    configs=(--config .swiftformat)
    for dir in ${nested[@]+"${nested[@]}"}; do
        if [[ -n "${group}" && ("${group}" == "${dir}" || "${group}" == "${dir}/"*) ]]; then
            configs+=(--config "${dir}/.swiftformat")
        fi
    done
    "${SWIFTFORMAT}" ${lint[@]+"${lint[@]}"} "${configs[@]}" "${members[@]}" || status=$?
done
exit "${status}"
