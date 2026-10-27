#!/usr/bin/env bash
# run-loop.sh — Loop Engineering 无人值守驱动器（macOS/Linux）
# 用法: 在项目根目录执行
#   ./runner/run-loop.sh [最大拉起次数=30] [--dangerously-skip-permissions]
# 参数顺序不限。职责只有两件: 拉起下一次主控会话, 按投影判停。不含调度逻辑。

STATE="loop/state.md"
FINAL="loop/FINAL.md"
MAX_GENERATIONS=30
PERM_ARGS=(--permission-mode acceptEdits)

# 投影「状态」行必须整行只有一个值。旧模板把三个值用竖线写在一起时, 这里返回 unknown,
# 避免被解析成永远的 running。waiting_human 是任务状态用的下划线写法, 接受为同义词。
get_status() {
  local state_file="${1:-$STATE}"
  local final_file="${2:-$FINAL}"
  if [[ -f "$state_file" ]]; then
    local line raw
    # 全角冒号单独成一支, 避免 C locale 下把 UTF-8 塞进方括号后匹配碎掉。
    line=$(tr -d '\r' < "$state_file" | grep -E '^[[:space:]]*-[[:space:]]*状态:|^[[:space:]]*-[[:space:]]*状态：' | head -n 1 || true)
    raw=$(printf '%s\n' "$line" | sed -E \
      -e 's/^[[:space:]]*-[[:space:]]*状态:[[:space:]]*//' \
      -e 's/^[[:space:]]*-[[:space:]]*状态：[[:space:]]*//' \
      -e 's/[[:space:]]+$//')
    case "$raw" in
      running|finished) printf '%s\n' "$raw"; return 0 ;;
      waiting-human|waiting_human) printf '%s\n' "waiting-human"; return 0 ;;
      *) printf '%s\n' "unknown"; return 0 ;;
    esac
  fi
  if [[ -f "$final_file" ]]; then
    printf '%s\n' "finished"
    return 0
  fi
  printf '%s\n' "fresh"
}

# 只认「项目」那一行里的 tick 分子。备忘或轮次摘要里出现的 tick: 数字不算进展。
get_tick() {
  local state_file="${1:-$STATE}"
  if [[ ! -f "$state_file" ]]; then
    printf '%s\n' "-1"
    return 0
  fi
  local line num
  line=$(tr -d '\r' < "$state_file" | grep -E '^[[:space:]]*-[[:space:]]*项目:|^[[:space:]]*-[[:space:]]*项目：' | head -n 1 || true)
  num=$(printf '%s\n' "$line" | grep -oE 'tick:[[:space:]]*[0-9]+|tick：[[:space:]]*[0-9]+' | head -n 1 | grep -oE '[0-9]+$' || true)
  if [[ -z "${num:-}" ]]; then
    printf '%s\n' "-1"
  else
    printf '%s\n' "$num"
  fi
}

# 返回「等待租约」的 Unix 秒; 没有、写的是「无」、或解析失败时输出空行。
get_lease_epoch() {
  local state_file="${1:-$STATE}"
  if [[ ! -f "$state_file" ]]; then
    printf '\n'
    return 0
  fi
  local line raw epoch
  line=$(tr -d '\r' < "$state_file" | grep -E '^[[:space:]]*-[[:space:]]*等待租约:|^[[:space:]]*-[[:space:]]*等待租约：' | head -n 1 || true)
  raw=$(printf '%s\n' "$line" | sed -E \
    -e 's/^[[:space:]]*-[[:space:]]*等待租约:[[:space:]]*//' \
    -e 's/^[[:space:]]*-[[:space:]]*等待租约：[[:space:]]*//' \
    -e 's/[[:space:]]+$//')
  if [[ -z "$raw" || "$raw" == "无" ]]; then
    printf '\n'
    return 0
  fi
  if [[ ! "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    printf '\n'
    return 0
  fi
  if epoch=$(date -u -d "$raw" +%s 2>/dev/null); then
    printf '%s\n' "$epoch"
    return 0
  fi
  if epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$raw" +%s 2>/dev/null); then
    printf '%s\n' "$epoch"
    return 0
  fi
  printf '\n'
}

parse_runner_args() {
  MAX_GENERATIONS=30
  local skip=0
  local arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --dangerously-skip-permissions|-DangerouslySkipPermissions|--DangerouslySkipPermissions)
        skip=1
        ;;
      --)
        shift
        break
        ;;
      ''|*[!0-9]*)
        echo "错误: 无法识别的参数「${arg}」。" >&2
        echo "用法: ./runner/run-loop.sh [最大拉起次数] [--dangerously-skip-permissions]" >&2
        return 1
        ;;
      *)
        MAX_GENERATIONS=$arg
        ;;
    esac
    shift
  done
  if [[ $# -gt 0 ]]; then
    echo "错误: -- 之后不接受额外参数。" >&2
    return 1
  fi
  if [[ "$skip" -eq 1 ]]; then
    PERM_ARGS=(--dangerously-skip-permissions)
  else
    PERM_ARGS=(--permission-mode acceptEdits)
  fi
}

run_driver() {
  set -u
  [[ -f "LOOP.md" ]] || { echo "错误: 未找到 LOOP.md, 请在部署了框架的项目根目录运行。" >&2; exit 1; }
  command -v claude >/dev/null 2>&1 || { echo "错误: 未找到 claude CLI, 驱动器无法拉起会话。" >&2; exit 1; }

  local stall=0
  local gen status tick_before tick_after prompt lease now delay
  for ((gen = 1; gen <= 10#$MAX_GENERATIONS; gen++)); do
    status=$(get_status "$STATE" "$FINAL")
    case "$status" in
      finished)
        echo "[runner] 循环已完成, 见 loop/FINAL.md。"
        echo "[runner] 若刚刚往 TASKS.md 追加了任务, 先人工说一次「按 LOOP.md 继续」, 等投影状态回到 running 后再跑本脚本。"
        exit 0
        ;;
      waiting-human)
        echo "[runner] 循环等待人工介入: 看 loop/state.md 的备忘与 loop/questions/ 待答问题。处理后重新运行本脚本。"
        exit 2
        ;;
      unknown)
        echo "[runner] 警告: loop/state.md 的「状态」行无法解析。它必须单独是 running、waiting-human 或 finished, 不能把三个值写在同一行。" >&2
        ;;
    esac

    lease=$(get_lease_epoch "$STATE")
    now=$(date -u +%s)
    if [[ "$status" == "running" && -n "$lease" && "$lease" -gt "$now" ]]; then
      delay=$((lease - now))
      if (( delay > 3600 )); then delay=3600; fi
      echo "[runner] 投影仍在等待未到期租约, 休眠 ${delay}s 后再拉起（单次最多 3600s）。这段等待不代表主控在干活。"
      sleep "$delay"
    fi

    tick_before=$(get_tick "$STATE")
    if [[ "$status" == "fresh" ]]; then
      prompt="按 LOOP.md 接管任务清单"
    else
      prompt="按 LOOP.md 继续"
    fi
    echo "[runner] 第 ${gen} 次拉起: claude -p \"${prompt}\"  (状态: ${status}, tick: ${tick_before})"

    set +e
    claude -p "$prompt" "${PERM_ARGS[@]}"
    local claude_rc=$?
    set -e
    set -u
    if [[ "$claude_rc" -ne 0 ]]; then
      echo "[runner] 警告: claude 退出码 ${claude_rc}（不立即终止, 交给判停与停滞检测）。"
    fi

    status=$(get_status "$STATE" "$FINAL")
    case "$status" in
      finished)
        echo "[runner] 循环已完成, 见 loop/FINAL.md。"
        exit 0
        ;;
      waiting-human)
        echo "[runner] 循环等待人工介入: 看 loop/state.md 的备忘与 loop/questions/ 待答问题。处理后重新运行本脚本。"
        exit 2
        ;;
      unknown)
        echo "[runner] 警告: 本轮结束后仍无法解析「状态」行。" >&2
        ;;
    esac

    tick_after=$(get_tick "$STATE")
    lease=$(get_lease_epoch "$STATE")
    now=$(date -u +%s)
    if (( tick_after <= tick_before )); then
      if [[ "$status" == "running" && -n "$lease" && "$lease" -gt "$now" ]]; then
        echo "[runner] 本轮 tick 未前进 (${tick_before} -> ${tick_after}), 但投影仍在等待未到期租约, 不记停滞。"
      else
        stall=$((stall + 1))
        echo "[runner] 警告: 本轮 tick 未前进 (${tick_before} -> ${tick_after}), 停滞计数 ${stall}/2。"
        if (( stall >= 2 )); then
          echo "[runner] 连续 2 次拉起无进展, 停止以避免空转烧钱。请人工检查 loop/state.md 与环境。" >&2
          exit 3
        fi
      fi
    else
      stall=0
    fi
  done

  echo "[runner] 已达拉起次数上限 ${MAX_GENERATIONS}, 停止。如需继续请再次运行。"
  exit 4
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  parse_runner_args "$@" || exit 1
  run_driver
fi
