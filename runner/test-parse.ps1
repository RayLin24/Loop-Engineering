# 判停解析的回归检查。不调用 claude。
# 保存为 UTF-8 with BOM。

$ErrorActionPreference = "Stop"
$env:LOOP_RUNNER_LIBRARY = "1"
. "$PSScriptRoot\run-loop.ps1"
Remove-Item Env:LOOP_RUNNER_LIBRARY

$fail = $false
function Check([string]$Name, $Got, $Want) {
    if ("$Got" -eq "$Want") {
        Write-Host "ok  $Name"
    } else {
        Write-Host "FAIL ${Name}: got '$Got' want '$Want'"
        $script:fail = $true
    }
}

$tmpdir = Join-Path ([System.IO.Path]::GetTempPath()) ("loop-parse-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tmpdir | Out-Null
$missing = Join-Path $tmpdir "missing-final.md"

function Write-State([string]$Text) {
    $path = Join-Path $tmpdir "state.md"
    [System.IO.File]::WriteAllText($path, $Text.Replace("`n", "`r`n"))
    return $path
}

$state = Write-State "- 项目: demo | 清单: TASKS.md (6 任务) | tick: 12/60 | 更新: 2026-07-08T14:30:00Z`n- 状态: running`n- 等待租约: 无`n- 备忘里出现 tick: 99 也不该被当成进展"
Check "tick numerator" (Get-TickNumber -StatePath $state) 12
Check "status running" (Get-LoopStatus -StatePath $state -FinalPath $missing) "running"

$state = Write-State "- 项目: demo | tick: 3/18`n- 状态: waiting-human"
Check "waiting-human" (Get-LoopStatus -StatePath $state -FinalPath $missing) "waiting-human"

$state = Write-State "- 项目: demo | tick: 3/18`n- 状态: waiting_human"
Check "waiting_human alias" (Get-LoopStatus -StatePath $state -FinalPath $missing) "waiting-human"

$state = Write-State "- 项目: demo | tick: 0/18`n- 状态: running | waiting-human | finished"
Check "piped status is unknown" (Get-LoopStatus -StatePath $state -FinalPath $missing) "unknown"

$final = Join-Path $tmpdir "FINAL.md"
[System.IO.File]::WriteAllText($final, "done")
$state = Write-State "- 项目: demo | tick: 4/18`n- 状态: running"
Check "stale FINAL does not override running" (Get-LoopStatus -StatePath $state -FinalPath $final) "running"
$state = Write-State "- 项目: demo | tick: 4/18`n这不是状态行"
Check "unreadable status ignores FINAL" (Get-LoopStatus -StatePath $state -FinalPath $final) "unknown"
$absent = Join-Path $tmpdir "no-state.md"
Check "FINAL alone is finished" (Get-LoopStatus -StatePath $absent -FinalPath $final) "finished"
Check "nothing is fresh" (Get-LoopStatus -StatePath $absent -FinalPath (Join-Path $tmpdir "nope.md")) "fresh"
Check "missing tick is -1" (Get-TickNumber -StatePath $absent) -1

$state = Write-State "- 项目: demo | tick： 7/18`n- 状态：finished"
Check "fullwidth colon" (Get-LoopStatus -StatePath $state -FinalPath $missing) "finished"
Check "fullwidth tick" (Get-TickNumber -StatePath $state) 7

$state = Write-State "- 项目: demo | tick: 1/18`n- 状态: running`n- 等待租约: 2099-01-01T00:00:00Z"
$epoch = Get-LeaseEpoch -StatePath $state
Check "lease epoch non-empty" ($(if ($null -ne $epoch) { "yes" } else { "no" })) "yes"
$state = Write-State "- 等待租约: 无"
Check "lease none is empty" ($(if ($null -eq (Get-LeaseEpoch -StatePath $state)) { "empty" } else { "set" })) "empty"
$state = Write-State "- 等待租约: tomorrow"
Check "bad lease is empty" ($(if ($null -eq (Get-LeaseEpoch -StatePath $state)) { "empty" } else { "set" })) "empty"

Remove-Item -Recurse -Force $tmpdir
if ($fail) { exit 1 }
Write-Host "all parser checks passed"
