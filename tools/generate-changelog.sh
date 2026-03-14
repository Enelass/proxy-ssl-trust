#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

version="$1"
prev_tag=""
if git describe --tags --abbrev=0 >/dev/null 2>&1; then
  prev_tag=$(git describe --tags --abbrev=0)
fi

if [[ -n "$prev_tag" ]]; then
  range="$prev_tag..HEAD"
else
  range="HEAD"
fi

log_output=$(git log --pretty=format:'%s' "$range" || true)

features=()
fixes=()
chores=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if [[ "$line" == feat* ]]; then
    features+=("$line")
  elif [[ "$line" == fix* ]]; then
    fixes+=("$line")
  elif [[ "$line" == docs* || "$line" == chore* || "$line" == refactor* || "$line" == perf* || "$line" == test* || "$line" == build* || "$line" == ci* ]]; then
    chores+=("$line")
  else
    chores+=("chore: $line")
  fi
done <<< "$log_output"

newline=$'\n'
today=$(date +%Y-%m-%d)

section="## [$version] - $today$newline$newline"

if (( ${#features[@]} > 0 )); then
  section+="### Features$newline"
  for item in "${features[@]}"; do
    section+="- ${item}$newline"
  done
  section+=$newline
fi

if (( ${#fixes[@]} > 0 )); then
  section+="### Fixes$newline"
  for item in "${fixes[@]}"; do
    section+="- ${item}$newline"
  done
  section+=$newline
fi

if (( ${#chores[@]} > 0 )); then
  section+="### Chore/Other$newline"
  for item in "${chores[@]}"; do
    section+="- ${item}$newline"
  done
  section+=$newline
fi

if [[ ! -f CHANGELOG.md ]]; then
  printf '# Changelog

All notable changes to this project will be documented in this file.

' > CHANGELOG.md
fi

# Prepend the new section after the header block (first two lines)
{
  head -n 2 CHANGELOG.md
  echo
  printf '%s
' "$section"
  tail -n +3 CHANGELOG.md
} > CHANGELOG.tmp

mv CHANGELOG.tmp CHANGELOG.md
