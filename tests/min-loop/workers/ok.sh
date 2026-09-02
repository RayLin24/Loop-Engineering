#!/usr/bin/env bash
# Fake Worker: apply the brief's T1/T2 file edit. Never touches git or events.jsonl.
set -eu
brief="${1:-}"
if printf '%s' "$brief" | grep -qE '(^# brief T1|brief T1:)'; then
  printf 'hello\n' > src/hello.txt
elif printf '%s' "$brief" | grep -qE '(^# brief T2|brief T2:)'; then
  printf 'world\n' > src/world.txt
elif printf '%s' "$brief" | grep -q 'src/hello.txt' && printf '%s' "$brief" | grep -q 'Write exactly the line `hello`'; then
  printf 'hello\n' > src/hello.txt
elif printf '%s' "$brief" | grep -q 'src/world.txt'; then
  printf 'world\n' > src/world.txt
else
  echo "ok.sh: cannot detect task from brief" >&2
  exit 1
fi
exit 0
