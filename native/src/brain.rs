// The native brain host (M4-T17, docs/architecture.md 17.13): the AI pilots' brains on the core's rows. The maths lives in
// `brain_maths.rs` and the behaviours in `brain_behaviours.rs` (both engine-free); this class binds the core, keeps one
// slot per pilot, picks nothing itself and hands answers over as packed numbers. The GDScript `AiPilot` is the facade and
// stays the reference. gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::sync::Mutex;

use godot::prelude::*;

use crate::brain_behaviours::{
    self, Brain, Context, Field, Inputs, KIND_NAMES, KINDS, MIRROR, Profile, Route, Scratch, Ship,
    Tactics,
};
use crate::brain_maths::{
    self, Capability, FlightCmd, Manoeuvre, Pcg, Pose, Temperament, deg_to_rad_lerp,
};
use crate::kernels::contact::{self, Grid, Query, Work};
use crate::row_commands::{CMD_LEN, EVENT_SELECT, EVENT_SETTLE};
use crate::rows::{Bolts, Rows};
use crate::sim_core::ScsSimCore;
use crate::threads::{self, Pass, Threads};

// `test_brain_parity`'s per-step layouts for a manoeuvre run.
const STEP_IN: usize = 23;
const STEP_OUT: usize = 16;
// `BodyKind` values of the rows that are obstacles (src/ai/body_kind.gd).
const KIND_MINE: u8 = 4;
const KIND_STATIC: u8 = 5;
// `ContactScan.SENSOR_RANGE_M`: the grid's cell size.
const SENSOR_RANGE_M: f64 = 5000.0;

/// `AiProfile` as the facade packs it: the nine weights in tie order, then stickiness, emergency_margin, min_dwell_s,
/// retreat_below, retreat_within_m, cruise_mps, aim_error_deg, fires, slashing, idle_hold.
pub const PROFILE_LEN: usize = KINDS + 10;
/// `RaiderTactics` as the facade packs it, in its field order.
pub const TACTICS_LEN: usize = 14;
/// A think's output: the four levels, strafe, rot, brake, fire, the wanted target in two halves, the dodge flags, the wish
/// (has, all axes, velocity), the behaviour in control, dwell, switches, the contacts seen, the raw and weighted scores by
/// kind, and the mirrored state.
pub const OUT_RAW: usize = 24;
pub const OUT_WEIGHTED: usize = OUT_RAW + KINDS;
pub const OUT_MIRROR: usize = OUT_WEIGHTED + KINDS;
pub const OUT_RAM: usize = OUT_MIRROR + MIRROR;
pub const OUT_LEN: usize = OUT_RAM + 1;
/// A batch think's output per ship (M4-T18): 1 when the host thought it (0: declined, the rest zeros), then `OUT_LEN`.
pub const BATCH_OUT: usize = OUT_LEN + 1;
/// A batch think's inputs per ship: the slot, the relation row's offset and length in the batch's relations, the
/// selection and the latest attacker (ints); dt, the hull, the latest hit and the latest bolt hit (floats).
pub const BATCH_INTS: usize = 5;
pub const BATCH_FLOATS: usize = 4;
/// A rows batch's inputs per ship (M4-T33): the slot, the relation row's offset and length, the latest attacker and
/// whether the ship is near the player (ints); dt, the latest hit and the latest bolt hit (floats). The hull and the
/// selection come from the ship's row.
pub const ROWS_INTS: usize = 5;
pub const ROWS_FLOATS: usize = 3;
/// `rows_events`' head: thinks near the player, thinks far, thinks declined, the most contacts a think saw; then a pair
/// (the ship's place in the batch, its events) for every ship whose driver has something to do.
pub const EVENTS_HEAD: usize = 4;
/// `set_fault`'s injected bug for the determinism test: a think adds to its main thrust what the worker's previous think
/// left behind, so it reads another row's output.
pub const FAULT_CARRY: i64 = 1;
/// `set_fault`'s injected panic: every think of a batch panics (without the panic hook's report).
pub const FAULT_PANIC: i64 = 2;

// What one worker thread fills for the thinks it runs: the query scratch, the picked lists, the keeps, and what the
// injected fault carries from one think to the next.
#[derive(Default)]
struct Worker {
    query: Query,
    scratch: Scratch,
    keep: Vec<i64>,
    carry: f64,
}

// One ship of a batch think: its brain (taken from the slot for the pass), its inputs and its packed output.
#[derive(Default)]
struct Item {
    slot: usize,
    brain: Option<Brain>,
    own_row: i64,
    relations: (usize, usize),
    selected_id: i64,
    last_attacker_id: i64,
    dt: f64,
    hull_fraction: f64,
    last_hit_s: f64,
    last_bolt_hit_s: f64,
    out: Vec<f64>,
    ok: bool,
    near: bool,
}

// What every think of a batch shares, read-only.
struct Shared<'a> {
    rows: &'a Rows,
    bolts: &'a Bolts,
    grid: &'a Grid,
    field: &'a Field,
    relations: &'a [u8],
    now_s: f64,
    friendly_fire: bool,
    origin: [f64; 3],
    nearest_k: i64,
    static_k: i64,
    fault: i64,
}

/// The AI pilots' native brains over the core's rows (or rows loaded from arrays, for the tests).
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsBrains {
    base: Base<RefCounted>,
    core: Option<Gd<ScsSimCore>>,
    own: Rows,
    own_names: Vec<GString>,
    own_bolts: Bolts,
    own_loaded: bool,
    grid: Grid,
    query: Query,
    grid_version: i64,
    field: Field,
    slots: Vec<Option<Brain>>,
    scratch: Scratch,
    keep_scratch: Vec<i64>,
    out: Vec<f64>,
    nearest_k: i64,
    static_k: i64,
    // The batch think's per-thread scratch, its ships and its output (M4-T18), kept between ticks.
    workers: Vec<Mutex<Worker>>,
    items: Vec<Item>,
    batch_out: Vec<f64>,
    // One thread for rows loaded from arrays (no core to give its threads).
    serial: Threads,
    fault: i64,
    pass_failures: i64,
    // The last rows batch's counts and events (M4-T33).
    events: Vec<i64>,
}

#[godot_api]
impl ScsBrains {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Reads the core's rows from now on (their grid is rebuilt whenever the core's rows change).
    #[func]
    fn attach_core(&mut self, core: Gd<ScsSimCore>) -> bool {
        self.own = Rows::default();
        self.own_bolts = Bolts::default();
        self.own_loaded = false;
        self.grid = Grid::default();
        self.grid.cell_m = SENSOR_RANGE_M;
        self.grid_version = -1;
        self.core = Some(core);
        true
    }

    /// Whether the host reads a core.
    #[func]
    fn on_core(&self) -> bool {
        self.core.is_some()
    }

    /// The nearest-k settings every think picks with (`ai_nearest_k`, `ai_nearest_static_k`).
    #[func]
    fn set_settings(&mut self, nearest_k: i64, static_k: i64) {
        self.nearest_k = nearest_k;
        self.static_k = static_k;
    }

    /// Takes rows from arrays instead of the core (the differential tests): one entry per row, the bases as three
    /// columns a row. Returns false, after logging why, when the arrays do not line up; the host then holds no rows.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn load_rows(
        &mut self,
        ids: PackedInt64Array,
        positions: PackedVector3Array,
        velocities: PackedVector3Array,
        bases: PackedVector3Array,
        radii: PackedFloat64Array,
        kinds: PackedByteArray,
        factions: PackedInt32Array,
        is_ship: PackedByteArray,
        hulls: PackedFloat64Array,
        target_ids: PackedInt64Array,
        reaches: PackedFloat64Array,
        names: PackedStringArray,
    ) -> bool {
        self.core = None;
        self.own = Rows::default();
        self.own_loaded = false;
        let n = ids.len();
        let lined_up = positions.len() == n
            && velocities.len() == n
            && bases.len() == n * 3
            && radii.len() == n
            && kinds.len() == n
            && factions.len() == n
            && is_ship.len() == n
            && hulls.len() == n
            && target_ids.len() == n
            && reaches.len() == n
            && names.len() == n;
        if !lined_up {
            godot_error!("ScsBrains.load_rows: array lengths differ ({n} ids); no rows are kept");
            return false;
        }
        let own = &mut self.own;
        own.ids = ids.as_slice().to_vec();
        own.body_ids = own.ids.clone();
        own.positions = positions.as_slice().to_vec();
        own.velocities = velocities.as_slice().to_vec();
        let b = bases.as_slice();
        own.bases = (0..n)
            .map(|i| {
                let (cx, cy, cz) = (b[i * 3], b[i * 3 + 1], b[i * 3 + 2]);
                Basis {
                    rows: [
                        Vector3::new(cx.x, cy.x, cz.x),
                        Vector3::new(cx.y, cy.y, cz.y),
                        Vector3::new(cx.z, cy.z, cz.z),
                    ],
                }
            })
            .collect();
        own.angular = vec![Vector3::ZERO; n];
        own.radii = radii.as_slice().to_vec();
        own.kinds = kinds.as_slice().to_vec();
        own.faction_ix = factions
            .as_slice()
            .iter()
            .map(|&f| u32::try_from(f).unwrap_or(u32::MAX))
            .collect();
        own.flags = vec![0; n];
        own.hull_ids = vec![0; n];
        own.handles = (1..=n as i64).collect();
        own.rigid = is_ship.as_slice().iter().map(|&b| b == 1).collect();
        own.is_static = own
            .kinds
            .iter()
            .map(|&k| k == KIND_MINE || k == KIND_STATIC)
            .collect();
        own.is_mine = own.kinds.iter().map(|&k| k == KIND_MINE).collect();
        own.hull_fraction = hulls.as_slice().to_vec();
        own.target_ids = target_ids.as_slice().to_vec();
        own.reach = reaches.as_slice().to_vec();
        own.name_keys = names
            .as_slice()
            .iter()
            .map(|s| s.to_string().to_lowercase())
            .collect();
        own.node_count = n;
        own.index_ids();
        self.own_names = names.as_slice().to_vec();
        self.grid = Grid::default();
        self.grid.cell_m = SENSOR_RANGE_M;
        self.grid.cells = contact::sorted_cells(&self.own.positions, SENSOR_RANGE_M);
        self.grid.max_static_radius = (0..n)
            .filter(|&i| self.own.is_static[i])
            .map(|i| self.own.radii[i].abs())
            .fold(0.0, f64::max);
        self.field
            .build(&self.own, &self.own_bolts, self.grid.cell_m);
        self.field.index_names(&self.own, wanted_names(&self.slots));
        self.own_loaded = true;
        true
    }

    /// The bolts in flight for loaded rows (the differential tests).
    #[func]
    fn load_bolts(
        &mut self,
        positions: PackedVector3Array,
        velocities: PackedVector3Array,
        factions: PackedInt32Array,
        shooters: PackedInt64Array,
    ) -> bool {
        let n = positions.len();
        if velocities.len() != n || factions.len() != n || shooters.len() != n {
            godot_error!(
                "ScsBrains.load_bolts: array lengths differ ({n} bolts); no bolts are kept"
            );
            self.own_bolts = Bolts::default();
            return false;
        }
        let b = &mut self.own_bolts;
        b.clear();
        b.ids = (0..n as i64).collect();
        b.positions = positions.as_slice().to_vec();
        b.velocities = velocities.as_slice().to_vec();
        b.last_steps = vec![Vector3::ZERO; n];
        b.faction_ix = factions
            .as_slice()
            .iter()
            .map(|&f| u32::try_from(f).unwrap_or(u32::MAX))
            .collect();
        b.shooters = shooters.as_slice().to_vec();
        b.kinds = vec![7; n];
        b.radii = vec![0.0; n];
        self.field
            .build(&self.own, &self.own_bolts, self.grid.cell_m);
        self.field.index_names(&self.own, wanted_names(&self.slots));
        true
    }

    // --- the slots -------------------------------------------------------------------------------------------------

    /// A brain for an `AiPilot`: its seed, its base profile and tactics (`PROFILE_LEN`, `TACTICS_LEN` numbers), the
    /// behaviours it has (kinds in tie order) and its temperament. Returns the slot, or -1 after logging why.
    #[func]
    fn create(
        &mut self,
        seed: i64,
        profile: PackedFloat64Array,
        tactics: PackedFloat64Array,
        kinds: PackedByteArray,
        skill: f64,
        aggression: f64,
    ) -> i64 {
        let Some(base) = profile_of(&profile, &tactics) else {
            godot_error!(
                "ScsBrains.create: a profile of {} and tactics of {} numbers do not line up; no slot",
                profile.len(),
                tactics.len()
            );
            return -1;
        };
        let brain = Brain::new(
            base,
            Temperament::new(skill, aggression),
            seed,
            kinds.as_slice(),
        );
        if let Some(free) = self.slots.iter().position(Option::is_none) {
            self.slots[free] = Some(brain);
            free as i64
        } else {
            self.slots.push(Some(brain));
            (self.slots.len() - 1) as i64
        }
    }

    /// Forgets a brain; its slot number may be reused.
    #[func]
    fn free_slot(&mut self, slot: i64) {
        if let Some(entry) = usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get_mut(i))
        {
            *entry = None;
        }
    }

    /// Brains held now.
    #[func]
    fn count(&self) -> i64 {
        self.slots.iter().filter(|s| s.is_some()).count() as i64
    }

    /// `AiPilot.reset`.
    #[func]
    fn reset(&mut self, slot: i64) {
        if let Some(b) = self.brain_mut(slot) {
            b.reset();
        }
    }

    /// `AiPilot.set_temperament`.
    #[func]
    fn set_temperament(&mut self, slot: i64, skill: f64, aggression: f64) {
        if let Some(b) = self.brain_mut(slot) {
            b.set_temperament(Temperament::new(skill, aggression));
        }
    }

    /// `AiPilot.add_behaviour` by kind (`KIND_NAMES` index); false for an unknown kind or one it has.
    #[func]
    fn add_behaviour(&mut self, slot: i64, kind: i64) -> bool {
        let Some(b) = self.brain_mut(slot) else {
            return false;
        };
        u8::try_from(kind).is_ok_and(|k| b.add_behaviour(k))
    }

    /// The ship this brain flies: its capability (as `test_brain_parity` packs it), where the bolts leave (ship frame), the
    /// weapon's muzzle speed and lifetime, the hull's bounding radius, the avoidance tie-break seed as the driver gives
    /// `AvoidanceMath.filter_seen` (`hash(display_name)`; the kernel takes its hash, made here), the body's instance id
    /// and the marker's (`Perception.self_id`).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn bind_ship(
        &mut self,
        slot: i64,
        cap: PackedFloat64Array,
        muzzle_local: Vector3,
        muzzle_speed_mps: f64,
        weapon_lifetime_s: f64,
        radius: f64,
        tie_hash: i64,
        own_body_id: i64,
        self_id: i64,
    ) {
        let capability = capability_of(&cap);
        if let Some(b) = self.brain_mut(slot) {
            b.ship = Ship {
                capability,
                muzzle_local,
                muzzle_speed_mps,
                weapon_lifetime_s,
                radius,
                tie_hash: brain_maths::hash_int(tie_hash),
                own_body_id,
                self_id,
            };
        }
    }

    /// The wing's view (`WingDirector.refresh` writes it every tick): the order, the leader and its target, the engage
    /// radius, the slot, the wingmates' ids, and the link to a leader out of sight (`link_valid` with its universe
    /// position in three doubles and its velocity).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn set_wing(
        &mut self,
        slot: i64,
        order: i64,
        leader_id: i64,
        leader_target_id: i64,
        engage_radius_m: f64,
        has_slot: bool,
        slot_offset: Vector3,
        wing_ids: PackedInt64Array,
        link_valid: bool,
        link_x: f64,
        link_y: f64,
        link_z: f64,
        link_velocity: Vector3,
    ) {
        if let Some(b) = self.brain_mut(slot) {
            let ctx: &mut Context = &mut b.ctx;
            ctx.order = u8::try_from(order).unwrap_or(0);
            ctx.leader_id = leader_id;
            ctx.leader_target_id = leader_target_id;
            ctx.engage_radius_m = engage_radius_m;
            ctx.has_slot = has_slot;
            ctx.slot_offset = slot_offset;
            ctx.wing_ids.clear();
            ctx.wing_ids.extend_from_slice(wing_ids.as_slice());
            ctx.link = if link_valid {
                Some([link_x, link_y, link_z])
            } else {
                None
            };
            ctx.link_velocity = link_velocity;
        }
    }

    /// `AiContext.clear_wing`.
    #[func]
    fn clear_wing(&mut self, slot: i64) {
        if let Some(b) = self.brain_mut(slot) {
            b.ctx.clear_wing();
        }
    }

    /// `AiContext.objective_name` ("" for none; matched case-insensitively).
    #[func]
    fn set_objective(&mut self, slot: i64, name: GString) {
        if let Some(b) = self.brain_mut(slot) {
            b.ctx.objective_key = name.to_string().to_lowercase();
            b.ctx.objective_id = 0;
        }
    }

    /// The guard post (`BehaviourGuard.attach`): a fixed universe point (`has_post`, three doubles) or a ship by name with
    /// an offset in its body frame, and the radius. An empty name and no post clear it.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn set_guard(
        &mut self,
        slot: i64,
        has_post: bool,
        post_x: f64,
        post_y: f64,
        post_z: f64,
        name: GString,
        offset: Vector3,
        radius_m: f64,
    ) {
        if let Some(b) = self.brain_mut(slot) {
            b.ctx.guard_post = if has_post {
                Some([post_x, post_y, post_z])
            } else {
                None
            };
            b.ctx.guard_key = name.to_string().to_lowercase();
            b.ctx.guard_id = 0;
            b.ctx.guard_offset = offset;
            b.ctx.guard_radius_m = radius_m;
        }
    }

    /// The route the pilot leads (`BehaviourFollowPath.attach`): four numbers a waypoint (its universe position and its
    /// hold), each waypoint's demo (`Manoeuvres.NAMES` index plus one, 0 for none), the cruise speed, the pace ship's id,
    /// whether it loops and whether it yields to an attack.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn set_route(
        &mut self,
        slot: i64,
        points: PackedFloat64Array,
        demos: PackedByteArray,
        cruise_mps: f64,
        pace_id: i64,
        loops: bool,
        yield_to_attack: bool,
    ) -> bool {
        let p = points.as_slice();
        let d = demos.as_slice();
        if !p.len().is_multiple_of(4) || d.len() != p.len() / 4 {
            godot_error!(
                "ScsBrains.set_route: {} numbers and {} demos do not line up; no route",
                p.len(),
                d.len()
            );
            return false;
        }
        let Some(b) = self.brain_mut(slot) else {
            return false;
        };
        let mut route = Route {
            cruise_mps,
            pace_id,
            loops,
            yield_to_attack,
            ..Default::default()
        };
        for (i, w) in p.as_chunks::<4>().0.iter().enumerate() {
            route.points.push([w[0], w[1], w[2]]);
            route.holds.push(w[3]);
            route.demos.push(d[i]);
        }
        b.ctx.route = Some(route);
        true
    }

    #[func]
    fn clear_route(&mut self, slot: i64) {
        if let Some(b) = self.brain_mut(slot) {
            b.ctx.route = None;
        }
    }

    /// `BehaviourRam.commit` from outside (the tests call it on the GDScript object; the facade mirrors it).
    #[func]
    fn ram_commit(&mut self, slot: i64, target_id: i64) {
        if let Some(b) = self.brain_mut(slot) {
            b.ram_commit(target_id);
        }
    }

    /// `BehaviourRam.commit` between thinks: the id committed to (the last think's attack target, else its nearest
    /// hostile), 0 when there was none.
    #[func]
    fn ram_commit_now(&mut self, slot: i64) -> i64 {
        self.brain_mut(slot).map_or(0, Brain::ram_commit_now)
    }

    /// One think for `slot`: `relations` is the ship's `Factions.Relation` to each faction of the table; then the sim
    /// time, the time since its last think, its hull 0..1, its selection (0 for none), its latest hit and bolt hit (sim
    /// time, -INF for none), its latest attacker, `settings.friendly_fire`, and the frame origin as three doubles. The
    /// perception is picked from the rows inside. Returns `OUT_LEN` numbers, or none when the ship has no row this tick.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn think(
        &mut self,
        slot: i64,
        relations: PackedByteArray,
        now_s: f64,
        dt: f64,
        hull_fraction: f64,
        selected_id: i64,
        last_hit_s: f64,
        last_bolt_hit_s: f64,
        last_attacker_id: i64,
        friendly_fire: bool,
        origin_x: f64,
        origin_y: f64,
        origin_z: f64,
    ) -> PackedFloat64Array {
        let Some(index) = usize::try_from(slot).ok().filter(|&i| i < self.slots.len()) else {
            return PackedFloat64Array::new();
        };
        let Some(mut brain) = self.slots[index].take() else {
            return PackedFloat64Array::new();
        };
        let inputs = Inputs {
            relations: relations.as_slice(),
            own_body_id: brain.ship.own_body_id,
            now_s,
            dt,
            hull_fraction,
            self_id: brain.ship.self_id,
            selected_id,
            last_hit_s,
            last_bolt_hit_s,
            last_attacker_id,
            friendly_fire,
            origin: [origin_x, origin_y, origin_z],
            nearest_k: self.nearest_k,
            static_k: self.static_k,
        };
        self.refresh_grid();
        let guard = self.core.as_ref().map(|c| c.bind());
        let (rows, bolts, own_row): (&Rows, &Bolts, i64) = match &guard {
            Some(c) => (&c.rows, &c.bolts, c.row_for_kernel(brain.ship.own_body_id)),
            None => (
                &self.own,
                &self.own_bolts,
                self.own
                    .body_ids
                    .iter()
                    .position(|&b| b == brain.ship.own_body_id)
                    .map_or(-1, |r| r as i64),
            ),
        };
        let mut out = PackedFloat64Array::new();
        if own_row >= 0 {
            let result = brain.think(
                rows,
                bolts,
                &mut Work {
                    grid: &self.grid,
                    query: &mut self.query,
                },
                &self.field,
                own_row as usize,
                &mut self.scratch,
                &mut self.keep_scratch,
                &inputs,
            );
            pack_output(&brain, &result, &mut self.out);
            out = PackedFloat64Array::from(self.out.as_slice());
        }
        drop(guard);
        self.slots[index] = Some(brain);
        out
    }

    /// Every thinking ship of a tick in one call (M4-T18), across the core's worker threads: per ship `BATCH_INTS` ints
    /// (slot, relation row offset and length in `relations`, selection, latest attacker) and `BATCH_FLOATS` floats (dt,
    /// hull, latest hit, latest bolt hit), the rest as `think` takes it. Returns `BATCH_OUT` numbers per ship in the
    /// order given: 1 and `think`'s output, or 0 and zeros when declined (no slot, a slot twice, no row). Each think reads
    /// the frozen rows and writes only its own brain and its output, so the result does not depend on the threads.
    /// `rows_version` is the core's version the drivers took their scan at: when the rows moved since (a resync or a
    /// rebase between the drivers and the batch), every ship is declined, so each holds its last command, as T17's
    /// per-ship check did. A think that panics declines the whole batch too, its brains kept (`pass_failures`).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn think_batch(
        &mut self,
        ints: PackedInt64Array,
        floats: PackedFloat64Array,
        relations: PackedByteArray,
        now_s: f64,
        friendly_fire: bool,
        origin_x: f64,
        origin_y: f64,
        origin_z: f64,
        rows_version: i64,
    ) -> PackedFloat64Array {
        let n = ints.len() / BATCH_INTS;
        if ints.len() != n * BATCH_INTS || floats.len() != n * BATCH_FLOATS {
            godot_error!(
                "ScsBrains.think_batch: {} ints and {} floats do not make whole ships; nothing thought",
                ints.len(),
                floats.len()
            );
            return PackedFloat64Array::new();
        }
        self.refresh_grid();
        let iv = ints.as_slice();
        let fv = floats.as_slice();
        let rel = relations.as_slice();
        if self.items.len() < n {
            self.items.resize_with(n, Item::default);
        }
        for (k, item) in self.items[..n].iter_mut().enumerate() {
            let i = &iv[k * BATCH_INTS..(k + 1) * BATCH_INTS];
            let f = &fv[k * BATCH_FLOATS..(k + 1) * BATCH_FLOATS];
            let start = usize::try_from(i[1]).unwrap_or(0).min(rel.len());
            let len = usize::try_from(i[2]).unwrap_or(0).min(rel.len() - start);
            item.slot = usize::try_from(i[0]).unwrap_or(usize::MAX);
            item.brain = self.slots.get_mut(item.slot).and_then(Option::take);
            item.relations = (start, start + len);
            item.selected_id = i[3];
            item.last_attacker_id = i[4];
            item.dt = f[0];
            item.hull_fraction = f[1];
            item.last_hit_s = f[2];
            item.last_bolt_hit_s = f[3];
            item.ok = false;
            item.near = false;
        }
        self.run_batch(
            n,
            rel,
            now_s,
            friendly_fire,
            [origin_x, origin_y, origin_z],
            rows_version,
            false,
        )
    }

    /// The rows path of `think_batch` (M4-T33): per ship `ROWS_INTS` ints and `ROWS_FLOATS` floats, the hull and the
    /// selection read from its row; returns the same output. Each think's command (its flight numbers and trigger) is
    /// written into the core's commands, which the flight step flies the same tick, and `rows_events` then holds the
    /// counts and the ships whose drivers have something to do: a first command from the row, a changed trigger, or a
    /// wanted target the ship has not selected. A declined think writes nothing, so its ship flies the row's command on.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn think_batch_rows(
        &mut self,
        ints: PackedInt64Array,
        floats: PackedFloat64Array,
        relations: PackedByteArray,
        now_s: f64,
        friendly_fire: bool,
        origin_x: f64,
        origin_y: f64,
        origin_z: f64,
        rows_version: i64,
    ) -> PackedFloat64Array {
        let n = ints.len() / ROWS_INTS;
        self.events.clear();
        self.events.resize(EVENTS_HEAD, 0);
        if ints.len() != n * ROWS_INTS || floats.len() != n * ROWS_FLOATS {
            godot_error!(
                "ScsBrains.think_batch_rows: {} ints and {} floats do not make whole ships; nothing thought",
                ints.len(),
                floats.len()
            );
            return PackedFloat64Array::new();
        }
        self.refresh_grid();
        let iv = ints.as_slice();
        let fv = floats.as_slice();
        let rel = relations.as_slice();
        if self.items.len() < n {
            self.items.resize_with(n, Item::default);
        }
        for (k, item) in self.items[..n].iter_mut().enumerate() {
            let i = &iv[k * ROWS_INTS..(k + 1) * ROWS_INTS];
            let f = &fv[k * ROWS_FLOATS..(k + 1) * ROWS_FLOATS];
            let start = usize::try_from(i[1]).unwrap_or(0).min(rel.len());
            let len = usize::try_from(i[2]).unwrap_or(0).min(rel.len() - start);
            item.slot = usize::try_from(i[0]).unwrap_or(usize::MAX);
            item.brain = self.slots.get_mut(item.slot).and_then(Option::take);
            item.relations = (start, start + len);
            item.selected_id = 0;
            item.last_attacker_id = i[3];
            item.near = i[4] != 0;
            item.dt = f[0];
            item.hull_fraction = 1.0;
            item.last_hit_s = f[1];
            item.last_bolt_hit_s = f[2];
            item.ok = false;
        }
        let out = self.run_batch(
            n,
            rel,
            now_s,
            friendly_fire,
            [origin_x, origin_y, origin_z],
            rows_version,
            true,
        );
        self.write_commands(n);
        out
    }

    /// The last `think_batch_rows`' counts and events (`EVENTS_HEAD`, then pairs).
    #[func]
    fn rows_events(&self) -> PackedInt64Array {
        PackedInt64Array::from(self.events.as_slice())
    }

    /// Batches a panic declined (each holding its brains and its ships' last commands).
    #[func]
    fn pass_failures(&self) -> i64 {
        self.pass_failures
    }

    /// Injects a bug for the determinism or the panic test (`FAULT_CARRY`, `FAULT_PANIC`), or none (0).
    #[func]
    fn set_fault(&mut self, kind: i64) {
        self.fault = kind;
    }

    /// The rows the last think picked: `[contacts, statics, broadcasts]` (the tests compare them with the scan's).
    #[func]
    fn last_lists(&self) -> VarArray {
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(self.scratch.contacts.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(self.scratch.statics.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(self.scratch.broadcasts.as_slice()).to_variant());
        out
    }

    /// `AiPilot.describe` for the behaviour in control: `behaviour`, `state`, `for_s`, its own fields and the `scores`
    /// (weighted, by id). Names of contacts are looked up in the rows by id.
    #[func]
    fn describe(&self, slot: i64) -> VarDictionary {
        let mut dict = VarDictionary::new();
        let Some(brain) = self.brain(slot) else {
            return dict;
        };
        let d = brain.describe();
        dict.set("behaviour", &GString::from(d.behaviour.as_str()));
        dict.set("state", &GString::from(d.state.as_str()));
        dict.set("for_s", d.for_s);
        for (key, value) in &d.numbers {
            dict.set(*key, *value);
        }
        for (key, value) in &d.flags {
            dict.set(*key, *value);
        }
        for (key, value) in &d.ints {
            dict.set(*key, *value);
        }
        for (key, value) in &d.texts {
            dict.set(*key, &GString::from(value.as_str()));
        }
        let guard = self.core.as_ref().map(|c| c.bind());
        let (rows, names): (&Rows, &[GString]) = match &guard {
            Some(c) => (&c.rows, &c.row_names),
            None => (&self.own, &self.own_names),
        };
        for (key, id) in &d.names {
            let name = name_of(rows, names, *id);
            if *key == "state" {
                dict.set("state", &GString::from(format!("to {name}").as_str()));
            } else {
                dict.set(*key, &GString::from(name.as_str()));
            }
        }
        let mut scores = VarDictionary::new();
        for (i, kind) in brain.behaviours.iter().enumerate() {
            scores.set(
                KIND_NAMES[usize::from(*kind)],
                brain_maths::snapped(brain.weighted[i], 0.01),
            );
        }
        dict.set("scores", &scores);
        dict
    }

    /// `BehaviourFollowPath.visited`: the waypoints reached, in order.
    #[func]
    fn path_visited(&self, slot: i64) -> PackedInt32Array {
        self.brain(slot).map_or_else(PackedInt32Array::new, |b| {
            PackedInt32Array::from(b.path_visited())
        })
    }

    /// `BehaviourFollowPath.results`: each finished demo's result with `demo` and `index`.
    #[func]
    fn path_results(&self, slot: i64) -> VarArray {
        let mut out = VarArray::new();
        let Some(brain) = self.brain(slot) else {
            return out;
        };
        for r in brain.path_results() {
            let mut dict = outcome_dict(&r.outcome);
            dict.set(
                "demo",
                &GString::from(brain_maths::MANOEUVRE_NAMES[usize::from(r.demo)]),
            );
            dict.set("index", r.index);
            out.push(&dict.to_variant());
        }
        out
    }

    // --- the maths, for the differential tests ---------------------------------------------------------------------

    /// `hash([seed, label])`.
    #[func]
    fn hash_seed(seed: i64, label: GString) -> i64 {
        brain_maths::hash_seed(seed, &label.to_string())
    }

    /// `hash(value)` of an int.
    #[func]
    fn hash_int(value: i64) -> i64 {
        brain_maths::hash_int(value)
    }

    /// The first `count` `randi()` draws of a generator seeded with `seed`.
    #[func]
    fn randi_sequence(seed: i64, count: i64) -> PackedInt64Array {
        let mut rng = Pcg::seeded(seed);
        (0..count.max(0))
            .map(|_| i64::from(rng.randi()))
            .collect::<Vec<i64>>()
            .as_slice()
            .into()
    }

    /// The first `count` `randf()` draws of a generator seeded with `seed`.
    #[func]
    fn randf_sequence(seed: i64, count: i64) -> PackedFloat64Array {
        let mut rng = Pcg::seeded(seed);
        (0..count.max(0))
            .map(|_| f64::from(rng.randf()))
            .collect::<Vec<f64>>()
            .as_slice()
            .into()
    }

    /// The first `count` `randf_range` draws over the test's six bounds in turn.
    #[func]
    fn randf_range_sequence(seed: i64, count: i64) -> PackedFloat64Array {
        const BOUNDS: [(f32, f32); 6] = [
            (0.05, 0.15),
            (0.15, 0.35),
            (0.0, std::f32::consts::TAU),
            (-45.0, 45.0),
            (2.0, 4.0),
            (-62.0, 62.0),
        ];
        let mut rng = Pcg::seeded(seed);
        (0..count.max(0) as usize)
            .map(|i| {
                let (a, b) = BOUNDS[i % BOUNDS.len()];
                f64::from(rng.randf_range(a, b))
            })
            .collect::<Vec<f64>>()
            .as_slice()
            .into()
    }

    /// `[deg_to_rad(x), rad_to_deg(x), lerpf(x, b, t)]`.
    #[func]
    fn angle_helpers(x: f64, b: f64, t: f64) -> PackedFloat64Array {
        PackedFloat64Array::from(&deg_to_rad_lerp(x, b, t)[..])
    }

    /// `[angle_to, face, face_tracking, align_roll]` of `PilotSteering`.
    #[func]
    fn steering_face(
        basis: Basis,
        direction: Vector3,
        omega: Vector3,
        rate_max: Vector3,
        gain: f64,
    ) -> VarArray {
        let mut out = VarArray::new();
        out.push(&brain_maths::angle_to(&basis, direction).to_variant());
        out.push(&brain_maths::face(&basis, direction, rate_max, gain).to_variant());
        out.push(
            &brain_maths::face_tracking(&basis, direction, omega, rate_max, gain).to_variant(),
        );
        out.push(&brain_maths::align_roll(&basis, direction, rate_max, gain).to_variant());
        out
    }

    /// `PilotSteering.seek` as `[main, retro, strafe]`; `cap` as `capability_of` reads it.
    #[func]
    fn steering_seek(
        velocity: Vector3,
        v_des: Vector3,
        basis: Basis,
        cap: PackedFloat64Array,
        horizon_s: f64,
        all_axes: bool,
    ) -> VarArray {
        let s = brain_maths::seek(
            velocity,
            v_des,
            &basis,
            &capability_of(&cap),
            horizon_s,
            all_axes,
        );
        let mut out = VarArray::new();
        out.push(&s.main.to_variant());
        out.push(&s.retro.to_variant());
        out.push(&Vector2::new(s.strafe_x, s.strafe_y).to_variant());
        out
    }

    /// `PilotSteering.lean_toward`.
    #[func]
    fn steering_lean(base: Vector3, accel: Vector3, a_side: f64, max_lean_rad: f64) -> Vector3 {
        brain_maths::lean_toward(base, accel, a_side, max_lean_rad)
    }

    /// `InterceptMath.solve` as `[ok, t, aim_dir, lead_point]`.
    #[func]
    fn intercept(
        shooter_pos: Vector3,
        shooter_vel: Vector3,
        target_pos: Vector3,
        target_vel: Vector3,
        bolt_speed: f64,
        max_time: f64,
    ) -> VarArray {
        let lead = brain_maths::solve(
            shooter_pos,
            shooter_vel,
            target_pos,
            target_vel,
            bolt_speed,
            max_time,
        );
        let mut out = VarArray::new();
        out.push(&lead.ok.to_variant());
        out.push(&lead.t.to_variant());
        out.push(&lead.aim_dir.to_variant());
        out.push(&lead.lead_point.to_variant());
        out
    }

    /// `AiTemperament`'s fifteen factors, in `test_brain_parity`'s order.
    #[func]
    fn temperament_factors(skill: f64, aggression: f64) -> PackedFloat64Array {
        let t = Temperament::new(skill, aggression);
        PackedFloat64Array::from(
            &[
                t.aim_factor(),
                t.reaction_s(),
                t.miss_factor(),
                t.jink_factor(),
                t.reversal_spread_deg(),
                t.attack_weight_factor(),
                t.evade_weight_factor(),
                t.retreat_weight_factor(),
                t.retreat_threshold_factor(),
                t.press_factor(),
                t.slash_chance(),
                t.close_pass_chance(),
                t.awareness(),
                f64::from(u8::from(t.never_starts())),
                f64::from(u8::from(t.may_ram())),
            ][..],
        )
    }

    /// `AiTemperament.apply` on `[attack weight, evade weight, retreat weight, retreat_below, aim_error_deg, fire_miss_m,
    /// near_range_m, break_range_m]`.
    #[func]
    fn temperament_apply(
        skill: f64,
        aggression: f64,
        base: PackedFloat64Array,
    ) -> PackedFloat64Array {
        let t = Temperament::new(skill, aggression);
        let b = base.as_slice();
        if b.len() != 8 {
            return PackedFloat64Array::new();
        }
        PackedFloat64Array::from(
            &[
                t.weight(b[0], t.attack_weight_factor()),
                t.weight(b[1], t.evade_weight_factor()),
                t.weight(b[2], t.retreat_weight_factor()),
                brain_maths::clamp01(b[3] * t.retreat_threshold_factor()),
                b[4] * t.aim_factor(),
                b[5] * t.miss_factor(),
                b[6] * t.press_factor(),
                b[7] * t.press_factor(),
            ][..],
        )
    }

    /// Flies manoeuvre `kind` through `steps` (`STEP_IN` numbers a step) with `cap`, and gives `[the commands, STEP_OUT
    /// numbers a step; the result as a Dictionary]`.
    #[func]
    fn manoeuvre_run(kind: i64, cap: PackedFloat64Array, steps: PackedFloat64Array) -> VarArray {
        let mut out = VarArray::new();
        let Some(mut m) = u8::try_from(kind).ok().and_then(Manoeuvre::create) else {
            return out;
        };
        let cap = capability_of(&cap);
        let s = steps.as_slice();
        let mut commands: Vec<f64> = Vec::with_capacity(s.len() / STEP_IN * STEP_OUT);
        for step in s.as_chunks::<STEP_IN>().0 {
            let v =
                |at: usize| Vector3::new(step[at] as f32, step[at + 1] as f32, step[at + 2] as f32);
            // The test packs the basis as GDScript reads it: `basis.x`, `basis.y`, `basis.z`, its columns.
            let (cx, cy, cz) = (v(4), v(7), v(10));
            let pose = Pose {
                now_s: step[0],
                position: v(1),
                basis: Basis {
                    rows: [
                        Vector3::new(cx.x, cy.x, cz.x),
                        Vector3::new(cx.y, cy.y, cz.y),
                        Vector3::new(cx.z, cy.z, cz.z),
                    ],
                },
                velocity: v(13),
                angular: v(16),
                origin: [step[19], step[20], step[21]],
            };
            let cmd: FlightCmd = m.step(&pose, &cap, step[22]);
            commands.extend([
                cmd.main_left,
                cmd.main_right,
                cmd.retro_left,
                cmd.retro_right,
                f64::from(cmd.strafe_x),
                f64::from(cmd.strafe_y),
                f64::from(cmd.rot.x),
                f64::from(cmd.rot.y),
                f64::from(cmd.rot.z),
                f64::from(u8::from(cmd.brake)),
                f64::from(u8::from(m.done)),
                f64::from(u8::from(m.timed_out)),
                f64::from(u8::from(m.has_desired_velocity)),
                f64::from(m.desired_velocity.x),
                f64::from(m.desired_velocity.y),
                f64::from(m.desired_velocity.z),
            ]);
        }
        out.push(&PackedFloat64Array::from(commands.as_slice()).to_variant());
        out.push(&outcome_dict(&m.result()).to_variant());
        out
    }
}

// One ship's think in a batch: its brain over the shared rows with the worker's scratch, its output packed into its item.
fn think_item(shared: &Shared, item: &mut Item, worker: &mut Worker) {
    item.ok = false;
    let Some(brain) = item.brain.as_mut() else {
        return;
    };
    let Ok(own_row) = usize::try_from(item.own_row) else {
        return;
    };
    if shared.fault == FAULT_PANIC {
        std::panic::resume_unwind(Box::new("the injected panic"));
    }
    let inputs = Inputs {
        relations: &shared.relations[item.relations.0..item.relations.1],
        own_body_id: brain.ship.own_body_id,
        now_s: shared.now_s,
        dt: item.dt,
        hull_fraction: item.hull_fraction,
        self_id: brain.ship.self_id,
        selected_id: item.selected_id,
        last_hit_s: item.last_hit_s,
        last_bolt_hit_s: item.last_bolt_hit_s,
        last_attacker_id: item.last_attacker_id,
        friendly_fire: shared.friendly_fire,
        origin: shared.origin,
        nearest_k: shared.nearest_k,
        static_k: shared.static_k,
    };
    let Worker {
        query,
        scratch,
        keep,
        carry,
    } = worker;
    let mut result = brain.think(
        shared.rows,
        shared.bolts,
        &mut Work {
            grid: shared.grid,
            query,
        },
        shared.field,
        own_row,
        scratch,
        keep,
        &inputs,
    );
    if shared.fault == FAULT_CARRY {
        result.flight.main_left = (result.flight.main_left * 0.5 + *carry).min(1.0);
        *carry = result.flight.main_left * 0.5;
    }
    pack_output(brain, &result, &mut item.out);
    item.ok = true;
}

// The names the slots' brains look for (objectives and guarded ships), for the tick's name index.
fn wanted_names(slots: &[Option<Brain>]) -> impl Iterator<Item = &str> {
    slots
        .iter()
        .flatten()
        .flat_map(|b| [b.ctx.objective_key.as_str(), b.ctx.guard_key.as_str()])
}

// A manoeuvre's `result()` as the Dictionary GDScript reports.
fn outcome_dict(result: &brain_maths::Outcome) -> VarDictionary {
    let mut dict = VarDictionary::new();
    for (key, value) in result.keys.iter().zip(result.values.iter()) {
        dict.set(*key, *value);
    }
    for (key, flag) in &result.flags {
        dict.set(*key, *flag);
    }
    for (key, count) in &result.ints {
        dict.set(*key, *count);
    }
    if let Some(legs) = &result.legs_m {
        let mut list = VarArray::new();
        for leg in legs {
            list.push(&leg.to_variant());
        }
        dict.set("legs_m", &list);
    }
    dict
}

// The output of a think, `OUT_LEN` numbers.
fn pack_output(brain: &Brain, result: &brain_behaviours::Output, out: &mut Vec<f64>) {
    out.clear();
    out.resize(OUT_LEN, 0.0);
    let f = &result.flight;
    out[0] = f.main_left;
    out[1] = f.main_right;
    out[2] = f.retro_left;
    out[3] = f.retro_right;
    out[4] = f64::from(f.strafe_x);
    out[5] = f64::from(f.strafe_y);
    out[6] = f64::from(f.rot.x);
    out[7] = f64::from(f.rot.y);
    out[8] = f64::from(f.rot.z);
    out[9] = f64::from(u8::from(f.brake));
    out[10] = f64::from(u8::from(result.fire));
    let (hi, lo) = brain_behaviours::split_id(brain.wanted_target_id);
    out[11] = hi;
    out[12] = lo;
    out[13] = f64::from(u8::from(brain.avoiding));
    out[14] = f64::from(u8::from(brain.avoiding_urgent));
    out[15] = f64::from(u8::from(brain.has_desired_velocity));
    out[16] = f64::from(u8::from(brain.desired_all_axes));
    out[17] = f64::from(brain.desired_velocity.x);
    out[18] = f64::from(brain.desired_velocity.y);
    out[19] = f64::from(brain.desired_velocity.z);
    out[20] = f64::from(brain.current_kind());
    out[21] = brain.dwell_s;
    out[22] = brain.switches as f64;
    out[23] = brain.contacts_seen as f64;
    for (i, kind) in brain.behaviours.iter().enumerate() {
        out[OUT_RAW + usize::from(*kind)] = brain.raw[i];
        out[OUT_WEIGHTED + usize::from(*kind)] = brain.weighted[i];
    }
    let mut mirror = [0.0; MIRROR];
    brain.mirror(&mut mirror);
    out[OUT_MIRROR..OUT_RAM].copy_from_slice(&mirror);
    out[OUT_RAM] = f64::from(u8::from(brain.ram_committed()));
}

// The display name of the row whose marker id is `id`, "" when none.
fn name_of(rows: &Rows, names: &[GString], id: i64) -> String {
    if id == 0 {
        return String::new();
    }
    rows.ids
        .iter()
        .position(|&r| r == id)
        .and_then(|r| names.get(r))
        .map_or_else(String::new, ToString::to_string)
}

// `AiProfile` and `RaiderTactics` from the facade's numbers.
fn profile_of(profile: &PackedFloat64Array, tactics: &PackedFloat64Array) -> Option<Profile> {
    let p = profile.as_slice();
    let t = tactics.as_slice();
    if p.len() != PROFILE_LEN || t.len() != TACTICS_LEN {
        return None;
    }
    let mut weights = [1.0; KINDS];
    weights.copy_from_slice(&p[..KINDS]);
    Some(Profile {
        weights,
        stickiness: p[KINDS],
        emergency_margin: p[KINDS + 1],
        min_dwell_s: p[KINDS + 2],
        retreat_below: p[KINDS + 3],
        retreat_within_m: p[KINDS + 4],
        cruise_mps: p[KINDS + 5],
        aim_error_deg: p[KINDS + 6],
        fires: p[KINDS + 7] != 0.0,
        slashing: p[KINDS + 8] != 0.0,
        idle_hold: p[KINDS + 9] != 0.0,
        tactics: Tactics {
            closing_far_mps: t[0],
            closing_near_mps: t[1],
            near_range_m: t[2],
            face_lead_delta_v_mps: t[3],
            fire_range_m: t[4],
            fire_cone_deg: t[5],
            fire_miss_m: t[6],
            break_range_m: t[7],
            max_time_on_target_s: t[8],
            break_speed_mps: t[9],
            break_duration_s: t[10],
            extend_min_s: t[11],
            extend_range_m: t[12],
            max_speed_mps: t[13],
        },
    })
}

impl ScsBrains {
    // Thinks the batch's first `n` items (inputs filled, brains taken from their slots) across the pool and packs their
    // outputs in order; with `from_rows` each ship's hull and selection are read from its own row first.
    #[allow(clippy::too_many_arguments)]
    fn run_batch(
        &mut self,
        n: usize,
        rel: &[u8],
        now_s: f64,
        friendly_fire: bool,
        origin: [f64; 3],
        rows_version: i64,
        from_rows: bool,
    ) -> PackedFloat64Array {
        let guard = self.core.as_ref().map(|c| c.bind());
        let (rows, bolts, threads): (&Rows, &Bolts, &Threads) = match &guard {
            Some(c) => (&c.rows, &c.bolts, c.worker_threads()),
            None => (&self.own, &self.own_bolts, &self.serial),
        };
        for item in &mut self.items[..n] {
            item.own_row = match (&item.brain, &guard) {
                (None, _) => -1,
                (Some(b), Some(c)) => c.row_for_kernel(b.ship.own_body_id),
                (Some(b), None) => rows
                    .body_ids
                    .iter()
                    .position(|&id| id == b.ship.own_body_id)
                    .map_or(-1, |r| r as i64),
            };
            if let (true, Ok(r)) = (from_rows, usize::try_from(item.own_row)) {
                // What the driver read from the ship's hull and targeting, as the sync stamped them (-1: none).
                let hull = rows.hull_fraction[r];
                item.hull_fraction = if hull < 0.0 { 1.0 } else { hull };
                item.selected_id = rows.target_ids[r].max(0);
            }
        }
        threads::ensure_workers(&mut self.workers, threads);
        let shared = Shared {
            rows,
            bolts,
            grid: &self.grid,
            field: &self.field,
            relations: rel,
            now_s,
            friendly_fire,
            origin,
            nearest_k: self.nearest_k,
            static_k: self.static_k,
            fault: self.fault,
        };
        let moved = guard
            .as_ref()
            .is_some_and(|c| c.rows_version_now() != rows_version);
        let items = &mut self.items[..n];
        let workers = &self.workers;
        let passed = moved
            || std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                threads.run(Pass::Brains, items, workers, |item, worker| {
                    think_item(&shared, item, worker);
                });
            }))
            .is_ok();
        drop(guard);
        if moved || !passed {
            for item in &mut self.items[..n] {
                item.ok = false;
            }
        }
        if !passed {
            if self.pass_failures == 0 {
                godot_warn!(
                    "ScsBrains.think_batch: a think panicked; the tick's {n} thinks are held, their brains kept"
                );
            }
            self.pass_failures += 1;
        }
        self.batch_out.clear();
        self.batch_out.resize(n * BATCH_OUT, 0.0);
        for (k, item) in self.items[..n].iter_mut().enumerate() {
            if let Some(brain) = item.brain.take() {
                self.slots[item.slot] = Some(brain);
            }
            if item.ok {
                let at = k * BATCH_OUT;
                self.batch_out[at] = 1.0;
                self.batch_out[at + 1..at + BATCH_OUT].copy_from_slice(&item.out);
            }
        }
        PackedFloat64Array::from(self.batch_out.as_slice())
    }

    // After a rows batch, on the main thread: every think's command into the core, the counts, and the events of the
    // ships whose drivers have something to do (see `think_batch_rows`).
    fn write_commands(&mut self, n: usize) {
        let mut core = self.core.clone();
        let mut guard = core.as_mut().map(|c| c.bind_mut());
        for k in 0..n {
            let item = &self.items[k];
            if !item.ok {
                self.events[2] += 1;
                continue;
            }
            self.events[if item.near { 0 } else { 1 }] += 1;
            self.events[3] = self.events[3].max(item.out[23] as i64);
            let (Some(c), Some(brain)) = (
                guard.as_mut(),
                self.slots.get(item.slot).and_then(Option::as_ref),
            ) else {
                continue;
            };
            let mut events = c.write_command(brain.ship.own_body_id, &item.out[..=CMD_LEN]);
            let wanted = brain.wanted_target_id;
            let selected = usize::try_from(item.own_row).map_or(-1, |r| c.rows.target_ids[r]);
            // The driver follows the brain's target: it clears a selection for none and selects anything else it wants.
            if wanted == 0 || (wanted < 0 && selected > 0) || (wanted > 0 && wanted != selected) {
                events |= EVENT_SELECT;
            }
            // Ram (0) and follow path (7) in control are mirrored at once, as the facade does, and so is a new commitment.
            let kind = item.out[20] as i64;
            if c.note_ram(brain.ship.own_body_id, item.out[OUT_RAM] != 0.0)
                || kind == 0
                || kind == 7
            {
                events |= EVENT_SETTLE;
            }
            if events != 0 {
                self.events.push(k as i64);
                self.events.push(i64::from(events));
            }
        }
    }

    // Rebuilds the contact grid when the core's rows changed under it.
    fn refresh_grid(&mut self) {
        let Some(core) = &self.core else {
            return;
        };
        let c = core.bind();
        if c.rows_version_now() == self.grid_version {
            return;
        }
        self.grid_version = c.rows_version_now();
        self.grid.cells = contact::sorted_cells(&c.rows.positions, self.grid.cell_m);
        self.grid.max_static_radius = (0..c.rows.positions.len())
            .filter(|&i| c.rows.is_static[i])
            .map(|i| c.rows.radii[i].abs())
            .fold(0.0, f64::max);
        self.field.build(&c.rows, &c.bolts, self.grid.cell_m);
        self.field.index_names(&c.rows, wanted_names(&self.slots));
    }

    fn brain(&self, slot: i64) -> Option<&Brain> {
        usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get(i))
            .and_then(Option::as_ref)
    }

    fn brain_mut(&mut self, slot: i64) -> Option<&mut Brain> {
        usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get_mut(i))
            .and_then(Option::as_mut)
    }
}

// `ShipCapability` as the tests pack it: a_main, a_retro, a_rcs x and y, the rate maxima, the angular acceleration maxima.
fn capability_of(cap: &PackedFloat64Array) -> Capability {
    let c = cap.as_slice();
    if c.len() < 10 {
        return Capability::default();
    }
    Capability {
        a_main: c[0],
        a_retro: c[1],
        a_rcs_x: c[2],
        a_rcs_y: c[3],
        rate_max: Vector3::new(c[4] as f32, c[5] as f32, c[6] as f32),
        alpha_max: Vector3::new(c[7] as f32, c[8] as f32, c[9] as f32),
    }
}
