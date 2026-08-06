# [SOLVED after 2 years] GA503RW random BSODs/freezes on battery + iGPU: it's deep CPU idle states (C-states), not your RAM, SSD, or battery

I posted here ~2 years ago about my Zephyrus G15 2022 (GA503RW, 6900HS, 3070Ti) bluescreening on battery in iGPU mode. Today I spent a full day doing this properly with dumps and instrumentation and actually found it. Posting everything because there are a *lot* of threads about this and the usual advice (RAM, MemTest, reinstall Windows, replace battery, update BIOS) is all wrong.

## TL;DR

**The board can no longer safely enter deep CPU idle states (C-states). Blocking deep idle in Windows stops the crashes completely.**

One command, run as admin:

```
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 5d76a2ca-e8c0-402f-a133-2158492d58ad 1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 5d76a2ca-e8c0-402f-a133-2158492d58ad 1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 893dee8e-2bef-41e0-89c6-b55d0929964c 100
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 893dee8e-2bef-41e0-89c6-b55d0929964c 100
powercfg /setactive SCHEME_CURRENT
```

That's "Processor idle disable" (a hidden power setting) + min processor state 100%. Costs battery life and fan noise. It is containment, not a cure. Revert by setting those to `0` and `5`.

## Symptoms this explains

- BSODs on battery, especially in Eco/iGPU mode
- **Idle makes it worse, load protects you** (this is the key clue)
- Random stop codes with random blamed processes: IRQL_NOT_LESS_OR_EQUAL, PAGE_FAULT_IN_NONPAGED_AREA, UNEXPECTED_KERNEL_MODE_TRAP, KMODE_EXCEPTION, DRIVER_POWER_STATE_FAILURE
- Slow-motion "disintegration" hangs: cursor stutters, clock jumps, apps die one by one, explorer dies, Ctrl+Alt+Del does nothing, music keeps playing, no BSOD — force power off
- Occasional freezes even while plugged in
- Fine after a reboot, then it comes back
- MemTest86 passes clean, fresh Windows doesn't help, DDU doesn't help

## Why nobody can debug this (important)

Two reasons your logs are empty:

1. **Your minidump folder is probably empty even though dumps are enabled.** These failures often don't survive long enough to write one.
2. **If you have a second NVMe throwing PCIe corrected errors, WHEA floods your System event log.** Mine logged 10,453 events in 13 minutes and 72,000 in one day. The System log is 20 MB circular by default — the storm rolls the entire log and destroys all crash history. That's why 2 years of "check event viewer" got me nothing.

Fix both before debugging anything:
```
wevtutil sl System /ms:268435456
```
and check `HKLM\SYSTEM\CurrentControlSet\Control\CrashControl` has `CrashDumpEnabled=7`, `AlwaysKeepMemoryDump=1`.

## The actual evidence

7 crashes reproduced on demand in one day, all dumped and analyzed in WinDbg:

| Bugcheck | Stack |
|---|---|
| 0x9F (3) | amdi2c stuck in a power IRP, `FAILURE_BUCKET_ID: 0x9F_3_amdi2c_IMAGE_ACPI.sys` |
| 0x1E | `ExpInterlockedPopEntrySListFault` → `CmpCallCallBacksEx` → `NtOpenKeyEx` |
| 0x3B | `ExpInterlockedPopEntrySListFault` → `CmpCallCallBacksEx` → `NtQueryValueKey` |
| **0xA** | **`PpmIdleExecuteTransition` → memset → page fault** |
| 0x7F | double fault, `KiLeaveCriticalRegionUnsafe` |

Three different stop codes hit the **exact same corrupted kernel structure** (the registry-callback SList), with a different innocent victim process each time. That's targeted corruption, not bad RAM.

And the smoking gun: **0xA crashed inside `PpmIdleExecuteTransition`** — that's the Windows kernel function that executes CPU idle state transitions. It crashed in the literal act of putting a core to sleep.

There's also always a leading indicator: **battery WMI queries (ACPI/EC calls) freeze minutes before any visible symptom**, sometimes while still on AC. I had a 1-second telemetry logger running; before every incident it stopped dead well before anything looked wrong.

## What I ruled out, with evidence

- **RAM** — crashes predate my 32 GB upgrade by a year; another user in an old thread removed their RAM upgrade and still crashed. Also: **MemTest86 passing means nothing here**, because MemTest hammers RAM continuously and never lets the CPU idle — it literally cannot reach the failure condition.
- **The SSD** — disabled my secondary NVMe entirely (off the bus, no DMA), crashed anyway.
- **The battery** — logged pack voltage every second. Rock steady at 14.1 V under 45 W load at the exact moment of death. Also ran 22 min at 54–68 W in Ultimate mode with zero sag. Don't buy a battery for this.
- **Third-party drivers** — ran Driver Verifier on all my VPN/filter drivers (NordVPN, GlobalProtect, WireGuard, OpenVPN TAPs, etc). Zero trips. Crashed with them all loaded and verified.
- **BIOS version** — **I downgraded to 311 (the version people say is clean) and it crashed within seconds of unplugging, identical behavior.** Then it crashed again on 318. Firmware version is NOT the variable. Don't bother flashing for this.

## So what actually is it

The deep-idle subsystem on this board is broken. Every quiet moment, the platform tries to power-gate cores and the SoC, and sometimes comes back with corrupted state — which then kills whatever thread touches it next, hence the randomness. Battery makes it worse because DC power policy idles far more aggressively. iGPU/Eco makes it worse because an active dGPU keeps the fabric awake and blocks the deepest states. Load protects you for the same reason.

My honest guess at root cause: **aged/marginal power delivery (VRM)**. My laptop was fine for its first year and sick ever since, and it reproduces identically across two firmware versions. That would mean the real cure is board-level repair (scope the rails, replace aged components) — cheap-ish at a good repair shop, much cheaper than a motherboard. I haven't done this yet.

Possible next step I haven't tried: AMD's hidden **"Global C-State Control"** in the AMD CBS menu, flippable via `setup_var` from a UEFI shell without modifying/reflashing the BIOS. That would disable deep C-states at firmware level instead of OS level. Has soft-brick risk (CMOS-clear recoverable).

## How to check if you have this

Run this while idle and watch which C-states you're using:
```
Get-Counter '\Processor Information(_Total)\% C1 Time','\Processor Information(_Total)\% C2 Time','\Processor Information(_Total)\% C3 Time' -Continuous
```
If you're spending most of your idle time in C2/C3 and you get these crashes, apply the powercfg block above and see if they stop. That's the whole test.

## Things that did NOT work (so you can skip them)

Fresh Windows install, BIOS updates, BIOS downgrade to 311, CMOS clear, EC hard reset (40s power button), DDU + driver reinstalls, chipset driver updates, MemTest86, Windows Memory Diagnostic, removing RAM upgrade, removing SSD, disabling every third-party driver, Driver Verifier, min processor state 95/100% alone (that's P-states, not C-states — different thing, doesn't fix it).

## Notes for ASUS owners generally

I'd still buy ASUS again — the hardware is genuinely great. But their power-state/ACPI/EC firmware quality is rough, and this class of "freezes but not crashes, only on battery, only at idle" issue seems to be a recurring theme across their AMD laptops. Worth knowing what you're getting into.

Happy to answer questions. If you have this and try the fix, please report back whether it worked for you — I'd like to know if it's my specific board aging or something broader.
