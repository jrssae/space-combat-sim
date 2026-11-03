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

Commands on this list are those on the `m5` branch. Commands from other branches join the list when they merge.

## Where a command exists

| Where | Meaning |
|---|---|
| always | Registered at launch by an autoload, so it works on the front end too. |
| front end, flight | Registered by nodes both the front end and the flight scene hold (the sky, the audio), so it exists in both. |
| in flight | Registered by the main scene, so it exists whenever flight is loaded (free flight, sandbox, a mission), not on the front end. |
| AI ships | Exists while at least one AI-flown ship is in the scene. |
| mission | Exists only while a mission runs. |
| route | Exists only in a scenario where a ship leads a route (the instructor). |
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
| `controls` | `[list\|use\|save\|show\|delete] [name\|action]` | Control profiles: list them, use or save one, show bindings, delete a saved one | always |
| `bind` | `<action> <binding>` | Add a binding to an action (session only until `controls save`) | always |
| `unbind` | `<action> <binding>` | Remove a binding from an action | always |

### Flight

| Command | Arguments | Does | Where |
|---|---|---|---|
| `respawn` | | Reset the ship to the scenario start (refused in a mission) | in flight |
| `pause` | `[on\|off]` | Pause or resume the game; no argument toggles | in flight |
| `scenario` | `[combat_sandbox\|free_flight\|instructor_route\|dogfight]` | Load a scenario for this session and reload the scene | in flight |
| `window` | `<width> <height>` or `max\|normal` | Resize the window, or maximize or restore it | in flight |
| `throttle` | `<level>` | Hold both main pods at a level, 0..1, on top of the pilot's input | in flight |
| `assist` | `[on\|off]` | Toggle or set flight assist | in flight |
| `running_lights` | `[on\|off]` | Toggle or set the running lights (the wing follows) | in flight |
| `refuel` | `[kg]` | Refill the reaction-mass tank, or add kg | in flight |
| `camera` | `[cockpit\|chase]` | Switch camera; no argument toggles | in flight |
| `look` | `<yaw> [pitch]` or `off` | Hold the view at an angle off the nose, for captures | in flight |
| `rebase` | `<dx> <dy> <dz>` | Shift the local origin by an offset in metres; nothing moves in universe terms | in flight |

### Rendering and effects

| Command | Arguments | Does | Where |
|---|---|---|---|
| `fallback` | `[on\|off]` | Show the fallback meshes and panorama sky instead of splats | in flight |
| `relight` | `[on\|off]` | Light hulls, chunks and buoys with the scene's lights, or draw them flat | front end, flight |
| `flare` | `[on\|off]` | Toggle the star's lens flare | front end, flight |
| `blur` | `[on\|off]` | Toggle motion blur on fast turns | front end, flight |
| `lod` | `<ship\|all> <hero\|0-3\|auto>` | Force a ship's splat level; `auto` lets its size on screen decide | in flight |
| `fxburst` | `[hit\|ram\|explosion_sparks\|explosion_fragments\|explosion_gas\|debris]` | Throw one burst of an effect 40 m in front of the camera | in flight |

### Combat

| Command | Arguments | Does | Where |
|---|---|---|---|
| `damage` | `<amount> [player\|target]` | Hit the player or the selected target with no shooter (god mode applies to the player) | in flight |
| `heal` | `[player\|target\|all]` | Restore the player's, the target's or every hull | in flight |
| `kill` | `[target\|all\|allies\|player]` | Destroy the target, every raider, every ally or the player now (bypasses god mode) | in flight |
| `relation` | `<a> [b] [friendly\|neutral\|hostile]` or `reset` | Show or set (this session only) how faction a regards faction b; `reset` reloads `data/factions.json` | in flight |

### Ships and waves

| Command | Arguments | Does | Where |
|---|---|---|---|
| `spawn` | `<raider\|ally> [options]` | Take a raider or an allied Starfury from the pool ahead of the player. Options: a behaviour (`idle`, `patrol`, `attack`, `aggro`, `ai`; allies take `idle` or `ai`), then distance in m, yaw and pitch in degrees, then `skill=`, `aggression=` and `lights=on\|off` | in flight |
| `despawn` | `[target\|all]` | Return the selected pooled ship, or every one, to the pool without effects | in flight |
| `wave` | `<start\|next\|stop\|restart> [index]` | Drive the raider waves | in flight |
| `wing` | `[order\|formation\|replenish] [value]` | Order the player's wing, change its formation or launch replacements; alone, show the wing | in flight |
| `ai` | `<name> [objective <target\|none>\|skill <rank\|0-1>\|aggression <level\|0-1>]` | Show an AI ship's behaviour and scores; send it at a target, or set its skill or aggression | AI ships |

### Audio

| Command | Arguments | Does | Where |
|---|---|---|---|
| `sfx` | `<pulse_fire\|raider_fire\|hit_hull\|explosion\|main_burst\|rcs_burst\|warning_beep\|target_blip>` | Play a sound at the player | front end, flight |

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
| `controls` | The active control profile, the profile list and unsaved binding changes | always |
| `input` | Connected pads, whether the keyboard is masked, and the last flight, combat and UI commands | in flight |
| `ship` | The player's ship: position, velocity, speed, angular rate, assist, pods, mass flow, fuel | in flight |
| `hull` | The player's hull points, fraction and destroyed state | in flight |
| `world` | The local origin, rebases and the automatic rebase distance | in flight |
| `camera` | The active camera mode (writable) and field of view | in flight |
| `weapons` | Pulse cannon fire mode (writable), cooldown and capacitor charge | in flight |
| `targeting` | The selected target (writable), its range and closing speed, and the targets in sensor range | in flight |
| `combat` | Bolts swept, hits resolved, the last hit and the cost of resolving them | in flight |
| `ram` | Rams resolved, the last one and the cost of the ram checks | in flight |
| `factions` | The faction ids, their listed relations and the friendly-fire mirror | in flight |
| `raiders` | The raider pool: size, free, alive, a list with hull and range, and the selected one's brain | in flight |
| `allies` | The allied pool, the same way | in flight |
| `waves` | The raider waves: wave number, name, state, countdown, raiders alive and the kill tally | in flight |
| `wing` | The player's wing: name, order, formation, members and the last acknowledgement | in flight |
| `hud` | Whether the HUD shows, and where the lead, prograde and target marks are | in flight |
| `screens` | The cockpit screens: shown, powered, paint counts and the lamps lit | in flight |
| `pause_menu` | Whether the pause menu is open, the page on top and how many pages are open | in flight |
| `render` | The splat backend, fallback switch, fps, GPU name, splat budget and GDGS counters | in flight |
| `lights` | Which emitters light the scene this frame and what that costs | front end, flight |
| `lod` | Each ship's splat level and the splats drawn | in flight |
| `post` | Lens flare and motion blur state and where the star is in the picture | front end, flight |
| `fx` | The particle emitter pool: emitters, busy, bursts thrown and the density in use | in flight |
| `debris` | The break-up chunk pool: sets, free sets, active chunks and held wrecks | in flight |
| `audio` | Sounds loaded, voices playing, engine voices and the SFX volume (writable) | front end, flight |
| `ai` | The AI ships and their behaviours, a count per behaviour and the AI's cost per tick | AI ships |
| `mission` | The running mission: id, title, state, result, step, objectives, time, trigger counts, waypoint and jump points | mission |
| `route` | The instructor's route: waypoint, count, lag, state and demo | route |
