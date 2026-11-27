# ITF reference review: candidate features for Space Combat Simulator

## Scope and reading notes

Reviewed the game-owned Godot code and scene/resource organization in `references/itf`, with attention to ships, sensors, AI, factions, crew/workstations, scenarios/content, UI, and game startup. Third-party `addons/` were not treated as game features. This is a feature review, not an endorsement of copying ITF's implementation.

The reference contains useful systems, but some are prototypes or stubs. In particular, the order manager does not yet create meaningful orders, the faction command tree has incomplete dispatch tasks, the weapon capability is not connected to player input, sensor detection is a simple inverse-square check, and the crew save/order serialization is unfinished. Those are design leads, not complete reference implementations.

The simulator already has substantial overlapping systems: authored missions and tutorial, wing AI and player wing orders, faction relations and civilian roles, a target menu and unidentified contacts, carrier launches and station docking, settings/control remapping, career qualification, and large-scale star-system simulation. The candidates below emphasize new depth or extensions rather than re-listing those systems.

## Top priorities

### Faction doctrine and fleet-level behavior

**Value: High; strategic sandbox depth.** Add data-driven doctrine per faction: patrol strength, threat response, retreat thresholds, interception range, and carrier reserve policy. A fleet director could use nearby contacts and available ships to schedule patrols, intercepts, escorts, or defensive launches. Show the player a brief explanation of the response (for example, patrol launched because a sector has too few defenders).

**Reference basis:** ITF has hierarchical factions, faction-level detection lists, doctrine resources, command role behavior trees, and tasks intended to evaluate patrol needs and build launch assignments. The actual assignment/dispatch chain is incomplete, so the feature should use the simulator's existing AI/performance architecture rather than copy the task scripts.

**Simulator overlap:** The simulator already has faction relation data, wing AI, carrier launch logic, and patrol/encounter behavior. The added feature is strategic, faction-wide scheduling and legible doctrine—not basic fighter tactics.

### Persistent wing/fleet orders with status and reassignment

**Value: Medium-high; useful after fleet doctrine.** Make orders explicit data with an objective, target/location, issuer, priority, and state. Support follow, guard, patrol, intercept, escort, recall, and hold-position orders; expose completion/failure reasons and allow the player or mission script to reassign an order.

**Reference basis:** ITF has order and objective resource types and separate active/pending order fields on crew, but `OrderManager.create_order()` is only a stub and serialization intentionally omits orders. This is a clear opportunity for the simulator to implement the idea more completely.

**Simulator overlap:** Player wing commands already cover core tactical behavior. This would make those commands persist, report outcomes, and work consistently across scenario-controlled allied groups.

## Low-priority candidates

These may have high potential value, but defer their implementation until the two priorities above are designed or a concrete mission need raises one of them.

### Signature-based sensors and stealth

**Value: High; good fit for a combat milestone.** Give ships separate EM and neutrino signatures affected by engines, weapons, damage, and active emissions. Sensor suites could have different sensitivities; contacts could progress from bearing/range-only to identified as signal quality improves. Add a quiet-running mode with a flight/combat tradeoff, and let AI react to uncertain contacts.

**Reference basis:** ITF exposes EM/neutrino output and sensitivity on ships and sensors, then uses distance-squared signal falloff in `sensor_check()`. Its angular-size visibility rule is explicitly a TODO, so build on the concept rather than its current detection formula. The simulator already has unidentified-contact and transponder hooks, which provide a natural starting point.

**Simulator overlap:** Contact identification and faction transponders exist; signature propagation, sensor loadouts, and stealth tradeoffs would add the new play.

### Multi-station crew gameplay for capital ships

**Value: High; long-term/optional mode.** Expand capital-ship play beyond the current single-player fighter role with stations such as helm, weapons, sensors, engineering, and command. Each station can expose a focused interface and useful actions; NPC crew could fill unattended roles, while the player can switch stations or pilot with a crewed ship. For a first slice, let the player board a capital ship, operate its helm, and assign a small crew.

**Reference basis:** ITF models characters as ship crew, limits capacity, lets a character occupy a console, and attaches capabilities and role behavior trees to it. The pattern is useful, though the reference has limited working roles and incomplete order handling.

**Simulator overlap:** Capital ships, a capital helm milestone, command displays, and carrier operations already exist or are planned. A multi-role bridge is a larger shift in gameplay and should be gated by a focused prototype.

### Sensor and command stations as playable interfaces

**Value: Medium; can be introduced as mission-specific interaction.** Add a sensor console for contact classification, bearing/range uncertainty, signal history, and threat prioritization. A command station could display fleet assignments, patrol coverage, and launch/recall controls. Keep each interface focused so it adds decisions instead of duplicating the flight HUD.

**Reference basis:** ITF's console/capability pattern binds a station to one or more capabilities and optional HUD scenes. Its sensor implementation is minimal, but the composition pattern can guide a future UI.

**Simulator overlap:** Existing target/radar HUD, comms ring, station commands, and capital consoles cover parts of this already. Prefer extending them with actual sensor uncertainty and fleet state.

### Crew roster, pilot identity, and service history

**Value: Medium; campaign layer.** Track wing pilots across missions: name, role, assigned craft, qualification, kills, losses, and temporary status. Let missions promote, transfer, or ground pilots and reflect that state in launch rosters and debriefs. Keep it optional for free flight.

**Reference basis:** ITF has persistent pilot IDs, crew membership/faction data, and save/restore hooks, but its save manager only sketches player saving and crew orders are not serialized. The useful idea is continuity of crew identity, not the implementation.

**Simulator overlap:** The simulator already records tutorial qualification in career data and has persistent settings. A roster would extend that persistence into a campaign layer.

### More player craft and role-specific flight experiences

**Value: Medium; content expansion.** Make additional craft playable with different flight envelopes and cockpit/HUD layouts, especially the Thunderbolt or shuttle-class craft already present in the content plans. Use craft-specific handling, sensor, weapon, and mission affordances rather than simply swapping the model.

**Reference basis:** ITF has a flyable Aurora Starfury cockpit with in-world UI and custom camera nodes, plus scene-specific ship systems. Its broader fleet is not uniformly playable. The strongest transfer is to make a small number of craft feel meaningfully distinct.

**Simulator overlap:** The roadmap already calls for more player-driven craft. This should be prioritized by mission value and cockpit readiness rather than fleet size alone.

### Optional immersive cockpit / VR support

**Value: Exploratory.** Prototype head-tracked cockpit viewing and controller/HOTAS interaction with cockpit controls. Start with the Starfury cockpit and a short test scene; validate readability, comfort, and control mapping before expanding to missions.

**Reference basis:** ITF contains OpenXR action maps, a VR option, cockpit scenes, and camera/view switching. Those files show an intended direction; they do not by themselves establish a polished or complete VR experience.

**Simulator overlap:** The simulator has cockpit assets, input remapping, and camera modes. VR would require a separate implementation and usability pass.

### In-game diagnostics for inputs and ship systems

**Value: Medium-low; quality-of-life.** Add a pilot-facing input diagnostic page that shows the active device, axis values, dead zones, bindings, and current control profile. Consider an accessible status page for flight assist, target mode, and weapon readiness.

**Reference basis:** ITF has gamepad diagnostics and input remapping menus. The simulator already has strong control profiles and diagnostics; the transferable part is making the active device/binding state easy to inspect while configuring controls.

## Lower-priority ideas

- **Mod/content manifest workflow:** ITF resolves namespaced content IDs through manifests and allows later registrations to override earlier ones. This can help if the simulator commits to user mods or total conversions. For current development, existing data-driven ship/faction/scenario files may be enough; avoid adding a plugin/mod architecture without a concrete use case.
- **Console capabilities as reusable modules:** ITF's capability nodes let a workstation expose commands and optional behavior logic. This is a useful pattern if the simulator grows crew stations, but unnecessary abstraction for isolated interfaces.
- **Ship launch inventory and crew transfer:** ITF sketches hangar launch requests and crew placement. The simulator already has carrier bays and station docking. Persistent bay inventory or crew transfers would only be worth adding when a mission or campaign depends on them.

## Individual-craft AI comparison

### Finding

ITF does not provide a developed autonomous space-fighter pilot system that improves on Space Combat Simulator's AI. Its game-owned `ai/` code centers on an unfinished capital-ship command role. The example's richer behavior-tree collection lives under `demo/ai/` and controls 2D melee/ranged creatures, not spacecraft. The character's default behavior tree has an empty selector, and `Starfury_Pilot.gd` is effectively empty. The command tree's patrol evaluator and assignment builder are partial, while launch dispatch simply returns success. There is no space-pilot target selection, dogfight, evasion, or formation algorithm to adopt.

### Space Combat Simulator already has the stronger craft AI foundation

- **Decision selection:** `AiPilot` scores weighted behaviors each think, uses a stable tie order, stickiness, and minimum dwell to avoid behavior flicker, and permits emergency overrides. It exposes the selected behavior and scores to the game's console/debug tooling.
- **Combat behavior:** `BehaviourAttack` chooses targets from hostility, range, closing speed, threats to friendlies, target damage, and wing coordination. It drives explicit attack-run phases and seeded slashing passes; the same system supports objectives and non-firing instructor pilots.
- **Survival and personality:** `BehaviourEvade` responds to tail threats, incoming fire, and recent hits with seeded jinks; `BehaviourRetreat` uses hull and close-threat thresholds; `AiTemperament` scales aim, reaction time, fire discipline, evasiveness, aggression, and retreat behavior.
- **Flight and coordination:** guard, patrol/follow-path, formation, rally, ram, and idle behaviors share a common steering interface. `AiContext` carries orders, leader data, cohesion, cover, leash, and objective state. Wing logic also handles callsigns, gaps, losses, flights, docking, and rejoining.
- **Scale and determinism:** the GDScript implementation is the reference behavior, with a native batched path for large fights. Think rates and near/far simulation tiers address CPU cost. Seeded behavior randomness and parity tests keep outcomes reproducible.

Taken together, the simulator has implemented most of the individual-pilot capabilities that ITF's demo behavior trees illustrate, and has substantially more suitable 3D flight/combat logic. Replacing the utility system with ITF's behavior-tree add-on would add complexity without adding a demonstrated space-combat capability.

### Small, conditional opportunities

1. **Optional visual authoring for bespoke mission behaviors.** ITF's behavior trees demonstrate a designer-facing way to compose selectors, sequences, conditions, and actions. If mission authors need NPCs to perform multi-step scripts that are not well expressed as an objective, route, or existing profile, a small authoring layer could compose existing `AiBehaviour`/mission actions into a reusable playbook. Keep the utility pilot responsible for continuous flight and combat, and use a playbook only to choose high-level intent. This is a workflow improvement, not a proven combat-AI upgrade.
2. **More profile presets, only where tests/playtests show distinct outcomes.** ITF's demo uses separate behavior trees for archetypes such as chargers, skirmishers, and ranged attackers. The simulator already supports named `AiProfile` resources and per-behavior weights, skill, aggression, aim error, and attack tactics, so it can express these variants without importing the tree system. The useful follow-up is adding and validating specific profiles for craft that need distinct tactics, not making every ship use a different AI framework.
3. **Do not port the 2D flanking task directly.** ITF's sample chooses a left/right side in a 2D plane, falls back to the opposite side if the point is blocked, and moves by short random waypoints. That is a reasonable demo task for melee NPCs but does not account for 3D intercept geometry, inertial flight, thrust limits, line-of-fire, or formation cohesion. Space Combat Simulator already has dedicated attack passes and steering/avoidance; any future three-dimensional flanking maneuver should be designed and benchmarked against those systems instead.

**Recommendation:** make no individual-craft AI feature a priority based on ITF alone. Continue building on the current pilot, profile, and wing systems. Revisit visual behavior authoring only if bespoke mission behavior becomes costly to express and maintain.

### Source map for the AI comparison

- ITF's unfinished space-game command AI: [`character.gd`](../../references/itf/characters/character.gd), [`character_behavior_tree.tres`](../../references/itf/characters/character_behavior_tree.tres), [`command.tres`](../../references/itf/ai/roles/command.tres), [`dispatch_launch_orders.gd`](../../references/itf/ai/tasks/command/dispatch_launch_orders.gd).
- ITF's 2D demo combat tasks and sample craft pilot: [`select_flanking_pos.gd`](../../references/itf/demo/ai/tasks/select_flanking_pos.gd), [`pursue.gd`](../../references/itf/demo/ai/tasks/pursue.gd), [`in_range.gd`](../../references/itf/demo/ai/tasks/in_range.gd), [`Starfury_Pilot.gd`](../../references/itf/ships/earth%20alliance/aurora_starfury/Starfury_Pilot.gd).
- Simulator's individual pilot and coordination: [`ai_pilot.gd`](../../src/ai/ai_pilot.gd), [`ai_behaviour.gd`](../../src/ai/ai_behaviour.gd), [`ai_context.gd`](../../src/ai/ai_context.gd), [`behaviour_attack.gd`](../../src/ai/behaviour_attack.gd), [`behaviour_evade.gd`](../../src/ai/behaviour_evade.gd), [`ai_temperament.gd`](../../src/ai/ai_temperament.gd), [`wing.gd`](../../src/ai/wing.gd), [`tier_director.gd`](../../src/ai/tier_director.gd).
- Relevant simulator checks: [`tests/unit/test_ai_pilot_selection.gd`](../../tests/unit/test_ai_pilot_selection.gd), [`tests/unit/test_ai_temperament.gd`](../../tests/unit/test_ai_temperament.gd), [`tests/integration/test_ai_attack.gd`](../../tests/integration/test_ai_attack.gd), [`tests/integration/test_ai_evade.gd`](../../tests/integration/test_ai_evade.gd), [`tests/integration/test_ai_formation.gd`](../../tests/integration/test_ai_formation.gd), [`tests/integration/test_wing_orders.gd`](../../tests/integration/test_wing_orders.gd).

## Do not port as features

- ITF's networking and synchronization stack (excluded by request).
- `OrderManager` as currently written: its create/process methods are placeholders.
- The current fleet patrol behavior tree as a finished system: its launch dispatch returns success without dispatching, while its need calculation leaves threat-based response TODOs.
- The current sensor formula as a complete sensor model: it has no angular-size implementation or richer contact state.
- Its simple helm thruster assignment as an upgrade to the simulator's flight model. ITF's `Engines.gd` explicitly describes its thrust allocation as a cheat and leaves a more complete solver for later.

## Suggested priority order

1. Faction doctrine and fleet-level tasking.
2. Persistent tactical orders with status, reassignment, and clear completion/failure reasons.
3. Defer the remaining ideas listed under low-priority candidates unless a mission or campaign makes one immediately useful.

## Reference implementation map

- Ship signatures, crew capacity, boarding, launch, and simple sensor checks: [`Ship.gd`](../../references/itf/ships/Ship.gd), [`crew.gd`](../../references/itf/ships/crew.gd), [`sensor.gd`](../../references/itf/ship_systems/sensors/sensor.gd).
- Workstation occupancy, capability composition, helm assist, and command role: [`console.gd`](../../references/itf/ship_systems/workstations/console.gd), [`console_capability.gd`](../../references/itf/ship_systems/workstations/console_capability.gd), [`helm.gd`](../../references/itf/ship_systems/workstations/helm.gd), [`command.gd`](../../references/itf/ship_systems/workstations/command.gd).
- Faction hierarchy/doctrine and unfinished patrol planning: [`faction.gd`](../../references/itf/factions/faction.gd), [`faction_doctrine.gd`](../../references/itf/factions/faction_doctrine.gd), [`command.tres`](../../references/itf/ai/roles/command.tres), [`evaluate_patrol_need.gd`](../../references/itf/ai/tasks/command/evaluate_patrol_need.gd), [`build_patrol_assignments.gd`](../../references/itf/ai/tasks/command/build_patrol_assignments.gd), [`dispatch_launch_orders.gd`](../../references/itf/ai/tasks/command/dispatch_launch_orders.gd).
- Orders and content/scenario loading: [`order_manager.gd`](../../references/itf/orders/order_manager.gd), [`order_data.gd`](../../references/itf/orders/order_data.gd), [`content_registry.gd`](../../references/itf/content/content_registry.gd), [`scenario_loader.gd`](../../references/itf/scenario/scenario_loader.gd).
- Current simulator baseline: [`roadmap.md`](../roadmap.md), [`M8 tutorial vertical slice`](../milestones/m8-tutorial-vertical-slice.md), [`M10 factions and capital ships`](../milestones/m10-factions-and-capital-ships.md), and [`architecture.md`](../architecture.md).
