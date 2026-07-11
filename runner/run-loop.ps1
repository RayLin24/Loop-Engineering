# run-loop.ps1 — Loop Engineering 无人值守驱动器（Windows）
# 用法: 在项目根目录执行  .\runner\run-loop.ps1 [-MaxGenerations 30] [-DangerouslySkipPermissions]
# 职责: 只做"拉起下一代主控会话 + 判停", 不含任何调度逻辑（调度智能在 prompts/ 与 protocol/）。

param(
    [int]$MaxGenerations = 30,
    [switch]$DangerouslySkipPermissions
)

$ErrorActionPreference = "Stop"
$stateFile = "loop/state.md"
$finalFile = "loop/FINAL.md"

if (-not (Test-Path "LOOP.md")) {
    Write-Host "错误: 未找到 LOOP.md, 请在部署了框架的项目根目录运行。" -ForegroundColor Red
    exit 1
}

function Get-LoopStatus {
    if (Test-Path $finalFile) { return "finished" }
    if (-not (Test-Path $stateFile)) { return "fresh" }
    $line = Select-String -Path $stateFile -Pattern '^\s*-\s*循环状态:\s*(\S+)' | Select-Object -First 1
    if ($null -eq $line) { return "unknown" }
    return $line.Matches[0].Groups[1].Value
}

function Get-RoundNumber {
    if (-not (Test-Path $stateFile)) { return -1 }
    $line = Select-String -Path $stateFile -Pattern '^\s*-\s*轮次:\s*(\d+)' | Select-Object -First 1
    if ($null -eq $line) { return -1 }
    return [int]$line.Matches[0].Groups[1].Value
}

$permArgs = @("--permission-mode", "acceptEdits")
if ($DangerouslySkipPermissions) { $permArgs = @("--dangerously-skip-permissions") }

$stallCount = 0
for ($gen = 1; $gen -le $MaxGenerations; $gen++) {
    $status = Get-LoopStatus
    switch ($status) {
        "finished" {
            Write-Host "[runner] 循环已完成, 见 loop/FINAL.md。" -ForegroundColor Green
            exit 0
        }
        "awaiting-human" {
            Write-Host "[runner] 循环等待人工介入, 详见 loop/state.md 的日志与备忘。处理后重新运行本脚本。" -ForegroundColor Yellow
            exit 2
        }
    }

    $roundBefore = Get-RoundNumber
    $prompt = if ($status -eq "fresh") { "按 LOOP.md 接管任务清单" } else { "按 LOOP.md 继续" }
    Write-Host "[runner] 第 $gen 代: claude -p `"$prompt`"  (状态: $status, 轮次: $roundBefore)" -ForegroundColor Cyan

    & claude -p $prompt @permArgs
    # 会话本身失败(非零退出)不立即终止——按停滞检测处理, 给瞬时故障一次机会

    $roundAfter = Get-RoundNumber
    if ($roundAfter -le $roundBefore) {
        $stallCount++
        Write-Host "[runner] 警告: 本代轮次未前进 ($roundBefore -> $roundAfter), 停滞计数 $stallCount/2。" -ForegroundColor Yellow
        if ($stallCount -ge 2) {
            Write-Host "[runner] 连续 2 代无进展, 停止以避免空转烧钱。请人工检查 loop/state.md 与环境。" -ForegroundColor Red
            exit 3
        }
    } else {
        $stallCount = 0
    }
}

Write-Host "[runner] 已达代数上限 $MaxGenerations, 停止。如需继续请再次运行。" -ForegroundColor Yellow
exit 4
