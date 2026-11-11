# Play-testing (M1 First Flight, then each milestone's section and the M4 return checklist)

Everything an agent can check runs in CI. What's left needs a person: a Linux desktop with a Vulkan GPU, a
gamepad and a keyboard. This page covers setup, the controls, and the checklist that closes M1.

## Setup (once)

Requirements: Linux x86_64, a Vulkan GPU driver, `git`, `curl`, `unzip`, `python3` with `numpy`.

```
git clone https://github.com/jrssae/space-combat-sim.git
cd space-combat-sim
git checkout m1-first-flight            # until it is merged into main
scripts/setup_godot.sh                  # Godot 4.7.2 into .tools/godot/ (SHA-256 checked)
scripts/gen_assets.sh                   # generates the Starfury, nav buoys and sky (a few seconds)
.tools/godot/godot --path . --import    # first import of the generated assets (~10 s)
```

Re-run `scripts/gen_assets.sh` after pulling changes to `tools/procgen`.
Run `scripts/build_native.sh` after a pull, then `.tools/godot/godot --headless --path . --import` once so Godot registers the library: it rebuilds the native library when `native/` changed. The game needs the library and refuses to start without it; the build needs rustup, and without cargo the script says so and exits 1.

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
Right stick   up/down: pitch (stick back = nose up)   Left stick  strafe left/right, up/down
              left/right: yaw;  the four diagonals: roll toward the side you lean (up-right or down-right = roll right)
D-pad Up      flight assist on/off                   D-pad Down  fire mode
D-pad Left    running lights on/off (key 5; the HUD says LIGHTS ON or OFF, and your wingmen follow)     D-pad Right  free
B             tap: nearest enemy (again: the 2nd nearest)   hold (about 0.35 s): the target menu (see "Target menu", M5)
X (toggle)    auto-track on/off: the nose swings onto the lead reticle of the selected target and follows it as it moves
              (with none selected it takes the nearest hostile; it switches itself off when none is left); your speed and
              direction are untouched, so you can keep thrusting and strafing while you aim. AUTO-TRACK shows on the HUD
R3            brake (hold): all stop; with a target selected the nose also swings onto it
L3 (hold)     free look: the right stick turns the view instead of flying (cockpit: your head turns; chase: the camera
              pans around the ship), faster the further you push it; centre the stick and the view stays where it is.
              Let go of L3 and the view returns to the nose. The ship ignores the stick meanwhile.
A             fire                                   Y  cockpit / chase camera
Back          respawn                                Start  pause
```

Keyboard and mouse (layout B: the left hand flies, the right hand stays on the mouse, which flies pitch and yaw):

```
Q / W / E     left main / both mains / right main     A / S / D   left retro / both retros / right retro
R / F         strafe up / down                        Z / C       strafe left / right
Caps Lock / G roll left / right                       X           brake (hold)           Shift  auto-track (toggle)
Space         fire                                    V           fire mode              T      flight assist on/off
5             running lights on/off (as D-pad Left)
B             tap: nearest enemy, hold: the target menu (as Mouse 2)                   Tab    cockpit / chase camera
Mouse         pitch and yaw: how fast you move it is how fast you turn (stop the mouse and the turn stops)
Alt (hold)    frees the mouse: the cursor appears, the ship ignores it and clicks do not fire; Alt + drag moves the window
Mouse 1       fire                                    Mouse 2     tap: nearest enemy, hold: the target menu
Wheel         previous / next target                  Middle button (hold)  free look, as L3
Mouse 4       auto-track (toggle)                     Mouse 5     fire mode (the side buttons, if your mouse has them)
N or Print    screenshot (saved to user://screenshots/, path printed)
Backspace     respawn                                 Esc         pause (also frees the mouse)       F3  debug overlay
```

No flight key sits right of G and B: pitch and yaw are the mouse (or the pad). Previous target and "nearest the nose" have no
keys of their own since M5 (the wheel cycles; `bind target_ahead key:H` gives the second one back). Ctrl is free, and keys 1-4 are the wing orders and 5 the
running lights. Caps Lock is read as a held key (down = roll left); if your desktop turns it into a toggle, tell the
maintainer (the fallback is Ctrl). Your own saved control profiles keep the keys they had: `controls use default` in the console
loads layout B.

Wing orders (keys 1-4, or `wing order <attack|form|engage|cover>`): **1** attack my target (your selected hostile only),
**2** form on me (formation only, no attacks), **3** engage at will (anything they see, no leash), **4** cover me, the default:
they hold formation and engage only hostiles within 2 km of you, and a wingman more than 3 km from you breaks off and rejoins.
The acknowledgement line stays on screen 3.5 s.

The ` key opens the debug console; it frees the mouse while open. Hunting a hull "jump" under thrust: `throttle 1` holds both main
pods, then try `set settings.physics_jitter_fix 0` (no frame-time smoothing) while it happens and note whether it stops. `window max` / `window normal` / `window 1800 900` resize the window from the console. Mouse feel: `set settings.mouse_full_rate_px_s 1200`
(the mouse speed that commands the full turn rate; lower = more sensitive) and `set settings.mouse_look_deg_per_px 0.12`
(free look). Sizes: `set settings.debug_text_size 22` (overlay text) and `set settings.chase_bolt_scale 3` (how much larger bolts
are drawn in the chase view) and `set settings.hud_chase_opacity 0.7` (how solid the HUD is in the chase view; in the cockpit view the
radar, speed and bars are on the console's screens) and `set settings.cockpit_light_energy 1.0` (the cabin lamp that lights the grey cockpit a dark red, 1.0 by default since M4-T30b; takes effect on the next spawn). Hull lighting: `set settings.ambient_level 0.3` (how much light the dark side of a hull gets) changes it live. Add `save` to keep a setting.

Changed after the first play test: yaw and roll swapped (the right stick used to yaw and the D-pad to roll), and
target-ahead moved to a D-pad Up hold because the pad had no stick clicks. Changed after the M2 play test: X is auto-track and
R3 is the brake; L3 is free look (the debug overlay is F3 only); the keyboard moved to the layout above and the mouse flies.
Changed in M3: keyboard layout B, every flight key under the left hand (the M2.1 layout had pitch, yaw, strafe and targets on
the right side, under the hand that holds the mouse). Changed after the M3 play test: the right stick flies all three axes (pitch
up/down, yaw left/right, roll on the diagonals), B selects targets (hold for the previous one), D-pad Up is flight assist and
D-pad Left/Right were free; free look holds its view until L3 is released. A control profile you saved with the old default pad
layout is moved onto the new one when it loads (your keys and mouse buttons stay; the console says so; `controls save <name>`
keeps it). Tune the hold with `set settings.target_hold_s 0.5`. Running lights on D-pad Left and key 5 came later (M3-T27): a saved profile gets them when
it loads, and one that already uses D-pad Left keeps it, with the lights on key 5 alone.

Nav buoys can be shot: six hits (60 hull) and one blows up with an explosion and shards. A destroyed buoy is gone until you
respawn (Back / Backspace, or dying), which restores them all. Any ship's bolts hurt them.

Flight notes:
- Newtonian: letting go of the triggers does not slow you down. Use the retros or hold R3 (keyboard X) to brake.
- R3 (keyboard X) is an all stop in both assist modes: it kills drift and any spin, and ignores the sticks and triggers
  while held. With a target selected it also turns the nose onto the target (about 2.6 s from 90° off) and holds it
  there; release it to fly again.
- Pad X (keyboard Shift) auto-tracks: only the nose is taken over (pitch and yaw; roll stays yours), the thrust and the drift are not.
- Speed: thrust fades as you go faster (the ship gets heavier, like relativity without the rest), so 9 999 m/s is the most you
  can reach and the last thousand take a long time. With assist on the flight computer stops adding speed at 5 000 m/s,
  the "maximum safe speed"; switch assist off (pad D-pad Up, keyboard T) to go beyond it. Bolts leave at 1 000 m/s relative to your ship, so fired
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
state render               renderer and frame    set targeting.selected "NAV BRAVO"
spawn raider attack 1500   an attacking raider 1.5 km ahead (idle|patrol|attack|aggro; despawn all removes)
spawn raider 40 35 20      an idle raider 40 m ahead, nose to you, yaw 35 / pitch 20
kill target                destroy the selected raider (kill all / kill player too; god on does not stop it)
damage 50 / heal           hit or restore your hull (god on blocks the damage)
running_lights off         your lights, and your wing's (on|off, alone it toggles)
spawn raider aggro 3000    a raider that patrols dark and lights up when it attacks you (lights=on|off on any spawn)
```

### Control profiles

Alternate layouts live in saved profiles you switch from the console (a controls menu comes with M5). Two are
built in and read-only: `default` (the layout above) and `m1_classic` (the original M1 pad layout: right stick X
yaws, D-pad Left/Right rolls, D-pad Up targets, B toggles assist; keyboard and mouse as in `default`).

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
`settings.control_profile`). `m1_classic` changes only the bindings: its stick yaws in proportion and rolls on its
diagonals, as the default's does, and its D-pad rolls at full rate on top.

## Acceptance checklist (the (H) criteria)

The full wording is in `docs/milestones/m1-first-flight.md`. Tick each one, or note what you saw.

- [ ] **AC12 Ship hull.** The Starfury renders as its textured hull in both cameras (since M4-T31 the only hull; M1 accepted
      an earlier renderer's hull, which M4 replaced).
- [ ] **AC13 Sky.** Stars and nebula visible; no parallax while flying; no popping between the sky and the hull;
      in the cockpit the frame hides the hull behind it.
- [ ] **AC14 Controls.** Equal triggers fly straight. With assist off, RT alone yaws left and LT alone yaws right.
      Bumpers retro per side. With assist on, one trigger turns at about 30 °/s and stops on release. Right stick
      pitches (up/down), yaws (left/right) and rolls (diagonals). Triggers reach full and rest at zero (overlay
      `PAD … axes`). No stick drift. Holding R3 brings you to an all stop (drift and spin) in both modes, and with a
      target selected swings the nose onto it. D-pad Up (assist) and Y work.
- [ ] **AC15 Performance.** 60 fps at 1080p (overlay FPS), no hitch when firing.
- [ ] **AC16 Glow and guns.** Pod plumes come out of the nozzles along their axes and follow each side's thrust,
      retros and trim; RCS plumes respond to strafe and rotation; bolts and muzzle flash visible from both cameras;
      the two fire modes look different.
- [ ] **AC16b Chase camera and hull occlusion.** The chase camera stays a fixed distance behind the ship while you
      yaw, roll and hold both bumpers (the ship never moves in frame, the stars do); `set settings.camera_chase_smoothing_s 0.2`
      lets the view swing softly, `0` is rigid again. In chase view the muzzle flash, bolts leaving the guns and the
      plumes behind the hull are hidden by the hull, not drawn through it; the hull has no black patches or dark
      outline. The hull does not judder against the plumes at speed.
- [ ] **AC17 Targeting.** Tapping B cycles buoys; holding it steps back one, once, without also cycling forward;
      holding keyboard B or Mouse 2 picks the one nearest the nose; bracket and readout look right; buoys are textured and spin; NAV DELTA
      (drifting) shows a non-zero closing speed.
- [ ] **AC18 Renderer.** Overlay shows `RENDER FORWARD_PLUS`. If not, note your GPU and driver.
- [ ] **AC22 Console.** ` opens and closes it without typing a character. Typing never moves the ship, and the pad
      still flies while it's open. Esc closes it. History and Tab work. `fps` and `watch ship.speed` work.
      `set` + `save` survives a restart; `set` alone does not.

Record your GPU, driver and FPS in the acceptance record at the end of the milestone doc. A screenshot plus the overlay text
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
state, raiders alive and three counts (the AI waves get harder: PATROL's raiders are rookies, the first STRIKE's are easy,
and every pass round the loop raises the floor until all are aces; aggression varies from raider to raider): `KILLS` (every raider destroyed, by anyone), `YOURS` (your bolt or ram made the kill)
and `ASSISTS` (you fired at it while it was your selected target, and someone else killed it).

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
bottom right        CHARGE: the weapon capacitor and the fire mode; above it LIGHTS ON, or LIGHTS OFF in amber (D-pad Left, key 5)
drift sphere        a small sphere left of the speed readout, always drawn: your ship at its centre, nose up the screen, and an arrow
                    along your direction of travel (straight up the sphere = flying where you point; sideways = drifting; down =
                    backing up; a short stalk to the equator tells above from below; the small circle is where you came from).
                    `set settings.hud_velocity_marker on` also draws the old in-world prograde / retrograde marker
bottom centre       three lines: speed (m/s); H and V, the horizontal and vertical angle of your direction of travel against
                    your nose in degrees (H + is to the right, V + is up; 0 / 0 = flying straight ahead, H 180 = backward);
                    REF, the distance to the launch point and how fast you are closing on it (+) or opening (-). The radar
                    sphere sits above them: the nose is up the screen, a dot per contact within 25 km (linear
                    to 5 km, logarithmic beyond), coloured by faction, the selected one ringed; the stalk shows above or below.
                    A hollow dot on the rim is a broadcast beyond 25 km, in its true direction: nav buoys are heard to
                    1 000 km and allied Starfuries to 100 km, and you can cycle to and select them (range in the target box)
cockpit grid        in the cockpit (or `set settings.hud_targeting_grid on`): an 8 x 8 grid with a circle; the square marker
                    is the target's offset from the nose (+-30 degrees)
```

`set settings.show_hud off` hides it all. The debug overlay (F3) hides its own target bracket while the HUD shows.

## Console additions (M2)

```
spawn raider [idle|patrol|attack|aggro] [distance_m] [yaw_deg] [pitch_deg]    a raider ahead of you, nose to you
despawn [target|all]       return raiders to the pool       kill [target|all|player]   destroy now (bypasses god)
damage <n> [player|target] hit with no shooter              heal [player|target|all]   restore hulls
wave start [1-3] | next | stop | restart     drive the waves          state waves     index, name, state, alive, kills, player_kills, player_assists, losses
scenario [combat_sandbox|free_flight|instructor_route|dogfight]    reload into a scenario (the startup script carries on)
controls ... / bind / unbind                 control profiles (above)
sfx <name>                 play a sound at you              set audio.volume 0.5    SFX gain (settings.sfx_volume)
state combat / hull / raiders / debris / hud / audio       the new providers
```

## Acceptance checklist (M2 (H) criteria, the full wording is in `docs/milestones/m2-combat-sandbox.md`)

- [ ] **AC15 Raider look.** Reads as the Delta-V of your references from front, side, top and three-quarter views; its textured
      hull in both cameras. (Proportions follow the sheet: 7.2 m x 17 m; see
      `docs/assets-raider.md`. If it is wrong, say what, and T13 is the look pass.)
- [ ] **AC16 Effects.** Impact flashes sit on the hull they hit; explosions and debris read well, hide behind hulls in front of
      them and show the raider breaking into its parts; no hitch when waves spawn or ships die.
- [ ] **AC17 HUD.** Readable at 1080p in both cameras: everything in the legend above. Holding the lead diamond on a crossing raider
      and firing scores hits.
- [ ] **AC18 Waves.** Target practice raiders drift, patrol raiders react when approached or shot, strike raiders make attack
      runs and sometimes hit; both fire modes kill raiders in a sensible time (a raider has 60 hull, a bolt does 10);
      death and respawn work; `god` works.
- [ ] **AC19 Performance.** 60 fps at 1080p with six raiders, bolts, an explosion and debris on screen.
- [ ] **AC20 Control profile.** `controls save mine`, `controls use mine`, `save`, restart: it is still selected.
- [ ] **AC21 Sound.** Weapons, hits, explosions and engines are positional, readable and not fatiguing; `set audio.volume` works.
- [ ] **Renderer** shows `RENDER FORWARD_PLUS` in the overlay (note GPU and driver if not).

Acceptance record: copy the block at the end of `docs/milestones/m2-combat-sandbox.md`, fill it in and send it back.

# Play-testing M3 (AI Pilots and Wingmen)

M3 adds other pilots to the sandbox: three wingmen who fly on you and take orders, raiders on the same AI, an instructor who leads a
route and shows manoeuvres, ram damage, kill credit, and a visual pass (relit hulls, ship lights, sparks and debris, running lights, a
sharper hull for your own ship, lens flare, motion blur). The Starfury has a new cockpit whose console screens carry the instruments.
This section is the guide for the (H) checks; the numbers an agent measured are in the milestone's acceptance record.

## Run it

The generators changed a lot, so build the assets again and import them once. The first import takes a few minutes (the texture maps are compressed then). If the cockpit shows no screens, or a ship warns about missing `nav_lights`, the assets are stale.

```
git checkout m3
scripts/gen_assets.sh
.tools/godot/godot --headless --path . --import
.tools/godot/godot --path .
```

The game opens in `combat_sandbox`: your three wingmen beside you and wave 1's countdown running. The console's `scenario` command
switches to the others, and any further commands in the same line still run:

```
scenario combat_sandbox      the waves, with your wing                  scenario instructor_route   the instructor's route
scenario dogfight            four allies against six raiders, 3 km ahead of where you start; you are not in it
scenario free_flight         only the nav buoys
```

## Controls

The tables in "Controls" at the top of this page are current. In short, keyboard layout B puts every flight key under your left hand and
the mouse flies pitch and yaw:

```
Q / W / E        left main / both mains / right main       A / S / D     left retro / both retros / right retro
R / F            strafe up / down                          Z / C         strafe left / right
Caps Lock / G    roll left / right                         X             brake (hold)
Space or Mouse 1 fire                                      V             fire mode
B or Mouse 2     tap: next target, hold: nearest the nose  Wheel         previous / next target
Shift or Mouse 4 auto-track                                T             flight assist
Tab              cockpit / chase camera                    Middle mouse  free look (hold)
1 2 3 4          wing orders                               5             running lights
```

On the pad the triggers are the mains and the bumpers the retros. The right stick pitches straight up or down, yaws straight left or
right, and rolls on the diagonals. The left stick strafes. A fires, B taps to the next target and holds for the previous one, X is
auto-track, Y the camera. D-pad Up is flight assist, Down the fire mode, Left the running lights, and Right is free. R3 is the brake and L3 held is
free look. Wing orders have no pad button in M3 (the comms menu comes with M5).

## Wing orders

Keys 1 to 4, or `wing order <attack|form|engage|cover>` in the console. The HUD names the order for 3.5 s, for example
`ALPHA 2: COPY, FORMING UP`.

- **1, attack my target:** every wingman goes for your selected hostile, and only that one. With no hostile selected it is refused
  (`ALPHA 2: UNABLE, NO HOSTILE SELECTED`) and the old order stands. In a console script under `--console-strict`, a refusal stops the
  script, as any failed command does.
- **2, form on me:** they hold formation and never attack.
- **3, engage at will:** they attack anything they see, with no leash.
- **4, cover me (the default):** they hold formation, engage only hostiles within 2 km of you, and a wingman more than 3 km from you
  breaks off and rejoins.

A wingman that goes down is replaced when the next wave starts, entering 1 500 m behind you. While you are dead they engage at will, and
they go back to their order when you respawn. `wing` prints the wing, `wing formation <finger_four|wedge|line_abreast>` changes its shape,
and `wing replenish` fills empty slots at once.

## Running lights

Every ship shows red on its left, green on its right and white on top. Key 5, D-pad Left or `running_lights [on|off]` switches yours; the HUD
says LIGHTS ON or LIGHTS OFF, and your wingmen follow within a second. Radar and AI detection do not change: it is how you look, not
whether you are seen. Raiders on patrol fly dark and light up with their first shot.

## The instructor

`scenario instructor_route` puts the instructor 200 m ahead of you. Follow it. The HUD marks it, marks its next waypoint with a diamond, and
says on the status line what comes next: `FOLLOW INSTRUCTOR`, `CLOSE UP ON INSTRUCTOR` when you have fallen behind (it stops within 1 600 m
and goes on when you close to 800 m), and `WATCH INSTRUCTOR` during a demo. It cannot be hurt and never fires. The six waypoints show a roll, a
strafe box, a pod turn, a flip and burn, and an all stop, in that order. `state route` and `ai INSTRUCTOR` show where it is up to.

## New console commands

```
wing [order|formation|replenish] [value]     orders, shape, replacements (above)
spawn <raider|ally> [behaviour] [distance_m] [yaw_deg] [pitch_deg] [skill=<rank|0-1>] [aggression=<level|0-1>] [lights=on|off]
                                             behaviours: raider idle|patrol|attack|aggro|ai, ally idle|ai. The ship is placed straight
                                             ahead of you; yaw and pitch turn the ship, not where it is
ai <name>                                    a pilot's behaviour, state and every score
ai <name> skill <rookie|regular|veteran|ace|0-1>    ai <name> aggression <passive|cautious|balanced|aggressive|reckless|0-1>
ai <name> objective <target|none>            send a pilot to a target (a broadcast is enough to find it)
relation <a> [b] [friendly|neutral|hostile]  show or change (this session) how two factions see each other; relation reset reloads the file
kill allies                                  destroy every allied ship
rebase <dx> <dy> <dz>                        shift the local origin (see "Far from the launch point")
flare [on|off]   blur [on|off]               the visual pass's switches
running_lights [on|off]                      your lights, and your wing's
look <yaw> [pitch]   look off                hold the view off the nose (free look from the console; in chase the camera orbits the ship)
fxburst [hit|ram|explosion_sparks|explosion_fragments|explosion_gas|debris]    one burst 40 m in front of the camera
scenario <name>                              as above
state wing|ai|factions|ram|route|lights|post|screens|world     the new providers
```

## New settings and their defaults

Set one with `set settings.<name> <value>`; add `save` to keep it. Every one is listed by `state settings`.

```
friendly_fire false            bolts hit anything but their shooter when on
ram_damage true                collisions hurt
ambient_level 0.3              how much light the dark side of a hull gets (M4-T30a)
particle_density 1.0           how much of each spark and debris burst is thrown; 0 costs nothing per frame
lens_flare true                the star's flare (flare on|off)
motion_blur false              blur on fast turns (blur on|off)
motion_blur_strength 0.5       how strong the blur is
cabin_glow_level 0.3           how much red the cockpit glow adds in the canopy, seen from outside
cabin_glow_view_m 150          how far off the glow can be seen
running_light_min_px 1         a running light is never smaller than this on screen; farther out it dims instead
cockpit_light_energy 1.0       the cabin lamp that lights the cockpit frame a dark red (takes effect on the next spawn; 1.6 before M4-T30b)
target_hold_s 0.35             how long a press on B is a hold
hud_targeting_grid false       the targeting grid in the chase view too (in the cockpit it is on the octagon)
hud_velocity_marker false      the prograde marker in the world
```

## Captures and measurements

`scripts/capture_m3.sh` takes the screenshots P5 to P13 into `reports/m3/`, and `scripts/capture_m3.sh p7 p9` takes only those.
`scripts/measure_m3.sh` measures the fight and the 100 ships at 1080p into `reports/m3/measure.log`, with `ac19`, `vsync`, `costs` or
`hundred` for one group. Both open short windows that close by themselves, and they take the mouse while they run. `F3` hides the debug text.

## Far from the launch point

The World keeps its origin within 5 km of you (`world.auto_rebase_distance_m`), re-centring as you fly ("a rebase"), so float32 positions
stay fine however far you go. `watch world.rebases` counts the rebases and `get world.rebase_us` gives the last one's cost. `rebase -900000 0 0`,
the console line that showed the jumping before, is now undone in the same tick: `world.rebases` goes up by two and `world.origin` lands back on
you. To be truly far away, fly: a few minutes of both mains with assist on (up to its 5 000 m/s) cover 900 km, and the HUD's `REF` range shows how far you are.

## Acceptance checklist (M3 (H) criteria; the full wording is in `docs/milestones/m3-ai-pilots-and-wingmen.md`)

Tick each one, or say what you saw. A screenshot with the debug text (`F3`) is the most useful report. Screenshots are in `reports/m3/` if you
ran the capture, and the milestone's as-built notes say what each one shows.

- [ ] **AC14 Keyboard layout B.** With your right hand on the mouse, every flight key is easy to reach without looking. Caps Lock rolls left while
      it is held and stops when released (press and release both register; if your desktop treats it as a toggle, say so: the fallback is Ctrl).
- [ ] **AC15 Wingmen and raiders.** In the sandbox the wing holds a believable finger-four on you (look back with L3, the middle mouse button or
      `look 165 15`), keeps it through turns, breaks to engage, and rejoins. Try orders 1 to 4. They are useful in a fight. Raiders fly in groups of
      two or three, evade when chased, and still make attack runs. Some pilots make slashing passes. The balance itself is yours to judge:
      `scenario dogfight` and the sandbox's wave 2, where rookies on slashing passes shoot down the wing.
- [ ] **AC16 Rams.** A bump under about 5 m/s does nothing, a hit around 30 m/s closing hurts badly, a head-on at speed kills both, and nothing passes
      through anything without a collision. `god on` protects you, and you still bounce.
- [ ] **AC17 Instructor.** On `scenario instructor_route` the route is easy to follow, the waypoint diamond reads, and every demo is clearly visible from
      behind.
- [ ] **AC18 Allied Starfuries.** At combat ranges (`spawn ally idle 150 35 20`) they look right; they use the lighter LOD1 hull. Close up they go soft: judge whether
      that matters. A Starfury's break-up shows its cabin and four arms tumbling apart (`set targeting.selected "ALPHA 2"`, `kill target`).
- [ ] **AC19 Frame rate.** Hold 60 fps at 1080p in a real fight (`god on; wing order engage; wave start 3`, overlay or `fps`). An agent measured the worst
      case on this GPU (136-182 fps with vsync off); see the acceptance record. With vsync on it read about one repeated frame a second, and half of those were there with no ships
      at all, so say if you feel stutter, in the fight or in empty space, and whether fullscreen changes it.
- [ ] **AC22 Far from the launch point.** After `rebase -900000 0 0`, and again after a long flight (`REF` several hundred km), thrust in every direction
      (both mains, retros, strafe, while pitching and yawing): the ship shows no jumping. Then fly at full speed through
      rebases (one every 5 km: every second at 5 000 m/s) in both cameras: no hitch at each one (the picture holds still for one tick at a rebase, everything
      together: at most one repeated frame; watch a buoy, a ship or your own bolts passing), and an explosion or debris flying when it happens stays where it is
      and looks as in M2 (AC16).
- [ ] **AC27 Play-test tweaks.** B selects targets (a tap goes to the next, a hold to the previous) and D-pad Up toggles assist. The right stick pitches, yaws and rolls
      (diagonals roll). L3 free look stays where you left it until you let go of L3. Gun and impact sounds sit two octaves lower than they did. Reverse and side thrust
      feel strong. The KILLS, YOURS and ASSISTS numbers read at a glance. Buoys and wingmen far out show on the radar's rim. Some AI ships make slashing passes and turn
      to chase.
- [ ] **AC35 Visual pass.** No visible pop as a ship changes level at combat ranges. Plumes light the pods, muzzle flashes light the nose, explosions light nearby hulls,
      and the star gives each hull a lit and a dark side as it rolls. Hits throw sparks and debris vents. Your own hull is sharp close up in the chase view. The flare follows the star and hides behind hulls. Motion blur (`blur on`) smears the stars on fast turns, not the
      HUD. Raiders read almost black from their unlit side at 80-150 m, gas puffs may read as flat discs, and a debris chunk can read as a flat black shape: say if any of that bothers you. If the flare is too strong or too yellow, its
      numbers are in `space_environment.tscn`.
- [ ] **AC39 Running lights and break-up.** Every ship shows red on its left, green on its right and white on top: read them at combat range and as points from several km
      (`spawn raider idle 3000`). Fly over a Starfury (`spawn ally idle 26 0 -80` turns its top toward you in the cockpit camera): its cabin top is lit, and it goes darker
      with `running_lights off`. The cockpit glow is soft, inside and in the canopy from outside within about 150 m. A dark raider is hard to spot and its lights coming on
      reads as a threat: `spawn raider aggro 3000` patrols dark and lights up when it attacks you (the sandbox's PATROL wave starts dark too, but it spawns inside your
      sensor range and attacks at once). D-pad Left or key 5 switches yours, the HUD says so, and your wingmen follow. Buoys keep a steady light and breathe slowly. A Starfury's
      death starts where it was hit and tears apart in stages: the first fireball hides much of that at 60 m or closer, so also watch one from a few hundred metres, and your own hull turns soft as it breaks up, because the chunks are the lighter LOD1. Knobs:
      `settings.top_lamp_energy`, `cabin_glow_level`, `cabin_glow_view_m`, `running_light_min_px`, `cockpit_light_energy`; positions are `nav_lights` in the generators.
- [ ] **AC41 Cockpit and screens.** The cockpit reads like the reference in your slimmer proportions: slim red-lit V struts with space and ships visible past them, and a console that looks
      built in. The screens are legible at a glance at 1080p without free look. The hull bar (left screen) and charge bar (right screen) read in a fight from the screens alone. Nothing
      important is hidden by the struts. Look too at what T29 left open: the strut on the star's side reads bright and the other dark (no shadows in the cabin), the shell behind you is
      plain facets (free look), and the four lamps have no labels (assist, guns, lights, track).

Record your GPU, driver, FPS and VRAM in the acceptance record at the end of the milestone doc.

## M4 return checklist

Look and feel items from M4 not yet seen by the maintainer (Q54), for one session on return. Each names the task that changed it.

- [ ] **M4-T36 The radar's dots.** The radar's contacts are drawn in batches now: every stalk first, then every dot over them (before,
      each contact's stalk and dot were drawn in turn, so a nearer contact's stalk could cross a farther dot), and the dots are 16-sided
      polygons. Check the chase radar and the cockpit octagon at `battle 300` and in the sandbox: dots read as round, colours as before,
      the selected contact ringed and on top, broadcast contacts hollow on the rim.
- [ ] **M4-T36 Hit sparks.** A bolt hit shows the flash and the particle sparks only; the 6 to 10 mesh spark streaks that flew off each
      hit are gone. Shoot a raider at 100 to 300 m: say if hits read too thin.
- [ ] **M4-T36 Plumes.** A ship holding one command stops updating its plumes once they reach their levels (within a ten-thousandth).
      Watch AI plumes at combat range: nothing should freeze or step.
- [ ] **M4-T36 The 3D at full resolution.** `RenderScale` no longer lowers a large window's 3D. Since M4-T41 the game opens through
      Wayland at the panel's own 3840x2160 (before, X11 under GNOME's 1.25 scale made it 6144x3456). Maximize the game: the 3D is
      at the window's size (`settings.upscaler native`); check the frame rate holds in the sandbox and at `typical` (GPU time was
      0.8 ms a frame at 1 080 lines in M4-T25's fullscreen check; full 4K is four times the pixels).
- [ ] **M4-T36 Motion blur on turns.** `settings.motion_blur on`, then a hard turn: the stars and the nebula smear by the turn, hulls by
      their own motion, and no hull paint is dragged across the stars. The pair `reports/perf/M4-T36_motion_blur/turn_blur_{false,true}.png`
      (a one-frame 40 degree look swing) shows what the agent saw.
- [ ] **M4-T36 The debug overlay** refreshes ten times a second instead of every frame: it should still read as live.
- [ ] **M4-T24 The AI one tick behind.** The AI step (every native brain's think, the hosted drivers' think rate, the commands into
      the rows) runs on a worker thread and its commands reach the ships one tick (16.7 ms) after the rows they were decided on
      (Q53). Fly the sandbox and `battle 300`: AI ships should turn, fire and dodge as before, with no visible hesitation or
      overshoot; a raider on your tail should still track you. M4-T37 removed the same-tick `inline` step, so there is no
      switch back to compare with; `set settings.sim_step delayed` runs the same one-tick handover on the main thread (the
      threaded step's bit-for-bit reference) if a difference between the two is suspected.
- [ ] **M4-T24 Input feel.** Your own stick is never behind (the player's command is sampled and applied in the same tick on
      every schedule), but the frame no longer carries the AI step: at `battle 300` and `500` the stick should feel more
      immediate than before. Check pitch, yaw and the trigger with vsync on and off; `state core` shows `step_misses` (should
      stay 0) and `step_wait_us`.
- [ ] **M4-T24 The catch-up cap.** `physics_max_steps_per_frame` is 3 (Godot's default was 8): when the tick cannot keep up
      (battle 500) the simulation slows instead of the frame stuttering through catch-up ticks. Judge whether the slow-motion
      at 500 reads better than the stutter did; `2` is the other candidate (`set settings.physics_max_steps_per_frame 2`).
- [ ] **M4-T35 Bolts as rows.** the AI ships' bolts are drawn by one multimesh per look (`core.bolt_draws`), interpolated between ticks as the nodes were. Check in a `battle` run: bolts leave the muzzles, fly straight and smoothly (no stutter against the hulls), hit flashes still appear where bolts land, the chase camera's larger bolts (`Projectile.visual_scale`) still apply, and nothing is drawn where a bolt was spent. (M4-T37 removed `perf_native_bolt_rows`, so there is no bolt-node run to compare with: the recorded battle in `test_bolt_rows` holds the rows to the nodes' hits.)
- [ ] **M4-T35 The AI ships' muzzle flashes.** the lean ships' flashes come from one pool (a multimesh of billboard quads and pooled lights), not a node per muzzle. Check in a `battle` run: a flash pops at the muzzle of every AI shot for about 50 ms, grows and fades as the player's own flashes do, rides with the ship, and lights the nose; no flash lingers on a parked or dead ship.
- [ ] **M4-T35 The AI ships' shot sounds.** `AudioDirector.watch_ship` listens to `shot_fired`, which both bolt paths emit (fix round 1). Confirm every AI shot in a `battle` run makes its pulse or raider sound at the muzzle (the AI ships' bolts are always rows since M4-T37 removed `perf_native_bolt_rows`).
- [ ] **M4-T21 The low-attention tier.** On by default since T23 (`settings.tier_radius_m` 10 000). AI fighters and capitals more than 10 km from you (`settings.tier_radius_m`) leave
      Jolt and fly as native core rows integrated at 20 Hz from their held command; within 10 km they are promoted back onto
      their bodies with their motion carried over exactly. In a `battle 300` or `500` run (`state tier` shows the rows and the
      handovers): fly toward a far fight: its ships are drawn from their rows beyond 10 km (T23: dots for fighters, the class's
      mesh for capitals) and should come onto their bodies at 10 km with no pop, jump, flicker or stutter, and keep flying as they
      flew; fly away from a fight: the same at 11 km the other way. Ships past 11 km stay on the radar and keep your lock (T23).
      A ship that crosses the line while
      shooting should fire again at once when it is back. Compare with the tier off (`set settings.tier_radius_m 0`).
- [ ] **M4-T22 The battle beyond the radius fights.** With the tier on (the default since T23, `settings.tier_radius_m` 10 000), tier fighters think
      three times a second (`settings.tier_brain_hz`) and their shots and the far capitals' guns, beams and missiles are rolled,
      not flown as bolts. In a `battle 500` run, fly into a far fight: the ships you meet at 10 km should be in the middle of a
      fight that went on without you (hurt hulls, ships missing that died out there, wingmen still in their slots), with no
      jump in a hull or a position at the moment they appear; your own bolts fired at a ship just beyond 11 km hit it. Say
      whether a fight met this way feels like the same fight you would have watched up close (a 3 Hz brain flies its attack
      runs a little looser). Far ships also think lean: they ignore rocks, mines, incoming fire and avoidance (they collide with
      nothing out there), so watch for a ship promoted inside or right against a rock at 10 km (a jolt, a hit or an explosion);
      `state tier` should show `brain_period_ticks` 20 (a settings file saved before T22's fix round 2 may hold 4 Hz). Since T23 a
      ship promoted inside a rock is moved clear first (`state tier` counts it as `cleared`), tier ships are drawn and on the
      radar, and a far death flashes. A known limit (fix round 1): a far fight that settles into a steady tail chase scores fewer hits than
      the same chase up close (a Starfury sitting behind a raider at 450 m lands about 73 % of its shots up close, about 30 %
      in the tier); say whether you notice far chases ending slower than near ones. Far missiles can now be shot down by the
      target side's interceptors, and committed rammers ram out of view too.
- [ ] **M4-T23 Far ships as dots.** In a `battle 500` or `1000` run (the tier on by default), the fighters beyond 11 km are
      dots from their rows (`state tier`: `proxy_dots`), in their hull's paint, a pixel at least, dimming with distance as the
      near far dots do. Say whether a far fight reads as a fight (moving specks) and whether the dots are too bright, too dim or
      too many next to the stars. Screenshot: `reports/perf/M4-T23_battle_1000_view.png`, `reports/perf/M4-T23_far_fight.png`.
- [ ] **M4-T23 Far capitals.** A capital beyond 11 km is drawn as its class's mesh from its row (`proxy_hulls`): at 11 to 20 km
      a carrier is still a hundred pixels or more. Fly toward and away from one through 10 and 11 km: no pop, no flicker and no
      jump at the handover; it should look exactly the same just before and just after (the bench's capitals use the plain box
      look; the station scene's the textured hull). Screenshot: `reports/perf/M4-T23_far_fight.png` (the grey hull ahead).
- [ ] **M4-T23 Far deaths.** The level follows the fireball's size on the 3D picture (fix round 1): the full explosion while its
      radius is 8 px or more, a reduced one (no light, a gas puff, no debris) down to 2 px, then a point flash with no node
      (`state tier`: `flashes`) that starts as big and as bright as the fireball it replaces and then fades out with distance. At
      1 080 lines (the default 3D at 0.5 on the 4K panel): a fighter's death is full to about 1.1 km, reduced to 4.3 km, and its
      flash reads to about 17 km; a destroyer's 36 km, 142 km and 570 km; a carrier's 71 km, 284 km and 1 140 km (twice as far at
      2 160 lines). In a battle run watch fighters die beyond 4 km (a bright point that flares and fades in about half a second)
      and kill a capital (`set targeting.selected "CRUISER 1"` then `kill`): within tens of km it is still the full explosion.
      Say whether the switches pop (a full or reduced blast handing over to the point) and how bright and how long the point
      should be. Screenshots: `reports/perf/M4-T23_far_fighter_death.png` and `M4-T23_far_capital_flash.png` (a raider at 7.5 km
      and a cruiser at 116 km, each past its switch, with an 8x crop around the flash, `*_crop8x.png`; distances in
      `M4-T23_far_flash_shots.txt`), and `M4-T23_far_capital_death.png` (a carrier at 16 km: the full explosion).
- [ ] **M4-T23 Capitals can die.** In `battle` runs capitals can now be destroyed (before T23 a capital at zero hull stayed in
      play): it explodes by the rule above and vanishes, its turrets with it. The bench's own capitals are invulnerable, so this
      shows with `kill` or outside the bench; say whether a capital simply vanishing after its blast is acceptable until M12's
      break-up.
- [ ] **M4-T23 A capital promoted near a rock.** A ship coming back from the tier inside a rock or a mine is moved out by the
      shortest way (a capital by its hull box): watch a carrier promoted at 10 km next to a rock field for a visible jump.
- [ ] **M4-T23 The radar with the tier.** At `battle 1000` the radar holds about a thousand contacts again (the tier's ships
      within 25 km and its broadcasting allies); check it stays readable and that selecting a far ship by `target_next` works
      and holds while it is promoted and demoted.
- [ ] **M4-T38 Anti-aliasing, the default.** `settings.anti_aliasing` is `smaa` now (it was no anti-aliasing). Compare the sheets in
      `reports/perf/m4-t38_compare/pairs/` (each the same frozen `battle` 300 frame in all six modes): `edges_2160.png` and
      `edges_1080.png` (a wing and a rock edge), `hull_detail_2160.png` and `hull_detail_1080.png` (struts, panel lines, the small
      parts), `stars_2160.png` and `far_dots_2160.png` (stars and small far objects must stay crisp single points), and
      `edges_native.png`, `hull_detail_native.png`, `stars_native.png` with the 3D at the 6K window's own size (taken through X11 before M4-T41; the game's window is now the 4K panel). Then fly the
      sandbox with `aa smaa`, `aa fxaa`, `aa msaa_4x` and `aa off`: say which you want as the default.
- [ ] **M4-T38 TAA in motion.** `aa taa`, then fly a `battle 300` run with hard turns: the stars and the nebula must stay steady and
      bright through a turn (no dimming, no trails; a measured softening: a star's brightest pixel fell from 0.59 to 0.45 of white
      on a turn under TAA, the light kept but spread, so say if the stars read soft), hull edges smooth, and a fast fighter crossing the view must leave no ghost.
      Bolts: under TAA they draw opaque (so they carry their own motion) and soften a little; check they read as bolts at 100 to 1 000
      m, and that no bolt flashes from somewhere else when it appears. Running lights of far ships may soften; far dots carry only the
      camera's turn, not their own motion, so a fast far dot may dim. Beams, missiles and hit flashes stay transparent (not measured). The sheet
      `reports/perf/m4-t38_compare/pairs/moving_2160.png` (no AA, SMAA, TAA, the live fight) shows what the agent saw.
- [ ] **M4-T38 TAA with motion blur.** `aa taa` and `blur on`: a hard turn smears the stars once (the blur), not twice; a still
      camera leaves the sky sharp.
- [ ] **M4-T41 The Wayland window.** The game now opens through Godot's Wayland display driver (it falls back to X11 when there
      is no Wayland session). Fullscreen should fill the panel at its own 3840x2160 (`get render.window`, `get render.display`)
      and look as sharp as before. Windowed, GNOME gives Godot no server-side title bar, so check that the window still has a
      usable title bar and can be moved and resized (libdecor draws it if installed). Say if anything about the window, the
      mouse, the pad or alt-tab behaves differently from before.
- [ ] **M4-T40 Upscaling, the default.** `settings.upscaler` is `native` (the 3D at the window's own size, as since T36), because
      FSR 2.2 measured dearer than native on this card. Compare the sheets in `reports/perf/m4-t40_compare/pairs/` (each the same
      frozen `battle` 300 frame in the 6K X11 window before M4-T41, twelve upscaler and preset turns): `edges.png`, `hull_detail.png`, `stars.png`,
      `far_dots.png` and `hud_text.png` (the HUD must be equally sharp in every turn). Then fly the sandbox with `upscale fsr1 quality`
      and `upscale native`: FSR 1.0 Quality costs about 1.4 ms less GPU at 6K, but the FPS gain is a few percent (+3 to +5 % in
      the agent's live round; the frame is CPU-bound); say if it looks as good as native, in which case it could be the default for
      a large window.
- [ ] **M4-T40 FSR 2.2 in motion.** `upscale fsr2 quality`, then a `battle 300` run with hard turns and fighters crossing close: no
      ghost behind a fast fighter, the stars steady through a turn, bolts still crisp at a distance (a sub-pixel point moving fast
      at half scale kept its light in a GPU measure but spread it, its brightest pixel 0.25 to 0.39 of white, so far bolts may read
      soft at `performance` and below). `aa` must say
      the anti-aliasing is held off, and `upscale native` must bring it back. If the ghosting is unacceptable, say so: FSR 3.1's
      upscaler in the native library is the fallback (Q60). The live sheets `moving_hull.png`, `moving_rocks.png` and
      `moving_left.png` (native, bilinear and FSR 1.0 Quality, FSR 2.2 Quality, Performance and Ultra Performance, each a different
      moment of the live fight) show what the agent saw: no ghosting, stars soft at Ultra Performance.
- [ ] **M4-T40 Low presets.** `upscale fsr1 ultra_performance` and `upscale fsr2 ultra_performance` (a third of the lines, for weaker
      GPUs): the stars and far dots enlarge into soft blobs; say whether that is acceptable for a low setting.
- [ ] **M4-T25 The 60 FPS bar at the screen (Q52).** The bar is yours to judge: 60 FPS at the screen with vsync on, fullscreen at the
      panel's 3840x2160. Fly `bench typical 58`, `bench battle 300`, `bench battle 500` and `bench battle 1000` (each with a long
      window, e.g. `bench battle 500 300`) and say where the picture stops being smooth. The agent measured with vsync off: the
      average over 60 FPS at every count (66 to 71 at 1 000), the 1 % low about 60 to 600 ships and 40 to 51 from 800. Through
      Wayland Godot keeps vsync on whatever the setting says and paces frames to at most about 145 FPS; say if anything feels
      different from X11 (`--display-driver x11` runs the old path).
- [ ] **M4-T30d Every other hull textured (AC7, Q44).** T30d merged on the agent's judgement; the sheets wait for your eye. Open
      `reports/perf/m4-t30d_sheets/`: the raider fighter (8 to 600 m), the nav buoy, the raider and Starfury break-up chunks, the
      cruiser, destroyer and carrier (300 m to 8 km), the B5 station (3, 8 and 20 km), and the Starfury's fine against coarse LOD
      sheets (Q45: the agent picked one; you may reverse it). Say which need a fix round.

# Play-testing M5 (Missions and Front End)

## Civilian escort (M5-T30; replaced Buoy defence)

Start the game windowed (`.tools/godot/godot --path .`), choose **Missions**, then **Civilian escort**. The briefing shows on the
right while it is focused. Each start from the menu draws a new seed, and with it a different civilian ship (any of the nine hulls;
**Retry** on the debrief keeps the ship). From the console, `play civilian_escort <seed>` picks the seed (seed 5 is the Skylark).

- **The intro.** The mission opens on the civilian beside NAV ALPHA with the belt somewhere ahead, then cuts to you and ALPHA 2
  coasting past the camera. The civilian's master hails over the fly-past; Control briefs once the camera is back, with your
  controls held until "the flight is yours". **A** or **Start** skips one shot.
- **The crossing.** The civilian flies to NAV BETA, 30 km out, at up to 120 m/s, threading the asteroid belt (24 km across, 8 km
  deep) in the middle of the route. The waypoint marks the civilian. Three raider waves jump in 6 to 12 km off it as it passes
  25 % (3 raiders, before the belt), 50 % (4, inside it) and 75 % (6, past it). Attacked, it runs (an Earth Alliance ship towards
  you or ALPHA 2, others straight away) and turns back onto its route a few seconds after the raiders are gone or dead.
- **Objectives.** Escort the civilian to NAV BETA (done when it is within 1.5 km of the buoy and every raider is down; failed if
  it is destroyed) and, optional, bring ALPHA 2 home. Losing yourself also ends it. A last line, then the debrief.
- **Console shortcuts.** `mission goto wave_one` (or `wave_two`, `wave_three`) skips ahead: the civilian is placed at the step's
  point and skipped waves leave no raider; `kill all` destroys every raider in play; `kill player` loses you; `mission skip`
  fast-forwards the step; `mission journal` lists what happened. `ai "<civilian name>"` shows whether it flies its route
  (`follow_path`) or runs (`retreat`).

Check (AC18, this mission's part):

- [ ] The intro reads well: the civilian at the buoy, the wing passing close, the lines readable in their time on screen.
- [ ] The pacing: the whole mission takes about 6 to 8 minutes when you fight each wave (Q40); the waves come neither too soon
      nor too late.
- [ ] The civilian: it runs when attacked and comes back to its route; a Saturn 8 gets through the belt without hitting rocks.
- [ ] The lines read as people, with the civilian's name filled in; the last line before the debrief is heard out.
- [ ] Losing the civilian, losing yourself and winning each end where you expect, with the right debrief.

## Target menu (M5-T25)

Fly the dogfight (`play dogfight`, or **Sandbox**, **Dogfight**) and a big battle (`bench battle 300 120` in the console).

```
B / Mouse 2 (tap)    the nearest enemy; tap again for the 2nd nearest; again for the nearest
B / Mouse 2 (hold)   the game pauses and the target menu opens at the left; it stays open when you let go
Right stick          points at a slice (centred, the highlight stays); arrow keys and moving the mouse do the same
A / Enter / Mouse 1  open the category, or pick the entry
B / Backspace / Mouse 2   back to the categories; from the categories, close and resume
Start / Esc          close it and open the pause menu
Wheel                cycles through every target, as before
```

The categories, clockwise from the top: **Enemies**, **Allies**, **Civilian**, **Unknown**, **Navigation**, **Objectives**. Each
opens a ring of its nearest five with **NONE** straight down. A ship you pick becomes the target and the game resumes. A beacon
or an objective becomes the waypoint (the diamond in the view, and a diamond round its dot on the radar); your target stays as it
was. NONE clears the target or the waypoint. A mission that sets its waypoint after your pick takes it back.

A contact more than 5 km away with no transponder is **unknown**: a grey dot on the radar, listed under Unknown with no name, and
`UNKNOWN` in grey if you target it. Inside 5 km it gets its colour and name. Allies, civilians and buoys broadcast and are always
known.

**The preview panel (M5-T43).** On a category's ring, the highlighted entry shows at the right: its hull as a slowly turning
green wireframe (only the near side's lines), its name in the IFF colour, class and faction, a hull bar, range and closing
speed (`+` closing). A Bokmai adds its cargo pods, a buoy and an objective have no hull bar, an unknown contact shows `NO ID`
and nothing about what it is, and a ship attacking you is flagged `ATTACKING YOU`. `play civilian_showcase` has every civilian
hull; `targetmenu highlight "saturn 8 tanker"` points at an entry without picking it and `state target_preview` shows the panel.

From the console: `targetmenu open`, `targetmenu pick enemies`, `targetmenu pick 1` (a slice, 0 at the top, clockwise) or
`targetmenu pick "raider 2"`, `targetmenu back`, `targetmenu close`; `state target_menu` shows it.

Check (T25's (H) items; screenshots of both rings are in `references/screenshots/T25 target menu/`):

- [ ] The ring reads at 1080 lines and at 4K: the category names, the ship names and ranges, the highlight.
- [ ] The pause and the resume mid-fight feel right, and nothing fires, turns or retargets as the game comes back.
- [ ] 0.35 s is the right hold (`set settings.target_hold_s 0.5` to try another).
- [ ] The tap: nearest, 2nd nearest, nearest. With no identified enemy it takes the nearest unknown contact: wanted, or not?
- [ ] Unknown contacts: the grey reads against the radar; a contact turning unknown again when it opens past 5 km is acceptable
      (the selected target keeps its name).
- [ ] Navigation and Objectives: the waypoint diamond and its radar mark are easy to find; the ship keeps facing its target.
- [ ] Keyboard and mouse: arrows (left or right alone take the upper slice), the mouse's direction, Enter, Backspace.
- [ ] **M5-T43 The preview panel** (screenshots in `references/screenshots/T43 target preview/`): the wireframes read as
      the ships (a raider, a Starfury, a Saturn 8, a Bokmai with its pods), with no far-side lines and no flat-panel
      diagonals; the dense spots are acceptable or want fewer lines; the turn's speed and angle; a long hull end-on is
      not too small; it reads at 1080 lines and at 4K; the class names; `NO ID` for an unknown contact; `ATTACKING YOU`
      appears on the raider that is on you. The first time a hull is highlighted its outline shows at once and its
      inner lines a moment later (up to 0.2 s for a Saturn 8).
