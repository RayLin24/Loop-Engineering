#!/usr/bin/env bash
# 判停解析的回归检查。不调用 claude。
set -u
cd "$(dirname "$0")/.."
source runner/run-loop.sh

fail=0
check() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "ok  $name"
  else
    echo "FAIL $name: got $(printf '%q' "$got") want $(printf '%q' "$want")" >&2
    fail=1
  fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

write_state() {
  printf '%s\n' "$1" > "$tmpdir/state.md"
}

write_state $'- 项目: demo | 清单: TASKS.md (6 任务) | tick: 12/60 | 更新: 2026-07-08T14:30:00Z\n- 状态: running\n- 等待租约: 无\n- 备忘里出现 tick: 99 也不该被当成进展'
check "tick numerator" "$(get_tick "$tmpdir/state.md")" "12"
check "status running" "$(get_status "$tmpdir/state.md" "$tmpdir/missing-final.md")" "running"

write_state $'- 项目: demo | tick: 3/18\n- 状态: waiting-human'
check "waiting-human" "$(get_status "$tmpdir/state.md" "$tmpdir/missing-final.md")" "waiting-human"

write_state $'- 项目: demo | tick: 3/18\n- 状态: waiting_human'
check "waiting_human alias" "$(get_status "$tmpdir/state.md" "$tmpdir/missing-final.md")" "waiting-human"

write_state $'- 项目: demo | tick: 0/18\n- 状态: running | waiting-human | finished'
check "piped status is unknown" "$(get_status "$tmpdir/state.md" "$tmpdir/missing-final.md")" "unknown"

write_state $'- 项目: demo | tick: 4/18\n- 状态: finished'
printf 'done\n' > "$tmpdir/FINAL.md"
check "finished status stays finished" "$(get_status "$tmpdir/state.md" "$tmpdir/FINAL.md")" "finished"
write_state $'- 项目: demo | tick: 4/18\n- 状态: running'
check "stale FINAL does not override running" "$(get_status "$tmpdir/state.md" "$tmpdir/FINAL.md")" "running"
write_state $'- 项目: demo | tick: 4/18\n这不是状态行'
check "unreadable status ignores FINAL" "$(get_status "$tmpdir/state.md" "$tmpdir/FINAL.md")" "unknown"
rm -f "$tmpdir/state.md"
check "FINAL alone is finished" "$(get_status "$tmpdir/state.md" "$tmpdir/FINAL.md")" "finished"
rm -f "$tmpdir/FINAL.md"
check "nothing is fresh" "$(get_status "$tmpdir/state.md" "$tmpdir/FINAL.md")" "fresh"
check "missing tick is -1" "$(get_tick "$tmpdir/state.md")" "-1"

printf '%s\r\n' '- 项目: demo | tick: 7/18' '- 状态：finished' > "$tmpdir/crlf.md"
check "crlf and fullwidth colon" "$(get_status "$tmpdir/crlf.md" "$tmpdir/missing-final.md")" "finished"
check "crlf tick" "$(get_tick "$tmpdir/crlf.md")" "7"

printf '%s\n' '- 项目: demo | tick: 1/18' '- 状态: running' '- 等待租约: 2099-01-01T00:00:00Z' > "$tmpdir/lease.md"
epoch=$(get_lease_epoch "$tmpdir/lease.md")
check "lease epoch non-empty" "$([[ -n "$epoch" ]] && echo yes || echo no)" "yes"
printf '%s\n' '- 等待租约: 无' > "$tmpdir/nolease.md"
check "lease 无 is empty" "$(get_lease_epoch "$tmpdir/nolease.md")" ""
printf '%s\n' '- 等待租约: tomorrow' > "$tmpdir/badlease.md"
check "bad lease is empty" "$(get_lease_epoch "$tmpdir/badlease.md")" ""

parse_runner_args --dangerously-skip-permissions
check "flag alone keeps default generations" "$MAX_GENERATIONS" "30"
check "flag alone switches perm" "${PERM_ARGS[*]}" "--dangerously-skip-permissions"
parse_runner_args 50 --dangerously-skip-permissions
check "generations before flag" "$MAX_GENERATIONS" "50"
parse_runner_args --dangerously-skip-permissions 12
check "generations after flag" "$MAX_GENERATIONS" "12"
parse_runner_args
check "default perm restored" "${PERM_ARGS[*]}" "--permission-mode acceptEdits"
if parse_runner_args --nope; then
  echo "FAIL bad arg should fail" >&2
  fail=1
else
  echo "ok  bad arg rejected"
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "all parser checks passed"
