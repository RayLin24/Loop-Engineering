# Loop Engineering — min-loop v0

Deterministic runner + one Worker. The runner parses `TASKS.md`, dispatches **one** task per tick into a git worktree, invokes `$LOOP_WORKER`, runs `checks`, and merges if the diff stays inside `touches`. The model is only the Worker: it does not write events, does not merge, and does not edit `TASKS.md`.

Protocol (frozen): [MIN-LOOP.md](MIN-LOOP.md).

v0 does **not** include parallel dispatch, an LLM Verifier, a Meta-Analyst, or a master/orchestrator model. The scheduler is `runner/run-loop.sh`.

## Write `TASKS.md`

Copy [examples/TASKS.example.md](examples/TASKS.example.md) or follow [protocol/task-list-spec.md](protocol/task-list-spec.md) (same fields as MIN-LOOP.md §2):

- `id` — `T` + digits, matches `### [T1]`
- `depends_on` — all listed ids must be `done` before this task is ready; cycles stop the loop
- `touches` — only paths the Worker may write; directories end with `/`
- `checks` — shell commands, run in the worktree; after a successful merge, every **done** task's checks run again
- `context_files` — optional read list for the brief (files only)
- body — instructions for a Worker that cannot see other tasks

Do not put secrets in the global context; name environment variables instead.

Humans edit `TASKS.md`. The Worker must not.

## Run the runner

From the **project** root (the repo that contains `TASKS.md` and is a git repository with at least one commit):

```bash
export LOOP_WORKER='claude -p --permission-mode acceptEdits'
./runner/run-loop.sh
```

`LOOP_WORKER` is a one-line host command. The runner does:

```bash
(cd "$WORKTREE" && $LOOP_WORKER "$(cat loop/briefs/<id>.md)")
```

The brief is written under the main repo `loop/briefs/` and copied into the worktree so the Worker can read a worktree-relative path. Override `LOOP_WORKER` with any CLI that edits files in cwd and exits (including a fake script in tests).

Optional: `LOOP_MAX_TICKS` — tick cap. Default is `max(30, 3 × number of tasks)`.

See [runner/README.md](runner/README.md).

## Exit codes

| code | meaning | what to read |
|---|---|---|
| 0 | finished | `loop/FINAL.md` |
| 2 | waiting-human | `loop/NEED_HUMAN.md` and/or worktree `loop/ASK.md` |
| 3 | two ticks in a row with no `task_done` / `task_failed` / `task_waiting` | `loop/events.jsonl` |
| 4 | tick cap | raise `LOOP_MAX_TICKS` or fix the list |

State is replayed from `loop/events.jsonl` (runner-only, append-only). `loop/state.md` is a projection; deleting it is safe.

## Layout

```
MIN-LOOP.md                 # protocol
TASKS.md                    # you write this in the target project
prompts/worker.md           # only Worker prompt
runner/run-loop.sh          # only scheduler
runner/parse-tasks          # TASKS.md → JSON + cycle detect
runner/replay               # events.jsonl → status + attempt
protocol/task-list-spec.md  # pointer / §2 fields
examples/TASKS.example.md
```

Runtime (not committed in this framework repo): `loop/state.md`, `loop/briefs/`, `loop/NEED_HUMAN.md`, `loop/FINAL.md`, `.loop-worktrees/`. `loop/events.jsonl` may be committed in a target project as the recovery log.
