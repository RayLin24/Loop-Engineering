#!/usr/bin/env bash
# MIN-LOOP.md §7 acceptance — toy git repo + fake LOOP_WORKER (no real Claude).
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/runner/run-loop.sh"
OK="$ROOT/tests/min-loop/workers/ok.sh"
OOB="$ROOT/tests/min-loop/workers/oob.sh"
SLOW="$ROOT/tests/min-loop/workers/slow.sh"
EVIL="$ROOT/tests/min-loop/workers/write-events.sh"
PASS=0
FAIL=0

chmod +x "$RUNNER" "$ROOT/runner/parse-tasks" "$ROOT/runner/replay" \
  "$OK" "$OOB" "$SLOW" "$EVIL"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }

assert() {
  local name="$1"
  if eval "$2"; then
    grn "  PASS  $name"
    PASS=$((PASS + 1))
  else
    red "  FAIL  $name"
    echo "        check: $2"
    FAIL=$((FAIL + 1))
  fi
}

TWO_TASKS='
# 任务清单：min-loop-§7

## 全局上下文
Toy repo for min-loop v0 acceptance. No secrets.

## 任务

### [T1] Write hello marker
id: T1
depends_on: []
touches:
  - src/hello.txt
checks:
  - test -f src/hello.txt
  - grep -qx hello src/hello.txt
context_files:
  - src/hello.txt
Write exactly the line `hello` into `src/hello.txt`.

### [T2] Write world marker
id: T2
depends_on: [T1]
touches:
  - src/world.txt
checks:
  - test -f src/world.txt
  - grep -qx world src/world.txt
context_files:
  - src/world.txt
Write exactly the line `world` into `src/world.txt`.
'

FAILING_T1='
# 任务清单：min-loop-§7-fail

## 全局上下文
T1 check always fails.

## 任务

### [T1] Write hello marker
id: T1
depends_on: []
touches:
  - src/hello.txt
checks:
  - false
context_files:
  - src/hello.txt
Write exactly the line `hello` into `src/hello.txt`.
'

make_toy() {
  local dir="$1"
  local tasks="$2"
  rm -rf "$dir"
  mkdir -p "$dir/src"
  printf '%s\n' "$tasks" > "$dir/TASKS.md"
  printf 'placeholder\n' > "$dir/src/hello.txt"
  printf 'placeholder\n' > "$dir/src/world.txt"
  cat > "$dir/.gitignore" <<'GI'
.loop-worktrees/
.idea/
loop/**
!loop/events.jsonl
GI
  git -C "$dir" init -q
  git -C "$dir" config user.email "min-loop-test@localhost"
  git -C "$dir" config user.name "min-loop-test"
  git -C "$dir" add TASKS.md src .gitignore
  git -C "$dir" commit -qm "baseline"
}

event_types() {
  python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    sys.exit(0)
for line in p.read_text().splitlines():
    if not line.strip():
        continue
    ev = json.loads(line)
    extra = ""
    if ev.get("id"):
        extra += " " + ev["id"]
    if ev.get("reason"):
        extra += " " + ev["reason"]
    print(f'{ev.get("seq")} {ev.get("type")}{extra}')
PY
}

replay_done() {
  python3 - "$ROOT/runner" "$1" "$2" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from looputil import load_events, parse_tasks, replay
events = load_events(Path(sys.argv[2]))
parsed = parse_tasks(Path(sys.argv[3]).read_text())
r = replay(events, [t["id"] for t in parsed["tasks"]])
for tid, rec in r["tasks"].items():
    print(f'{tid} {rec["status"]} {rec["attempt"]}')
PY
}

echo "=== min-loop §7 ==="
echo "framework: $ROOT"

# ---------------------------------------------------------------------------
echo
echo "[1] 2-task list, T2 depends T1, one runner run → two merges, exit 0, both done"
TOY="$(mktemp -d /tmp/min-loop-1-XXXXXX)"
make_toy "$TOY" "$TWO_TASKS"
BASE1="$(git -C "$TOY" rev-parse HEAD)"
set +e
( cd "$TOY" && LOOP_WORKER="$OK" "$RUNNER" ) >"$TOY/runner.log" 2>&1
RC1=$?
set -e
echo "    exit=$RC1"
echo "    events:"
event_types "$TOY/loop/events.jsonl" | sed 's/^/      /'
echo "    replay:"
replay_done "$TOY/loop/events.jsonl" "$TOY/TASKS.md" | sed 's/^/      /'
MERGES1="$(git -C "$TOY" rev-list --min-parents=2 --count HEAD)"
assert "exit 0" "[[ $RC1 -eq 0 ]]"
assert "two merge commits" "[[ $MERGES1 -eq 2 ]]"
assert "hello file" "[[ \$(cat '$TOY/src/hello.txt') == hello ]]"
assert "world file" "[[ \$(cat '$TOY/src/world.txt') == world ]]"
assert "T1 done attempt 1" "replay_done '$TOY/loop/events.jsonl' '$TOY/TASKS.md' | grep -qx 'T1 done 1'"
assert "T2 done attempt 1" "replay_done '$TOY/loop/events.jsonl' '$TOY/TASKS.md' | grep -qx 'T2 done 1'"
assert "FINAL exists" "[[ -f '$TOY/loop/FINAL.md' ]]"
assert "loop_finished event" "grep -q '\"type\":\"loop_finished\"' '$TOY/loop/events.jsonl'"
assert "two task_done" "[[ \$(grep -c '\"type\":\"task_done\"' '$TOY/loop/events.jsonl') -eq 2 ]]"

# ---------------------------------------------------------------------------
echo
echo "[2] T1 check always fails: 3 failures, exit 2, main has no T1 diff"
TOY2="$(mktemp -d /tmp/min-loop-2-XXXXXX)"
make_toy "$TOY2" "$FAILING_T1"
BASE2="$(git -C "$TOY2" rev-parse HEAD)"
set +e
( cd "$TOY2" && LOOP_WORKER="$OK" "$RUNNER" ) >"$TOY2/runner.log" 2>&1
RC2=$?
set -e
echo "    exit=$RC2"
echo "    events:"
event_types "$TOY2/loop/events.jsonl" | sed 's/^/      /'
FAILS2="$(grep -c '"reason":"checks"' "$TOY2/loop/events.jsonl" || true)"
DIFF2="$(git -C "$TOY2" diff --name-only "$BASE2" HEAD)"
assert "exit 2" "[[ $RC2 -eq 2 ]]"
assert "three checks failures" "[[ $FAILS2 -eq 3 ]]"
assert "NEED_HUMAN exists" "[[ -f '$TOY2/loop/NEED_HUMAN.md' ]]"
assert "main has no T1 diff vs baseline" "[[ -z '$DIFF2' ]]"
assert "hello still placeholder" "[[ \$(cat '$TOY2/src/hello.txt') == placeholder ]]"
assert "no merge commits" "[[ \$(git -C '$TOY2' rev-list --min-parents=2 --count HEAD) -eq 0 ]]"

# ---------------------------------------------------------------------------
echo
echo "[3] Worker edits a file outside touches: no merge, task_failed reason=touches"
TOY3="$(mktemp -d /tmp/min-loop-3-XXXXXX)"
make_toy "$TOY3" "$TWO_TASKS"
BASE3="$(git -C "$TOY3" rev-parse HEAD)"
set +e
( cd "$TOY3" && LOOP_WORKER="$OOB" "$RUNNER" ) >"$TOY3/runner.log" 2>&1
RC3=$?
set -e
echo "    exit=$RC3"
echo "    events:"
event_types "$TOY3/loop/events.jsonl" | sed 's/^/      /'
assert "task_failed reason=touches" "grep -q '\"type\":\"task_failed\".*\"reason\":\"touches\"\\|\"reason\":\"touches\".*\"type\":\"task_failed\"' '$TOY3/loop/events.jsonl'"
assert "no merge" "[[ \$(git -C '$TOY3' rev-list --min-parents=2 --count HEAD) -eq 0 ]]"
assert "main hello unchanged" "[[ \$(cat '$TOY3/src/hello.txt') == placeholder ]]"
assert "evil not on main" "[[ ! -f '$TOY3/src/evil.txt' ]]"

# ---------------------------------------------------------------------------
echo
echo "[4] Kill after dispatched, rerun: no lost task, no double merge, attempt not incremented wrongly"
TOY4="$(mktemp -d /tmp/min-loop-4-XXXXXX)"
make_toy "$TOY4" "$TWO_TASKS"
set +e
( cd "$TOY4" && LOOP_WORKER="$SLOW" "$RUNNER" ) >"$TOY4/runner.log" 2>&1 &
PID4=$!
killed=0
for _ in $(seq 1 100); do
  if [[ -f "$TOY4/loop/events.jsonl" ]] && grep -q '"type":"dispatched"' "$TOY4/loop/events.jsonl"; then
    kill -9 "$PID4" >/dev/null 2>&1
    wait "$PID4" 2>/dev/null
    killed=1
    break
  fi
  sleep 0.1
done
if [[ "$killed" -ne 1 ]]; then
  kill -9 "$PID4" >/dev/null 2>&1
  wait "$PID4" 2>/dev/null
fi
# leftover locks
rm -f "$TOY4/.git/index.lock" "$TOY4/.git/HEAD.lock"
find "$TOY4/.git" -name '*.lock' -delete 2>/dev/null || true
echo "    events after kill:"
event_types "$TOY4/loop/events.jsonl" | sed 's/^/      /'
DISP_BEFORE="$(grep -c '"type":"dispatched"' "$TOY4/loop/events.jsonl" || true)"
DONE_BEFORE="$(grep -c '"type":"task_done"' "$TOY4/loop/events.jsonl" || true)"
( cd "$TOY4" && LOOP_WORKER="$OK" "$RUNNER" ) >"$TOY4/runner2.log" 2>&1
RC4=$?
set -e
echo "    exit after rerun=$RC4"
echo "    events after rerun:"
event_types "$TOY4/loop/events.jsonl" | sed 's/^/      /'
echo "    replay:"
replay_done "$TOY4/loop/events.jsonl" "$TOY4/TASKS.md" | sed 's/^/      /'
MERGES4="$(git -C "$TOY4" rev-list --min-parents=2 --count HEAD)"
DONE4="$(grep -c '"type":"task_done"' "$TOY4/loop/events.jsonl" || true)"
assert "killed after dispatched" "[[ $killed -eq 1 && $DONE_BEFORE -eq 0 && $DISP_BEFORE -ge 1 ]]"
assert "rerun exit 0" "[[ $RC4 -eq 0 ]]"
assert "both tasks done (not lost)" "replay_done '$TOY4/loop/events.jsonl' '$TOY4/TASKS.md' | grep -qx 'T1 done 1' && replay_done '$TOY4/loop/events.jsonl' '$TOY4/TASKS.md' | grep -qx 'T2 done 1'"
assert "exactly two merges (no double merge)" "[[ $MERGES4 -eq 2 ]]"
assert "exactly two task_done" "[[ $DONE4 -eq 2 ]]"
assert "T1 attempt is 1 (crash did not increment)" "replay_done '$TOY4/loop/events.jsonl' '$TOY4/TASKS.md' | grep -qx 'T1 done 1'"

# ---------------------------------------------------------------------------
echo
echo "[5] No second prompt file; model never writes jsonl (only runner appends events)"
PROMPTS="$(find "$ROOT/prompts" -type f ! -name '.*' | sort)"
assert "only prompts/worker.md" "[[ \$PROMPTS == '$ROOT/prompts/worker.md' ]]"
assert "no orchestrator/verifier/meta-analyst prompts" \
  "[[ ! -f $ROOT/prompts/orchestrator.md && ! -f $ROOT/prompts/verifier.md && ! -f $ROOT/prompts/meta-analyst.md ]]"

TOY5="$(mktemp -d /tmp/min-loop-5-XXXXXX)"
make_toy "$TOY5" "$TWO_TASKS"
set +e
( cd "$TOY5" && LOOP_WORKER="$EVIL" "$RUNNER" ) >"$TOY5/runner.log" 2>&1
RC5=$?
set -e
echo "    exit=$RC5"
echo "    events:"
event_types "$TOY5/loop/events.jsonl" | sed 's/^/      /'
TYPES5="$(python3 - "$TOY5/loop/events.jsonl" <<'PY'
import json, sys
from pathlib import Path
ok = {"loop_started","dispatched","task_done","task_failed","task_waiting","loop_finished"}
bad = []
seqs = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if not line.strip():
        continue
    ev = json.loads(line)
    seqs.append(ev.get("seq"))
    if ev.get("type") not in ok:
        bad.append(ev.get("type"))
    extra = set(ev) - {"seq", "ts", "type", "id", "reason"}
    if extra:
        bad.append("extra-fields:" + ",".join(sorted(extra)))
print("bad=" + ",".join(bad) if bad else "clean")
print("seqs=" + ",".join(str(s) for s in seqs))
print("monotonic=" + ("yes" if seqs == list(range(1, len(seqs)+1)) else "no"))
PY
)"
assert "exit 0 despite worker writing events" "[[ $RC5 -eq 0 ]]"
assert "no evil event types / extra fields" "printf '%s\n' \"$TYPES5\" | grep -qx 'clean'"
assert "seq is 1..n" "printf '%s\n' \"$TYPES5\" | grep -qx 'monotonic=yes'"
assert "no type=evil in jsonl" "! grep -q '\"type\":\"evil' '$TOY5/loop/events.jsonl'"

echo
echo "=== result: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -ne 0 ]]; then
  echo
  echo "---- logs (last 40 lines each) ----"
  for log in "$TOY/runner.log" "$TOY2/runner.log" "$TOY3/runner.log" "$TOY4/runner.log" "$TOY4/runner2.log" "$TOY5/runner.log"; do
    if [[ -f "$log" ]]; then
      echo "#### $log"
      tail -n 40 "$log"
    fi
  done
  exit 1
fi
exit 0
