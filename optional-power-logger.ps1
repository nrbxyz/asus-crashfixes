# Power/battery telemetry logger for GA503RW crash investigation.
# Samples every second and flushes each line to disk, so an abrupt power loss
# still leaves the final moments on disk.
# Stop with: Get-Process pwsh,powershell | Where-Object { $_.CommandLine -like '*power-logger*' } | Stop-Process

$ErrorActionPreference = 'SilentlyContinue'
$out = Join-Path $PSScriptRoot 'power-telemetry.csv'

$header = 'time,ac_online,charging,discharging,pct,voltage_mV,discharge_mW,charge_mW,remaining_mWh,cpu_pct,uptime_s'

# This appends roughly 3-4 MB per day. Rotate past 50 MB so it can't grow forever.
if ((Test-Path $out) -and (Get-Item $out).Length -gt 50MB) {
    Move-Item $out ($out -replace '\.csv$', '.old.csv') -Force
}
if (-not (Test-Path $out)) { Set-Content -Path $out -Value $header }

$sw = New-Object System.IO.StreamWriter($out, $true)
$sw.AutoFlush = $true

# Marker so we can tell sessions apart and spot abrupt endings.
$sw.WriteLine("# SESSION START $(Get-Date -Format 'o')")

$lastCpu = 0
while ($true) {
    try {
        $bs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus | Select-Object -First 1
        $wb = Get-CimInstance Win32_Battery | Select-Object -First 1
        $os = Get-CimInstance Win32_OperatingSystem
        $up = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds

        $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor |
                Where-Object Name -eq '_Total').PercentProcessorTime
        if ($null -eq $cpu) { $cpu = $lastCpu } else { $lastCpu = $cpu }

        $line = '{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}' -f `
            (Get-Date -Format 'HH:mm:ss.fff'),
            $bs.PowerOnline, $bs.Charging, $bs.Discharging,
            $wb.EstimatedChargeRemaining,
            $bs.Voltage, $bs.DischargeRate, $bs.ChargeRate, $bs.RemainingCapacity,
            $cpu, $up

        $sw.WriteLine($line)
    } catch {
        $sw.WriteLine("# ERROR $(Get-Date -Format 'HH:mm:ss') $($_.Exception.Message)")
    }
    Start-Sleep -Seconds 1
}
