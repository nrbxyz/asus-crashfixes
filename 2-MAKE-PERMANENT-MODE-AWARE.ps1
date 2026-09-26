# ============================================================================
#  2-MAKE-PERMANENT-MODE-AWARE.ps1   -   Run as Administrator, after 1-FIX.ps1.
#                                        Use this INSTEAD of 2-MAKE-PERMANENT.ps1.
# ============================================================================
#
#  Same idea as 2-MAKE-PERMANENT.ps1 (a guard that re-applies the fix to every
#  power plan at every logon), but with one carve-out:
#
#    Ultimate / dGPU mode, plugged in  : deep C-states ALLOWED
#    everything else, and ALL battery  : deep C-states blocked
#
#  An active dGPU keeps the fabric awake and the AC policy idles less deeply,
#  so this combination is the least exposed one. Allowing idle there gets back
#  some of the heat, fan noise and idle draw the full block costs you.
#  Trade-off: dGPU mode is "safer, not immune" (see SYMPTOMS.md). If you still
#  crash plugged in on Ultimate, go back to plain 2-MAKE-PERMANENT.ps1.
#
#  Fail-closed: the guard blocks everything first, and only opens the AC
#  carve-out when it positively sees the NVIDIA GPU driving the display and the
#  AMD iGPU driving none. Presence of the NVIDIA device is not enough - G-Helper's
#  Ultimate keeps the iGPU enumerated. At logon the display driver may not have
#  claimed the screen yet, so it waits up to ~2 minutes before deciding.
#
#  The mode is only checked at logon. Switch GPU mode, then sign out and back
#  in (or reboot) for the guard to pick up the new mode.
#
#  Uses the same task name and script path as 2-MAKE-PERMANENT.ps1, so the two
#  replace each other, and 3-UNDO-EVERYTHING.ps1 removes either.
#
#  UNDO:   .\2-MAKE-PERMANENT-MODE-AWARE.ps1 -Remove
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

# The guard. Runs at logon as SYSTEM.
@'
# IdleGuard v3.1 - mode-aware C-state policy for GA503RW crash containment.
# Runs at logon (SYSTEM). FAIL-CLOSED.
#
#   Ultimate                  : AC = C-states ALLOWED   DC = blocked
#   Everything else / unsure  : AC + DC = blocked
#
# Ultimate = NVIDIA adapter actively drives a display (has a current mode)
#            AND the AMD iGPU drives none. Device presence is not used:
#            G-Helper's Ultimate keeps the iGPU enumerated.
# At logon the GPU driver may not have claimed the display yet, so block
# everything IMMEDIATELY, then wait up to ~2 min for some adapter to own the
# display before deciding whether to open the AC carve-out.
$SUB  = '54533251-82be-4824-96c1-47b60b740d00'
$IDLE = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
$MIN  = '893dee8e-2bef-41e0-89c6-b55d0929964c'
$MAX  = '9943e905-9a30-4ec1-9b99-44dd3b76f7a2'

function Apply-Policy([int]$acIdle) {
    foreach ($m in [regex]::Matches((powercfg /list | Out-String), 'GUID:\s*([0-9a-fA-F\-]{36})')) {
        $g = $m.Groups[1].Value
        powercfg /setacvalueindex $g $SUB $IDLE $acIdle 2>$null
        powercfg /setdcvalueindex $g $SUB $IDLE 1       2>$null   # battery: ALWAYS blocked
        powercfg /setacvalueindex $g $SUB $MIN  100     2>$null
        powercfg /setdcvalueindex $g $SUB $MIN  100     2>$null
        powercfg /setacvalueindex $g $SUB $MAX  0       2>$null
        powercfg /setdcvalueindex $g $SUB $MAX  0       2>$null
    }
    powercfg /setactive SCHEME_CURRENT
}

# 1. Protect first: full block while we figure out the mode.
Apply-Policy 1

# 2. Wait for display ownership to become readable (driver init race at logon).
$ultimate = $false
for ($i = 0; $i -lt 24; $i++) {
    try {
        $vc = Get-CimInstance Win32_VideoController -ErrorAction Stop
        $nvDrives  = [bool]($vc | Where-Object { $_.Name -match 'NVIDIA' -and $_.CurrentHorizontalResolution -gt 0 })
        $amdDrives = [bool]($vc | Where-Object { $_.Name -match 'AMD|Radeon' -and $_.CurrentHorizontalResolution -gt 0 })
        if ($nvDrives -or $amdDrives) {           # somebody owns the display: verdict is trustworthy
            $ultimate = $nvDrives -and (-not $amdDrives)
            break
        }
    } catch { }                                   # CIM not ready yet: keep waiting
    Start-Sleep -Seconds 5
}

# 3. Open the AC carve-out only on a positively confirmed Ultimate mode.
if ($ultimate) { Apply-Policy 0 }
'@ | Set-Content -Path $GuardPath -Encoding UTF8

Write-Host "Mode-aware guard installed to $GuardPath"

# powershell.exe (built into Windows), not pwsh.exe - so this keeps working on
# machines that never installed PowerShell 7, or if it's removed later.
$a = New-ScheduledTaskAction -Execute 'powershell.exe' `
     -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$GuardPath`""
$t = New-ScheduledTaskTrigger -AtLogOn
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger $t -Settings $s `
     -User 'SYSTEM' -RunLevel Highest -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) { Write-Host "FAILED - the task did not register." -ForegroundColor Red; exit 1 }
Write-Host "Task '$TaskName' registered" -ForegroundColor Green

Write-Host "`nRunning the guard now (can take up to ~2 minutes to decide the GPU mode)..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 5
    if ((Get-ScheduledTask -TaskName $TaskName).State -ne 'Running') { break }
}

Write-Host "`nChecking every power plan (battery should be DC=1 on all):" -ForegroundColor Cyan
$SUB='54533251-82be-4824-96c1-47b60b740d00'; $IDLE='5d76a2ca-e8c0-402f-a133-2158492d58ad'
$bad = 0; $acOpen = 0
foreach ($m in [regex]::Matches((powercfg /list | Out-String), 'GUID:\s*([0-9a-fA-F\-]{36})\s*\(([^)]*)\)')) {
    $q = powercfg /query $m.Groups[1].Value $SUB $IDLE 2>$null | Out-String
    $ac = ([regex]::Match($q,'Current AC Power Setting Index:\s*(\S+)')).Groups[1].Value
    $dc = ([regex]::Match($q,'Current DC Power Setting Index:\s*(\S+)')).Groups[1].Value
    if ($dc -ne '0x00000001') { $bad++ }
    if ($ac -eq '0x00000000') { $acOpen++ }
    "  {0,-30} AC={1} DC={2}" -f $m.Groups[2].Value, $ac, $dc
}

if ($bad -ne 0) {
    Write-Host "`n$bad plan(s) unprotected on battery - run .\1-FIX.ps1 first, then this again." -ForegroundColor Yellow
} elseif ($acOpen -gt 0) {
    Write-Host "`nDone. Ultimate mode detected: C-states allowed when plugged in, blocked on battery." -ForegroundColor Green
} else {
    Write-Host "`nDone. Not in Ultimate mode (or couldn't confirm it): blocked on AC and battery." -ForegroundColor Green
}
Write-Host "Re-checked at every logon. After switching GPU mode, sign out and back in."
