#!/usr/bin/env bash
# run-loop.sh — Loop Engineering 无人值守驱动器（macOS/Linux）
# 用法: 在项目根目录执行  ./runner/run-loop.sh [最大代数=30] [--dangerously-skip-permissions]
# 职责: 只做"拉起下一代主控会话 + 判停", 不含任何调度逻辑（调度智能在 prompts/ 与 protocol/）。

set -u
MAX_GENERATIONS="${1:-30}"
PERM_ARGS=(--permission-mode acceptEdits)
[[ "${2:-}" == "--dangerously-skip-permissions" ]] && PERM_ARGS=(--dangerously-skip-permissions)

STATE="loop/state.md"
FINAL="loop/FINAL.md"

[[ -f "LOOP.md" ]] || { echo "错误: 未找到 LOOP.md, 请在部署了框架的项目根目录运行。" >&2; exit 1; }

get_status() {
  [[ -f "$FINAL" ]] && { echo "finished"; return; }
  [[ -f "$STATE" ]] || { echo "fresh"; return; }
  local s
  s=$(grep -oE '^\s*-\s*状态:\s*\S+' "$STATE" | head -1 | awk -F': *' '{print $2}')
  echo "${s:-unknown}"
}

get_tick() {
  [[ -f "$STATE" ]] || { echo "-1"; return; }
  local t
  t=$(grep -oE '^\s*-\s*项目:.*tick:\s*[0-9]+' "$STATE" | head -1 | grep -oE 'tick:\s*[0-9]+' | grep -oE '[0-9]+$')
  echo "${t:--1}"
}

stall=0
for ((gen = 1; gen <= MAX_GENERATIONS; gen++)); do
  status=$(get_status)
  case "$status" in
    finished)
      echo "[runner] 循环已完成, 见 loop/FINAL.md。"; exit 0 ;;
    waiting-human)
      echo "[runner] 循环等待人工介入: 看 loop/state.md 的备忘与 loop/questions/ 待答问题。处理后重新运行本脚本。"; exit 2 ;;
  esac

  tick_before=$(get_tick)
  prompt="按 LOOP.md 继续"
  [[ "$status" == "fresh" ]] && prompt="按 LOOP.md 接管任务清单"
  echo "[runner] 第 ${gen} 代: claude -p \"${prompt}\"  (状态: ${status}, tick: ${tick_before})"

  claude -p "$prompt" "${PERM_ARGS[@]}"
  # 会话本身失败(非零退出)不立即终止——按停滞检测处理, 给瞬时故障一次机会

  tick_after=$(get_tick)
  if (( tick_after <= tick_before )); then
    stall=$((stall + 1))
    echo "[runner] 警告: 本代 tick 未前进 (${tick_before} -> ${tick_after}), 停滞计数 ${stall}/2。"
    if (( stall >= 2 )); then
      echo "[runner] 连续 2 代无进展, 停止以避免空转烧钱。请人工检查 loop/state.md 与环境。" >&2
      exit 3
    fi
  else
    stall=0
  fi
done

echo "[runner] 已达代数上限 ${MAX_GENERATIONS}, 停止。如需继续请再次运行。"
exit 4
