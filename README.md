# ASUS Zephyrus G15 (GA503) — random BSODs, freezes and hangs on battery

**The board can no longer safely enter deep CPU idle states (C-states). Blocking deep idle in Windows stops the crashes.**

```powershell
# Right-click PowerShell -> Run as administrator
.\1-FIX.ps1              # fixes it now
.\2-MAKE-PERMANENT.ps1   # stops Windows undoing it later
```

It costs battery life and fan noise. It is containment, not a repair.

---

## Does this apply to me?

If you get **any** of these on an ASUS AMD laptop, especially on battery:

- BSODs with random stop codes blaming random processes — `IRQL_NOT_LESS_OR_EQUAL`, `PAGE_FAULT_IN_NONPAGED_AREA`, `UNEXPECTED_KERNEL_MODE_TRAP`, `KMODE_EXCEPTION_NOT_HANDLED`, `SYSTEM_SERVICE_EXCEPTION`, `DRIVER_POWER_STATE_FAILURE`
- Slow-motion freezes: cursor lags, apps die one by one, explorer dies, Ctrl+Alt+Del does nothing, but music already playing keeps going
- Instant power-off with no blue screen
- Empty `C:\Windows\Minidump` even though dumps are enabled
- Pixel corruption on screen that a reboot fixes
- Terrible idle battery drain (~20 W when it should be 7–12 W)

...and it's **worse when idle, better under load, much worse on battery, much worse in iGPU/Eco mode** — this is very likely the same fault.

They are not separate problems. They're one fault with many faces. See [SYMPTOMS.md](SYMPTOMS.md).

## Files

| File | What it does |
|---|---|
| **`1-FIX.ps1`** | The fix. Blocks deep C-states on AC and battery, across every power plan, then verifies it worked. Undo: `.\1-FIX.ps1 -Revert` |
| **`2-MAKE-PERMANENT.ps1`** | Makes it survive Windows updates and power-plan switches. Self-contained. Undo: `.\2-MAKE-PERMANENT.ps1 -Remove` |
| `optional-crash-evidence.ps1` | Only if you want to confirm the diagnosis yourself. Preserves crash evidence that otherwise deletes itself. |
| `optional-power-logger.ps1` | Deep debugging. Per-second power telemetry, flushed to disk so it survives an instant power-off. |
| [SYMPTOMS.md](SYMPTOMS.md) | Every symptom explained, and everything that does **not** fix it. |

## How to test it

After running `1-FIX.ps1`:

1. Unplug the charger
2. Switch to Eco / iGPU mode
3. Leave it completely idle for an hour

That combination kills affected machines fastest — usually within minutes. Survive an hour and you have your answer.

## Just the commands

```powershell
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 5d76a2ca-e8c0-402f-a133-2158492d58ad 1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 5d76a2ca-e8c0-402f-a133-2158492d58ad 1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 893dee8e-2bef-41e0-89c6-b55d0929964c 100
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 893dee8e-2bef-41e0-89c6-b55d0929964c 100
powercfg /setactive SCHEME_CURRENT
```

Undo: same lines with `0` instead of `1`, and `5` instead of `100`.

> **This only writes the *active* power plan.** Switch plans later (ASUS Recommended, a G-Helper plan, High Performance) and the crashes come back with no warning. `1-FIX.ps1` covers every plan — that's why it exists.

Verify — `% C2 Time` and `% C3 Time` should read `0.0`:

```powershell
Get-Counter '\Processor Information(_Total)\% C1 Time','\Processor Information(_Total)\% C2 Time','\Processor Information(_Total)\% C3 Time' -SampleInterval 2 -MaxSamples 1
```

## Two things that waste everyone's time

**A clean MemTest86 does not exonerate your machine.** MemTest hammers RAM continuously, so the CPU never idles, so the failure condition is never reached. It *cannot* catch this.

**"Minimum processor state 100%" is a different setting.** That controls P-states (clock speed/voltage), not C-states. Idle cores still enter deep sleep — they just wake at a higher clock. That's exactly why people report "it helped a bit but I still crashed." You need the hidden *Processor idle disable* setting.

## Trade-offs — read before running

- Runs hotter, fans run more. Cores never rest. Thermal throttling still protects the chip, but clean your fans first if they're clogged.
- Idle draw ~30 W instead of ~20 W. Battery runtime gets noticeably worse.
- `optional-crash-evidence.ps1` keeps crash dumps — `MEMORY.DMP` can be 2–4 GB.

Nothing here touches your files, security settings, or how Windows boots. No network access, no telemetry. All plain readable text — inspect it before running.

## Scope

Confirmed on one **GA503RW** (Ryzen 9 6900HS / RTX 3070 Ti), on **BIOS 311 and 318**, Windows 11 build 26100. Based on 7 crash dumps and continuous power telemetry, all reproduced in a single day.

The fix avoids the broken hardware states rather than repairing them. The suspected real cause is **aged power delivery (VRM)**, which would need board-level repair.

**If you try this, please open an issue saying whether it worked.** It matters whether this is one aging board or something broader.

## License

[MIT](LICENSE) — do whatever you want with it.
