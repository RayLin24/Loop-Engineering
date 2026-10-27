# run-loop.ps1 — Loop Engineering 无人值守驱动器（Windows）
# 用法: 在项目根目录执行
#   .\runner\run-loop.ps1 [-MaxGenerations 30] [-DangerouslySkipPermissions]
# 职责: 只做"拉起下一次主控会话 + 判停", 不含任何调度逻辑。
# 本文件必须保存为 UTF-8 with BOM, 否则 Windows PowerShell 5.1 会按系统代码页误解析中文。

param(
    [int]$MaxGenerations = 30,
    [switch]$DangerouslySkipPermissions
)

$script:LoopStateFile = "loop/state.md"
$script:LoopFinalFile = "loop/FINAL.md"
$script:LoopMaxGenerations = $MaxGenerations
if ($DangerouslySkipPermissions) {
    $script:LoopPermArgs = @("--dangerously-skip-permissions")
} else {
    $script:LoopPermArgs = @("--permission-mode", "acceptEdits")
}

function Get-LoopText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    return ([System.IO.File]::ReadAllText($Path) -replace "`r", "")
}

function Get-LoopStatus {
    param(
        [string]$StatePath = $script:LoopStateFile,
        [string]$FinalPath = $script:LoopFinalFile
    )
    if (Test-Path -LiteralPath $StatePath) {
        $text = Get-LoopText -Path $StatePath
        $match = [regex]::Match($text, '(?m)^\s*-\s*状态[:：]\s*(.+?)\s*$')
        if (-not $match.Success) { return "unknown" }
        switch ($match.Groups[1].Value.Trim()) {
            "running" { return "running" }
            "finished" { return "finished" }
            "waiting-human" { return "waiting-human" }
            "waiting_human" { return "waiting-human" }
            default { return "unknown" }
        }
    }
    if (Test-Path -LiteralPath $FinalPath) { return "finished" }
    return "fresh"
}

function Get-TickNumber {
    param([string]$StatePath = $script:LoopStateFile)
    if (-not (Test-Path -LiteralPath $StatePath)) { return -1 }
    $text = Get-LoopText -Path $StatePath
    $match = [regex]::Match($text, '(?m)^\s*-\s*项目[:：].*?tick[:：]\s*(\d+)')
    if (-not $match.Success) { return -1 }
    return [int]$match.Groups[1].Value
}

function Get-LeaseEpoch {
    param([string]$StatePath = $script:LoopStateFile)
    if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
    $text = Get-LoopText -Path $StatePath
    $match = [regex]::Match($text, '(?m)^\s*-\s*等待租约[:：]\s*(.+?)\s*$')
    if (-not $match.Success) { return $null }
    $raw = $match.Groups[1].Value.Trim()
    if ($raw -eq "" -or $raw -eq "无") { return $null }
    if ($raw -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { return $null }
    try {
        $dto = [datetimeoffset]::Parse($raw, [cultureinfo]::InvariantCulture)
        $epoch = [datetimeoffset]::new(1970, 1, 1, 0, 0, 0, [timespan]::Zero)
        return [int64][math]::Floor(($dto.ToUniversalTime() - $epoch).TotalSeconds)
    } catch {
        return $null
    }
}

function Invoke-LoopDriver {
    $ErrorActionPreference = "Stop"
    # PowerShell 7 会把原生命令的非零退出当成终止错误。会话失败要交给停滞检测, 不要在这里停。
    $PSNativeCommandUseErrorActionPreference = $false

    if (-not (Test-Path -LiteralPath "LOOP.md")) {
        Write-Host "错误: 未找到 LOOP.md, 请在部署了框架的项目根目录运行。" -ForegroundColor Red
        exit 1
    }
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Host "错误: 未找到 claude CLI, 驱动器无法拉起会话。" -ForegroundColor Red
        exit 1
    }

    $stallCount = 0
    for ($gen = 1; $gen -le $script:LoopMaxGenerations; $gen++) {
        $status = Get-LoopStatus
        switch ($status) {
            "finished" {
                Write-Host "[runner] 循环已完成, 见 loop/FINAL.md。" -ForegroundColor Green
                Write-Host "[runner] 若刚刚往 TASKS.md 追加了任务, 先人工说一次「按 LOOP.md 继续」, 等投影状态回到 running 后再跑本脚本。"
                exit 0
            }
            "waiting-human" {
                Write-Host "[runner] 循环等待人工介入: 看 loop/state.md 的备忘与 loop/questions/ 待答问题。处理后重新运行本脚本。" -ForegroundColor Yellow
                exit 2
            }
            "unknown" {
                Write-Host "[runner] 警告: loop/state.md 的「状态」行无法解析。它必须单独是 running、waiting-human 或 finished, 不能把三个值写在同一行。" -ForegroundColor Yellow
            }
        }

        $lease = Get-LeaseEpoch
        $now = [int64][math]::Floor(([datetimeoffset]::UtcNow - [datetimeoffset]::new(1970, 1, 1, 0, 0, 0, [timespan]::Zero)).TotalSeconds)
        if ($status -eq "running" -and $null -ne $lease -and $lease -gt $now) {
            $delay = [int]($lease - $now)
            if ($delay -gt 3600) { $delay = 3600 }
            Write-Host "[runner] 投影仍在等待未到期租约, 休眠 ${delay}s 后再拉起（单次最多 3600s）。这段等待不代表主控在干活。" -ForegroundColor Yellow
            Start-Sleep -Seconds $delay
        }

        $tickBefore = Get-TickNumber
        $prompt = if ($status -eq "fresh") { "按 LOOP.md 接管任务清单" } else { "按 LOOP.md 继续" }
        Write-Host "[runner] 第 $gen 次拉起: claude -p `"$prompt`"  (状态: $status, tick: $tickBefore)" -ForegroundColor Cyan

        & claude -p $prompt @script:LoopPermArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[runner] 警告: claude 退出码 $LASTEXITCODE（不立即终止, 交给判停与停滞检测）。" -ForegroundColor Yellow
        }

        $status = Get-LoopStatus
        switch ($status) {
            "finished" {
                Write-Host "[runner] 循环已完成, 见 loop/FINAL.md。" -ForegroundColor Green
                exit 0
            }
            "waiting-human" {
                Write-Host "[runner] 循环等待人工介入: 看 loop/state.md 的备忘与 loop/questions/ 待答问题。处理后重新运行本脚本。" -ForegroundColor Yellow
                exit 2
            }
            "unknown" {
                Write-Host "[runner] 警告: 本轮结束后仍无法解析「状态」行。" -ForegroundColor Yellow
            }
        }

        $tickAfter = Get-TickNumber
        $lease = Get-LeaseEpoch
        $now = [int64][math]::Floor(([datetimeoffset]::UtcNow - [datetimeoffset]::new(1970, 1, 1, 0, 0, 0, [timespan]::Zero)).TotalSeconds)
        if ($tickAfter -le $tickBefore) {
            if ($status -eq "running" -and $null -ne $lease -and $lease -gt $now) {
                Write-Host "[runner] 本轮 tick 未前进 ($tickBefore -> $tickAfter), 但投影仍在等待未到期租约, 不记停滞。" -ForegroundColor Yellow
            } else {
                $stallCount++
                Write-Host "[runner] 警告: 本轮 tick 未前进 ($tickBefore -> $tickAfter), 停滞计数 $stallCount/2。" -ForegroundColor Yellow
                if ($stallCount -ge 2) {
                    Write-Host "[runner] 连续 2 次拉起无进展, 停止以避免空转烧钱。请人工检查 loop/state.md 与环境。" -ForegroundColor Red
                    exit 3
                }
            }
        } else {
            $stallCount = 0
        }
    }

    Write-Host "[runner] 已达拉起次数上限 $script:LoopMaxGenerations, 停止。如需继续请再次运行。" -ForegroundColor Yellow
    exit 4
}

# 测试脚本会先设置 LOOP_RUNNER_LIBRARY=1 再点源本文件, 避免点源检测在不同 PowerShell 宿主上不可靠。
if ($env:LOOP_RUNNER_LIBRARY -ne "1") {
    Invoke-LoopDriver
}
