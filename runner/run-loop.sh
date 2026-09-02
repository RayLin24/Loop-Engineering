#!/usr/bin/env bash
# run-loop.sh — min-loop v0 deterministic scheduler.
# Usage (from the project root that has TASKS.md):
#   LOOP_WORKER='claude -p --permission-mode acceptEdits' ./runner/run-loop.sh
# Exit: 0 finished · 2 waiting-human · 3 stalled · 4 tick cap
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(pwd)"
PARSE="$SCRIPT_DIR/parse-tasks"
REPLAY="$SCRIPT_DIR/replay"
PY="$SCRIPT_DIR/looputil.py"

export PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}"

if [[ ! -f "$ROOT/TASKS.md" ]]; then
  echo "error: TASKS.md not found in $ROOT (run from the project root)" >&2
  exit 1
fi
if [[ ! -x "$PARSE" ]]; then
  chmod +x "$PARSE" "$REPLAY" 2>/dev/null || true
fi

LOOP_WORKER="${LOOP_WORKER:-claude -p --permission-mode acceptEdits}"
EVENTS="$ROOT/loop/events.jsonl"
STATE="$ROOT/loop/state.md"
FINAL="$ROOT/loop/FINAL.md"
NEED="$ROOT/loop/NEED_HUMAN.md"

log() { echo "[runner] $*"; }

ensure_gitignore() {
  local gi="$ROOT/.gitignore"
  touch "$gi"
  grep -qxF '.loop-worktrees/' "$gi" 2>/dev/null || echo '.loop-worktrees/' >> "$gi"
  grep -qxF '.idea/' "$gi" 2>/dev/null || echo '.idea/' >> "$gi"
  if ! grep -qxF 'loop/' "$gi" 2>/dev/null && ! grep -qxF 'loop/**' "$gi" 2>/dev/null; then
    {
      echo 'loop/**'
      echo '!loop/events.jsonl'
    } >> "$gi"
  fi
}

ensure_git() {
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: not a git repository (worktrees require git)" >&2
    exit 1
  fi
  if ! git -C "$ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "error: repository has no commits" >&2
    exit 1
  fi
  if [[ -z "$(git -C "$ROOT" config user.email || true)" ]]; then
    git -C "$ROOT" config user.email "loop-runner@localhost"
  fi
  if [[ -z "$(git -C "$ROOT" config user.name || true)" ]]; then
    git -C "$ROOT" config user.name "loop-runner"
  fi
}

python_json() {
  python3 -c "$1" "${@:2}"
}

count_tasks() {
  python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
print(len(json.loads(p.read_text()).get("tasks") or []))
PY
}

ask_json_for() {
  python3 - "$ROOT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
found = {}
wt = root / ".loop-worktrees"
if wt.is_dir():
    for d in wt.iterdir():
        if not d.is_dir():
            continue
        name = d.name  # T1-a1
        tid = name.split("-a")[0]
        ask = d / "loop" / "ASK.md"
        if ask.is_file() and ask.read_text(encoding="utf-8").strip():
            found[tid] = True
print(json.dumps(found))
PY
}

write_need_and_stop() {
  local reason="$1"
  mkdir -p "$ROOT/loop"
  unlock_events
  REASON="$reason" DETAIL="${2:-}" NEED_PATH="$NEED" python3 - <<'PY'
import os, json, sys
sys.path.insert(0, os.environ.get("PYTHONPATH", "").split(":")[0])
from looputil import need_human_text
reason = os.environ["REASON"]
raw = os.environ.get("DETAIL") or ""
try:
    detail = json.loads(raw) if raw.startswith("[") or raw.startswith("{") else raw
except Exception:
    detail = raw
Path = __import__("pathlib").Path
Path(os.environ["NEED_PATH"]).write_text(need_human_text(reason, detail), encoding="utf-8")
PY
  project_state
  log "waiting-human ($reason). see loop/NEED_HUMAN.md"
  exit 2
}

project_state() {
  local ask
  ask="$(ask_json_for)"
  local fe=""
  [[ -f "$FINAL" ]] && fe="--final-exists"
  "$REPLAY" "$EVENTS" --tasks "$ROOT/TASKS.md" --project "$STATE" --ask-json "$ask" $fe >/dev/null
}

append_event() {
  # append_event TYPE [id] [reason]
  local typ="$1"
  local id="${2:-}"
  local reason="${3:-}"
  TYPE="$typ" EID="$id" REASON="$reason" EVENTS_PATH="$EVENTS" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ.get("PYTHONPATH", "").split(":")[0])
from pathlib import Path
from looputil import append_event
kw = {}
if os.environ.get("EID"):
    kw["id"] = os.environ["EID"]
if os.environ.get("REASON"):
    kw["reason"] = os.environ["REASON"]
append_event(Path(os.environ["EVENTS_PATH"]), os.environ["TYPE"], **kw)
PY
}

lock_events_ro() {
  if [[ -f "$EVENTS" ]]; then
    chmod a-w "$EVENTS" 2>/dev/null || true
  fi
}

unlock_events() {
  if [[ -f "$EVENTS" ]]; then
    chmod u+w "$EVENTS" 2>/dev/null || true
  fi
}

cleanup_worktree() {
  local wt="$1"
  local branch="$2"
  if git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -q "^worktree $wt$"; then
    git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  fi
  if [[ -d "$wt" ]]; then
    git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  fi
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  if [[ -n "$branch" ]] && git -C "$ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$ROOT" branch -D "$branch" >/dev/null 2>&1 || true
  fi
}

touches_ok() {
  local base="$1" wt_head="$2"
  local touches_json="$3"
  python3 - "$base" "$wt_head" "$touches_json" "$ROOT" <<'PY'
import subprocess, sys, json
from pathlib import Path
sys.path.insert(0, __import__("os").environ.get("PYTHONPATH", "").split(":")[0])
from looputil import path_in_touches
base, wt, touches_json, root = sys.argv[1:5]
touches = json.loads(touches_json)
diff = subprocess.check_output(
    ["git", "-C", root, "diff", "--name-only", f"{base}..{wt}"],
    text=True,
)
files = [ln.strip() for ln in diff.splitlines() if ln.strip()]
bad = [f for f in files if not path_in_touches(f, touches)]
if bad:
    print("OUT_OF_TOUCHES " + " ".join(bad), file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
}

run_checks() {
  local wt="$1"
  shift
  local cmd
  for cmd in "$@"; do
    log "check: $cmd"
    if ! (cd "$wt" && bash -c "$cmd"); then
      log "check failed: $cmd"
      return 1
    fi
  done
  return 0
}

# --- one tick (MIN-LOOP.md §4 order) ---
# prints TICK_TERMINAL=1 if task_done|task_failed|task_waiting was appended
# returns 10=continue, 0=finished (already exited), 2=need human (already exited)
one_tick() {
  TICK_TERMINAL=0
  mkdir -p "$ROOT/loop"
  unlock_events

  # 1. read TASKS.md; replay events
  local parsed_file replay_file
  parsed_file="$(mktemp "${TMPDIR:-/tmp}/loop-tasks.XXXXXX.json")"
  replay_file="$(mktemp "${TMPDIR:-/tmp}/loop-replay.XXXXXX.json")"
  if ! "$PARSE" "$ROOT/TASKS.md" > "$parsed_file"; then
    local cyc
    cyc="$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print("cycle" if p.get("cycle") else "parse-error")' "$parsed_file")"
    local det
    det="$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(json.dumps(p.get("cycle") or p.get("errors") or []))' "$parsed_file")"
    rm -f "$parsed_file" "$replay_file"
    write_need_and_stop "$cyc" "$det"
  fi

  if [[ ! -f "$EVENTS" ]]; then
    append_event loop_started
  fi

  local ask
  ask="$(ask_json_for)"
  local fe=""
  [[ -f "$FINAL" ]] && fe="--final-exists"
  "$REPLAY" "$EVENTS" --tasks "$parsed_file" --decide --ask-json "$ask" $fe --project "$STATE" > "$replay_file"

  # 2–4. decide
  local action
  action="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["decision"]["action"])' "$replay_file")"

  if [[ "$action" == "need_human" ]]; then
    python3 - "$replay_file" "$NEED" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
Path(sys.argv[2]).write_text(data.get("need_human_md") or "# NEED_HUMAN\n", encoding="utf-8")
PY
    if [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["decision"].get("reason") or "")' "$replay_file")" == "retry-exhausted" ]]; then
      # record the exhausted reason once
      local eid
      eid="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["decision"].get("detail") or []; print(d[0] if d else "")' "$replay_file")"
      if [[ -n "$eid" ]]; then
        unlock_events
        append_event task_failed "$eid" retry-exhausted
      fi
    fi
    project_state
    rm -f "$parsed_file" "$replay_file"
    log "waiting-human. see loop/NEED_HUMAN.md"
    exit 2
  fi

  if [[ "$action" == "finished" ]]; then
    python3 - "$replay_file" "$FINAL" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
Path(sys.argv[2]).write_text(data.get("final_md") or "# FINAL\n", encoding="utf-8")
PY
    if [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("loop_finished"))' "$replay_file")" != "True" ]]; then
      append_event loop_finished
    fi
    project_state
    rm -f "$parsed_file" "$replay_file"
    log "finished. see loop/FINAL.md"
    exit 0
  fi

  local tid attempt wt_rel wt branch base_sha
  tid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["decision"]["id"])' "$replay_file")"
  attempt="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["decision"]["attempt"])' "$replay_file")"
  wt_rel=".loop-worktrees/${tid}-a${attempt}"
  wt="$ROOT/$wt_rel"
  branch="loop/${tid}-a${attempt}"
  base_sha="$(git -C "$ROOT" rev-parse HEAD)"

  # 5. append dispatched; create worktree
  append_event dispatched "$tid"
  mkdir -p "$ROOT/.loop-worktrees"
  cleanup_worktree "$wt" "$branch"
  if ! git -C "$ROOT" worktree add -b "$branch" "$wt" HEAD >/dev/null; then
    log "worktree add failed for $wt_rel"
    unlock_events
    append_event task_failed "$tid" worker-nonzero
    TICK_TERMINAL=1
    project_state
    rm -f "$parsed_file" "$replay_file"
    return 10
  fi

  # 6. write brief in MAIN and copy into worktree (Worker cwd = worktree)
  local brief_main brief_wt worker_prompt
  brief_main="$ROOT/loop/briefs/${tid}.md"
  brief_wt="$wt/loop/briefs/${tid}.md"
  worker_prompt=""
  if [[ -f "$ROOT/prompts/worker.md" ]]; then
    worker_prompt="$ROOT/prompts/worker.md"
  elif [[ -f "$SCRIPT_DIR/../prompts/worker.md" ]]; then
    worker_prompt="$SCRIPT_DIR/../prompts/worker.md"
  fi
  PARSED="$parsed_file" TID="$tid" BRIEF_MAIN="$brief_main" BRIEF_WT="$brief_wt" WPROMPT="$worker_prompt" python3 - <<'PY'
import json, os, sys
from pathlib import Path
sys.path.insert(0, os.environ.get("PYTHONPATH", "").split(":")[0])
from looputil import write_brief
parsed = json.loads(Path(os.environ["PARSED"]).read_text())
task = next(t for t in parsed["tasks"] if t["id"] == os.environ["TID"])
prompt = Path(os.environ["WPROMPT"]).read_text(encoding="utf-8") if os.environ.get("WPROMPT") and Path(os.environ["WPROMPT"]).is_file() else None
write_brief(Path(os.environ["BRIEF_MAIN"]), parsed, task, prompt)
wt = Path(os.environ["BRIEF_WT"])
wt.parent.mkdir(parents=True, exist_ok=True)
wt.write_text(Path(os.environ["BRIEF_MAIN"]).read_text(encoding="utf-8"), encoding="utf-8")
PY

  # 7. invoke Worker. Main events.jsonl is read-only so the model cannot append.
  lock_events_ro
  local worker_rc=0
  log "worker $tid attempt=$attempt cwd=$wt_rel"
  (
    cd "$wt" || exit 1
    # brief lives at worktree-relative loop/briefs/<id>.md
    eval "$LOOP_WORKER \"\$(cat \"loop/briefs/${tid}.md\")\""
  ) || worker_rc=$?
  unlock_events

  if [[ "$worker_rc" -ne 0 ]]; then
    log "worker exited $worker_rc"
    append_event task_failed "$tid" worker-nonzero
    TICK_TERMINAL=1
    cleanup_worktree "$wt" "$branch"
    project_state
    rm -f "$parsed_file" "$replay_file"
    return 10
  fi

  if [[ -f "$wt/loop/ASK.md" ]]; then
    log "worker wrote loop/ASK.md — waiting"
    append_event task_waiting "$tid"
    TICK_TERMINAL=1
    mkdir -p "$ROOT/loop"
    {
      echo "# NEED_HUMAN"
      echo
      echo "reason: waiting"
      echo
      echo "Worker asked a question. See $wt_rel/loop/ASK.md"
      echo "Answer or delete the questions, then rerun."
      echo
    } > "$NEED"
    project_state
    rm -f "$parsed_file" "$replay_file"
    exit 2
  fi

  # Restore events.jsonl in the worktree so a Worker edit cannot merge.
  if [[ -f "$EVENTS" ]]; then
    mkdir -p "$wt/loop"
    git -C "$wt" checkout HEAD -- loop/events.jsonl >/dev/null 2>&1 || cp "$EVENTS" "$wt/loop/events.jsonl" 2>/dev/null || true
  fi

  # Commit worktree changes (runner, not Worker) so merge --no-ff has a commit.
  git -C "$wt" add -A
  git -C "$wt" reset HEAD -- loop/events.jsonl >/dev/null 2>&1 || true
  git -C "$wt" checkout -- loop/events.jsonl >/dev/null 2>&1 || true
  if git -C "$wt" diff --cached --quiet && git -C "$wt" diff --quiet; then
    git -C "$wt" commit --allow-empty -m "loop: ${tid} ok" >/dev/null
  else
    git -C "$wt" add -A
    git -C "$wt" reset HEAD -- loop/events.jsonl >/dev/null 2>&1 || true
    git -C "$wt" checkout -- loop/events.jsonl >/dev/null 2>&1 || true
    git -C "$wt" commit -m "loop: ${tid} ok" >/dev/null
  fi
  local wt_head
  wt_head="$(git -C "$wt" rev-parse HEAD)"

  # 8. diff ⊆ touches
  local touches_json
  touches_json="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["decision"]["task"]["touches"]))' "$replay_file")"
  if ! touches_ok "$base_sha" "$wt_head" "$touches_json"; then
    log "touches violated — no merge"
    unlock_events
    append_event task_failed "$tid" touches
    TICK_TERMINAL=1
    # keep a fail commit message only in logs; do not merge
    cleanup_worktree "$wt" "$branch"
    project_state
    rm -f "$parsed_file" "$replay_file"
    return 10
  fi

  # 9. this task checks, then all already-done checks
  mapfile -t this_checks < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["decision"]["task"]["checks"]))' "$replay_file")
  mapfile -t done_checks < <(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for t in d["decision"].get("done_tasks") or []:
    for c in t.get("checks") or []:
        print(c)
' "$replay_file")
  if ! run_checks "$wt" "${this_checks[@]+"${this_checks[@]}"}" "${done_checks[@]+"${done_checks[@]}"}"; then
    log "checks failed — no merge"
    unlock_events
    append_event task_failed "$tid" checks
    TICK_TERMINAL=1
    cleanup_worktree "$wt" "$branch"
    project_state
    rm -f "$parsed_file" "$replay_file"
    # same tick: 3rd failure → stop
    local att
    att="$(python3 -c 'import json,sys; from pathlib import Path
sys.path.insert(0, sys.argv[3])
from looputil import load_events, replay
ev=load_events(Path(sys.argv[1]))
r=replay(ev, [sys.argv[2]])
print(r["tasks"][sys.argv[2]]["attempt"])
' "$EVENTS" "$tid" "$SCRIPT_DIR")"
    if [[ "$att" -ge 3 ]]; then
      write_need_and_stop retry-exhausted "[\"$tid\"]"
    fi
    return 10
  fi

  # 10. merge --no-ff into current branch; task_done; remove worktree; project
  if ! git -C "$ROOT" merge --no-ff "$branch" -m "loop: ${tid} ok"; then
    log "merge failed — treating as checks failure"
    git -C "$ROOT" merge --abort >/dev/null 2>&1 || true
    append_event task_failed "$tid" checks
    TICK_TERMINAL=1
    cleanup_worktree "$wt" "$branch"
    project_state
    rm -f "$parsed_file" "$replay_file"
    return 10
  fi
  append_event task_done "$tid"
  TICK_TERMINAL=1
  cleanup_worktree "$wt" "$branch"
  project_state
  rm -f "$parsed_file" "$replay_file"
  log "$tid done"
  return 10
}

# ---- outer loop ----
ensure_gitignore
ensure_git
mkdir -p "$ROOT/loop/briefs"
unlock_events

parsed_boot="$(mktemp)"
"$PARSE" "$ROOT/TASKS.md" > "$parsed_boot" || true
n_tasks="$(count_tasks "$parsed_boot")"
rm -f "$parsed_boot"
default_max=$((n_tasks * 3))
if [[ "$default_max" -lt 1 ]]; then
  default_max=30
fi
# algebraic cap default 30 unless LOOP_MAX_TICKS is set; also at least 3× tasks
if [[ -n "${LOOP_MAX_TICKS:-}" ]]; then
  MAX_TICKS="$LOOP_MAX_TICKS"
else
  if [[ "$default_max" -gt 30 ]]; then
    MAX_TICKS="$default_max"
  else
    MAX_TICKS=30
  fi
fi

log "max ticks=$MAX_TICKS (LOOP_WORKER set=${LOOP_WORKER:+yes})"

stall=0
tick=1
while [[ "$tick" -le "$MAX_TICKS" ]]; do
  log "tick $tick/$MAX_TICKS"
  TICK_TERMINAL=0
  one_tick
  rc=$?
  if [[ "$TICK_TERMINAL" -eq 1 ]]; then
    stall=0
  else
    stall=$((stall + 1))
    log "no terminal event this tick ($stall/2)"
    if [[ "$stall" -ge 2 ]]; then
      log "stalled: two ticks without task_done/task_failed/task_waiting"
      exit 3
    fi
  fi
  tick=$((tick + 1))
done

log "tick cap $MAX_TICKS reached"
exit 4
