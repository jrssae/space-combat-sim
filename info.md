# Console commands

Every console command and state provider in the game. A task that adds, renames or removes one updates this file in the
same commit; `tests/integration/test_console_command_list.gd` fails when the file and the game disagree.

## Using the console

- The console is always on. Press the ` key to open or close it; Esc also closes it. Type
  `help` for the command list and `help <command>` for one command's usage. Tab completes names.
- State is read through `provider.key` paths (`get ship.speed`, `set weapons.mode linked`, `watch hull.hp`). `state` lists
  the providers and `state <provider>` shows all of one's keys. Only whitelisted keys exist.
- Several commands go on one line, separated by `;`. `#` starts a comment.
- Scripts after `--` on the command line:
  - `--console-exec="cmd; cmd"` runs commands once the first scene is ready.
  - `--console-file=<path>` runs a file of commands, one or more per line (`user://autoexec.cfg` runs first, if present).
  - `--console-strict` quits with exit code 1 at the first error.
  - Example: `.tools/godot/godot --headless --path . -- --console-strict --console-exec="wait 30; state ship; quit"`
- Details: `docs/architecture.md` §6.4, §15.13, §16.4 and §18.4.

Commands on this list are those on the `m5` branch, which holds all of M4 since the merge of `main` on 2026-11-08.

## Where a command exists

| Where | Meaning |
|---|---|
| always | Registered at launch by an autoload, so it works on the front end too. |
| front end, flight | Registered by nodes both the front end and the flight scene hold (the sky, the audio), so it exists in both. |
| front end | Registered by the front end alone (M7-T09: its Cobra-bay hangar backdrop), not in flight. |
| in flight | Registered by the main scene, so it exists whenever flight is loaded (free flight, sandbox, a mission), not on the front end. |
| AI ships | Exists while at least one AI-flown ship is in the scene. |
| mission | Exists only while a mission runs. |
| route | Exists only in a scenario where a ship leads a route (the instructor). |
| free flight | Exists only in a scenario with an encounter pools file (`data/encounters/<scenario_id>.json`): free flight. |
| benchmark | Exists only in a benchmark run. The test cannot boot a benchmark and skips these rows. |

## Commands

Arguments in `<angle brackets>` are required, `[square brackets]` optional, `a|b` a choice.

### Console

| Command | Arguments | Does | Where |
|---|---|---|---|
| `help` | `[command]` | List the commands, or show one command's usage | always |
| `clear` | | Clear the console log | always |
| `state` | `[provider]` | List the state providers, or every key = value of one (`*` marks unsaved settings) | always |
| `get` | `<path>` | Print one value, e.g. `get ship.speed` | always |
| `set` | `<path> <value>` | Type-checked write; `settings.*` applies now and stays session-only until `save` | always |
| `toggle` | `<path>` | Flip a writable bool | always |
| `default` | `<path>` | Reset a setting to its default (session only until `save`) | always |
| `save` | | Write all settings to `user://settings.cfg` | always |
| `revert` | | Reload the settings from disk, dropping unsaved changes | always |
| `watch` | `<path>` | Show a live value under the FPS counter (at most 8) | always |
| `unwatch` | `<path\|all>` | Stop watching a path, or all of them | always |
| `fps` | `[on\|off]` | Show or hide the FPS counter | always |
| `overlay` | `[on\|off]` | Show or hide the debug overlay (`settings.show_overlay`, F3); no argument toggles | always |
| `god` | `[on\|off]` | Toggle invulnerability for the player; session only | always |
| `timescale` | `<0.05..1>` | Debug slow motion | always |
| `exec` | `<file>` | Run commands from a `res://` or `user://` file | always |
| `wait` | `<frames>` | Delay the rest of the line by N physics frames (for scripts) | always |
| `screenshot` | `[path]` | Save the last rendered frame as a PNG (default `user://screenshots/`) | always |
| `quit` | `[code]` | Quit with an exit code (default 0) | always |

### Game flow and controls

| Command | Arguments | Does | Where |
|---|---|---|---|
| `menu` | | Go back to the front end | always |
| `play` | `<scenario_id> [seed]` | Play a scenario through the loading screen, as the menu does; the same seed plays the same run | always |
| `retry` | | From the debrief, play the same mission again (same scenario and seed) through the loading screen; refused anywhere else | always |
| `controls` | `[list\|use\|save\|show\|delete] [name\|action]` | Control profiles: list them, use or save one, show bindings, delete a saved one | always |
| `bind` | `<action> <binding>` | Add a binding to an action (session only until `controls save`) | always |
| `unbind` | `<action> <binding>` | Remove a binding from an action | always |

### Flight

| Command | Arguments | Does | Where |
|---|---|---|---|
| `respawn` | | Reset the ship to the scenario start (refused in a mission) | in flight |
| `pausemenu` | `[on\|off]` | Open or close the pause menu (the camera move starts behind it); no argument toggles | in flight |
| `pause` | `[on\|off]` | Pause or resume the game; no argument toggles; refused while the pause menu is open (resume from it) | in flight |
| `targetmenu` | `open\|pick <entry>\|highlight <entry>\|back\|close` | The target menu (a hold of the target button): `open` pauses the game and shows the categories; `pick` takes a slice 0-5 clockwise from the top or its label (`enemies`, `none`, `"raider 2"`) and opens that category or makes the pick; `highlight` points at an entry without picking it (the preview panel shows it); `back` goes back a ring; `close` resumes | in flight |
| `interact` | `[status\|run\|hold] [seconds]` | The hold-X interaction (M7-T27): `status` says what the selected target offers within reach (2 km: the gate's `jump`; the station bays' `dock` and `cargo` placeholders, which answer "not available"); `run` runs it as a completed 2 s hold would; `hold [s]` holds X that long through the input path (default the hold time plus a little), so the bar across the top fills and a short one cancels, for scripts and captures. Target a bay with `set targeting.selected "BABYLON 5 DOCKING BAY"` or `"BABYLON 5 CARGO BAY"` | in flight |
| `commsmenu` | `open\|pick <entry>\|highlight <entry>\|back\|close` | The comms menu (D-pad Right), a radial menu: `open` pauses the game and shows the wing orders; `pick` takes a slice 0-3 clockwise from the top or its label (`attack`, `"form on me"`, `engage`, `"cover me"`) and sends the order; `highlight` points at an entry without sending it; `back` goes back a ring or closes; `close` resumes | in flight |
| `scenario` | `[combat_sandbox\|free_flight\|instructor_route\|dogfight\|civilian_showcase\|belt_showcase\|station_launch\|station_showcase]` | Load a scenario for this session and reload the scene (`station_launch`: a launch from Babylon 5's Cobra bay Alpha 3 with your wing, M7-T08; `station_showcase`: the same launch, then free flight round Babylon 5 with its maintenance bots, a freighter backed in at the cargo bay and the `tour` command, M7-T12) | in flight |
| `window` | `<width> <height>` or `max\|normal` | Resize the window, or maximize or restore it | in flight |
| `throttle` | `<level>` | Hold both main pods at a level, 0..1, on top of the pilot's input | in flight |
| `assist` | `[on\|off]` | Toggle or set flight assist | in flight |
| `running_lights` | `[on\|off]` | Toggle or set the running lights (the wing follows) | in flight |
| `refuel` | `[kg]` | Refill the reaction-mass tank, or add kg | in flight |
| `camera` | `[cockpit\|chase]` | Switch camera; no argument toggles; during a cinematic, the camera to go back to after the shot | in flight |
| `look` | `<yaw> [pitch]` or `off` | Hold the view at an angle off the nose, for captures | in flight |
| `rebase` | `<dx> <dy> <dz>` | Shift the local origin by an offset in metres; nothing moves in universe terms | in flight |
| `frame` | `[status\|orbit <altitude km> [body]\|drop <altitude km> [body]\|rail <place>\|off]` | The free-falling frame's anchor (M6-T04). `orbit`, `drop` and `rail` carry the player (only the player: not its wing) and the frame to the new place; Babylon 5, the gate, the belts, the planet and every other world object keep their universe positions and velocities, and what is tied to the anchor (the station, the gate, buoys, belts) keeps riding the rail the scenario was laid out on (M7-T66). `orbit` puts the player on a circular orbit that high over the body (default `epsilon_iii`; out along +X, prograde along -Z), the frame on a free-falling anchor there: 400 km over Epsilon III leaves the station some 27 000 km away; `drop` (M7-T14) puts the player at rest that high over the body (`epsilon_iii` by default, `epsilon` the star) with the frame riding the body's rail, so the ship falls straight in under its whole pull (ALT counts down; the planet's atmosphere destroys it), refused outside the body's zone (D66: about 13 550 km over Epsilon III, 14.2 million km over the star); `rail <place>` puts the player at rest beside a place, riding its rail, as far from it as the scenario's start is (`rail babylon5`: back at the start, the station and the gate exactly where they were); `off`: no pull | in flight |
| `boost` | `<dvx> <dvy> <dvz>` | Velocity rebase by hand (M6-T05): the frame gains this velocity in m/s and every local velocity loses it, at the end of the tick; nothing moves differently | in flight |
| `ride` | | Velocity rebase back onto the anchor, at the end of the tick: the frame rides its anchor again | in flight |
| `reference` | `[auto\|<id>]` | The player's reference, the HUD's `REF` (M6-T08): what the speed, the brake, the assist and the ceiling read against; `auto` is Q6's pick (the nearest place whose broadcast holds the ship, else the dominant body), an id (`babylon5`, `jumpgate`, `epsilon_iii`) sets it as a mission does; no argument shows it | in flight |
| `gate` | `[status\|open\|close\|jump\|cancel\|target\|approach\|view] [arrival\|departure\|<view>] [hold_s]` | The jumpgate (M6-T14, T19): show it, open its vortex for an arrival (blue) or a departure (orange) after the arms' activation (held open 20 s to look at, or `hold_s` seconds: `gate open departure 1`), close it, start the player's jump through it (only from within 2 km of it, M7-T28: farther out it answers `out of range`), cancel the jump, target the gate, put the player 6 km in front of it facing it (or `gate approach <km>` that far: `gate approach 1.9`), or hold the camera on it for captures: `view front\|three_quarter\|close\|tip\|run_in\|side\|behind\|reference\|off` (`reference` is the pose of `references/jumpgate/jumpgate.png`, the maintainer's acceptance view); says so in a scenario with no gate | in flight |
| `vortex` | `[status\|open\|close\|view\|lod\|collapse] [arrival\|departure\|<radii>\|<level>] [radius_m]` | A stand-alone jump vortex (M6-T19), a debug tool: `open arrival\|departure` one ahead of the player facing them (mouth radius default 300 m, held 20 s; it starts as a blue-purple star that swells to its flare, M7-T23; held by no ship, which in play only a jump-capable ship could open, M6-T23), `close` every console point, `view [radii]` hold the camera in front of the newest open point (console, mission, encounter or bench), that many mouth radii away if given; `lod <auto\|0-6>` draws every vortex at one detail level (M6-T20: 0 every layer, 1 to 3 without the finest, fine and broad hairs, 4 without the patches and wisps, 5 without the fine cloud, 6 the soft disc), `auto` by size on screen again; `collapse` destroys the newest held point's opener, so the point collapses in its closing flash and kills every ship in its funnel (M6-T23) | in flight |
| `transit` | `[arrive\|depart\|carrier\|status] [gate\|point] [fighter\|capital] [none\|follow]` | Ships through a jump vortex's funnel (M6-T22), a debug tool: `arrive gate` brings a fighter (a pooled raider with no pilot) or a capital (a cruiser stand-in) out of the gate's black ring once its vortex is open, shrunk, growing as it flies out; `arrive point` brings one out of a point opened 2.5 km ahead of the player (a capital opens and holds its own; a fighter's is held by nothing, which no fighter could do in play, M6-T23); `carrier` brings a cruiser stand-in out of its own point 2.5 km ahead with two fighters coming out with it, after which it jumps back through a point it opens ahead of itself (M6-T23; `transit carrier point fighter follow` watches a fighter); `depart gate` sends one in from 1.7 km in front of the gate, down its funnel to the ring and its flash; `follow` holds a cinematic camera on the ship (behind it going in, ahead of it coming out); `status` counts the passages | in flight |

### Rendering and effects

| Command | Arguments | Does | Where |
|---|---|---|---|
| `flare` | `[on\|off]` | Toggle the star's lens flare | front end, flight |
| `blur` | `[on\|off]` | Toggle motion blur on fast turns | front end, flight |
| `sky` | `<stars\|nebula> [on\|off]` | Show or hide the star points or the nebula panorama; no state toggles | front end, flight |
| `scaled` | `[status\|epoch <hours>\|show\|hide]` | The scaled-space layer (M6-T10), the star and the planets at their true place and size: show it, look at the system `<hours>` later than the World's system time (moves the sun and the planet's phase for captures; 0 by default: the scenario sets the epoch, M6-T09), or draw the far bodies or not (to measure them) | front end, flight |
| `far` | `[status\|station\|view\|off] [gate\|station] [km]` | Far props (M6-T15): each big prop's draw path (near, shrunk toward the eye past the far plane, fading, far dot), distance and size on screen; `station` takes the station away or puts it back at the station's place (a scenario that names the station's rail places it for good, M6-T09); `view gate\|station <km>` holds the camera that far from it for captures; `off` ends the view | in flight |
| `station_lights` | `[status\|on\|off]` | Babylon 5's exterior lights (M7-T18): `status` (points, floods, the sections lit and the most floods one section sums, those following the drum); `off` hides the beacons, navigation lights, bay lamps and floods (for A/B captures), `on` shows them | in flight, station placed |
| `airlock` | `[status\|open\|shut\|auto]` | The main docking bay's inner doors (M7-T25): `status` (open, shut, opening or closing, how far, ships asking); `open` or `shut` holds them so (for captures); `auto` gives them back to the traffic, which opens them for a docking or undocking ship and shuts them once it is wholly through | in flight, station placed |
| `station` | `[info\|section\|heal\|spin\|goto] [name\|on\|off\|tour point] [damage] [amount]` | Babylon 5 in the game (M7-T06): `info` (where it stands, the drum's angle, each damage section's health, its collision); `section <name> damage <n>` takes n off one damage section as a hit would (a section at 0 is lost, the station goes on, Q5); `heal` makes every section whole; `spin on\|off` turns or holds the drum (held, its skin is still to a ship that touches it); `goto <tour point>` puts the player at one of the station's tour points at rest against it | in flight |
| `grid` | `[info\|free\|hold\|repair] [side\|mount\|all]` | Babylon 5's defense grid (M7-T07, D75): `info` (its mounts by kind and how many the core holds, the sides it is weapons free against, the mounts knocked out and each damaged one's health, the guns' shots, the interceptor batteries' pulses fired and the projectiles they met, shots the station's hull blocked); `free <side>` sets it weapons free against a hostile side as a shot at the station would (it never fires first); `hold [side]` holds fire again against that side or every side (the interceptors stay on); `repair <mount\|all>` makes a knocked-out or damaged mount whole again (`grid repair L9`) | in flight, station placed |
| `launch` | `[<alpha\|beta\|delta\|zeta> <1-6>\|wing <wing\|all>\|skip\|status\|cut\|seed <n\|off>\|preview <variant>]` | Cobra-bay launches from Babylon 5 (M7-T08): `launch <wing> <door>` puts the player on that door's rack (stored at 90 degrees, controls held), its wingmen on the arm's other racks and the second row, and plays the launch: the clamp turns each fighter nose-out, the doors fire in a 0.25 to 0.5 s ripple along the arm, each fighter is ejected nose first in 0.75 s, with a camera cut drawn from the shot pools; `launch wing <wing>` launches twelve AI Starfuries from that arm in two waves 10 s apart (the ally pool is topped up if short); a wing the player leads (Alpha, the player its Alpha 1) takes them as the player's wingmen, as many as its eleven slots hold, and they answer the wing orders (keys 1-4, the comms menu, `wing order`) (M7-T58); `launch wing all` launches every wing, one line each; `skip` jumps the player to the hand-off (under the spine it waits for clear space); `status` lists every launch's fighters; `cut` shows the last launch's camera cut and seed; `seed <n>` pins the cuts' seed (`off` seeds each launch again); `preview <variant>` plays one shot variant now on the player's launch, for look sheets | in flight, station placed |
| `tour` | `[<stop>\|stop\|status\|seed <n\|off>]` | The station's exterior tour (M7-T12): `tour` plays every stop on the cinematic camera, one shot each with a caption in the lower bar, in order (`bow`, `main_docking_bay`, `cobra_arm`, `defense_grid`, `heavy_cannons`, `drum`, `vanes`, `cargo_bay`); `tour <stop>` plays one; `stop` ends it; `status` says where it is; `seed <n>` pins the draws of the camera moves (`off` seeds each tour again). The Cobra arm and the defense grid (the light turrets on an arm's prong) are filmed on whichever wing's arm is out from under the spine for the whole shot. A or Start skips the tour. Not while the player is still launching (`launch skip` first) | in flight, station placed |
| `bots` | `[info\|hide\|show\|send\|peace\|battle\|follow\|skip\|goto\|cargo] [area\|n\|on\|off\|seconds\|view\|bayview] [metres\|hp]` | The station's maintenance bots (M7-T11, M7-T35): a crew of 12 living in the cargo bay. In peace 3 to 6 patrol, one bot an area at a time and irregularly (the spine, the fins port and starboard, the drum fore and aft riding its turn, and out to the jumpgate and along an arm); in a fight one bot goes to each damaged section or grid mount (up to 12) and adds 10 hp/s until it is whole (a knocked-out mount works again above zero, a lost section comes back). `info` (each bot's job, phase, speed and place, the areas and the last tick's cost); `hide` calls every bot home and holds it there; `show` lets them out again; `send <area>` sends a patrol now (`spine`, `fins_port`, `fins_starboard`, `drum_fore`, `drum_aft`, `gate`; one bot an area, so it fails while that area's bot is still out or on its way home); `peace on\|off` starts or stops the patrols (off calls them home); `battle [n] [hp]` damages n of the station's sections and mounts (default 6 by 600 hp: L10, green_zone, L3, vanes, command, I6, ...) and sounds the alarm, so the crew goes out to repair; `follow <n\|area\|off> [metres]` holds a cinematic camera behind bot n or the bot on a peace area or repair area (a section or mount name such as `spine` or `L10`; a peace area with none gets one sent); `skip [seconds]` runs the crew that far ahead at once (default 60, at most 1200) so a far patrol or a long repair can be watched now; `goto <n> [metres]` puts the player that far from bot n looking at it, for captures; `cargo [n\|off\|view\|bayview]` is `pods cargo` (the cargo scene is the cargo pods' since M7-T34; the bots carry no cargo) | in flight, station placed |
| `pods` | `[info\|hide\|show\|cargo] [n\|off\|view\|bayview]` | The station's cargo pods (M7-T34): the 6 m craft that carry every freighter's cargo between it and the cargo bay (`traffic freighter`), launching from the cargo bay's back wall and landing in it; in a fight away from the bay they let go and go home, and come back after the quiet (they heed the maintenance crew's alarm). `info` (each pod's phase and arms: reach 0..1, jaws 1 open to 0 shut); `hide` calls every pod home and holds it there (a block being carried away from the bay waits where it is); `show` lets them out again; `cargo [n]` backs a Saturn 3 in at the cargo bay's hold point (stern toward the bay, nose away, its cargo nearest it, held by an idle brain) and starts n cargo pods (default 5, at most 12) shuttling between it and the bay, staggered, reaching out at the Saturn and hiding in the bay's wall when fighting starts; `cargo off` removes them and returns the Saturn to the pool; `cargo view` puts the player 250 m from the Saturn toward the bay, to one side and above, looking at its cargo with the pods flying past (`cargo bayview` from just behind the Saturn, looking down the lane at the bay). `bots cargo ...` is the same | in flight, station placed |
| `traffic` | `[status\|dock\|undock\|freighter\|raid\|scramble\|auto\|clear] [near\|n\|wing\|on\|off]`, `freighter [type] [near\|hold\|show] [load]` | Traffic at Babylon 5 (M7-T10, Q8): `status` (with how many are inside the station: in the docking bay's black void, off the radar and out of every target list and shot, M7-T62); `dock` sends a civilian that fits the mouth (Skylark, Narn transport, Brezebel) into the main docking bay: it flies the lane on the drum's axis, matches the drum's roll (0.148 rad/s, lying square in the mouth) before the mouth, the inner doors open ahead of it, it flies wholly into the black void behind them, they shut and it leaves the world (M7-T25; `dock near` starts it on the lane, 1.2 km from the mouth, instead of at the jumpgate or 2.5 km farther out); `undock` brings one out of the void through the opened doors (they shut behind it) and away (through the gate when there is one); `freighter [type] [near\|hold\|show] [load]` flies a Saturn's cargo cycle (M7-T30, M7-T34): to the cargo bay's lane, a stop 700 m short of the hold point where it turns its stern to the bay, backing in to the hold point, the station's cargo pods (`pods`) carrying its cargo blocks or tanks into the cargo bay one by one (one cargo pod a Saturn 3 block, two a long block or tank, front and back, hands on its end faces; tanks turned onto their side before the mouth; in a fight they let go, the block waits, and they come back after the quiet), and away nose first once they are done. `type` is `saturn_3_freighter`, `saturn_4_transport`, `saturn_4_tanker`, `saturn_8_transport` or `saturn_8_tanker` (default each in turn); `near` starts it on the lane, `hold` already holding at the bay, `show` backing in its last 300 m with the cargo pods already on their way and the player put beside the lane to watch (the first block taken about 75 s later); `load` brings it without its cargo and the cargo pods carry it out of the bay onto it (its hull whole again when the last is on); `raid [n]` sends n raiders (default 6, at most 12) at the station (they answer whoever fires at them first and go for the grid's mounts) and has the wings in `data/station/traffic.json` meet it: a scrambled wing still out (launching, or at least half strong) takes the raid at will and nothing launches, the next wing in the file's order goes only when the ones before it are gone or below half strength (M7-T13 fix; the raiders and a full wing are built when the scenario loads); `scramble <wing>` launches one of the station's wings (as `launch wing`, the twelve a wing with a leader, engaging at will); `auto on\|off` starts or stops the run by itself (M7-T56: 5 civilians kept on their way between the jumpgate and the station, the run full from the start, one more arriving through the gate or undocking whenever one has docked or left, at least 40 s apart; it runs by itself in free flight with encounters on); `clear` returns every traffic ship to its pool | in flight, station placed |
| `aa` | `[off\|fxaa\|smaa\|msaa_2x\|msaa_4x\|taa]` | Show or set the 3D view's anti-aliasing, live (`settings.anti_aliasing`) | front end, flight |
| `upscale` | `[native\|bilinear\|fsr1\|fsr2] [preset\|<scale>]` | Show or set how the 3D view is rendered and enlarged to the window, live | front end, flight |
| `backdrop` | `<move\|wide\|close\|rack\|second> [time_s]` | The menu's Cobra-bay hangar (M7-T09, M7-T20): show it from its slow camera move (`time_s` sets how far into the move) or from the look sheets' fixed views: wide, one racked fighter close, the six racks, or the second row | front end |
| `sheet` | `<asset_id> [distance_m] [lit\|dark\|off] [wing:number\|-] [view]` | Park one idle ship of an asset ahead of the camera for a look sheet | in flight |
| `livery` | `<wing\|plain> [number] [ship]` | Paint a ship in a wing's livery with its number, to look at it | in flight |
| `fxburst` | `[hit\|ram\|explosion_sparks\|explosion_fragments\|explosion_gas\|debris\|intercept]` | Throw one burst of an effect 40 m in front of the camera | in flight |

### Combat

| Command | Arguments | Does | Where |
|---|---|---|---|
| `damage` | `<amount> [player\|target]` | Hit the player or the selected target with no shooter (god mode applies to the player) | in flight |
| `heal` | `[player\|target\|all]` | Restore the player's, the target's or every hull | in flight |
| `kill` | `[target\|all\|allies\|player]` | Destroy the target (any target with a hull, a capital too), every raider, every ally or the player now (bypasses god mode) | in flight |
| `relation` | `<a> [b] [friendly\|neutral\|hostile]` or `reset` | Show or set (this session only) how faction a regards faction b; `reset` reloads `data/factions.json` | in flight |

### Ships and waves

| Command | Arguments | Does | Where |
|---|---|---|---|
| `spawn` | `<raider\|ally> [options]` | Take a raider or an allied Starfury from the pool ahead of the player. Options: a behaviour (`idle`, `patrol`, `attack`, `aggro`, `ai`; allies take `idle` or `ai`), then distance in m, yaw and pitch in degrees, then `skill=`, `aggression=` and `lights=on\|off` | in flight |
| `despawn` | `[target\|all]` | Return the selected pooled ship, or every one, to the pool without effects | in flight |
| `wave` | `<start\|next\|stop\|restart> [index]` | Drive the raider waves | in flight |
| `wing` | `[order\|formation\|replenish] [value]` | Order the player's wing, change its formation or launch replacements; alone, show the wing | in flight |
| `ai` | `<name> [objective <target\|none>\|skill <rank\|0-1>\|aggression <level\|0-1>]` | Show an AI ship's behaviour and scores; send it at a target, or set its skill or aggression | AI ships |
| `encounters` | `[status\|on\|off\|next\|force\|clear] [raid\|patrol\|traffic]` | Free-flight encounters: show them, turn them on (building their pools) or off, start the next one now (the one after comes its gap later, 1 to 3 minutes at the default interval; M7-T56), force one of a kind (off the schedule), or return every encounter ship to its pool. In free flight traffic events fly the station's run from the jumpgate and a share of raids goes for Babylon 5 | free flight |

### Audio

| Command | Arguments | Does | Where |
|---|---|---|---|
| `sfx` | `<pulse_fire\|raider_fire\|hit_hull\|explosion\|main_burst\|rcs_burst\|warning_beep\|target_blip>` | Play a sound at the player | front end, flight |

### Performance

| Command | Arguments | Does | Where |
|---|---|---|---|
| `perf` | `[on\|off]` | Time every tick's stages (the `perf` provider); no argument toggles | in flight |
| `native` | `[bench]` | Say whether the native library is loaded (it is required since M4-T37); `bench` times calls into it | in flight |
| `bench` | `<furball\|spread\|transit\|battle\|typical> <n> [options]` | Fly a benchmark layout with n ships and write `reports/perf/<label>/` (`scripts/bench.sh`); in `battle` and `typical` every ship comes in out of a jump point, in waves of up to 100 points (M6-T20; the warm-up waits for the last wave): each capital opens its own and a fighter group comes through its side's capital point close by, or through the battle's own jumpgate 4 km below the first fight (M6-T23), or `arrive=placed` puts them in place at the start | in flight |
| `mines` | `[view\|set_off] [metres]` | A battle's mines (M7-T64): `view` puts the player that far (default 800 m) from the nearest mine in play, at rest and looking at it; `set_off` sets that mine off as a shot would, so it explodes and takes its group with it (for captures and play-tests of the blasts) | benchmark (battle layouts) |
| `station_scene` | `<near\|far\|off>` | Open the render comparison's station scene (M4-T27; `station` until M7-T06) | in flight |

### Missions

| Command | Arguments | Does | Where |
|---|---|---|---|
| `mission` | `[status\|skip\|goto\|objectives\|journal] [step]` | Show the running mission, fast-forward its step (`skip`), skip to a step (`goto <step>`), list its objectives or the world changes so far | mission |

## State providers

Read with `get <provider>.<key>`, list with `state <provider>`. Keys marked writable can be changed with `set`.

| Provider | Shows | Where |
|---|---|---|
| `settings` | Every setting, typed and ranged (all writable; `save` keeps them) | always |
| `debug` | `invulnerable` (writable): the player takes no damage | always |
| `time` | Sim time, time warp and the engine time scale | always |
| `game` | The game flow: `state`, the `request` being played and the `last_result` | always |
| `debrief` | The last mission's debrief: result, reason, time, kills, assists, wing losses, shots fired and hit, accuracy, objectives (`none` until a mission ends) | always |
| `controls` | The active control profile, the profile list and unsaved binding changes | always |
| `input` | Connected pads, whether the keyboard is masked, and the last flight, combat and UI commands | in flight |
| `ship` | The player's ship: position, velocity, speed (against its reference, M6-T08), the velocity that speed is read against (`rest_velocity`), angular rate, assist, pods, mass flow, fuel | in flight |
| `reference` | The player's reference (M6-T08): its `name` (the HUD's `REF`), `kind` (none, place or body), `rest_velocity` (a body's: the circular orbit's at the ship), `rest_accel`, the ship's `speed` against it, `range`, `altitude` above the body near (nan when none) and the reference a mission or the console set (`mission`) | in flight |
| `hull` | The player's hull points, fraction and destroyed state | in flight |
| `world` | The local origin, rebases and the automatic rebase distance; the frame's anchor (`anchor`, `anchor_state`), whether anything pulls near the local space (`gravity`) and the anchor's own pull (`anchor_pull`); the velocity rebase: the frame's velocity against its anchor (`origin_velocity`), `riding`, the threshold (`auto_boost_speed_mps`, 0 = off; 2 000 in flight), `boosts` and the last one's cost (`boost_us`); the anchor's velocity in the local frame (`rest_velocity`, M6-T08) and the ships destroyed on a planet (`planet_impacts`, `last_impact`); the shiftable nodes a rebase walks (`shiftables_in_play`) and the rocks that live as Jolt bodies near a ship (`rocks_live`, M6-T21) | in flight |
| `camera` | The active camera mode (cockpit, chase or cinematic; writable) and field of view, the cinematic shot playing and its time, the pause backdrop running (`backdrop`) and its loop phase | in flight |
| `gate` | The jumpgate: count, name, distance, targeted, whether the jump is offered (`prompt`), the vortex's phase (`activate`, `flash`, `grow`, `open`, `closing`, `end_flash` (its closing flash), `closed`) on the timings of `data/jump/vortex_look.json` (M7-T23), direction, age and openings, ships arrived, departed, waiting and departing, and the player's jump (state, time in it, completed, aborted, last abort) | in flight |
| `vortex` | Stand-alone jump points: how many are open (console, mission, encounter and bench points) and how many carry a light (`lit`), the newest open point's detail level (`lod`) and size on screen (`radius_px`), the forced level (`forced_lod`), how many `vortex open` opened, the newest console point's phase, mouth radius and depth, the newest held point's opener (`opener`), hold range (`hold_range_m`, twice its length by default) and distance from its mouth (`opener_distance_m`), the points ships hold now (`held`), points collapsed and the ships they killed (`collapses`, `collapse_kills`) and why the last one went (`last_collapse`: `out_of_range`, `opener_destroyed`, `opener_disabled`, `opener_gone`, `opener_through`) (M6-T23), and the gate vortex's fit (`gate_rim_m` the rim's half height, `gate_half_width_m` its half width, `gate_depth_m`, `gate_mouth_z_m`) | in flight |
| `transit` | Ships flying a jump vortex's funnel (M6-T22): how many now (`passing`), arrivals begun and done (`arrivals`, `arrived`), arrivals too small on screen (under 2 px) to fly the funnel, placed at once with the ring's flash (`unseen`), departures begun and done (`departures`, `departed`), the ring flashes showing (`flashes`) and shown so far (`flashes_shown`), the last and worst tick's cost (`step_us`, `worst_step_us`, profiling) | in flight |
| `carriers` | Carriers bringing raids in through their own jump points (M6-T23, `CarrierJumps`): carriers at work now (`active`), built at load (`built`) and free (`free`), brought in so far (`used`), fighters brought through their points (`fighters`), carriers gone back through their own point (`departed`), the newest one's state (`arriving`, `holding`, `leaving`) | in flight |
| `system` | The star system: its bodies (GM, radius, atmosphere top, zone), the places' positions from Epsilon III's centre, the gate's distance from the station and the station's orbit period; the scenario's epoch (`epoch_h`), the system time now (`time_h`) and where the scenario put the World (`anchor`: `place babylon5 at <x y z>` m, `body <id>` or `orbit <id>`, M6-T09) | in flight |
| `weapons` | Pulse cannon fire mode (writable), cooldown and capacitor charge | in flight |
| `targeting` | The selected target (writable), its range and closing speed, and the targets in sensor range | in flight |
| `interact` | The hold-X interaction (M7-T27): what a hold of X runs now (`offered`: jump, dock, cargo or none), whether it does anything yet (`available`), the hold's progress 0..1 (`progress`, the bar), the hold time (`hold_s`, `settings.interact_hold_s`), the HUD's prompt or answer line (`prompt`), interactions run (`runs`) and the last one with its answer (`last`) | in flight |
| `combat` | Bolts swept, hits resolved, mines a shot set off (`mines_struck`, M7-T64), the last hit and the cost of resolving them | in flight |
| `ram` | Rams resolved, the last one and the cost of the ram checks | in flight |
| `factions` | The faction ids, their listed relations and the friendly-fire mirror | in flight |
| `raiders` | The raider pool: size, free, alive, a list with hull and range, and the selected one's brain | in flight |
| `encounters` | Free-flight encounters: on, pools built, seed, interval, cap, ships in play by kind, the next event and its time, the one waiting, events started, ships released, the last event, the release check's work, the pools' build time, and the events through the jumpgate and ships waiting for it (`gate_events`, `gate_in_transit`) | free flight |
| `allies` | The allied pool, the same way | in flight |
| `belts` | The scenario's asteroid belts: belts, rocks, collision spheres and the multimeshes drawing them | in flight |
| `waves` | The raider waves: wave number, name, state, countdown, raiders alive and the kill tally | in flight |
| `wing` | The player's wing: name, order, formation, members and the last acknowledgement | in flight |
| `hud` | Whether the HUD shows, and where the lead, prograde and target marks are; `radar_plot_us` and `radar_paint_us`, the radar's frame cost (T34) | in flight |
| `screens` | The cockpit screens: shown, powered, paint counts and the lamps lit | in flight |
| `pause_menu` | Whether the pause menu is open, the page on top and how many pages are open | in flight |
| `comms_menu` | The comms menu (D-pad Right): whether it is open, the page, the highlighted entry, the ring's entries, orders picked, the last order, why it last closed and the focus pull | in flight |
| `target_menu` | The target menu: whether it is open, the ring and its entries, the highlight, the ship's target as the HUD names it, the HUD waypoint, the last pick, why it last closed, and what the last opening cost, and the focus pull's amount (`focus`) | in flight |
| `target_preview` | The target menu's preview panel: whether it shows, the entry and its kind, the hull drawn as a wireframe and its line count, whether its edges are still being found and its viewport renders, the panel's rows and flag, the meshes whose edges are kept, what the last edge search cost (in all, its longest frame, frames) and the panel's CPU work per frame | in flight |
| `render` | The renderer (`forward_plus` or `headless`), fps, frame time, draw calls, triangles, VRAM, far dots, GPU, display and window | in flight |
| `lights` | Which emitters light the scene this frame and what that costs | front end, flight |
| `sky` | The star points and the nebula panorama: loaded and shown | front end, flight |
| `backdrop` | The menu's Cobra-bay hangar (M7-T09, M7-T20): `loaded` (else M5's sky), `fighters` in the hall (racked and the second row), work `lights` in the light rig, the camera's `view` and `time_s` into its move | front end |
| `scaled` | The scaled-space layer (M6-T10): far `bodies` drawn, each one's angular size, direction, true distance and stand-in (`layout`), whether the key light follows the true sun (`has_sun`), `sun_direction`, the key light's factor in a planet's shadow (`key_light`, 0 to 1), the layer's epoch offset (`epoch_h`) and the planets drawn with their generated maps and haze (`mapped`, M6-T11) | front end, flight |
| `far` | Far props (M6-T15): how many big props a `FarProp` draws far out (`props`) and each one's draw path, distance, shrink, bounding radius and covered area on screen, cross-fade and range (`layout`) | in flight |
| `airlock` | The main docking bay's inner doors (M7-T25): `state` (open, shut, opening, closing), `open` (0..1), ships `asking`, `mode` (auto, or held open or shut) and the door `leaves` found | in flight, station placed |
| `station_lights` | Babylon 5's exterior lights (M7-T18): `points` (beacons, navigation lights, bay lamps), `floods`, `lit_sections` (hull sections with floods of their own), `max_section_floods` (the shader holds 64), `turning_floods` (floods following the drum over the other piece), `beacons_lit` (they show now), `beacon_level` (their brightness 0 to 1 over the 4 s fade, sim time), `shown` | in flight, station placed |
| `bay_lights` | The bays' red lamps (M7-T25, M7-T32: two down the main docking bay's mouth, two in the cargo bay): how many (`lamps`) and how many hold one of the light rig's slots now (`lit`) | in flight, station placed |
| `grid_lights` | The floodlights on the bow frame's heavy cannons and the bow tower's battery (M7-T57): how many (`floods`) | in flight, station placed |
| `station` | Babylon 5 (M7-T06): where it stands in the universe frame (`place`), the drum's turn (`drum_deg`) and whether it turns (`spinning`), each damage section's health (`sections`), how far its beacon is heard (`broadcast_km`) and its Jolt shapes and hit volumes per piece, with whether the core holds them as surfaces (`collision`) | in flight |
| `grid` | Babylon 5's defense grid (M7-T07): its mounts by kind and how many the core holds (`mounts`), the sides it is weapons free against (`free`), the mounts knocked out and each damaged one's health (`knocked_out`), the light and heavy guns' shots, the interceptor pulses fired, the projectiles they met (missiles) and shots the station's hull blocked (`shots`) | in flight, station placed |
| `launch` | Cobra-bay launches (M7-T08): how many run (`active`), whether the player is on a rack or rail with the controls held (`player`), each launch's fighters with bay, wave and phase (staged, moving, racked, rotating, held, dropping, released: `fighters`), the fighters holding under the spine (`held`), the player's last hand-off (`handoff`: bay, speed against the station, skipped), the scenario's start bay (`start_bay`), the last camera cut with its seed (`cut`) and the player launches this run (`launches`) | in flight |
| `tour` | The exterior tour (M7-T12): whether it is playing (`playing`), the stop on screen (`point`) and its camera move (`variant`), which stop of how many (`stop`, `stops`) and the tours this run (`tours`) | in flight |
| `bots` | The station's maintenance bots (M7-T11, M7-T35): the crew's size (`count`), bots out of the cargo bay (`out`), on patrol (`peace_out`), on a repair (`repair_out`), working at their spot now (`working`), in the bay (`hidden`), health added so far (`repaired_hp`), each bot out with its job and step (`jobs`), the peace areas with their bot or the seconds to the next trip and the damaged sections and mounts with theirs (`areas`), whether `bots hide` holds them (`held`), and the last physics tick's bot work in microseconds (`tick_us`, `tick_us_avg`) | in flight, station placed |
| `pods` | The station's cargo pods (M7-T34): how many are out or in (`count`), inside the cargo bay's wall (`hidden`), whether `pods hide` holds them (`held`), the cargo scene's pods and whether its Saturn 3 is at the hold point (`scene`), and each pod's phase and arms (`jobs`) | in flight, station placed |
| `traffic` | Traffic at Babylon 5 (M7-T10): whether the run between the jumpgate and the station keeps itself going (`auto`), the civilians it keeps on their way and the least time between its own starts (`lane_ships`, `lane_spacing_s`, M7-T56), its own civilians on their way now (`flow`), its ships in play (`alive`, `docking`, `undocking`, `freighters`, `raiders`), of them those inside the station (`inside`, M7-T62: in the docking bay's black void, unavailable to everyone outside), ships that docked behind the shut inner doors (`docked`) or came out and left (`undocked`), freighter cycles finished, cargo blocks the cargo pods carried into the cargo bay or onto freighters (`freighters_done`, `pods_in`, `pods_out`), each freighter at the bay with its hull, unloading or loading and pods carried (`cargo`), raids sent at the station (`raids`), the milliseconds the scenario's load spent building the raids' and wings' ships (`reserved_ms`, M7-T13) and the last thing started (`last_event`) | in flight |
| `aa` | The anti-aliasing mode, what the viewport uses, and the bolts' and sky's motion-vector state | front end, flight |
| `upscale` | The upscaler, its preset, the scale applied, sharpness and the window's and 3D view's lines | front end, flight |
| `post` | Lens flare and motion blur state, where the star is in the picture, and the strength of the jump flash's own lens flare now (`flash_flare`: the brightest gate or jump-point flash in view, 0 with none; M7-T23) | front end, flight |
| `livery` | The player's livery and every ship's in the world | in flight |
| `frame` | The frame's passes (plumes, flashes, impacts, far dots, bolts, turret models): their cost and what each walks | always |
| `core` | The native simulation core: rows, bodies, bolts, syncs, threads and their costs; the defensive turrets (`turrets`, `turret_shots`, `turret_shots_total`, `turret_us`, `turret_picks_stale`, `attackers`; M5-T21); gravity on the movers (`gravity_rows`: ships, tier rows and bolts the frame's pull reached last tick; `gravity_us`: the tier's and the bolts' share of its cost; M6-T07) | in flight |
| `flight` | The native flight batch: ships stepped and the gather and step costs | in flight |
| `tier` | The low-attention tier: radius, rates, fighter and capital rows, hulks, promotions and demotions | in flight |
| `perf` | The tick's stage timings and per-entity counts (on while `perf on` or a bench runs) | in flight |
| `mines` | A battle's mine belts (M7-T64): mines laid and in play, set off so far and by what (`by_trigger`: a hull hostile to the mine's side within 50 m; `by_touch`: any hull touching its 3 m body; `by_shot`: any bolt, beam or missile; `by_blast`: another mine's blast), whether a spent mine is laid again (`relays`, only during a bench run), and the nearest mine in play to the player (`nearest_m`, `nearest_side`, `nearest_hostile`) | benchmark (battle layouts) |
| `fx` | The particle emitter pool: emitters, busy, bursts thrown and the density in use | in flight |
| `debris` | The break-up chunk pool: sets, free sets, active chunks and held wrecks | in flight |
| `audio` | Sounds loaded, voices playing, engine voices (granted, sounding, the frame's work and the re-rank's work, `engine_rank_work`), `shots_culled` (gun shots skipped beyond earshot) and the SFX volume (writable) | front end, flight |
| `ai` | The AI ships and their behaviours, a count per behaviour and the AI's cost per tick | AI ships |
| `mission` | The running mission: id, title, state, result, step, objectives, time, trigger counts, waypoint, controls locked, jump points, whether holding X skips the opening now (`opening_skip`) and the HUD's hull bars (`hull_bars`: name and hull %, M7-T54) | mission |
| `dialog` | The comms panel: whether a line shows, its id, speaker callsign and text, lines queued, time left and lines shown | mission |
| `route` | The instructor's route: waypoint, count, lag, state and demo | route |
