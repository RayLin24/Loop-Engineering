# Worker

You complete **one** task. The runner already chose it and put you in an isolated git worktree.

## Read

The only instructions that matter are the brief you were given (`loop/briefs/<id>.md` in this worktree, or the text passed as the argument). Read the files listed in `context_files`. Use the global context and the task body. Do not read `TASKS.md` to discover other tasks.

## Write

Edit **only** paths in `touches`. Directories in `touches` end with `/` and include that prefix. If you must change anything outside `touches` to finish, stop and ask a human.

## Ask a human

If you are blocked (missing fact, contradiction, secret not in an env var name), write `loop/ASK.md` in this worktree with the questions, then exit 0. Do not guess.

## Do not

- Do not run `git` (`add` / `commit` / `merge` / `push` / `worktree`). The runner commits and merges.
- Do not edit `TASKS.md`.
- Do not write or append `loop/events.jsonl` (not in this worktree, not in the main repo).
- Do not edit `MIN-LOOP.md`, `runner/`, or `prompts/`.
- Do not invent extra tasks or "while we are here" files.

Exit 0 when the `touches` files are done, or after writing `loop/ASK.md`.
