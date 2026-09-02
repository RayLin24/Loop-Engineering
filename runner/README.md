# runner — min-loop v0 scheduler

`run-loop.sh` **is** the scheduler. It is not a session launcher around a master LLM. It parses `TASKS.md`, picks the lowest ready id, creates a git worktree, invokes `$LOOP_WORKER`, checks `touches` and `checks`, merges with `git merge --no-ff`, and appends `loop/events.jsonl`.

The model is only Worker. It must not write events, must not merge, must not edit `TASKS.md`.

## Run

From the project root:

```bash
export LOOP_WORKER='claude -p --permission-mode acceptEdits'
./runner/run-loop.sh
```

The runner executes:

```bash
(cd "$WORKTREE" && $LOOP_WORKER "$(cat loop/briefs/<id>.md)")
```

Worktree path: `.loop-worktrees/<id>-a<attempt>` (attempt is 1-based; a crash before a terminal event reuses the same attempt).

## Environment

| variable | meaning |
|---|---|
| `LOOP_WORKER` | Host command. Default: `claude -p --permission-mode acceptEdits` |
| `LOOP_MAX_TICKS` | Outer tick cap. If unset: `max(30, 3 × task count)` |

## Exit codes

| code | meaning |
|---|---|
| 0 | finished — read `loop/FINAL.md` |
| 2 | waiting-human — read `loop/NEED_HUMAN.md` / `loop/ASK.md` |
| 3 | stalled — two consecutive ticks with no `task_done` / `task_failed` / `task_waiting` |
| 4 | tick cap (`LOOP_MAX_TICKS`) |

## Helpers

- `parse-tasks` — read `TASKS.md`, emit JSON, detect `depends_on` cycles
- `replay` — replay `loop/events.jsonl` to per-id `status` + `attempt`; `--project` rewrites `loop/state.md`; `--decide` prints the next tick action

Helpers are deterministic. They do not call a model.
