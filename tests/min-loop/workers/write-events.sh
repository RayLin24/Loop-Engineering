#!/usr/bin/env bash
# Fake Worker: finish T1/T2 AND try to append events (must not stick on main).
set -eu
brief="${1:-}"
if printf '%s' "$brief" | grep -qE '(^# brief T1|brief T1:)'; then
  printf 'hello\n' > src/hello.txt
elif printf '%s' "$brief" | grep -qE '(^# brief T2|brief T2:)'; then
  printf 'world\n' > src/world.txt
else
  echo "write-events.sh: cannot detect task" >&2
  exit 1
fi
mkdir -p loop
printf '%s\n' '{"seq":99,"ts":"1970-01-01T00:00:00Z","type":"evil"}' >> loop/events.jsonl || true
# try the main repo via the shared git dir (should be chmod a-w)
git_common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
if [[ -n "$git_common" && -d "$git_common/.." ]]; then
  main="$(cd "$git_common/.." && pwd)"
  printf '%s\n' '{"seq":100,"ts":"1970-01-01T00:00:00Z","type":"evil-main"}' >> "$main/loop/events.jsonl" 2>/dev/null || true
fi
exit 0
