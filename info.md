# Console commands

The debug console is always on. Press the ` key (the physical key left of 1) to open it; keyboard and mouse bindings are ignored while it is open. Type `help` for the full list, `help <command>` for one command's usage, and `state` for the list of state providers.

Every statement and its output is also printed to stdout as `[console] > cmd` and `[console] output`. Errors go to stderr as `[console] error: ...`.

Commands can also run from the command line (all flags go after `--`):

- `--console-exec="cmd; cmd"` runs the commands once the scene is ready.
- `--console-file=<path>` runs the commands in a file, one or more per line.
- `user://autoexec.cfg` runs first, if it exists.
- `--console-strict` quits with exit code 1 on the first error.

Example: `.tools/godot/godot --headless --path . -- --console-strict --console-exec="wait 30; state ship; quit"`

Paths are `provider.key`, for example `get ship.speed` or `set settings.show_fps on`.

Keep this file in step with the code: add a row here in the same commit that registers a command.

## Console basics

Source: `src/autoload/debug_console.gd`

| Command | Arguments | What it does |
|---|---|---|
| `help` | `[command]` | Lists commands, or shows one command's usage. |
| `clear` | | Clears the console log. |
| `state` | `[provider]` | Lists state providers, or shows every key = value of one (`*` marks unsaved settings). |
| `get` | `<path>` | Prints one value, for example `get ship.speed`. |
| `set` | `<path> <value>` | Writes a value with a type check; `settings.*` applies now and stays session-only until `save`. |
| `toggle` | `<path>` | Flips a writable bool. |
| `default` | `<path>` | Resets a setting to its default (session only until `save`). |
| `save` | | Persists all settings to `user://settings.cfg`. |
| `revert` | | Reloads settings from `user://settings.cfg`, dropping unsaved changes. |
| `watch` | `<path>` | Shows a live value under the FPS counter (at most 8, session only). |
| `unwatch` | `<path\|all>` | Stops watching a path, or all of them. |
| `fps` | `[on\|off]` | Shows or hides the FPS counter (toggles `settings.show_fps`). |
| `god` | `[on\|off]` | Toggles invulnerability (`debug.invulnerable`); session only, never saved. |
| `timescale` | `<0.05..1>` | Debug slow motion through `Engine.time_scale`, clamped to 0.05..1. |
| `exec` | `<file>` | Runs commands from a `res://` or `user://` file, one or more per line. |
| `wait` | `<frames>` | Delays the rest of the queue by N physics frames. |
| `screenshot` | `[path]` | Saves the last rendered frame as a PNG (default `user://screenshots/`); not available with `--headless`. |
| `quit` | `[code]` | Quits with an exit code (default 0). |

## Flight and ship

| Command | Arguments | What it does | Source |
|---|---|---|---|
| `assist` | `[on\|off]` | Toggles or sets flight assist. | `src/ship/ship.gd` |
| `running_lights` | `[on\|off]` | Toggles or sets the running lights (the wing follows). | `src/ship/ship.gd` |
| `refuel` | `[kg]` | Refills the reaction-mass tank, or adds kg. | `src/ship/ship.gd` |
| `throttle` | `<level>` | Holds both main pods at this level, 0..1 (debug; on top of the pilot's input). | `src/game/main.gd` |
| `respawn` | | Resets the ship to the scenario start. | `src/game/main.gd` |
| `rebase` | `<dx> <dy> <dz>` | Shifts the local origin by an offset in metres (`World.rebase`); nothing moves in universe terms. With the automatic rebase on, the next one brings the player back. | `src/world/world_frame.gd` |

## Game and scenario

| Command | Arguments | What it does | Source |
|---|---|---|---|
| `scenario` | `[combat_sandbox\|free_flight\|instructor_route\|dogfight]` | Loads a scenario: sets `settings.scenario` for this session and reloads the scene. | `src/game/main.gd` |
| `pause` | `[on\|off]` | Pauses or resumes the game (toggles with no argument). | `src/game/main.gd` |
| `window` | `<width_or_mode> [height]` | Resizes the game window (width and height in pixels), or `window max` / `window normal` to maximize or restore it. | `src/game/main.gd` |
| `wave` | `<start\|next\|stop\|restart> [index]` | Drives the waves: `start [index]` (1 = the first), `next` skips this wave, `stop`, `restart`. | `src/game/wave_director.gd` |

## Ships, wing and AI

| Command | Arguments | What it does | Source |
|---|---|---|---|
| `spawn` | `<raider\|ally> [options]` | Takes a raider or an allied Starfury from the pool ahead of the player, nose toward the player, turned by yaw then pitch. | `src/game/ship_pool.gd` |
| `despawn` | `[target\|all]` | Returns the selected pooled ship, or every one (raiders and allies), to the pool without effects. | `src/game/ship_pool.gd` |
| `wing` | `[order\|formation\|replenish] [value]` | Orders the player's wing (`wing order attack\|form\|engage\|cover`), changes its formation (`wing formation finger_four\|wedge\|line_abreast`) or launches replacements for its empty slots from the pool (`wing replenish`); alone, shows the wing. | `src/game/wing_director.gd` |
| `ai` | `<name>` | Shows an AI ship's behaviour, its state and every behaviour's last score. `ai <name> objective <target\|none>` sends it at a target from any broadcast range; `ai <name> skill <rookie\|regular\|veteran\|ace\|0-1>` and `ai <name> aggression <passive\|cautious\|balanced\|aggressive\|reckless\|0-1>` change its temperament. | `src/ai/ai_console.gd` |
| `relation` | `<a> [b] [friendly\|neutral\|hostile]` | Shows or sets (this session only) how faction `a` regards faction `b`; `relation reset` reloads `data/factions.json`. | `src/combat/faction_console.gd` |

## Combat

| Command | Arguments | What it does | Source |
|---|---|---|---|
| `damage` | `<amount> [player\|target]` | Hits the player or the selected target with no shooter (god mode applies to the player). | `src/combat/hit_resolver.gd` |
| `heal` | `[player\|target\|all]` | Restores the player's, the target's or every hull. | `src/combat/hit_resolver.gd` |
| `kill` | `[target\|all\|allies\|player]` | Destroys the selected target, every raider, every allied ship or the player now (bypasses god mode). | `src/combat/destruction_director.gd` |
| `fxburst` | `[hit\|ram\|explosion_sparks\|explosion_fragments\|explosion_gas\|debris]` | Throws one burst of an effect 40 m in front of the camera (for looking at it). | `src/combat/fx_pool.gd` |

## Camera, rendering and audio

| Command | Arguments | What it does | Source |
|---|---|---|---|
| `camera` | `[cockpit\|chase]` | Switches to the cockpit or chase camera; with no argument, toggles. | `src/camera/camera_rig.gd` |
| `look` | `<yaw> [pitch]` | Holds the view at yaw and pitch degrees off the nose, for captures; L3 and the mouse do nothing until `look off`. | `src/camera/camera_rig.gd` |
| `sky` | `<stars\|nebula> [on\|off]` | Shows or hides one part of the sky (M4-T30c): the star points or the nebula panorama (a hidden nebula no longer dims the stars behind it); with no state, toggles; answers "missing" when no panorama is loaded. For comparisons and measures. | `src/environment/space_environment.gd` |
| `sheet` | `<asset_id> [distance_m] [lit\|dark\|off] [wing:number\|-] [three_quarter\|top\|side]` | Parks one idle ship of the asset (`starfury_aurora`, `raider_fighter`) ahead of the camera at that distance for a look sheet (M4-T30a), hides the player's hull and turns the key star to light it from behind the camera (`lit`) or from behind the ship (`dark`), optionally in a wing's livery with a number (M4-T30b, e.g. `delta:7`, `plain:0`, `-` for none) and seen from above or the side instead of three-quarters on; `sheet off` puts everything back. M4-T30d: also the hulls that are not pooled ships, `nav_buoy`, `raider_fighter_chunks` and `starfury_aurora_chunks` (the break-up chunks spread apart), `capital_cruiser`, `capital_destroyer`, `capital_carrier` and `b5_station`. M4-T31: the look argument went (every hull has one look, its textured mesh). | `src/rendering/look_scene.gd` |
| `livery` | `<wing\|plain> [number] [ship]` | Paints a ship in a wing's livery with its number, for looking at it (M4-T30b): `player` (the default), `sheet` (the parked ship) or a ship's name such as `ALPHA 2`. Any wing name works: the named wings have their own, any other a stable pick, `plain` the field grey with no number. | `src/rendering/look_scene.gd` |
| `flare` | `[on\|off]` | Toggles or sets the star's lens flare. | `src/rendering/post_effects.gd` |
| `blur` | `[on\|off]` | Toggles or sets motion blur on fast turns. | `src/rendering/post_effects.gd` |
| `sfx` | `<pulse_fire\|raider_fire\|hit_hull\|explosion\|engine_loop\|thruster_loop\|warning_beep\|target_blip>` | Plays a sound at the player. | `src/audio/audio_director.gd` |

## Controls

| Command | Arguments | What it does | Source |
|---|---|---|---|
| `controls` | `[list\|use\|save\|show\|delete] [name\|action]` | Control profiles: lists them, uses or saves one, shows bindings, deletes a user profile. | `src/autoload/control_profiles.gd` |
| `bind` | `<action> <binding>` | Adds a binding to an action (session only until `controls save`); `pad:button:<0-14>`, `pad:axis:<0-5><+\|->`, `key:<name>`, `mouse:<1\|2\|3\|8\|9>`. | `src/autoload/control_profiles.gd` |
| `unbind` | `<action> <binding>` | Removes a binding from an action (session only until `controls save`). | `src/autoload/control_profiles.gd` |

## Performance

| Command | Arguments | What it does | Source |
|---|---|---|---|
| `perf` | `[on\|off]` | Times every tick's stages (the `perf` provider); toggles with no argument. | `src/perf/perf_probe.gd` |
| `bench` | `<furball\|spread\|transit\|battle\|typical> <n> [options]` | Flies a benchmark layout with n ships from the pools, measures `[seconds]` (30) after `warmup=<s>` (5), and writes `reports/perf/<label>/`. Options: `seed=<k> label=<name> probe=paired rebase_m=<m> sleep=keep rocks=<count>`. `battle` and `typical` (M4-T07) add the battle's stand-ins (capitals with turrets and interceptors, the asteroid field, the moon, carrier launches; four sides in `battle`) and print the mix; M4-T12 adds the missiles the mix keeps in flight, two beam lasers per capital and the mine belts, and the summary's weapons line; `rocks=` overrides the asteroid count (0 for none). M4-T20: `summary.json`'s `weapons.path` says whether the native rows (`perf_native_weapons`) or the GDScript stand-ins stepped the weapons. | `src/perf/bench_runner.gd` |
| `station` | `<near\|far\|off>` | Opens the render comparison's station scene (M4-T27): the Babylon 5 station stand-in about 3 km ahead, 10 capitals at rest around it, 80 invulnerable fighters (40 Starfuries, 40 raiders) fighting beside it and a planet 40 km off with its pull; puts the player at rest near the station or 11 km off, nose on it. Every hull is drawn as its textured mesh; `off` takes it all down. | `src/perf/station_scene.gd` |
| `native` | `[bench]` | Says whether the native library is loaded, whether `perf_native` is on and which path the probe takes; `bench` times calls into the library from GDScript against the GDScript code (M4-T05). | `src/perf/perf_probe.gd` |

## State providers

`state <provider>` prints every key of a provider; `get <provider>.<key>` prints one. The list below is what `state` prints in a normal run.

| Provider | Source |
|---|---|
| `ai` | `src/ai/ai_console.gd` (M4-T17 adds `thinks_native`: AI ships whose think ran in the native brains in the last tick, and `thinks_fallback`: native pilots the host declined, each holding its last command; M4-T33 adds `rows_events`: drivers the last rows batch handed something to do, and `row_commands`: AI ships flying their pilot's command from the core's row; M4-T35 adds `hosted`: drivers whose step the native host decides) |
| `allies` | `src/game/ship_pool.gd` |
| `audio` | `src/audio/audio_director.gd` |
| `camera` | `src/camera/camera_rig.gd` |
| `combat` | `src/combat/hit_resolver.gd` (M4-T15 adds `source` and `gather_us`) |
| `controls` | `src/autoload/control_profiles.gd` |
| `debris` | `src/combat/debris_pool.gd` |
| `debug` | `src/autoload/debug_console.gd` |
| `factions` | `src/combat/faction_console.gd` (registered by `src/combat/hit_resolver.gd`) |
| `core` | `src/perf/sim_core.gd` (M4-T15: the native simulation core: `path`, `rows`, `bodies`, `statics`, `bolts`, `syncs`, `sync_us`, `bolts_us`, `sync_calls`, `fallback_calls`, `attribute_reads`, `touched`; M4-T18: `threads`, `parallel_passes`, `parallel_min` and `flight_parallel_min` (both settable with `set core.<key> <n>`), `batch_us`, `batch_ships`, `live_workers`; the thread count itself is the setting `perf_threads`, `set settings.perf_threads <n>`; M4-T35: `bolt_path` (rows or nodes), `owned_bolts`, `cannons`, `cannon_us`, `bolt_step_us`, `shots`, `expired`, `bolt_draws`, `event_columns`, `body_direct`, `watched_selections`, `selection_clears`) |
| `flight` | `src/ship/flight_batch.gd` (M4-T10: the native flight batch: `path`, `ships`, `stepped`, `gather_us`, `step_us`, `positions`; M4-T15: `source`, `fallback_reads`) |
| `frame` | `src/rendering/frame_passes.gd` (M4-T36: the frame's passes, `plumes_us`, `flashes_us`, `impacts_us`, `lod_us`, and what each walks: `plumes`, `flashes`, `impacts`, `impact_pool`, `switchers`) |
| `fx` | `src/combat/fx_pool.gd` |
| `hud` | `src/hud/hud.gd` |
| `hull` | `src/combat/damageable.gd` |
| `input` | `src/autoload/debug_console.gd` |
| `lights` | `src/rendering/light_rig.gd` |
| `livery` | `src/rendering/look_scene.gd` (M4-T30b: `player`, the player's livery; `list`, every ship in the world and its livery) |
| `perf` | `src/perf/perf_probe.gd` |
| `post` | `src/rendering/post_effects.gd` |
| `raiders` | `src/game/ship_pool.gd` |
| `ram` | `src/combat/ram_resolver.gd` (M4-T15 adds `source` and `gather_us`) |
| `render` | `src/rendering/render_status.gd` (M4-T31: `renderer` (`forward_plus`, or `headless`), `fps`, `frame_ms`, `draw_calls`, `triangles`, `vram_mb`, `far_dots` (the ships in play drawn as far dots past `settings.far_ship_dot_m`, M4-T11), `gpu`, `gpu_ms`) |
| `screens` | `src/hud/cockpit_screens.gd` |
| `settings` | `src/autoload/debug_console.gd` (one key per settings entry) |
| `ship` | `src/ship/ship.gd` |
| `sky` | `src/environment/space_environment.gd` (M4-T30c: `stars`, `stars_shown`, `panorama`, `nebula_shown`) |
| `targeting` | `src/targeting/targeting_controller.gd` |
| `time` | `src/autoload/debug_console.gd` |
| `waves` | `src/game/wave_director.gd` |
| `weapons` | `src/weapons/pulse_cannon.gd` |
| `wing` | `src/game/wing_director.gd` |
| `world` | `src/world/world_frame.gd` |

One more provider, `route`, exists only while the `instructor_route` scenario is loaded (`src/game/main.gd`).
