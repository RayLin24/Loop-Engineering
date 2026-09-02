#!/usr/bin/env python3
"""Shared parse + replay helpers for min-loop v0. No extra event types or fields."""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LEGAL_TYPES = (
    "loop_started",
    "dispatched",
    "task_done",
    "task_failed",
    "task_waiting",
    "loop_finished",
)
FAIL_REASONS = ("checks", "touches", "worker-nonzero", "retry-exhausted")
HEADING_RE = re.compile(r"^### \[T(\d+)\]\s*(.*)$")
ID_RE = re.compile(r"^T(\d+)$")
FIELD_KEYS = ("id", "depends_on", "touches", "checks", "context_files")


def utc_ts() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def id_num(tid: str) -> int:
    m = ID_RE.match(tid)
    if not m:
        return 10**9
    return int(m.group(1))


def parse_inline_list(raw: str) -> list[str]:
    s = raw.strip()
    if not s:
        return []
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        if not inner:
            return []
        return [p.strip().strip("'\"") for p in inner.split(",") if p.strip()]
    return [s.strip().strip("'\"")]


def parse_tasks(text: str) -> dict[str, Any]:
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    name = ""
    global_lines: list[str] = []
    section = "pre"
    tasks: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    current_list: str | None = None
    body_lines: list[str] = []
    in_fields = True

    def finish_task() -> None:
        nonlocal current, body_lines, current_list, in_fields
        if current is None:
            return
        current["body"] = "\n".join(body_lines).strip()
        if not current.get("id"):
            current["id"] = current["_heading_id"]
        current.setdefault("depends_on", [])
        current.setdefault("touches", [])
        current.setdefault("checks", [])
        current.setdefault("context_files", [])
        current.pop("_heading_id", None)
        tasks.append(current)
        current = None
        body_lines = []
        current_list = None
        in_fields = True

    for raw in lines:
        line = raw.rstrip("\n")
        stripped = line.strip()

        if section == "pre":
            if line.startswith("# "):
                name = line[2:].strip()
                if name.startswith("任务清单：") or name.startswith("任务清单:"):
                    name = name.split("：", 1)[-1].split(":", 1)[-1].strip()
            if re.match(r"^##\s+全局上下文", stripped):
                section = "global"
                continue
            if re.match(r"^##\s+任务", stripped):
                section = "tasks"
                continue
            continue

        if section == "global":
            if re.match(r"^##\s+任务", stripped):
                section = "tasks"
                continue
            global_lines.append(line)
            continue

        # tasks
        hm = HEADING_RE.match(stripped)
        if hm:
            finish_task()
            current = {
                "_heading_id": f"T{hm.group(1)}",
                "id": f"T{hm.group(1)}",
                "title": hm.group(2).strip(),
                "depends_on": [],
                "touches": [],
                "checks": [],
                "context_files": [],
            }
            body_lines = []
            current_list = None
            in_fields = True
            continue

        if current is None:
            continue

        if stripped in ("```", "```yaml", "```yml"):
            continue

        key_m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", stripped)
        if in_fields and key_m and key_m.group(1) in FIELD_KEYS:
            key = key_m.group(1)
            rest = key_m.group(2).strip()
            current_list = None
            if key == "id":
                current["id"] = rest
                current_list = None
            elif key == "depends_on":
                if rest in ("", "|"):
                    current["depends_on"] = []
                    current_list = "depends_on"
                else:
                    current["depends_on"] = parse_inline_list(rest)
                    current_list = None
            elif key in ("touches", "checks", "context_files"):
                current[key] = parse_inline_list(rest) if rest and not rest.startswith("|") else []
                current_list = key
            continue

        list_m = re.match(r"^-\s+(.*)$", stripped)
        if in_fields and current_list and list_m:
            current[current_list].append(list_m.group(1).strip())
            continue

        if in_fields and not stripped:
            continue

        # body
        in_fields = False
        current_list = None
        body_lines.append(line)

    finish_task()

    errors: list[str] = []
    seen: set[str] = set()
    for t in tasks:
        tid = t["id"]
        if not ID_RE.match(tid):
            errors.append(f"invalid id {tid!r} (want T + digits)")
        if tid in seen:
            errors.append(f"duplicate id {tid}")
        seen.add(tid)
        if t.get("title") is not None and t.get("_heading_id"):
            pass
        if not t["touches"]:
            errors.append(f"{tid}: touches is required")
        if not t["checks"]:
            errors.append(f"{tid}: checks is required")
        if not t["body"]:
            errors.append(f"{tid}: body is required")
        for dep in t["depends_on"]:
            if dep not in seen and dep not in {x["id"] for x in tasks}:
                # checked after loop
                pass

    ids = {t["id"] for t in tasks}
    for t in tasks:
        for dep in t["depends_on"]:
            if dep not in ids:
                errors.append(f"{t['id']}: depends_on unknown {dep}")

    cycle = find_cycle(tasks)
    return {
        "name": name,
        "global_context": "\n".join(global_lines).strip(),
        "tasks": tasks,
        "cycle": cycle,
        "errors": errors,
    }


def find_cycle(tasks: list[dict[str, Any]]) -> list[str] | None:
    graph = {t["id"]: list(t["depends_on"]) for t in tasks}
    visiting: set[str] = set()
    visited: set[str] = set()
    stack: list[str] = []

    def dfs(node: str) -> list[str] | None:
        if node in visited:
            return None
        visiting.add(node)
        stack.append(node)
        for nxt in graph.get(node, []):
            if nxt in visiting:
                i = stack.index(nxt)
                return stack[i:] + [nxt]
            found = dfs(nxt)
            if found:
                return found
        stack.pop()
        visiting.remove(node)
        visited.add(node)
        return None

    for tid in graph:
        found = dfs(tid)
        if found:
            return found
    return None


def load_events(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    events: list[dict[str, Any]] = []
    raw = path.read_text(encoding="utf-8")
    for i, line in enumerate(raw.splitlines(), 1):
        s = line.strip()
        if not s:
            continue
        try:
            ev = json.loads(s)
        except json.JSONDecodeError:
            # tolerate a truncated last line (crash during append)
            if i == len([ln for ln in raw.splitlines() if ln.strip()]) or line == raw.splitlines()[-1]:
                continue
            raise
        if isinstance(ev, dict) and ev.get("type"):
            events.append(ev)
    return events


def replay(events: list[dict[str, Any]], task_ids: list[str]) -> dict[str, Any]:
    """Replay events → per-id status + attempt. Crash dispatch (no terminal) does not increment attempt."""
    state: dict[str, dict[str, Any]] = {
        tid: {"status": "pending", "attempt": 0, "open_dispatch": False} for tid in task_ids
    }
    extra_done: list[str] = []
    last_seq = 0
    saw_loop_finished = False

    for ev in events:
        seq = ev.get("seq")
        if isinstance(seq, int):
            last_seq = max(last_seq, seq)
        typ = ev.get("type")
        tid = ev.get("id")
        if typ == "loop_finished":
            saw_loop_finished = True
            continue
        if typ not in ("dispatched", "task_done", "task_failed", "task_waiting"):
            continue
        if not tid:
            continue
        if tid not in state:
            if typ == "task_done":
                extra_done.append(tid)
            state[tid] = {"status": "pending", "attempt": 0, "open_dispatch": False}

        rec = state[tid]
        if typ == "dispatched":
            if not rec["open_dispatch"]:
                rec["pre_dispatch_status"] = rec["status"]
            rec["open_dispatch"] = True
            rec["status"] = "running"
            continue

        # terminal for this id
        if typ == "task_failed" and ev.get("reason") == "retry-exhausted":
            rec["open_dispatch"] = False
            rec["status"] = "failed"
            continue
        if typ == "task_done":
            rec["attempt"] = rec["attempt"] + 1
            rec["status"] = "done"
        elif typ == "task_failed":
            rec["attempt"] = rec["attempt"] + 1
            rec["status"] = "failed"
        elif typ == "task_waiting":
            rec["attempt"] = rec["attempt"] + 1
            rec["status"] = "waiting"
        rec["open_dispatch"] = False
        rec["pre_dispatch_status"] = rec["status"]

    # open dispatch without terminal = crash: treat as not happened; attempt unchanged
    for tid, rec in state.items():
        if rec["open_dispatch"]:
            rec["status"] = rec.get("pre_dispatch_status") or (
                "pending" if rec["attempt"] == 0 else "failed"
            )
            rec["open_dispatch"] = False

    tasks_out = {}
    for tid in task_ids:
        rec = state.get(tid, {"status": "pending", "attempt": 0})
        tasks_out[tid] = {"status": rec["status"], "attempt": rec["attempt"]}

    return {
        "last_seq": last_seq,
        "tasks": tasks_out,
        "deleted_done": extra_done,
        "loop_finished": saw_loop_finished,
        "has_events": bool(events),
    }


def apply_waiting_to_pending(task_states: dict[str, dict[str, Any]], ask_present: dict[str, bool]) -> None:
    """waiting → pending on the next tick if ASK is gone / empty."""
    for tid, rec in task_states.items():
        if rec["status"] == "waiting" and not ask_present.get(tid, False):
            rec["status"] = "pending"


def ready_ids(parsed: dict[str, Any], task_states: dict[str, dict[str, Any]]) -> list[str]:
    done = {tid for tid, rec in task_states.items() if rec["status"] == "done"}
    ready: list[str] = []
    for t in parsed["tasks"]:
        tid = t["id"]
        rec = task_states.get(tid, {"status": "pending", "attempt": 0})
        if rec["status"] not in ("pending", "failed"):
            continue
        if rec["attempt"] >= 3:
            continue
        deps = t["depends_on"]
        if all(d in done for d in deps):
            ready.append(tid)
    ready.sort(key=id_num)
    return ready


def loop_status(
    parsed: dict[str, Any],
    replayed: dict[str, Any],
    *,
    final_exists: bool,
    need_human: bool,
) -> str:
    if need_human:
        return "waiting-human"
    if not replayed["has_events"]:
        return "fresh"
    states = replayed["tasks"]
    if parsed["tasks"] and all(states[t["id"]]["status"] == "done" for t in parsed["tasks"]) and final_exists:
        return "finished"
    if any(states[t["id"]]["status"] == "waiting" for t in parsed["tasks"]):
        return "waiting-human"
    return "running"


def project_state_md(
    parsed: dict[str, Any],
    replayed: dict[str, Any],
    status: str,
) -> str:
    lines = [
        "# loop state（投影，勿手改；删了可从 events.jsonl 重算）",
        "",
        f"- 状态: {status}",
        f"- 项目: {parsed.get('name') or '-'}",
        "",
        "## 任务",
        "",
    ]
    if not parsed["tasks"]:
        lines.append("（无任务）")
    for t in parsed["tasks"]:
        rec = replayed["tasks"].get(t["id"], {"status": "pending", "attempt": 0})
        lines.append(f"- {t['id']}: {rec['status']}  attempt={rec['attempt']}  {t.get('title', '')}".rstrip())
    lines.append("")
    return "\n".join(lines)


def append_event(events_path: Path, typ: str, **fields: Any) -> dict[str, Any]:
    if typ not in LEGAL_TYPES:
        raise ValueError(f"illegal event type {typ}")
    events_path.parent.mkdir(parents=True, exist_ok=True)
    existing = load_events(events_path)
    seq = 1
    if existing:
        seq = max(int(ev.get("seq") or 0) for ev in existing) + 1
    ev: dict[str, Any] = {"seq": seq, "ts": utc_ts(), "type": typ}
    for k, v in fields.items():
        if v is not None:
            ev[k] = v
    # schema lock: only allowed keys
    allowed = {"seq", "ts", "type"}
    if typ in ("dispatched", "task_done", "task_failed", "task_waiting"):
        allowed.add("id")
    if typ == "task_failed":
        allowed.add("reason")
    ev = {k: ev[k] for k in ev if k in allowed}
    if typ in ("dispatched", "task_done", "task_failed", "task_waiting") and "id" not in ev:
        raise ValueError(f"{typ} requires id")
    if typ == "task_failed":
        if ev.get("reason") not in FAIL_REASONS:
            raise ValueError(f"illegal fail reason {ev.get('reason')}")
    line = json.dumps(ev, ensure_ascii=False, separators=(",", ":"))
    fd = os.open(str(events_path), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    try:
        if sys.platform != "win32":
            import fcntl

            fcntl.flock(fd, fcntl.LOCK_EX)
        os.write(fd, (line + "\n").encode("utf-8"))
    finally:
        os.close(fd)
    return ev


def write_brief(path: Path, parsed: dict[str, Any], task: dict[str, Any], worker_prompt: str | None = None) -> str:
    def bullets(items: list[str]) -> str:
        if not items:
            return "(none)"
        return "\n".join(f"- {x}" for x in items)

    parts = []
    if worker_prompt:
        parts.append(worker_prompt.rstrip() + "\n")
    parts.append(f"# brief {task['id']}: {task.get('title', '')}".rstrip())
    parts.append("")
    parts.append("## global_context (also TASKS.md ## 全局上下文)")
    parts.append(parsed.get("global_context") or "(empty)")
    parts.append("")
    parts.append("## body")
    parts.append(task.get("body") or "")
    parts.append("")
    parts.append("## context_files")
    parts.append(bullets(task.get("context_files") or []))
    parts.append("")
    parts.append("## touches")
    parts.append(bullets(task["touches"]))
    parts.append("")
    parts.append("## checks")
    parts.append(bullets(task["checks"]))
    parts.append("")
    text = "\n".join(parts)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return text


def path_in_touches(relpath: str, touches: list[str]) -> bool:
    rel = relpath.replace("\\", "/").lstrip("./")
    if rel == "loop/events.jsonl":
        return False
    for t in touches:
        t = t.replace("\\", "/").lstrip("./")
        if not t:
            continue
        if t.endswith("/"):
            if rel.startswith(t) or rel == t[:-1]:
                return True
        elif rel == t:
            return True
        elif rel.startswith(t + "/"):
            return True
        elif t.startswith(rel + "/"):
            # directory listed without files? not a match for a file
            continue
        elif rel.startswith(t) and (len(rel) == len(t) or rel[len(t) : len(t) + 1] in ("/", ".")):
            # prefix containment: src/foo matches src/foo.py
            return True
    return False


def decide(
    parsed: dict[str, Any],
    replayed: dict[str, Any],
    *,
    ask_present: dict[str, bool],
    final_exists: bool,
) -> dict[str, Any]:
    if parsed.get("errors"):
        return {"action": "need_human", "reason": "parse-error", "detail": parsed["errors"]}
    if parsed.get("cycle"):
        return {"action": "need_human", "reason": "cycle", "detail": parsed["cycle"]}

    # done ids deleted from TASKS.md
    listed = {t["id"] for t in parsed["tasks"]}
    deleted = [tid for tid in replayed.get("deleted_done", []) if tid not in listed]
    # also: replayed tasks marked done that are no longer in the list
    for tid, rec in replayed["tasks"].items():
        if rec["status"] == "done" and tid not in listed:
            deleted.append(tid)
    deleted = sorted(set(deleted), key=id_num)
    if deleted:
        return {"action": "need_human", "reason": "done-deleted", "detail": deleted}

    apply_waiting_to_pending(replayed["tasks"], ask_present)
    ready = ready_ids(parsed, replayed["tasks"])
    waiting = [t["id"] for t in parsed["tasks"] if replayed["tasks"][t["id"]]["status"] == "waiting"]
    failed_exhausted = [
        t["id"]
        for t in parsed["tasks"]
        if replayed["tasks"][t["id"]]["status"] == "failed" and replayed["tasks"][t["id"]]["attempt"] >= 3
    ]
    all_done = bool(parsed["tasks"]) and all(replayed["tasks"][t["id"]]["status"] == "done" for t in parsed["tasks"])
    if not parsed["tasks"]:
        all_done = True

    if not ready:
        if waiting:
            return {"action": "need_human", "reason": "waiting", "detail": waiting, "ready": []}
        if failed_exhausted:
            return {"action": "need_human", "reason": "retry-exhausted", "detail": failed_exhausted, "ready": []}
        return {"action": "finished", "reason": "all-done", "ready": [], "final_exists": final_exists}

    pick = ready[0]
    task = next(t for t in parsed["tasks"] if t["id"] == pick)
    rec = replayed["tasks"][pick]
    # worktree uses 1-based next attempt index; crash reuse = attempt+1
    next_attempt = rec["attempt"] + 1
    done_tasks = [t for t in parsed["tasks"] if replayed["tasks"][t["id"]]["status"] == "done"]
    return {
        "action": "dispatch",
        "id": pick,
        "attempt": next_attempt,
        "task": task,
        "done_tasks": done_tasks,
        "ready": ready,
    }


def need_human_text(reason: str, detail: Any) -> str:
    lines = [
        "# NEED_HUMAN",
        "",
        f"reason: {reason}",
        "",
    ]
    if reason == "cycle":
        lines.append("TASKS.md depends_on has a cycle:")
        lines.append(" -> ".join(detail) if isinstance(detail, list) else str(detail))
    elif reason == "done-deleted":
        lines.append("These ids were done in events.jsonl but are missing from TASKS.md:")
        lines.append(", ".join(detail) if isinstance(detail, list) else str(detail))
    elif reason == "waiting":
        lines.append("A worker asked a human (loop/ASK.md). Answer or delete the questions, then rerun.")
        lines.append(str(detail))
    elif reason == "retry-exhausted":
        lines.append("A task failed 3 times. Edit TASKS.md / checks, then rerun.")
        lines.append(str(detail))
    elif reason == "parse-error":
        lines.append("TASKS.md could not be parsed:")
        for item in detail if isinstance(detail, list) else [detail]:
            lines.append(f"- {item}")
    else:
        lines.append(str(detail))
    lines.append("")
    lines.append("Delete this file after handling, then run ./runner/run-loop.sh again.")
    lines.append("")
    return "\n".join(lines)


def final_text(parsed: dict[str, Any], replayed: dict[str, Any]) -> str:
    lines = [
        "# FINAL",
        "",
        f"project: {parsed.get('name') or '-'}",
        "",
        "All tasks are done.",
        "",
    ]
    for t in parsed["tasks"]:
        rec = replayed["tasks"][t["id"]]
        lines.append(f"- {t['id']}: done  attempt={rec['attempt']}  {t.get('title', '')}".rstrip())
    lines.append("")
    return "\n".join(lines)
