#!/usr/bin/env bash
# Print a JSON array of the components to build for the diff BASE..HEAD.
# A change under components/<name>/ selects <name>; a change to shared build
# inputs (hack/, .github/, devbox.json/.lock) selects every component, as does
# an unusable BASE (new branch, manual run). Usage: hack/discover.sh [BASE]
set -euo pipefail
cd "$(dirname "$0")/.."

base=${1:-}
all=$(find components -mindepth 2 -maxdepth 2 -name apko.yaml -printf '%h\n' \
  | cut -d/ -f2 | sort)

if [[ -z $base || $base =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  selected=$all
else
  changed=$(git diff --name-only "$base" HEAD)
  if grep -qE '^(hack/|\.github/|devbox\.(json|lock)$)' <<<"$changed"; then
    selected=$all
  else
    # Only components that still exist (a deleted one has nothing to build).
    selected=$(grep -oE '^components/[^/]+/' <<<"$changed" | cut -d/ -f2 \
      | sort -u | grep -Fx -f <(echo "$all") || true)
    # A component sharing another's file through a symlink (python-dev's
    # melange.yaml -> ../python/melange.yaml) is selected when the target changes.
    while read -r link; do
      [[ -n $link ]] || continue
      if grep -qFx "$(realpath --relative-to=. "$link")" <<<"$changed"; then
        selected=$(printf '%s\n%s\n' "$selected" "$(cut -d/ -f2 <<<"$link")")
      fi
    done < <(find components -mindepth 2 -maxdepth 2 -type l)
    selected=$(sort -u <<<"$selected")
  fi
fi

jq -cn --arg s "$selected" '$s | split("\n") | map(select(. != ""))'
