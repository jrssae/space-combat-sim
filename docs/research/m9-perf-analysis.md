# M9 performance analysis: free flight with the wings launched (RTX 3060 PC)

Analysis only, 2026-11-27, on `m9` at `957e49f5`. No code was changed. Machine: Windows 11, NVIDIA RTX 3060 12 GB
(driver dated July 2026), Ryzen 9 5900X (12C/24T), 32 GB RAM, power plan Balanced, Defender real-time on.

## Symptom

The maintainer saw 8 to 15 fps in free flight after ordering Babylon 5 to launch fighters; the Linux RX 6950 XT
machine does not show it.

## Repro

`play free_flight; wait 300; wait 900; stationcmd launch all; wait 1500`, windowed (1920x1080 and 960x540). Control
answers "ALPHA, BETA, DELTA, ZETA WINGS: CLEARED TO LAUNCH" and 48 ships are in play. A per-second probe logged fps,
frame and GPU time, physics ticks per frame and the `PerfProbe` stage averages; a PowerShell sampler logged system CPU
and the top processes beside it.

## Finding: an outside CPU load, not the game

BOINC (Einstein@Home: `einstein_O4MD_2.01_windows_x86_64`, `hsgamma_FGRP5`, one CUDA task) runs on this PC and takes
16 to 21 of the 24 logical cores in bursts of about 10 s on, 15 to 20 s off. Every slow period lined up with a burst.

| 1080p, Vulkan | Before launch (1 ship) | After launch (48 ships) |
|---|---|---|
| BOINC idle | 57-60 fps, tick 1.3-2.0 ms, GPU 3.5-5 ms | 58-60 fps (vsync cap), tick 2.7-3.7 ms, GPU 3.5-5 ms |
| BOINC running | 32-39 fps, tick 6.4-6.9 ms | 13-16 fps, tick about 15 ms, 3 ticks per frame |

- Total CPU 91 to 100 % during bursts while the game used 1.2 to 1.5 cores; every tick stage slowed about 5x at once,
  GDScript included (flight 0.55 ms to 3-5 ms with one ship). High process priority did not help (15.2 fps): the
  contention is for shared cores, cache and memory bandwidth, not scheduling.
- Ruled out: resolution (960x540 the same), the driver (`--rendering-driver d3d12` the same), GPU and VRAM (198-256 draw
  calls, 0.28-0.38 M triangles, 0.97 GB of 12 GB), the thread count (1 and 24 the same; no parallel pass ran at 48
  ships).
- The exported release's ticks are about 25 % cheaper than the editor binary run from source, with the same collapse
  under load.

## Slowdowns, ranked

1. **The BOINC load** (above).
2. **The catch-up cap amplifies it:** `physics_max_steps_per_frame` = 3 (`src/autoload/settings_schema.gd:236`). Once a
   tick passes about 5 ms, every frame runs 3 ticks, frames reach 50-75 ms and the sim slows to 36-54 ticks a second.
3. **The launch hitch, on every machine:** one tick of 0.46-1.87 s when the wings launch. `main.ensure_free`
   (`src/mission/launch_director.gd:312`) builds about 47 ally ships at that moment, because only station scenarios
   reserve them at load (the code's own comment says a launch elsewhere "may hitch").
4. GPU and VRAM: not a factor. `vram_used_gb` reads -1 on Windows (it reads Linux sysfs only), as planned.

## Speed-up opportunities, ranked

| # | Change | Gain | Effort | Scope |
|---|---|---|---|---|
| 1 | The game's exes in BOINC's exclusive applications, or BOINC snoozed while playing | steady 60 fps | S, no code | this PC |
| 2 | Reserve the ally ships at load in free flight, or spread `ensure_free` over several ticks | removes the 0.5-1.9 s hitch | S-M | all |
| 3 | Degrade more gracefully under slow ticks: a cap of 2, or an adaptive cap | holds up better on loaded machines; the sim runs slower when it engages | M, changes feel | all |
| 4 | Move the remaining per-tick GDScript work native (`late` 0.8 ms, `other` 0.9-1.3 ms at 48 ships) | headroom; script code suffered most under contention | M-L | all |
| 5 | Physical-core count on Windows in `performance_cores()` (`native/src/threads.rs:352` falls back to 24 logical cores) | none measured at 48 ships; untested in big battles | S | Windows |

## Why the Linux machine is fine

Between bursts this PC runs the scene well inside budget (3 ms ticks, 4 ms GPU at 48 ships). Most likely BOINC does not
run on the Linux machine (not checked). To confirm here: snooze BOINC and fly the same scene; it should hold 60 fps.

## Not isolated

Shader-compile stutter at first launch (load hitches of 2.7-12 s looked alike across runs); the Windows timer, Defender
and the power plan.
