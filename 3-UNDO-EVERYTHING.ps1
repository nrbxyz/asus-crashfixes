# ============================================================================
#  3-UNDO-EVERYTHING.ps1   -   Puts your machine back exactly how it was.
#                              Run as Administrator.
# ============================================================================
#
#  Reverses everything the other scripts in this repo do:
#    * restores Windows' default CPU idle behaviour on every power plan
#    * removes the logon guard task and its script
#    * optionally restores the default event log size and crash dump settings
#
#  Nothing in this repo touches your files, your security settings, or how
#  Windows boots - so this really is the complete undo. After running it, the
#  only trace left is any crash dumps that were written, and you can delete
#  those yourself from C:\Windows\Minidump and C:\Windows\MEMORY.DMP.
#
#  Use  -All  to also revert the logging/dump changes made by
#  optional-crash-evidence.ps1 (otherwise those are left alone, since bigger
#  logs and working crash dumps are useful regardless).
# ============================================================================

param([switch]$All)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Must run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as administrator, then run this again."
    exit 1
}

$SUB  = '54533251-82be-4824-96c1-47b60b740d00'
$IDLE = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
$MIN  = '893dee8e-2bef-41e0-89c6-b55d0929964c'
$MAX  = '9943e905-9a30-4ec1-9b99-44dd3b76f7a2'

Write-Host "1) Removing the logon guard (if installed)..." -ForegroundColor Cyan
$hadTask = (Get-ScheduledTask -TaskName 'IdleGuard' -ErrorAction SilentlyContinue) -ne $null
Unregister-ScheduledTask -TaskName 'IdleGuard' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item 'C:\ProgramData\idle-guard.ps1' -Force -ErrorAction SilentlyContinue
Write-Host $(if ($hadTask) { "   guard removed" } else { "   no guard was installed" })

Write-Host "`n2) Restoring default CPU idle behaviour on every power plan..." -ForegroundColor Cyan
$schemes = [regex]::Matches((powercfg /list | Out-String), 'GUID:\s*([0-9a-fA-F\-]{36})\s*\(([^)]*)\)')
foreach ($m in $schemes) {
    $g = $m.Groups[1].Value
    powercfg /setacvalueindex $g $SUB $IDLE 0 2>$null   # idle states allowed again
    powercfg /setdcvalueindex $g $SUB $IDLE 0 2>$null
    powercfg /setacvalueindex $g $SUB $MIN  5 2>$null   # Windows default
    powercfg /setdcvalueindex $g $SUB $MIN  5 2>$null
    powercfg /setacvalueindex $g $SUB $MAX  0 2>$null   # no idle-depth cap
    powercfg /setdcvalueindex $g $SUB $MAX  0 2>$null
    "   {0}" -f $m.Groups[2].Value
}
powercfg /setactive SCHEME_CURRENT

# re-hide the settings we unhid, so Power Options looks stock again
powercfg -attributes $SUB $IDLE +ATTRIB_HIDE 2>$null
powercfg -attributes $SUB $MAX  +ATTRIB_HIDE 2>$null

if ($All) {
    Write-Host "`n3) Restoring default event log size and crash dump settings..." -ForegroundColor Cyan
    wevtutil sl System /ms:20971520
    wevtutil sl Application /ms:20971520
    $cc = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    Set-ItemProperty $cc -Name CrashDumpEnabled     -Value 7 -ErrorAction SilentlyContinue
    Set-ItemProperty $cc -Name AlwaysKeepMemoryDump -Value 0 -ErrorAction SilentlyContinue
    Write-Host "   done (log sizes back to 20 MB, dumps no longer force-kept)"
} else {
    Write-Host "`n3) Leaving event log size and crash dump settings alone." -ForegroundColor DarkGray
    Write-Host "   (they're harmless and useful. Use -All if you want those reverted too)" -ForegroundColor DarkGray
}

Write-Host "`nVerifying - every plan should now read AC=0 DC=0:" -ForegroundColor Cyan
$bad = 0
foreach ($m in $schemes) {
    $q = powercfg /query $m.Groups[1].Value $SUB $IDLE 2>$null | Out-String
    $ac = ([regex]::Match($q,'Current AC Power Setting Index:\s*(\S+)')).Groups[1].Value
    $dc = ([regex]::Match($q,'Current DC Power Setting Index:\s*(\S+)')).Groups[1].Value
    if ($ac -ne '0x00000000' -or $dc -ne '0x00000000') { $bad++ }
    "  {0,-30} AC={1} DC={2}" -f $m.Groups[2].Value, $ac, $dc
}

Write-Host "`nC-state usage (C2/C3 should be non-zero again within a few seconds of idle):" -ForegroundColor Cyan
$c = Get-Counter '\Processor Information(_Total)\% C1 Time','\Processor Information(_Total)\% C2 Time','\Processor Information(_Total)\% C3 Time' -SampleInterval 2 -MaxSamples 1 -ErrorAction SilentlyContinue
$c.CounterSamples | ForEach-Object { "  {0,-10} {1,5:N1}%" -f ($_.Path -replace '.*\\'), $_.CookedValue }

if ($bad -eq 0) {
    Write-Host "`nDone. Your machine is back to stock power behaviour." -ForegroundColor Green
    Write-Host "The crashes will come back too, if you had them - that's expected."
} else {
    Write-Host "`n$bad plan(s) didn't revert. Try running this again as Administrator." -ForegroundColor Yellow
}
