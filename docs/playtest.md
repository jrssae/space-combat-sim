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

The game opens in the **combat sandbox**: wave 1's countdown starts at once (TARGET PRACTICE, then PATROL, then STRIKE and the loop).
For the old free-flight scene with only the nav buoys use `scenario free_flight` in the console (or `set settings.scenario free_flight`, then `save`).

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
X (toggle)    auto-track on/off: the nose swings onto the lead reticle of the selected target and follows it as it moves
              (with none selected it takes the nearest hostile; it switches itself off when none is left); your speed and
              direction are untouched, so you can keep thrusting and strafing while you aim. AUTO-TRACK shows on the HUD
R3            brake (hold): all stop; with a target selected the nose also swings onto it
L3 (hold)     free look: the right stick looks around instead of flying (cockpit: your head turns; chase: the camera
              pans around the ship). Let go and the view returns to the nose. The ship ignores the stick meanwhile.
A             fire                                   B  flight assist on/off      Y  cockpit / chase camera
Back          respawn                                Start  pause
```

Keyboard and mouse (layout B: the left hand flies, the right hand stays on the mouse, which flies pitch and yaw):

```
Q / W / E     left main / both mains / right main     A / S / D   left retro / both retros / right retro
R / F         strafe up / down                        Z / C       strafe left / right
Caps Lock / G roll left / right                       X           brake (hold)           Shift  auto-track (toggle)
Space         fire                                    V           fire mode              T      flight assist on/off
B             tap: next target, hold: target nearest the nose (as D-pad Up)              Tab    cockpit / chase camera
Mouse         pitch and yaw: how fast you move it is how fast you turn (stop the mouse and the turn stops)
Alt (hold)    frees the mouse: the cursor appears, the ship ignores it and clicks do not fire; Alt + drag moves the window
Mouse 1       fire                                    Mouse 2     tap: next target, hold: target nearest the nose
Wheel         previous / next target                  Middle button (hold)  free look, as L3
Mouse 4       auto-track (toggle)                     Mouse 5     fire mode (the side buttons, if your mouse has them)
N or Print    screenshot (saved to user://screenshots/, path printed)
Backspace     respawn                                 Esc         pause (also frees the mouse)       F3  debug overlay   F4  fallback meshes
```

No flight key sits right of G and B: pitch and yaw are the mouse (or the pad), and previous target and "nearest the nose"
have no keys of their own (the wheel and a B or Mouse 2 hold do both). Ctrl and the number row are free (keys 1-4 arrive with
the wing orders). Caps Lock is read as a held key (down = roll left); if your desktop turns it into a toggle, tell the
maintainer (the fallback is Ctrl). Your own saved control profiles keep the keys they had: `controls use default` in the console
loads layout B.

The ` key opens the debug console; it frees the mouse while open. Hunting the splat-hull "jump" under thrust (only the splat hull shows it; the
mesh hull does not): `throttle 1` holds both main pods, then flip these while it happens and note which one stops it:
`set settings.hull_splat_sync off` (engine interpolates the splat node), `set settings.hull_depth_proxy off` (no black depth proxy),
`set settings.physics_jitter_fix 0` (no frame-time smoothing). `window max` / `window normal` / `window 1800 900` resize the window from the console. Mouse feel: `set settings.mouse_full_rate_px_s 1200`
(the mouse speed that commands the full turn rate; lower = more sensitive) and `set settings.mouse_look_deg_per_px 0.12`
(free look). Sizes: `set settings.debug_text_size 22` (overlay text) and `set settings.chase_bolt_scale 3` (how much larger bolts
are drawn in the chase view) and `set settings.hud_chase_opacity 0.7` (how solid the HUD is in the chase view, where the radar
and speed readout also sit in the bottom-right corner instead of the middle) and `set settings.cockpit_light_energy 1.6` (the cabin lamp that lights the cockpit frame; takes effect on the next spawn). Add `save` to keep a setting.

Changed after the first play test: yaw and roll swapped (the right stick used to yaw and the D-pad to roll), and
target-ahead moved to a D-pad Up hold because the pad had no stick clicks. Changed after the M2 play test: X is auto-track and
R3 is the brake; L3 is free look (the debug overlay is F3 only); the keyboard moved to the layout above and the mouse flies.
Changed in M3: keyboard layout B, every flight key under the left hand (the M2.1 layout had pitch, yaw, strafe and targets on
the right side, under the hand that holds the mouse). Tune the hold with `set settings.target_hold_s 0.5` and the D-pad yaw ramp with `set settings.yaw_ramp_s 0.4`.

Nav buoys can be shot: six hits (60 hull) and one blows up with an explosion and shards. A destroyed buoy is gone until you
respawn (Back / Backspace, or dying), which restores them all. Any ship's bolts hurt them.

Flight notes:
- Newtonian: letting go of the triggers does not slow you down. Use the retros or hold R3 (keyboard X) to brake.
- R3 (keyboard X) is an all stop in both assist modes: it kills drift and any spin, and ignores the sticks, D-pad and triggers
  while held. With a target selected it also turns the nose onto the target (about 2.6 s from 90° off) and holds it
  there; release it to fly again.
- Pad X (keyboard Shift) auto-tracks: only the nose is taken over (pitch and yaw; roll stays yours), the thrust and the drift are not.
- Speed: thrust fades as you go faster (the ship gets heavier, like relativity without the rest), so 9 999 m/s is the most you
  can reach and the last thousand take a long time. With assist on the flight computer stops adding speed at 5 000 m/s,
  the "maximum safe speed"; switch assist off (pad B, keyboard T) to go beyond it. Bolts leave at 1 000 m/s relative to your ship, so fired
  forward at 5 000 m/s they fly at 6 000 m/s, fired backward at 4 000 m/s.
- Assist on (default): uneven triggers turn the ship smoothly (overlay `POD YAW`). Assist off: raw physics,
  so uneven pods tank-steer and spins persist (until you hold R3).

## Debug console cheat sheet

```
help                       all commands          state                 all providers
state ship                 every ship value      watch ship.speed      live value under the FPS counter
fps                        FPS counter           god                   no damage (M2+), session only
set settings.invert_y on   change a setting      save                  persist settings to disk
timescale 0.25             slow motion           respawn / pause       same as Back / Start
camera cockpit             set camera            set weapons.mode linked
set settings.fuel_unlimited off   finite fuel    set ship.fuel_kg 0 / refuel   empty / refill the tank
set weapons.charge 0       empty the capacitor   get ship.fuel_fraction / weapons.charge   the HUD gauges
fallback on                force mesh fallback   set targeting.selected "NAV BRAVO"
spawn raider attack 1500   an attacking raider 1.5 km ahead (idle|patrol|attack|aggro; despawn all removes)
spawn raider 40 35 20      an idle raider 40 m ahead, nose to you, yaw 35 / pitch 20
kill target                destroy the selected raider (kill all / kill player too; god on does not stop it)
damage 50 / heal           hit or restore your hull (god on blocks the damage)
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
`mouse:<1|2|3|8|9>`. `bind` adds a binding. To move a pad button, bind the new one first and then `unbind` the old one,
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
      `PAD … axes`). No stick drift. Holding R3 brings you to an all stop (drift and spin) in both modes, and with a
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

# Play-testing M2 (Combat Sandbox)

M2 adds a wave sandbox on top of free flight: raiders (the Delta-V flying wing) that idle, patrol and attack, hit detection and
hull damage, explosions and debris, a combat HUD, sound and a respawn. Setup is the M1 setup above (`scripts/gen_assets.sh`
now also writes the raider, its chunks and the sounds). Run `.tools/godot/godot --path .`: the game opens in the sandbox and
wave 1's countdown starts at once. `scenario free_flight` (console) is the old M1 scene.

`scripts/capture_m2.sh` (or `CAPTURE_REAL_GPU=1 scripts/capture_m2.sh 1920x1080` on your desktop) writes the P1-P4 screenshots to
`reports/m2/`; attach them when you report back.

## The waves

1. **TARGET PRACTICE** (5 s delay): three raiders drifting 1.3-2 km out; they do not shoot.
2. **PATROL** (8 s): three raiders on triangular patrol loops 2-3 km out; they attack when you come within 1.5 km or shoot them.
3. **STRIKE** (8 s): four raiders arrive from 4 km, two seconds apart, and make gun runs. Then it loops: each pass adds one more
   attacker, up to six.

Each wave clears when every raider is gone; a short pause, then the next countdown. If you die, you respawn at the start after
3 s with a full hull; the wave carries on and the raiders left come for you again. The status line (top centre) shows wave,
state, raiders alive and kills.

## HUD legend (green line style; sizes scale with the window height)

```
+ (cross)           where your nose points (1 km ahead)
circle with wings   where you are going (prograde); circle with an X = where you are coming from (retrograde, shown when
                    prograde is behind the camera)
corner brackets     the selected target: red hostile, blue friendly, yellow neutral; name, range, closing speed (m/s,
                    + closing), and a hull bar (none on buoys)
arrow on the edge   the selected target is off screen or behind you
diamond             the lead point: put it on the target and fire. It hides when the bolt cannot reach (too far, or the
                    target outruns it)
bottom left         HULL bar (green, amber under 50 %, red under 25 %; GOD when `god` is on) and a FUEL bar (only when the
                    tank is finite: `set settings.fuel_unlimited off`). Above it, your ship's outline (front view: cabin and the
                    four arms): a part turns yellow, orange, then red as it takes damage
beside the radar    the target's outline in the same colours (Raiders: the two wings and the centre), while a ship is selected
bottom right        CHARGE: the weapon capacitor and the fire mode
drift sphere        a small sphere left of the speed readout, always drawn: your ship at its centre, nose up the screen, and an arrow
                    along your direction of travel (straight up the sphere = flying where you point; sideways = drifting; down =
                    backing up; a short stalk to the equator tells above from below; the small circle is where you came from).
                    `set settings.hud_velocity_marker on` also draws the old in-world prograde / retrograde marker
bottom centre       three lines: speed (m/s); H and V, the horizontal and vertical angle of your direction of travel against
                    your nose in degrees (H + is to the right, V + is up; 0 / 0 = flying straight ahead, H 180 = backward);
                    REF, the distance to the launch point and how fast you are closing on it (+) or opening (-). The radar
                    sphere sits above them: the nose is up the screen, a dot per contact within 25 km (linear
                    to 5 km, logarithmic beyond), coloured by faction, the selected one ringed; the stalk shows above or below
cockpit grid        in the cockpit (or `set settings.hud_targeting_grid on`): an 8 x 8 grid with a circle; the square marker
                    is the target's offset from the nose (+-30 degrees)
```

`set settings.show_hud off` hides it all. The debug overlay (F3) hides its own target bracket while the HUD shows.

## Console additions (M2)

```
spawn raider [idle|patrol|attack|aggro] [distance_m] [yaw_deg] [pitch_deg]    a raider ahead of you, nose to you
despawn [target|all]       return raiders to the pool       kill [target|all|player]   destroy now (bypasses god)
damage <n> [player|target] hit with no shooter              heal [player|target|all]   restore hulls
wave start [1-3] | next | stop | restart     drive the waves          state waves     index, name, state, alive, kills, losses
scenario [combat_sandbox|free_flight]        reload into a scenario (the startup script carries on)
controls ... / bind / unbind                 control profiles (above)
sfx <name>                 play a sound at you              set audio.volume 0.5    SFX gain (settings.sfx_volume)
state combat / hull / raiders / debris / hud / audio       the new providers
```

## Acceptance checklist (M2 (H) criteria, the full wording is in `docs/milestones/m2-combat-sandbox.md`)

- [ ] **AC15 Raider look.** Reads as the Delta-V of your references from front, side, top and three-quarter views; splats in both
      cameras; F4 shows the fallback mesh in the same place. (Proportions follow the sheet: 7.2 m x 17 m; see
      `docs/assets-raider.md`. If it is wrong, say what, and T13 is the look pass.)
- [ ] **AC16 Effects.** Impact flashes sit on the hull they hit; explosions and debris read well, hide behind hulls in front of
      them and show the raider breaking into its parts; no hitch when waves spawn or ships die.
- [ ] **AC17 HUD.** Readable at 1080p in both cameras: everything in the legend above. Holding the lead diamond on a crossing raider
      and firing scores hits.
- [ ] **AC18 Waves.** Target practice raiders drift, patrol raiders react when approached or shot, strike raiders make attack
      runs and sometimes hit; both fire modes kill raiders in a sensible time (a raider has 60 hull, a bolt does 10);
      death and respawn work; `god` works.
- [ ] **AC19 Performance.** 60 fps at 1080p (Compute) with six raiders, bolts, an explosion and debris on screen.
- [ ] **AC20 Control profile.** `controls save mine`, `controls use mine`, `save`, restart: it is still selected.
- [ ] **AC21 Sound.** Weapons, hits, explosions and engines are positional, readable and not fatiguing; `set audio.volume` works.
- [ ] **Splat backend** shows `SPLATS COMPUTE` in the overlay (note GPU and driver if not).

Acceptance record: copy the block at the end of `docs/milestones/m2-combat-sandbox.md`, fill it in and send it back.

# Play-testing M3 (AI Pilots and Wingmen)

The full M3 guide (keyboard, orders, instructor, AC14-AC19) comes with M3-T12. This check can be run now.

Far from the launch point (maintainer Q13): the World now keeps its origin within 5 km of you (`world.auto_rebase_distance_m`),
re-centring as you fly ("a rebase"), so float32 positions stay fine however far you go. `watch world.rebases` counts the rebases
and `get world.rebase_us` gives the last one's cost. `rebase -900000 0 0`, the console line that showed the jumping before, is
now undone in the same tick (you will see `world.rebases` go up by two and `world.origin` back on you); to be truly far away, fly:
a few minutes of both mains with assist on (up to its 5 000 m/s) cover 900 km, and the HUD's `REF` range shows how far you are.

- [ ] **AC22 Far from the launch point.** After `rebase -900000 0 0`, and again after a long flight (`REF` several hundred km),
      thrust in every direction (both mains, retros, strafe, while pitching and yawing): the ship shows no jumping, in splat mode
      and in mesh mode (F4). Then fly at full speed through rebases (one every 5 km: every second at 5 000 m/s) in both cameras:
      no hitch at each one, and an explosion or debris flying when it happens stays where it is.
