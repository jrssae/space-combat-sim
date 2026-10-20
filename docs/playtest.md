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
RT / LT       right / left main pods (analog)        RB / LB   right / left retros
Right stick   pitch / yaw (stick back = nose up)     Left stick  strafe left/right, up/down
D-pad L/R     roll (tap for fine corrections)        A  fire     X  brake (hold)
B             flight assist on/off                    Y  cockpit / chase camera
D-pad Up      next target   D-pad Down  fire mode    R3 target nearest the nose
Back          respawn       Start       pause        L3 debug overlay
```

Keyboard fallback: W both mains, E/Q right/left main, S both retros, D/A right/left retro, I/K pitch, J/L yaw,
arrows strafe, U/O roll, Space fire, X brake, Z assist, V camera, T/F/G target/fire mode/target ahead,
Backspace respawn, Esc pause, F3 overlay, F4 fallback meshes. The ` key opens the debug console.

Flight notes:
- Newtonian: letting go of the triggers does not slow you down. Use the retros or hold X to brake.
- Assist on (default): uneven triggers turn the ship smoothly (overlay `POD YAW`). Assist off: raw physics,
  so uneven pods tank-steer and spins persist.

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

## Acceptance checklist (the (H) criteria)

The full wording is in `docs/milestones/m1-first-flight.md`. Tick each one, or note what you saw.

- [ ] **AC12 Ship splats.** The Starfury renders as splats in both cameras. F4 swaps to the mesh fallback, and
      the mesh sits exactly where the splats were.
- [ ] **AC13 Sky.** Stars and nebula visible; no parallax while flying; no popping between the sky and the hull;
      in the cockpit the frame hides the hull behind it.
- [ ] **AC14 Controls.** Equal triggers fly straight. With assist off, RT alone yaws left and LT alone yaws right.
      Bumpers retro per side. With assist on, one trigger turns at about 30 °/s and stops on release. Triggers
      reach full and rest at zero (overlay `PAD … axes`). No stick drift. Brake stops you in both modes. B and Y
      work.
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
- [ ] **AC17 Targeting.** D-pad Up cycles buoys, R3 picks the one nearest the nose; bracket and readout look
      right; buoys are splats and spin; NAV DELTA (drifting) shows a non-zero closing speed.
- [ ] **AC18 Backend.** Overlay shows `SPLATS COMPUTE`. If it says `RASTER` or `NONE`, note your GPU and driver.
- [ ] **AC22 Console.** ` opens and closes it without typing a character. Typing never moves the ship, and the pad
      still flies while it's open. Esc closes it. History and Tab work. `fps` and `watch ship.speed` work.
      `set` + `save` survives a restart; `set` alone does not.

Record your GPU, driver and FPS in the acceptance record at the end of the milestone doc. If a splat check
(AC12/AC13) fails, that triggers M1-T16 (fallback triage) before anything else. A screenshot plus the overlay text
is the most useful bug report.
