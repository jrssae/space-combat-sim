# Play-testing M1 (First Flight)

Everything an agent can check runs in CI. What's left needs a person: a Linux desktop with a Vulkan GPU, a
gamepad and a keyboard. This page covers setup, the controls, and the checklist that closes M1.

## Setup (once)

Requirements: Linux x86_64, a Vulkan GPU driver, `git`, `curl`, `unzip`, `python3` with `numpy` (and `pillow` for
the fallback panorama sky).

```
git clone https://github.com/jrssae/space-combat-sim.git
cd space-combat-sim
git checkout m1-first-flight            # until it is merged into main
scripts/setup_godot.sh                  # Godot 4.7.2 into .tools/godot/ (SHA-256 checked)
scripts/gen_assets.sh                   # generates the Starfury, nav buoys and sky (a few seconds)
.tools/godot/godot --path . --import    # first import of the generated assets (~10 s)
```

Re-run `scripts/gen_assets.sh` after pulling changes to `tools/procgen`.

## Run

```
.tools/godot/godot --path .             # play
.tools/godot/godot --path . -e          # open the editor instead
```

Plug the pad in before launching if you can. Hot-plug also works; trigger calibration then takes about half a
second.

## Controls

```
RT / LT       right / left main pods (analog)        RB / LB     right / left retros
Right stick   pitch / roll (stick back = nose up,    Left stick  strafe left/right, up/down
              stick right = roll right)
D-pad L/R     yaw (tap for fine corrections)         D-pad Down  fire mode
D-pad Up      tap: next target                       hold (about 0.35 s): target nearest the nose
X             brake (hold): all stop; with a target selected the nose also swings onto it
A             fire                                   B  flight assist on/off      Y  cockpit / chase camera
Back          respawn                                Start  pause
R3            target nearest the nose (if the pad has stick clicks)    L3  debug overlay (if the pad has it)
```

Changed after the first play test: yaw and roll swapped (the right stick used to yaw and the D-pad to roll), and
target-ahead moved to a D-pad Up hold because the pad had no stick clicks. R3 and L3 still work on pads that have
them; F3 toggles the overlay from the keyboard. Tune the hold with `set settings.target_hold_s 0.5` and the D-pad
yaw ramp with `set settings.yaw_ramp_s 0.4` (then `save` to keep them).

Keyboard fallback: W both mains, E/Q right/left main, S both retros, D/A right/left retro, I/K pitch, J/L yaw
(ramped like the D-pad), arrows strafe, U/O roll, Space fire, X brake, Z assist, V camera, T target (tap next, hold
ahead), F fire mode, G target ahead, Backspace respawn, Esc pause, F3 overlay, F4 fallback meshes. The ` key opens
the debug console.

Flight notes:
- Newtonian: letting go of the triggers does not slow you down. Use the retros or hold X to brake.
- X is an all stop in both assist modes: it kills drift and any spin, and ignores the sticks, D-pad and triggers
  while held. With a target selected it also turns the nose onto the target (about 2.6 s from 90° off) and holds it
  there; release X to fly again.
- Assist on (default): uneven triggers turn the ship smoothly (overlay `POD YAW`). Assist off: raw physics,
  so uneven pods tank-steer and spins persist (until you hold X).

## Debug console cheat sheet

```
help                       all commands          state                 all providers
state ship                 every ship value      watch ship.speed      live value under the FPS counter
fps                        FPS counter           god                   no damage (M2+), session only
set settings.invert_y on   change a setting      save                  persist settings to disk
timescale 0.25             slow motion           respawn / pause       same as Back / Start
camera cockpit             set camera            set weapons.mode linked
fallback on                force mesh fallback   set targeting.selected "NAV BRAVO"
```

### Control profiles

Alternate layouts live in saved profiles you switch from the console (a controls menu comes with M4). Two are
built in and read-only: `default` (the layout above) and `m1_classic` (the original M1 pad layout: right stick X
yaws, D-pad Left/Right rolls; everything else is as in `default`).

```
controls list                 the profiles; * marks the one in use
controls use m1_classic       switch now (session only); `save` then keeps the choice for the next start
bind fire pad:button:7        add a binding to an action (L3 fires); unbind fire pad:button:0 removes one
controls show fire            the action's bindings; `controls show` lists every action
controls save mine            write your current bindings to user://controls/mine.cfg and select it
controls use default          back to the default layout (drops unsaved bind/unbind changes)
controls delete mine          remove a saved profile (not the one in use)
```

Bindings are `pad:button:<0-14>`, `pad:axis:<0-5>+` or `-` (`pad:axis:2+` is right stick X to the right; the
triggers only have `+`), `key:<name>` (`key:K`, `key:Space`, `key:F3`: a physical key, no modifiers) or
`mouse:<1|2|3>`. `bind` adds a binding. To move a pad button, bind the new one first and then `unbind` the old one,
because every action keeps at least one pad binding. Anything that breaks the rules (a missing action, a pad
button above 14 or the Guide button, the ` console key) is refused with the reason and changes nothing. `bind` and
`unbind` last until you quit unless you `controls save <name>`. Profiles are plain text (one list of bindings per
action), so `user://controls/<name>.cfg` can also be edited by hand; a broken file is reported by `controls use`,
and a start-up with a broken or missing selected profile falls back to `default` with a warning.

To keep a custom layout across restarts: `controls save mine`, then `save` (the console's, which persists
`settings.control_profile`). `m1_classic` changes only the bindings: the stick yaws through the same ramp as the
D-pad (full rate once past the deadzone) and the D-pad rolls at full rate, not proportionally as in the very first
M1 build.

## Acceptance checklist (the (H) criteria)

The full wording is in `docs/milestones/m1-first-flight.md`. Tick each one, or note what you saw.

- [ ] **AC12 Ship splats.** The Starfury renders as splats in both cameras. F4 swaps to the mesh fallback, and
      the mesh sits exactly where the splats were.
- [ ] **AC13 Sky.** Stars and nebula visible; no parallax while flying; no popping between the sky and the hull;
      in the cockpit the frame hides the hull behind it.
- [ ] **AC14 Controls.** Equal triggers fly straight. With assist off, RT alone yaws left and LT alone yaws right.
      Bumpers retro per side. With assist on, one trigger turns at about 30 °/s and stops on release. Right stick
      pitches and rolls; D-pad left/right yaws (taps give fine yaw). Triggers reach full and rest at zero (overlay
      `PAD … axes`). No stick drift. Holding X brings you to an all stop (drift and spin) in both modes, and with a
      target selected swings the nose onto it. B and Y work.
- [ ] **AC15 Performance.** 60 fps at 1080p (overlay FPS), no hitch when firing.
- [ ] **AC16 Glow and guns.** Pod plumes come out of the nozzles along their axes and follow each side's thrust,
      retros and trim; RCS plumes respond to strafe and rotation; bolts and muzzle flash visible from both cameras;
      the two fire modes look different.
- [ ] **AC16b Chase camera and hull occlusion.** The chase camera stays a fixed distance behind the ship while you
      yaw, roll and hold both bumpers (the ship never moves in frame, the stars do); `set settings.camera_chase_smoothing_s 0.2`
      lets the view swing softly, `0` is rigid again. In chase view the muzzle flash, bolts leaving the guns and the
      plumes behind the hull are hidden by the hull, not drawn through it; the hull has no black patches or dark
      outline (that would mean the depth proxy sticks out: `HullDepthProxy.inset_m`, default 0.04 m). The hull does
      not judder against the plumes at speed.
- [ ] **AC17 Targeting.** Tapping D-pad Up cycles buoys; holding it picks the one nearest the nose without also
      cycling (so does R3, if your pad has it); bracket and readout look right; buoys are splats and spin; NAV DELTA
      (drifting) shows a non-zero closing speed.
- [ ] **AC18 Backend.** Overlay shows `SPLATS COMPUTE`. If it says `RASTER` or `NONE`, note your GPU and driver.
- [ ] **AC22 Console.** ` opens and closes it without typing a character. Typing never moves the ship, and the pad
      still flies while it's open. Esc closes it. History and Tab work. `fps` and `watch ship.speed` work.
      `set` + `save` survives a restart; `set` alone does not.

Record your GPU, driver and FPS in the acceptance record at the end of the milestone doc. If a splat check
(AC12/AC13) fails, that triggers M1-T16 (fallback triage) before anything else. A screenshot plus the overlay text
is the most useful bug report.
