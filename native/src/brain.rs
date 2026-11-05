// The native brain host (M4-T17, docs/architecture.md 17.13): the AI pilots' brains on the core's rows. The maths lives in
// `brain_maths.rs` and the behaviours in `brain_behaviours.rs` (both engine-free); this class binds the core, keeps one
// slot per pilot, picks nothing itself and hands answers over as packed numbers. The GDScript `AiPilot` is the facade and
// stays the reference. The batch itself is a job over a snapshot of the rows (`brain_step.rs`, M4-T24) that runs on the
// main thread or on the step's worker thread; this class launches it, joins it and keeps what GDScript asks for while
// the brains are away. gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::collections::{HashMap, HashSet};
use std::thread::ThreadId;
use std::time::Instant;

use godot::prelude::*;

use crate::brain_behaviours::{Brain, Context, KIND_NAMES, KINDS, Profile, Route, Ship, Tactics};
use crate::brain_maths::{
    self, Capability, FlightCmd, Manoeuvre, Pcg, Pose, Temperament, deg_to_rad_lerp,
};
use crate::brain_step::{
    self, Done, DriverFrame, EVENTS_HEAD, Hosted, Job, Params, Snapshot, Work,
};
use crate::rows::{Bolts, Rows};
use crate::sim_core::ScsSimCore;
use crate::threads::{Runner, StepThread};

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
/// A batch think's inputs per ship: the slot, the relation row's offset and length in the batch's relations, the
/// selection and the latest attacker (ints); dt, the hull, the latest hit and the latest bolt hit (floats).
pub const BATCH_INTS: usize = 5;
pub const BATCH_FLOATS: usize = 4;
/// A rows batch's inputs per ship (M4-T33): the slot, the relation row's offset and length, the latest attacker and
/// whether the ship is near the player (ints); dt, the latest hit and the latest bolt hit (floats). The hull and the
/// selection come from the ship's row.
pub const ROWS_INTS: usize = 5;
pub const ROWS_FLOATS: usize = 3;
// The step thread's name.
const STEP_THREAD: &str = "scs-sim-step";

// A change to a hosted driver that arrived while the brains were away (M4-T24): applied at the join, before the next
// launch, which is when today's hits reach the next think too.
enum Pending {
    Host {
        slot: usize,
        body_id: i64,
        ordinal: i64,
        steps: i64,
        since_think_s: f64,
        woken: bool,
        attacker_id: i64,
        hit_s: f64,
        bolt_hit_s: f64,
    },
    Hits {
        slot: i64,
        attacker_id: i64,
        hit_s: f64,
        bolt_hit_s: f64,
    },
    Live {
        slot: i64,
        live: bool,
    },
    Wake {
        slot: i64,
    },
}

// What the frame's readers see of a hosted driver while the brains are away: its state as the launch found it.
#[derive(Default, Clone)]
struct HostedView {
    slot: usize,
    thinks: i64,
    dt: f64,
    attack_target: i64,
    out: Vec<f64>,
    steps: i64,
    since_think_s: f64,
    woken: bool,
    near: bool,
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
    own_version: i64,
    // The brains and the batch's state (M4-T24): here between jobs, in the job while one runs (`work` is None then).
    work: Option<Box<Work>>,
    // The step's thread, the result of a job run on the main thread (delayed or inline), and the spare snapshot buffer.
    step: Option<StepThread<Job, Done>>,
    done: Option<Done>,
    spare: Option<Snapshot>,
    launched_at: Option<Instant>,
    main_thread: Option<ThreadId>,
    // False from a launch until `join_step` hands the job's results over: the hosted readers see the launch's view until
    // then, whatever an early join brought back, so a reader never sees a think before the tick that applies it.
    handed_over: bool,
    // What arrived for the hosted drivers while the brains were away, and what the frame's readers see meanwhile.
    pending: Vec<Pending>,
    mirror: Vec<HostedView>,
    asked: HashSet<usize>,
    describe_cache: HashMap<usize, VarDictionary>,
    path_cache: HashMap<usize, (PackedInt32Array, VarArray)>,
    // Readouts: panicked passes, the last job's run time and the time the main thread waited for it, the deadlines
    // missed (a join that had to wait), the joins forced early by a reader, and whether the last job ran off the main thread.
    pass_failures: i64,
    // The last joined job's output, until `join_step` (or the inline wrappers) hand it over: a join forced early keeps it.
    last_out: Option<Vec<f64>>,
    step_us: i64,
    wait_us: i64,
    misses: i64,
    early_joins: i64,
    off_main: bool,
    warned: bool,
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
        let work = self.work();
        work.grid_version = -1;
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
        let work = self.work();
        work.nearest_k = nearest_k;
        work.static_k = static_k;
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
        self.own_version += 1; // the next job rebuilds its grid and field from these rows
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
        self.own_version += 1;
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
        let slots = &mut self.work().slots;
        if let Some(free) = slots.iter().position(Option::is_none) {
            slots[free] = Some(brain);
            free as i64
        } else {
            slots.push(Some(brain));
            (slots.len() - 1) as i64
        }
    }

    /// Forgets a brain; its slot number may be reused.
    #[func]
    fn free_slot(&mut self, slot: i64) {
        if let Some(entry) = usize::try_from(slot)
            .ok()
            .and_then(|i| self.work().slots.get_mut(i))
        {
            *entry = None;
        }
    }

    /// Brains held now.
    #[func]
    fn count(&mut self) -> i64 {
        self.work().slots.iter().filter(|s| s.is_some()).count() as i64
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
    /// A batch of one, run at once (M4-T24).
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
        let ints = PackedInt64Array::from(
            &[
                slot,
                0,
                relations.len() as i64,
                selected_id,
                last_attacker_id,
            ][..],
        );
        let floats =
            PackedFloat64Array::from(&[dt, hull_fraction, last_hit_s, last_bolt_hit_s][..]);
        let version = self.rows_version_now();
        if !self.launch_batch(
            ints,
            floats,
            relations,
            now_s,
            friendly_fire,
            origin_x,
            origin_y,
            origin_z,
            version,
            false,
        ) {
            return PackedFloat64Array::new();
        }
        self.join();
        self.handed_over = true;
        let out = self.last_out.take().unwrap_or_default();
        if out.first().copied().unwrap_or(0.0) != 0.0 {
            PackedFloat64Array::from(&out[1..])
        } else {
            PackedFloat64Array::new()
        }
    }

    /// Every thinking ship of a tick in one call (M4-T18), across the core's worker threads: per ship `BATCH_INTS` ints
    /// (slot, relation row offset and length in `relations`, selection, latest attacker) and `BATCH_FLOATS` floats (dt,
    /// hull, latest hit, latest bolt hit), the rest as `think` takes it. Returns `BATCH_OUT` numbers per ship in the
    /// order given: 1 and `think`'s output, or 0 and zeros when declined (no slot, a slot twice, no row). Each think reads
    /// the frozen rows and writes only its own brain and its output, so the result does not depend on the threads.
    /// `rows_version` is the core's version the drivers took their scan at: when the rows moved since (a resync or a
    /// rebase between the drivers and the batch), every ship is declined, so each holds its last command, as T17's
    /// per-ship check did. A think that panics declines the whole batch too, its brains kept (`pass_failures`).
    /// The inline step (M4-T24): `launch_batch` and `join` in one call.
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
        if !self.launch_batch(
            ints,
            floats,
            relations,
            now_s,
            friendly_fire,
            origin_x,
            origin_y,
            origin_z,
            rows_version,
            false,
        ) {
            return PackedFloat64Array::new();
        }
        self.join();
        self.handed_over = true;
        PackedFloat64Array::from(self.last_out.take().unwrap_or_default().as_slice())
    }

    /// The rows path of `think_batch` (M4-T33): per ship `ROWS_INTS` ints and `ROWS_FLOATS` floats, the hull and the
    /// selection read from its row; returns the same output. Each think's command (its flight numbers and trigger) is
    /// written into the core's commands, which the flight step flies the same tick, and `rows_events` then holds the
    /// counts and the ships whose drivers have something to do: a first command from the row, a changed trigger, or a
    /// wanted target the ship has not selected. A declined think writes nothing, so its ship flies the row's command on.
    /// The inline step (M4-T24): `launch_rows` and `join` in one call.
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
        if !self.launch_rows(
            ints,
            floats,
            relations,
            now_s,
            friendly_fire,
            origin_x,
            origin_y,
            origin_z,
            rows_version,
            false,
        ) {
            return PackedFloat64Array::new();
        }
        self.join();
        self.handed_over = true;
        PackedFloat64Array::from(self.last_out.take().unwrap_or_default().as_slice())
    }

    // --- the step as a job (M4-T24) ----------------------------------------------------------------------------------

    /// `think_batch`'s launch: the batch becomes a job over a snapshot of the rows, run on the step's thread when
    /// `threaded`, else at once on this thread; `join_step` gives its output. False, after logging why, when the
    /// arrays do not make whole ships.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn launch_batch(
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
        threaded: bool,
    ) -> bool {
        let n = ints.len() / BATCH_INTS;
        if ints.len() != n * BATCH_INTS || floats.len() != n * BATCH_FLOATS {
            godot_error!(
                "ScsBrains.think_batch: {} ints and {} floats do not make whole ships; nothing thought",
                ints.len(),
                floats.len()
            );
            return false;
        }
        let iv = ints.as_slice();
        let fv = floats.as_slice();
        let rel = relations.as_slice();
        let work = self.work();
        if work.items.len() < n {
            work.items.resize_with(n, brain_step::Item::default);
        }
        work.events.clear();
        for (k, item) in work.items[..n].iter_mut().enumerate() {
            let i = &iv[k * BATCH_INTS..(k + 1) * BATCH_INTS];
            let f = &fv[k * BATCH_FLOATS..(k + 1) * BATCH_FLOATS];
            let start = usize::try_from(i[1]).unwrap_or(0).min(rel.len());
            let len = usize::try_from(i[2]).unwrap_or(0).min(rel.len() - start);
            item.slot = usize::try_from(i[0]).unwrap_or(usize::MAX);
            item.brain = work.slots.get_mut(item.slot).and_then(Option::take);
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
        let params = Params {
            n,
            rel: rel.to_vec(),
            now_s,
            friendly_fire,
            origin: [origin_x, origin_y, origin_z],
            rows_version,
            from_rows: false,
        };
        self.launch(params, threaded);
        true
    }

    /// `think_batch_rows`' launch (see `launch_batch`): the hosted drivers are stepped in the job too, and the commands
    /// its thinks write reach the core's rows at the join.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn launch_rows(
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
        threaded: bool,
    ) -> bool {
        let n = ints.len() / ROWS_INTS;
        if ints.len() != n * ROWS_INTS || floats.len() != n * ROWS_FLOATS {
            godot_error!(
                "ScsBrains.think_batch_rows: {} ints and {} floats do not make whole ships; nothing thought",
                ints.len(),
                floats.len()
            );
            return false;
        }
        let iv = ints.as_slice();
        let fv = floats.as_slice();
        let rel = relations.as_slice();
        let work = self.work();
        work.events.clear();
        work.events.resize(EVENTS_HEAD, 0);
        if work.items.len() < n {
            work.items.resize_with(n, brain_step::Item::default);
        }
        for (k, item) in work.items[..n].iter_mut().enumerate() {
            let i = &iv[k * ROWS_INTS..(k + 1) * ROWS_INTS];
            let f = &fv[k * ROWS_FLOATS..(k + 1) * ROWS_FLOATS];
            let start = usize::try_from(i[1]).unwrap_or(0).min(rel.len());
            let len = usize::try_from(i[2]).unwrap_or(0).min(rel.len() - start);
            item.slot = usize::try_from(i[0]).unwrap_or(usize::MAX);
            item.brain = work.slots.get_mut(item.slot).and_then(Option::take);
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
        let params = Params {
            n,
            rel: rel.to_vec(),
            now_s,
            friendly_fire,
            origin: [origin_x, origin_y, origin_z],
            rows_version,
            from_rows: true,
        };
        self.launch(params, threaded);
        true
    }

    /// Joins the job out (waits for it when it has not finished: a deadline missed, counted), takes its state back,
    /// applies what arrived meanwhile, hands its commands to the core, and returns its output (`BATCH_OUT` a ship; empty
    /// when no job was out). `rows_events` and `hosted_item_slots` then describe it.
    #[func]
    fn join_step(&mut self) -> PackedFloat64Array {
        self.join();
        self.handed_over = true;
        PackedFloat64Array::from(self.last_out.take().unwrap_or_default().as_slice())
    }

    /// Whether a job is out (launched and not joined).
    #[func]
    fn step_pending(&self) -> bool {
        self.done.is_some() || self.step.as_ref().is_some_and(StepThread::pending)
    }

    /// The last job's run time (its own thread's clock) and how long the last join waited for it, microseconds.
    #[func]
    fn step_us(&self) -> i64 {
        self.step_us
    }

    #[func]
    fn step_wait_us(&self) -> i64 {
        self.wait_us
    }

    /// Joins that found the job still running (waited for, never skipped), and joins a reader forced before the tick's.
    #[func]
    fn deadline_misses(&self) -> i64 {
        self.misses
    }

    #[func]
    fn early_joins(&self) -> i64 {
        self.early_joins
    }

    /// Whether the last joined job ran off the main thread.
    #[func]
    fn step_off_main(&self) -> bool {
        self.off_main
    }

    /// Step threads alive (1 once a threaded job has run, 0 before and after the host goes).
    #[func]
    fn step_threads(&self) -> i64 {
        self.step.as_ref().map_or(0, StepThread::live)
    }

    // --- the drivers' step (M4-T35) ----------------------------------------------------------------------------------

    /// Steps the driver of the pilot in `slot` here from now on (`perf_native_driver_step`): its ship's body, its place
    /// in the think rate's stagger and the think rate's state and hits as the driver kept them.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn host_driver(
        &mut self,
        slot: i64,
        body_id: i64,
        ordinal: i64,
        steps: i64,
        since_think_s: f64,
        woken: bool,
        attacker_id: i64,
        hit_s: f64,
        bolt_hit_s: f64,
    ) {
        let Ok(slot) = usize::try_from(slot) else {
            return;
        };
        self.mutate(Pending::Host {
            slot,
            body_id,
            ordinal,
            steps,
            since_think_s,
            woken,
            attacker_id,
            hit_s,
            bolt_hit_s,
        });
    }

    /// Gives the driver its step back: `[steps, since_think_s, woken]` as the host left them (empty when not hosted).
    #[func]
    fn unhost_driver(&mut self, slot: i64) -> PackedFloat64Array {
        let Ok(slot) = usize::try_from(slot) else {
            return PackedFloat64Array::new();
        };
        let hosted = &mut self.work().hosted;
        let Some(at) = hosted.iter().position(|h| h.slot == slot) else {
            return PackedFloat64Array::new();
        };
        let h = hosted.remove(at);
        PackedFloat64Array::from(
            &[
                h.steps as f64,
                h.since_think_s,
                f64::from(u8::from(h.woken)),
            ][..],
        )
    }

    /// The driver's latest hits (`AiPilotDriver._on_hit_taken`): the attacker, the hit's time and the bolt hit's; a hit
    /// wakes the ship for the next tick. Queued while the brains are away (M4-T24).
    #[func]
    fn set_driver_hits(&mut self, slot: i64, attacker_id: i64, hit_s: f64, bolt_hit_s: f64) {
        self.mutate(Pending::Hits {
            slot,
            attacker_id,
            hit_s,
            bolt_hit_s,
        });
    }

    /// Whether the driver's node processes (a parked ship's does not step).
    #[func]
    fn set_driver_live(&mut self, slot: i64, live: bool) {
        self.mutate(Pending::Live { slot, live });
    }

    /// Wakes the driver for the next tick (a new pilot would).
    #[func]
    fn wake_driver(&mut self, slot: i64) {
        self.mutate(Pending::Wake { slot });
    }

    /// The tick's frame for the hosted drivers: the tick length, the player (live, and where) and the think rate's
    /// settings (`ai_think_rate`, `ai_think_near_m` squared, the far period in ticks).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn set_driver_frame(
        &mut self,
        delta: f64,
        player_live: bool,
        player_at: Vector3,
        rate_on: bool,
        near_sq: f64,
        period: i64,
    ) {
        self.work().frame = DriverFrame {
            delta,
            player_live,
            player_at,
            rate_on,
            near_sq,
            period: period.max(1),
        };
    }

    /// The relation matrix over the core's factions, a row per faction of `stride` entries (`Factions.Relation` values),
    /// what a hosted ship's think reads as its relation row.
    #[func]
    fn set_relation_matrix(&mut self, matrix: PackedByteArray, stride: i64) {
        let work = self.work();
        work.matrix = matrix.as_slice().to_vec();
        work.stride = usize::try_from(stride).unwrap_or(0);
    }

    #[func]
    fn hosted_count(&self) -> i64 {
        match &self.work {
            Some(w) if self.handed_over => w.hosted.len() as i64,
            _ => self.mirror.len() as i64,
        }
    }

    /// The slots of the hosted items the last rows batch thought, in the order they followed the queued ships.
    #[func]
    fn hosted_item_slots(&mut self) -> PackedInt64Array {
        PackedInt64Array::from(self.work().hosted_slots.as_slice())
    }

    /// A hosted driver's last think: its output (`OUT_LEN` numbers, empty before the first), how many thinks the host
    /// ran for it, and the time its last think was given. While the brains are away (M4-T24) these read the state the
    /// launch found.
    #[func]
    fn slot_output(&self, slot: i64) -> PackedFloat64Array {
        self.view(slot, |v| PackedFloat64Array::from(v.out.as_slice()))
            .unwrap_or_default()
    }

    #[func]
    fn slot_think_count(&self, slot: i64) -> i64 {
        self.view(slot, |v| v.thinks).unwrap_or(0)
    }

    #[func]
    fn driver_dt(&self, slot: i64) -> f64 {
        self.view(slot, |v| v.dt).unwrap_or(0.0)
    }

    /// The target of the hosted driver's last think that attacked (0 for none yet): what the pilot's context keeps as
    /// `attack_target_id` across thinks its mirror never read.
    #[func]
    fn slot_attack_target(&self, slot: i64) -> i64 {
        self.view(slot, |v| v.attack_target).unwrap_or(0)
    }

    /// A hosted driver's think rate state, `[steps, since_think_s, woken, near]` (the console and tests).
    #[func]
    fn driver_state(&self, slot: i64) -> PackedFloat64Array {
        self.view(slot, |v| {
            PackedFloat64Array::from(
                &[
                    v.steps as f64,
                    v.since_think_s,
                    f64::from(u8::from(v.woken)),
                    f64::from(u8::from(v.near)),
                ][..],
            )
        })
        .unwrap_or_default()
    }

    /// The last `think_batch_rows`' counts and events (`EVENTS_HEAD`, then pairs).
    #[func]
    fn rows_events(&mut self) -> PackedInt64Array {
        PackedInt64Array::from(self.work().events.as_slice())
    }

    /// Batches a panic declined (each holding its brains and its ships' last commands).
    #[func]
    fn pass_failures(&self) -> i64 {
        self.pass_failures
    }

    /// Injects a bug for the determinism or the panic test (`FAULT_CARRY`, `FAULT_PANIC`), a slow job (`FAULT_SLOW`), or
    /// none (0).
    #[func]
    fn set_fault(&mut self, kind: i64) {
        self.work().fault = kind;
    }

    /// The rows the last think picked: `[contacts, statics, broadcasts]` (the tests compare them with the scan's).
    #[func]
    fn last_lists(&mut self) -> VarArray {
        let mut out = VarArray::new();
        let work = self.work();
        let Some(worker) = work.workers.first() else {
            return out;
        };
        let worker = worker
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        out.push(&PackedInt32Array::from(worker.scratch.contacts.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(worker.scratch.statics.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(worker.scratch.broadcasts.as_slice()).to_variant());
        out
    }

    /// `AiPilot.describe` for the behaviour in control: `behaviour`, `state`, `for_s`, its own fields and the `scores`
    /// (weighted, by id). Names of contacts are looked up in the rows by id. While the brains are away (M4-T24) a slot
    /// asked for since the last launch answers from the launch; one not asked for before joins the job first.
    #[func]
    fn describe(&mut self, slot: i64) -> VarDictionary {
        let Ok(at) = usize::try_from(slot) else {
            return VarDictionary::new();
        };
        self.asked.insert(at);
        if self.work.is_none() {
            if let Some(cached) = self.describe_cache.get(&at) {
                return cached.clone();
            }
            self.early_joins += 1;
            self.join();
        }
        let dict = self.describe_now(at);
        self.describe_cache.insert(at, dict.clone());
        dict
    }

    /// `BehaviourFollowPath.visited`: the waypoints reached, in order.
    #[func]
    fn path_visited(&mut self, slot: i64) -> PackedInt32Array {
        self.path(slot).0
    }

    /// `BehaviourFollowPath.results`: each finished demo's result with `demo` and `index`.
    #[func]
    fn path_results(&mut self, slot: i64) -> VarArray {
        self.path(slot).1
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
    // The brains and the batch's state, joined first when a job holds them (a reader or writer that cannot wait).
    fn work(&mut self) -> &mut Work {
        if self.work.is_none() && self.step_pending() {
            self.early_joins += 1;
            self.join();
        }
        self.work.get_or_insert_with(|| {
            let mut work = Box::new(Work::default());
            work.grid.cell_m = SENSOR_RANGE_M;
            work.grid_version = -1;
            work
        })
    }

    // A change to a hosted driver: applied now, or queued for the join while the brains are away.
    fn mutate(&mut self, change: Pending) {
        if self.work.is_some() || !self.step_pending() {
            let work = self.work();
            Self::apply(work, &change);
        } else {
            self.pending.push(change);
        }
    }

    fn hosted_of(work: &mut Work, slot: i64) -> Option<&mut Hosted> {
        let slot = usize::try_from(slot).ok()?;
        work.hosted.iter_mut().find(|h| h.slot == slot)
    }

    fn apply(work: &mut Work, change: &Pending) {
        let find = Self::hosted_of;
        match *change {
            Pending::Host {
                slot,
                body_id,
                ordinal,
                steps,
                since_think_s,
                woken,
                attacker_id,
                hit_s,
                bolt_hit_s,
            } => {
                work.hosted.retain(|h| h.slot != slot);
                work.hosted.push(Hosted {
                    slot,
                    body_id,
                    ordinal,
                    steps,
                    since_think_s,
                    woken,
                    attacker_id,
                    hit_s,
                    bolt_hit_s,
                    live: true,
                    near: false,
                    thinks: 0,
                    dt: 0.0,
                    out: Vec::new(),
                    attack_target: 0,
                });
            }
            Pending::Hits {
                slot,
                attacker_id,
                hit_s,
                bolt_hit_s,
            } => {
                if let Some(h) = find(work, slot) {
                    h.attacker_id = attacker_id;
                    h.hit_s = hit_s;
                    h.bolt_hit_s = bolt_hit_s;
                    h.woken = true;
                }
            }
            Pending::Live { slot, live } => {
                if let Some(h) = find(work, slot) {
                    h.live = live;
                }
            }
            Pending::Wake { slot } => {
                if let Some(h) = find(work, slot) {
                    h.woken = true;
                }
            }
        }
    }

    // A hosted driver as the readers see it: the state itself once the tick's job was handed over, else the launch's view.
    fn view<T>(&self, slot: i64, read: impl Fn(&HostedView) -> T) -> Option<T> {
        let slot = usize::try_from(slot).ok()?;
        match &self.work {
            Some(w) if self.handed_over => w.hosted.iter().find(|h| h.slot == slot).map(|h| {
                read(&HostedView {
                    slot: h.slot,
                    thinks: h.thinks,
                    dt: h.dt,
                    attack_target: h.attack_target,
                    out: h.out.clone(),
                    steps: h.steps,
                    since_think_s: h.since_think_s,
                    woken: h.woken,
                    near: h.near,
                })
            }),
            _ => self.mirror.iter().find(|v| v.slot == slot).map(read),
        }
    }

    // The version the next job's grid is keyed on: the core's rows version, or the loaded rows' own count.
    fn rows_version_now(&self) -> i64 {
        match &self.core {
            Some(core) => core.bind().rows_version_now(),
            None => self.own_version,
        }
    }

    // The launch itself: the frame's readers' views taken, the rows copied into the spare snapshot, the brains and the
    // batch handed to the job, which runs on the step's thread when asked (else here, its result kept for the join).
    fn launch(&mut self, params: Params, threaded: bool) {
        if self.step_pending() {
            self.early_joins += 1;
            self.join();
        }
        self.main_thread
            .get_or_insert_with(|| std::thread::current().id());
        self.refresh_views();
        let work = self.work.take().expect("joined above");
        let mut snapshot = self.spare.take().unwrap_or_default();
        let runner = match self.core.clone() {
            Some(mut core) => {
                let mut c = core.bind_mut();
                c.snapshot_into(&mut snapshot);
                c.worker_threads().runner()
            }
            None => {
                snapshot.rows.clone_from(&self.own);
                snapshot.bolts.clone_from(&self.own_bolts);
                snapshot.body_rows.clear();
                snapshot.body_rows.extend(
                    self.own
                        .body_ids
                        .iter()
                        .enumerate()
                        .map(|(r, &b)| (b, r as u32)),
                );
                snapshot.touched.clear();
                snapshot.commands.clear();
                snapshot.rows_version = self.own_version;
                Runner::default()
            }
        };
        let job = Job {
            work,
            snapshot,
            params,
            runner,
        };
        self.launched_at = Some(Instant::now());
        self.handed_over = false;
        if threaded {
            let step = self
                .step
                .get_or_insert_with(|| StepThread::start(STEP_THREAD, brain_step::run));
            if let Err(job) = step.launch(job) {
                self.done = Some(brain_step::run(job));
            }
        } else {
            self.done = Some(brain_step::run(job));
        }
    }

    // The join: the job's result taken (waited for when it still runs), the state back, what arrived meanwhile applied,
    // the commands into the core, the snapshot kept as the next spare. The output, or nothing when no job was out.
    fn join(&mut self) {
        let waited = Instant::now();
        let done = match self.done.take() {
            Some(done) => Some(done),
            None => match self.step.as_mut() {
                Some(step) if step.pending() => {
                    let ready = step.try_take();
                    if ready.is_some() {
                        ready
                    } else {
                        self.misses += 1;
                        step.take()
                    }
                }
                _ => None,
            },
        };
        self.wait_us = waited.elapsed().as_micros() as i64;
        let Some(mut done) = done else {
            return;
        };
        self.step_us = done.run_us;
        self.off_main = self.main_thread.is_some_and(|main| done.thread != main);
        if done.work.failed {
            done.work.failed = false;
            if !self.warned {
                self.warned = true;
                godot_warn!(
                    "ScsBrains.think_batch: a think panicked; the tick's thinks are held, their brains kept"
                );
            }
            self.pass_failures += 1;
        }
        for change in std::mem::take(&mut self.pending) {
            Self::apply(&mut done.work, &change);
        }
        self.work = Some(done.work);
        if done.from_rows
            && let Some(core) = self.core.as_mut()
        {
            core.bind_mut().take_commands(&mut done.snapshot.commands);
        }
        self.spare = Some(done.snapshot);
        self.last_out = Some(done.out);
    }

    // What the frame's readers see while the brains are away: every hosted driver's state, and the description and
    // path of every slot asked for since the last launch.
    fn refresh_views(&mut self) {
        let asked: Vec<usize> = self.asked.drain().collect();
        self.describe_cache.clear();
        self.path_cache.clear();
        for at in asked {
            let dict = self.describe_now(at);
            self.describe_cache.insert(at, dict);
            let path = self.path_now(at);
            self.path_cache.insert(at, path);
        }
        let Some(work) = self.work.as_ref() else {
            return;
        };
        self.mirror
            .resize_with(work.hosted.len(), HostedView::default);
        for (v, h) in self.mirror.iter_mut().zip(work.hosted.iter()) {
            v.slot = h.slot;
            v.thinks = h.thinks;
            v.dt = h.dt;
            v.attack_target = h.attack_target;
            v.out.clear();
            v.out.extend_from_slice(&h.out);
            v.steps = h.steps;
            v.since_think_s = h.since_think_s;
            v.woken = h.woken;
            v.near = h.near;
        }
    }

    // `describe` from the brains here.
    fn describe_now(&mut self, at: usize) -> VarDictionary {
        let mut dict = VarDictionary::new();
        let Some(brain) = self.work().slots.get(at).and_then(Option::as_ref) else {
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
        let mut scores = VarDictionary::new();
        for (i, kind) in brain.behaviours.iter().enumerate() {
            scores.set(
                KIND_NAMES[usize::from(*kind)],
                brain_maths::snapped(brain.weighted[i], 0.01),
            );
        }
        let names: Vec<(&str, i64)> = d.names.clone();
        let guard = self.core.as_ref().map(|c| c.bind());
        let (rows, row_names): (&Rows, &[GString]) = match &guard {
            Some(c) => (&c.rows, &c.row_names),
            None => (&self.own, &self.own_names),
        };
        for (key, id) in names {
            let name = name_of(rows, row_names, id);
            if key == "state" {
                dict.set("state", &GString::from(format!("to {name}").as_str()));
            } else {
                dict.set(key, &GString::from(name.as_str()));
            }
        }
        dict.set("scores", &scores);
        dict
    }

    // `path_visited` and `path_results` together: cached from the launch while the brains are away.
    fn path(&mut self, slot: i64) -> (PackedInt32Array, VarArray) {
        let Ok(at) = usize::try_from(slot) else {
            return (PackedInt32Array::new(), VarArray::new());
        };
        self.asked.insert(at);
        if self.work.is_none() {
            if let Some(cached) = self.path_cache.get(&at) {
                return cached.clone();
            }
            self.early_joins += 1;
            self.join();
        }
        let path = self.path_now(at);
        self.path_cache.insert(at, path.clone());
        path
    }

    fn path_now(&mut self, at: usize) -> (PackedInt32Array, VarArray) {
        let mut results = VarArray::new();
        let Some(brain) = self.work().slots.get(at).and_then(Option::as_ref) else {
            return (PackedInt32Array::new(), results);
        };
        let visited = PackedInt32Array::from(brain.path_visited());
        for r in brain.path_results() {
            let mut dict = outcome_dict(&r.outcome);
            dict.set(
                "demo",
                &GString::from(brain_maths::MANOEUVRE_NAMES[usize::from(r.demo)]),
            );
            dict.set("index", r.index);
            results.push(&dict.to_variant());
        }
        (visited, results)
    }

    fn brain_mut(&mut self, slot: i64) -> Option<&mut Brain> {
        let at = usize::try_from(slot).ok()?;
        self.work().slots.get_mut(at).and_then(Option::as_mut)
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
