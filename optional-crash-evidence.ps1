# enable-crash-evidence.ps1 - run this FIRST, as Administrator, before debugging anything.
#
# On affected machines the crash evidence destroys itself:
#  - a WHEA error storm from a failing PCIe device can log 10,000+ events in minutes,
#    rolling the 20MB circular System log and erasing all crash history
#  - crash dumps often never get written
# This script preserves everything so your NEXT crash is actually diagnosable.
# It changes no performance or power behaviour.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Must run as Administrator." -ForegroundColor Red; exit 1
}

$out = Join-Path $PSScriptRoot 'logsnapshot'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "1) Snapshotting current logs before anything overwrites them..." -ForegroundColor Cyan
foreach ($l in 'System','Application','Microsoft-Windows-Kernel-WHEA/Errors','Microsoft-Windows-Kernel-WHEA/Operational') {
    $safe = ($l -replace '[/\\]','_')
    wevtutil epl "$l" "$out\$safe.evtx" /ow:true 2>$null
    if (Test-Path "$out\$safe.evtx") { Write-Host "   saved $safe.evtx" }
}

Write-Host "`n2) Enlarging event logs (System 20MB -> 256MB)..." -ForegroundColor Cyan
wevtutil sl System /ms:268435456
wevtutil sl Application /ms:134217728
wevtutil gl System | Select-String 'maxSize'

Write-Host "`n3) Forcing crash dumps to be written and kept..." -ForegroundColor Cyan
$cc = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
Set-ItemProperty $cc -Name CrashDumpEnabled     -Value 7    # automatic (MEMORY.DMP + minidump)
Set-ItemProperty $cc -Name AlwaysKeepMemoryDump -Value 1    # never auto-delete
Set-ItemProperty $cc -Name MinidumpsCount       -Value 100
Set-ItemProperty $cc -Name LogEvent             -Value 1
New-Item -ItemType Directory -Force -Path 'C:\Windows\Minidump' | Out-Null
Get-ItemProperty $cc | Select-Object CrashDumpEnabled,AlwaysKeepMemoryDump,MinidumpsCount,AutoReboot | Format-List

Write-Host "4) Checking whether anything is deleting your dumps..." -ForegroundColor Cyan
$ss = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
if (Test-Path $ss) { Write-Host "   Storage Sense IS configured - check it isn't set to remove dump files" }
else { Write-Host "   Storage Sense not configured (good)" }

Write-Host "`n5) Are you getting a WHEA storm? (PCIe corrected errors, last 24h)" -ForegroundColor Cyan
$w = (Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue).Count
Write-Host "   WHEA events in last 24h: $w"
if ($w -gt 1000) { Write-Host "   ^ That's a storm. A PCIe device (often a secondary NVMe) has a failing link." -ForegroundColor Yellow }

Write-Host "`nDONE. Now reproduce the crash, then analyze C:\Windows\Minidump\*.dmp in WinDbg with !analyze -v" -ForegroundColor Green
