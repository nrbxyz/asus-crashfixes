# ============================================================================
#  1-FIX.ps1   -   THE FIX. Run this as Administrator.
# ============================================================================
#
#  Blocks deep CPU idle states (C-states) on AC and battery, across every
#  power plan. On affected ASUS/AMD boards those idle transitions corrupt
#  system state and cause BSODs, freezes and hangs.
#
#  UNDO:   .\1-FIX.ps1 -Revert
#
#  COST:   laptop runs hotter, fans run more, idle power ~30W instead of ~20W,
#          worse battery runtime. This is containment, not a repair.
#
#  This lasts until Windows resets your power plans, or until you switch to a
#  plan that wasn't protected. Run 2-MAKE-PERMANENT.ps1 to stop that happening.
# ============================================================================

param([switch]$Revert)

$SUB  = '54533251-82be-4824-96c1-47b60b740d00'   # Processor power management
$IDLE = '5d76a2ca-e8c0-402f-a133-2158492d58ad'   # Processor idle disable (hidden)
$MIN  = '893dee8e-2bef-41e0-89c6-b55d0929964c'   # Minimum processor state
$MAX  = '9943e905-9a30-4ec1-9b99-44dd3b76f7a2'   # Processor idle state maximum

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Must run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as administrator, then run this again."
    exit 1
}

# make these visible in the GUI too (they're hidden by default)
powercfg -attributes $SUB $IDLE -ATTRIB_HIDE
powercfg -attributes $SUB $MAX  -ATTRIB_HIDE

$idleVal = if ($Revert) { 0 } else { 1 }
$minVal  = if ($Revert) { 5 } else { 100 }

# Every plan, not just the active one. If you only do the active plan, switching
# to another plan later silently removes your protection.
$schemes = [regex]::Matches((powercfg /list | Out-String), 'GUID:\s*([0-9a-fA-F\-]{36})\s*\(([^)]*)\)')
foreach ($m in $schemes) {
    $g = $m.Groups[1].Value
    powercfg /setacvalueindex $g $SUB $IDLE $idleVal 2>$null
    powercfg /setdcvalueindex $g $SUB $IDLE $idleVal 2>$null
    powercfg /setacvalueindex $g $SUB $MIN  $minVal  2>$null
    powercfg /setdcvalueindex $g $SUB $MIN  $minVal  2>$null
    powercfg /setacvalueindex $g $SUB $MAX  0 2>$null   # the "allow C1 only" cap
    powercfg /setdcvalueindex $g $SUB $MAX  0 2>$null   # was tested - didn't work
    "  {0,-30} {1}" -f $m.Groups[2].Value, $(if($Revert){'reverted to default'}else{'idle blocked'})
}
powercfg /setactive SCHEME_CURRENT

Write-Host "`nPer-plan check (want AC=1 DC=1 on all, if applying):" -ForegroundColor Cyan
foreach ($m in $schemes) {
    $q = powercfg /query $m.Groups[1].Value $SUB $IDLE 2>$null | Out-String
    "  {0,-30} AC={1} DC={2}" -f $m.Groups[2].Value,
        ([regex]::Match($q,'Current AC Power Setting Index:\s*(\S+)')).Groups[1].Value,
        ([regex]::Match($q,'Current DC Power Setting Index:\s*(\S+)')).Groups[1].Value
}

Write-Host "`nActual C-state usage right now (2 second sample):" -ForegroundColor Cyan
$c = Get-Counter '\Processor Information(_Total)\% C1 Time','\Processor Information(_Total)\% C2 Time','\Processor Information(_Total)\% C3 Time' -SampleInterval 2 -MaxSamples 1 -ErrorAction SilentlyContinue
$c.CounterSamples | ForEach-Object { "  {0,-10} {1,5:N1}%" -f ($_.Path -replace '.*\\'), $_.CookedValue }

if (-not $Revert) {
    Write-Host "`nC2 and C3 should read 0.0% above. That's the proof it's working." -ForegroundColor Green
    Write-Host "`nNOW TEST IT: unplug, switch to Eco/iGPU mode, leave it idle for an hour." -ForegroundColor Green
    Write-Host "If it survives where it used to die in minutes, that's your answer."
    Write-Host "`nThen run 2-MAKE-PERMANENT.ps1 so Windows can't undo this." -ForegroundColor Yellow
}
