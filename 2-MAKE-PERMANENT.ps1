# ============================================================================
#  2-MAKE-PERMANENT.ps1   -   Run this as Administrator, after 1-FIX.ps1.
# ============================================================================
#
#  Makes the fix survive everything:
#    * Windows feature updates, which can reset your power plans
#    * switching power plans (ASUS Recommended, G-Helper/MyASUS, High Perf)
#    * OEM utilities that create and switch to their own plans
#
#  It installs a small script to C:\ProgramData and registers a task that
#  re-applies the fix to every power plan at every logon.
#
#  UNDO:   .\2-MAKE-PERMANENT.ps1 -Remove
#          (that removes the task; to undo the fix itself: .\1-FIX.ps1 -Revert)
#
#  This file is self-contained - it needs no other files to work.
# ============================================================================

param([switch]$Remove)

$TaskName  = 'IdleGuard'
# Deliberately on C:. If the guard lived on a secondary drive that isn't ready
# at logon (or is failing), it would silently do nothing and you'd never know.
$GuardPath = 'C:\ProgramData\idle-guard.ps1'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Must run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as administrator, then run this again."
    exit 1
}

if ($Remove) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $GuardPath -Force -ErrorAction SilentlyContinue
    Write-Host "Guard removed. Your current power settings are unchanged." -ForegroundColor Yellow
    Write-Host "To also undo the fix itself:  .\1-FIX.ps1 -Revert"
    exit 0
}

# The guard: re-applies the block to every power plan. Idempotent and silent.
@'
$SUB  = '54533251-82be-4824-96c1-47b60b740d00'
$IDLE = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
$MIN  = '893dee8e-2bef-41e0-89c6-b55d0929964c'
$MAX  = '9943e905-9a30-4ec1-9b99-44dd3b76f7a2'
foreach ($m in [regex]::Matches((powercfg /list | Out-String), 'GUID:\s*([0-9a-fA-F\-]{36})')) {
    $g = $m.Groups[1].Value
    powercfg /setacvalueindex $g $SUB $IDLE 1   2>$null
    powercfg /setdcvalueindex $g $SUB $IDLE 1   2>$null
    powercfg /setacvalueindex $g $SUB $MIN  100 2>$null
    powercfg /setdcvalueindex $g $SUB $MIN  100 2>$null
    powercfg /setacvalueindex $g $SUB $MAX  0   2>$null
    powercfg /setdcvalueindex $g $SUB $MAX  0   2>$null
}
powercfg /setactive SCHEME_CURRENT
'@ | Set-Content -Path $GuardPath -Encoding UTF8

Write-Host "Guard installed to $GuardPath"

# powershell.exe (built into Windows), not pwsh.exe - so this keeps working on
# machines that never installed PowerShell 7, or if it's removed later.
$a = New-ScheduledTaskAction -Execute 'powershell.exe' `
     -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$GuardPath`""
$t = New-ScheduledTaskTrigger -AtLogOn
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger $t -Settings $s `
     -User 'SYSTEM' -RunLevel Highest -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 3

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) { Write-Host "FAILED - the task did not register." -ForegroundColor Red; exit 1 }
Write-Host "Task '$TaskName' registered (state: $($task.State))" -ForegroundColor Green

Write-Host "`nChecking every power plan (want AC=1 DC=1 on all):" -ForegroundColor Cyan
$SUB='54533251-82be-4824-96c1-47b60b740d00'; $IDLE='5d76a2ca-e8c0-402f-a133-2158492d58ad'
$bad = 0
foreach ($m in [regex]::Matches((powercfg /list | Out-String), 'GUID:\s*([0-9a-fA-F\-]{36})\s*\(([^)]*)\)')) {
    $q = powercfg /query $m.Groups[1].Value $SUB $IDLE 2>$null | Out-String
    $ac = ([regex]::Match($q,'Current AC Power Setting Index:\s*(\S+)')).Groups[1].Value
    $dc = ([regex]::Match($q,'Current DC Power Setting Index:\s*(\S+)')).Groups[1].Value
    if ($ac -ne '0x00000001' -or $dc -ne '0x00000001') { $bad++ }
    "  {0,-30} AC={1} DC={2}" -f $m.Groups[2].Value, $ac, $dc
}

if ($bad -eq 0) {
    Write-Host "`nDone. All plans protected, and it re-applies at every logon." -ForegroundColor Green
    Write-Host "You don't need to think about this again."
} else {
    Write-Host "`n$bad plan(s) still unprotected - run .\1-FIX.ps1 first, then this again." -ForegroundColor Yellow
}
