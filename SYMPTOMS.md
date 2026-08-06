===============================================================================
EVERY SYMPTOM THIS CAUSES, AND WHY THEY ARE ALL ONE FAULT
===============================================================================


HOW IT WORKS (plain english)
-------------------------------------------------------------------------------
Modern laptops save power by putting things to sleep thousands of times a
second. Not "sleep mode" - micro-naps. While you read a page and nothing is
happening, CPU cores physically power down between keystrokes, the memory
controller idles, devices drop to low power, and the fabric connecting it all
winds down. This is called deep idle (C-states).

Entering and leaving these states is delicate. Voltage drops and comes back.
Caches are flushed and restored. Clocks stop and restart. The embedded
controller and firmware coordinate the handshakes.

On an affected board, this sometimes comes back WRONG. State that should have
been preserved comes back corrupted, or a device never finishes its transition.

What happens next is luck:

  corruption lands on unused memory   ->  nothing, you never know
  corruption lands on something live  ->  BSOD blaming a random process
  a device hangs mid-transition       ->  system slowly jams solid
  corruption lands on video memory    ->  pixel garbage on screen
  the transition silently fails       ->  power wasted, battery drains fast

That is why it looks like a dozen unrelated problems.
It is one fault with many faces.


THE SYMPTOMS
-------------------------------------------------------------------------------

1. BSODs with random stop codes and random blamed processes

   IRQL_NOT_LESS_OR_EQUAL, PAGE_FAULT_IN_NONPAGED_AREA,
   UNEXPECTED_KERNEL_MODE_TRAP, KMODE_EXCEPTION_NOT_HANDLED,
   SYSTEM_SERVICE_EXCEPTION, DRIVER_POWER_STATE_FAILURE.

   The blamed process is meaningless - browser, Discord, PowerToys, an ASUS
   service, whatever touched the damaged memory first. In testing, three
   different stop codes all hit the SAME corrupted kernel structure. The stop
   code only describes how the kernel noticed, not what broke.


2. Slow-motion death with no BSOD (the worst one)

   Cursor gets laggy -> clock stutters -> apps stop responding one by one ->
   explorer.exe dies -> Ctrl+Alt+Del does nothing -> Ctrl+Shift+Esc opens
   nothing -> but music already playing keeps playing and alt-tab still works
   for a while. Ends with holding the power button.

   Why: a device hung its power transition. Everything needing that subsystem
   queues behind it forever. Music already streaming needs nothing new, so it
   continues. Launching Task Manager needs the jammed machinery, so nothing
   opens. No BSOD because nothing technically crashed - it is all just waiting.


3. Instant power-off, no blue screen

   Same fault, harder landing. Nothing survives long enough to write a dump.


4. Empty minidump folder even though dumps are enabled

   Not a misconfiguration. These failures often kill execution before Windows
   can finish writing. If CrashDumpEnabled=7 and AlwaysKeepMemoryDump=1 and the
   folder is still empty, that is itself a diagnostic clue.


5. Event Viewer has no history

   If you also have an NVMe drive throwing PCIe corrected errors, WHEA logs them
   by the thousand. One machine logged 10,453 events in 13 minutes and about
   72,000 in a day. The System log is 20 MB circular by default, so the storm
   rolls the whole log and erases every crash before it.

   This is why years of "just check event viewer" produces nothing.
   Fix it first:   wevtutil sl System /ms:268435456


6. Screen pixel corruption in waves

   Rare, fixed by reboot, shows up for weeks then vanishes for a year. Same
   corruption landing on display memory instead of kernel memory.


7. Terrible idle battery drain (20W when it should be 7-12W)

   The other side of the same coin. When the platform FAILS to reach deep idle
   states, it silently burns power. Broken deep idle costs you both stability
   and battery life.


8. Possibly degraded Wi-Fi throughput

   Unconfirmed. Wireless throughput depends on low interrupt latency, and deep
   idle adds wake-up latency to every interrupt. One machine went from needing
   an absurd workaround ritual to full speed after blocking deep idle. Needs
   more data from other people.


WHY IT FEELS RANDOM - THE TRIGGER CONDITIONS
-------------------------------------------------------------------------------

  On battery          much worse   DC power policy idles far more aggressively
  Idle / light use    much worse   deep idle only happens when nothing happens
  Under load          protected    busy cores never enter deep C-states
  iGPU / Eco mode     much worse   an active dGPU keeps the fabric awake
  dGPU / Ultimate     safer        same reason - but not immune
  Plugged in          rare         AC still idles, just less often and less deep
  Just after reboot   fine briefly clean state until the next bad transition

Every idle moment is a dice roll. These conditions change the odds, not the
outcome. That is the whole reason this is so maddening to pin down.


WHAT DOES NOT FIX IT - ALL VERIFIED
-------------------------------------------------------------------------------

RAM replacement or removal
   Crashes predated the RAM upgrade by a year. Another owner removed their RAM
   upgrade and still crashed.

MemTest86
   Passes clean and CANNOT catch this. MemTest hammers RAM continuously, so the
   CPU never idles, so the failure condition is never reached.
   A CLEAN MEMTEST DOES NOT EXONERATE YOUR MACHINE. This is why everyone gets
   sent down the wrong path.

Replacing the battery
   Pack voltage was logged every second. Rock steady at 14.1V under 45W load at
   the exact instant of death, and sustained 68W for 22 minutes with no sag.
   Do not buy a battery for this.

BIOS updates
   Crossed 313 -> 316 -> 317 -> 318. No help.

BIOS downgrade to 311
   Actually flashed it. Crashed within seconds of unplugging, identical
   behaviour. FIRMWARE VERSION IS NOT THE VARIABLE. Do not bother flashing.

Fresh Windows install          no help (multiple owners)
DDU + driver reinstalls        no help
Chipset driver updates         no help
CMOS clear                     no help
EC hard reset (40s power btn)  no help
Removing the secondary SSD     disabled it entirely at PCIe level, crashed anyway
Uninstalling VPN/filter drivers, and running Driver Verifier on all of them
                               zero trips, crashed with them all verified

Minimum processor state 95% or 100% ON ITS OWN
   This is the big one people try. It controls P-states (clock speed and
   voltage), NOT C-states. Idle cores still enter deep sleep, they just wake up
   at a higher clock. That is exactly why people report "it helped a bit but I
   still crashed". You need the hidden Processor Idle Disable setting.

Processor idle state maximum = 1 (allow shallow C1 only)
   Tested. Did NOT work - the slow-motion hang came straight back.
   Skip the middle ground, go to the full block.


HOW TO CONFIRM YOU HAVE THIS
-------------------------------------------------------------------------------

1. Run enable-crash-evidence.ps1 as admin (preserves evidence that otherwise
   destroys itself)

2. Crash it deliberately: unplug, Eco/iGPU mode, leave it idle

3. Open the dump from C:\Windows\Minidump in WinDbg and run:  !analyze -v

   Look for any of these:
     PpmIdleExecuteTransition        <- the CPU idle transition engine.
                                        If this is in the stack, that is
                                        definitive - it crashed in the literal
                                        act of putting a core to sleep.
     ExpInterlockedPopEntrySListFault / CmpCallCallBacksEx
                                     <- the memory corruption signature
     0x9F with IMAGE_ACPI.sys        <- a device hung inside a firmware power
                                        method

4. Run apply-fix.ps1 and repeat step 2. If it survives an hour where it used to
   die in minutes, you are done.


THE REAL CURE (hardware)
-------------------------------------------------------------------------------
The fix avoids the broken states. It does not repair them.

If your machine was healthy for its first year and got sick later, the likely
cause is aged or marginal power delivery (VRM components). A board-level repair
shop can scope the rails and replace them - far cheaper than a motherboard, and
it is the only path that makes deep idle SAFE again rather than avoided.

Untested option: AMD's hidden "Global C-State Control" lives in the AMD CBS menu
that ASUS ships but hides. It can be flipped with setup_var from a UEFI shell
WITHOUT modifying or reflashing the BIOS, which would disable deep C-states at
firmware level instead of OS level. Risk: a wrong offset can soft-brick until a
CMOS clear. Not yet tested.
