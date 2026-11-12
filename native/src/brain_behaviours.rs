//! The AI pilot's behaviours in native code (M4-T17b, docs/architecture.md 17.13): `AiContext.refresh`, `AiPilot`'s scoring
//! and selection, and the nine behaviours (ram, retreat, evade, attack with `AttackBrain` and `AttackSlash`, guard,
//! formation, rally, follow path, idle), as a pure function of the core's frozen rows and one ship's state. The maths
//! repeats the GDScript step for step: 32-bit vectors, 64-bit scalars, a scalar rounded to 32 bits before it scales a
//! vector, the engine's order of operations and its rolls, so a native brain and its GDScript twin give the same bits.
//! Plain data in and out, the caller's scratch, no engine type (the guard in `test_sim_core` reads this file).
use std::f64::consts::TAU;

use godot::builtin::{Basis, Vector3};

use crate::brain_maths::{
    self, Capability, FlightCmd, Manoeuvre, Pcg, Pose, Temperament, hash_seed,
};
use crate::civilian;
use crate::kernels::{contact, pilot};
use crate::rows::{Bolts, Rows};
use crate::v3::{
    RIGHT, UP, add, clampf, col_b, col_c, cross, deg_to_rad, dist_sq, distance, div_s, dot, length,
    length_squared, limit_length, maxf, minf, neg, normalized, rad_to_deg, rotated, scale,
    snappedf, sub, xform,
};

/// The behaviour kinds in `AiPilot.TIE_ORDER`.
pub const KINDS: usize = 9;
pub const KIND_RAM: u8 = 0;
pub const KIND_RETREAT: u8 = 1;
pub const KIND_EVADE: u8 = 2;
pub const KIND_ATTACK: u8 = 3;
pub const KIND_GUARD: u8 = 4;
pub const KIND_FORMATION: u8 = 5;
pub const KIND_RALLY: u8 = 6;
pub const KIND_FOLLOW_PATH: u8 = 7;
pub const KIND_IDLE: u8 = 8;
pub const KIND_NAMES: [&str; KINDS] = [
    "ram",
    "retreat",
    "evade",
    "attack",
    "guard",
    "formation",
    "rally",
    "follow_path",
    "idle",
];

/// `AiContext.Order`.
pub const ORDER_ENGAGE_AT_WILL: u8 = 0;
pub const ORDER_ATTACK_MY_TARGET: u8 = 1;
pub const ORDER_FORM_ON_ME: u8 = 2;
pub const ORDER_COVER_ME: u8 = 3;

const SENSOR_RANGE_M: f64 = 5000.0;
const KEEP_ATTACKER_S: f64 = brain_maths::PROVOKED_S;
const URGENT_SEEK_HORIZON_S: f64 = 0.25;
const COVER_LEASH_M: f64 = 3000.0;
const TARGET_NONE: i64 = -1;

/// A ship's constants as its brain needs them: the capability, where the bolts leave (ship frame), the weapon's muzzle
/// speed and lifetime, the hull's bounding radius, and the avoidance tie-break (`hash(display_name)`).
#[derive(Clone, Copy, Debug, Default)]
pub struct Ship {
    pub capability: Capability,
    pub muzzle_local: Vector3,
    pub muzzle_speed_mps: f64,
    pub weapon_lifetime_s: f64,
    pub radius: f64,
    pub tie_hash: i64,
    pub own_body_id: i64,
    pub self_id: i64,
}

/// `RaiderTactics`.
#[derive(Clone, Copy, Debug, Default)]
pub struct Tactics {
    pub closing_far_mps: f64,
    pub closing_near_mps: f64,
    pub near_range_m: f64,
    pub face_lead_delta_v_mps: f64,
    pub fire_range_m: f64,
    pub fire_cone_deg: f64,
    pub fire_miss_m: f64,
    pub break_range_m: f64,
    pub max_time_on_target_s: f64,
    pub break_speed_mps: f64,
    pub break_duration_s: f64,
    pub extend_min_s: f64,
    pub extend_range_m: f64,
    pub max_speed_mps: f64,
}

/// `AiProfile` with its tactics: the pilot's character, as given (`base`) or scaled by the temperament (`profile`).
#[derive(Clone, Copy, Debug, Default)]
pub struct Profile {
    pub weights: [f64; KINDS],
    pub stickiness: f64,
    pub emergency_margin: f64,
    pub min_dwell_s: f64,
    pub retreat_below: f64,
    pub retreat_within_m: f64,
    pub cruise_mps: f64,
    pub aim_error_deg: f64,
    pub fires: bool,
    pub slashing: bool,
    pub idle_hold: bool,
    pub tactics: Tactics,
}

impl Profile {
    /// `AiTemperament.apply`: a copy with the weights, the retreat threshold, the aim error and the attack's miss gate,
    /// engage and break-off ranges scaled.
    pub fn scaled(&self, t: &Temperament) -> Profile {
        let mut out = *self;
        out.weights[KIND_ATTACK as usize] =
            t.weight(self.weights[KIND_ATTACK as usize], t.attack_weight_factor());
        out.weights[KIND_EVADE as usize] =
            t.weight(self.weights[KIND_EVADE as usize], t.evade_weight_factor());
        out.weights[KIND_RETREAT as usize] = t.weight(
            self.weights[KIND_RETREAT as usize],
            t.retreat_weight_factor(),
        );
        out.retreat_below = clampf(self.retreat_below * t.retreat_threshold_factor(), 0.0, 1.0);
        out.aim_error_deg = self.aim_error_deg * t.aim_factor();
        out.tactics.fire_miss_m = self.tactics.fire_miss_m * t.miss_factor();
        out.tactics.near_range_m = self.tactics.near_range_m * t.press_factor();
        out.tactics.break_range_m = self.tactics.break_range_m * t.press_factor();
        out
    }
}

/// What the driver gives a think beside the rows: the ship's hull and ids, the clock, the hits, the frame origin, the
/// settings, and its relation to each faction of the core's table.
pub struct Inputs<'a> {
    pub relations: &'a [u8],
    pub own_body_id: i64,
    pub now_s: f64,
    pub dt: f64,
    pub hull_fraction: f64,
    pub self_id: i64,
    pub selected_id: i64,
    pub last_hit_s: f64,
    pub last_bolt_hit_s: f64,
    pub last_attacker_id: i64,
    pub friendly_fire: bool,
    pub origin: [f64; 3],
    pub nearest_k: i64,
    pub static_k: i64,
    /// A low-attention tier row's think (M4-T22 fix round 2): it skips what a tier row cannot use, the rocks and mines, the
    /// incoming fire and the avoidance (a tier row collides with nothing and no bolt flies in a tier fight).
    pub lean: bool,
}

/// The per-ship scratch a think fills: the picked lists and the context's split (owned by the caller, reused).
#[derive(Default)]
pub struct Scratch {
    pub contacts: Vec<i32>,
    pub statics: Vec<i32>,
    pub broadcasts: Vec<i32>,
    pub lists: pilot::Lists,
    pub bolt_candidates: Vec<u32>,
    named: Vec<u32>,
    hostile_row: Vec<bool>,
    friendly_row: Vec<bool>,
}

/// What the host builds once per tick over the rows and bolts for every think: the bolts by grid cell with the fastest
/// bolt's speed (the incoming-fire query then visits the cells a bolt could reach the ship from), and the rows with a
/// broadcast reach, in row order.
#[derive(Default)]
pub struct Field {
    pub bolt_cells: Vec<((i32, i32, i32), u32)>,
    pub max_bolt_speed: f64,
    pub broadcasters: Vec<u32>,
    /// The ships' rows alone (no rocks or mines), in scan order: what the nearest-contacts query walks, the same contacts
    /// for fewer rows and no sort (M4-T22 fix round 2).
    pub ship_rows: Vec<u32>,
    /// The rows of every name a brain asks for (an objective or a guarded ship, lowered), in row order: matched once per
    /// rows version, not per think (M4-T18).
    pub named: Vec<(String, Vec<u32>)>,
    /// Civilians fleeing (M5-T16), by row, as their last thinks left them: running from a threat or an alarm, and of those
    /// the ones that see a threat themselves (their alarm spreads, Q25). Marked by the job before its pass, every tick.
    pub fleeing: Vec<bool>,
    pub alarmed: Vec<bool>,
}

impl Field {
    /// Builds the field for this tick's rows and bolts.
    pub fn build(&mut self, rows: &Rows, bolts: &Bolts, cell_m: f64) {
        contact::sorted_cells_into(&bolts.positions, cell_m, &mut self.bolt_cells);
        self.ship_rows.clear();
        self.ship_rows
            .extend((0..rows.positions.len() as u32).filter(|&i| !rows.is_static[i as usize]));
        self.max_bolt_speed = bolts
            .velocities
            .iter()
            .map(|v| f64::from(length(*v)))
            .fold(0.0, f64::max);
        self.broadcasters.clear();
        self.broadcasters.extend(
            (0..rows.reach.len())
                .filter(|&i| rows.reach[i] > 0.0)
                .map(|i| i as u32),
        );
    }

    /// Marks the fleeing civilians among `brains` on the rows (`row_of` gives a body's row, -1 for none): one pass over the
    /// brains before the thinks, so every think reads the same marks whatever thread runs it.
    pub fn mark_flight<'b>(
        &mut self,
        rows: &Rows,
        brains: impl Iterator<Item = &'b Brain>,
        row_of: impl Fn(i64) -> i64,
    ) {
        let n = rows.ids.len();
        self.fleeing.clear();
        self.alarmed.clear();
        for brain in brains {
            let Ok(r) = usize::try_from(row_of(brain.ship.own_body_id)) else {
                continue;
            };
            if r >= n || !rows.is_civilian(r) {
                continue;
            }
            // Sized on the first civilian: a tick with none marks nothing and costs one pass over the brains.
            if self.fleeing.len() != n {
                self.fleeing.resize(n, false);
                self.alarmed.resize(n, false);
            }
            let (fleeing, alarmed) = brain.flight_flags();
            self.fleeing[r] = fleeing;
            self.alarmed[r] = alarmed;
        }
    }

    /// Indexes the rows of each wanted name (empty names skipped, each name once).
    pub fn index_names<'a>(&mut self, rows: &Rows, wanted: impl Iterator<Item = &'a str>) {
        self.named.clear();
        for key in wanted {
            if key.is_empty() || self.named.iter().any(|(k, _)| k == key) {
                continue;
            }
            let list = rows_named(rows, key);
            self.named.push((key.to_string(), list));
        }
    }
}

// Every row named `key`, in row order.
fn rows_named(rows: &Rows, key: &str) -> Vec<u32> {
    let wanted = rows.name_id(key);
    if wanted == 0 {
        return Vec::new();
    }
    rows.name_ids
        .iter()
        .enumerate()
        .filter(|(_, n)| **n == wanted)
        .map(|(r, _)| r as u32)
        .collect()
}

/// A route a pilot leads (`Route`): waypoints as universe positions with a demo (kind + 1, 0 for none) and a hold.
#[derive(Clone, Debug, Default)]
pub struct Route {
    pub points: Vec<[f64; 3]>,
    pub demos: Vec<u8>,
    pub holds: Vec<f64>,
    pub cruise_mps: f64,
    pub pace_id: i64,
    pub loops: bool,
    pub yield_to_attack: bool,
}

impl Route {
    fn next_index(&self, index: usize) -> i64 {
        if index + 1 < self.points.len() {
            return (index + 1) as i64;
        }
        if self.loops && !self.points.is_empty() {
            0
        } else {
            -1
        }
    }

    fn pace_factor(lag_m: f64) -> f64 {
        clampf((1500.0 - lag_m) / (1500.0 - 600.0), 0.0, 1.0)
    }

    fn pace_speed(&self, lag_m: f64) -> f64 {
        self.cruise_mps * Self::pace_factor(lag_m)
    }

    fn should_wait(lag_m: f64, waiting: bool) -> bool {
        if waiting {
            lag_m >= 800.0
        } else {
            lag_m > 1600.0
        }
    }
}

/// The wing's view and the pilot's own fields of `AiContext`, set from outside the brain and kept across ticks.
#[derive(Clone, Debug, Default)]
pub struct Context {
    pub order: u8,
    pub leader_id: i64,
    pub leader_target_id: i64,
    pub engage_radius_m: f64,
    pub has_slot: bool,
    pub slot_offset: Vector3,
    pub wing_ids: Vec<i64>,
    pub link: Option<[f64; 3]>,
    pub link_velocity: Vector3,
    pub objective_key: String,
    /// The marker id of the row the objective's name matched in the latest think (0 for none), a readout.
    pub objective_id: i64,
    pub guard_post: Option<[f64; 3]>,
    pub guard_key: String,
    pub guard_id: i64,
    pub guard_offset: Vector3,
    pub guard_radius_m: f64,
    pub route: Option<Route>,
    pub attack_target_id: i64,
    pub current_target_id: i64,
}

impl Context {
    pub fn new() -> Self {
        Context {
            engage_radius_m: 2000.0,
            guard_radius_m: 1500.0,
            ..Default::default()
        }
    }

    /// `AiContext.clear_wing`.
    pub fn clear_wing(&mut self) {
        self.order = ORDER_ENGAGE_AT_WILL;
        self.leader_id = 0;
        self.leader_target_id = 0;
        self.engage_radius_m = 2000.0;
        self.has_slot = false;
        self.slot_offset = Vector3::ZERO;
        self.link = None;
        self.link_velocity = Vector3::ZERO;
        self.wing_ids.clear();
    }
}

// This tick's perception of the own ship, as `Perception` carries it.
#[derive(Clone, Copy)]
struct Percept {
    now_s: f64,
    position: Vector3,
    basis: Basis,
    velocity: Vector3,
    angular: Vector3,
    forward: Vector3,
    hull_fraction: f64,
    muzzle_offset: Vector3,
    incoming_fire: i64,
    last_hit_s: f64,
    last_bolt_hit_s: f64,
    last_attacker_id: i64,
    friendly_fire: bool,
    origin: [f64; 3],
}

impl Percept {
    fn pose(&self) -> Pose {
        Pose {
            now_s: self.now_s,
            position: self.position,
            basis: self.basis,
            velocity: self.velocity,
            angular: self.angular,
            origin: self.origin,
        }
    }

    fn local_of(&self, point: [f64; 3]) -> Vector3 {
        self.pose().local_of(point)
    }
}

// This tick's derived context (`AiContext.refresh`): the leader, the objective and the guard post as rows.
#[derive(Clone, Copy, Default)]
struct Derived {
    leader: i32,
    objective: i32,
    objective_range_m: f64,
    guarding: bool,
    guard_point: Vector3,
    guard_velocity: Vector3,
    guarded: i32,
}

/// Everything a behaviour reads this tick: the rows, the picked lists, the split and the own perception.
struct Tick<'a> {
    rows: &'a Rows,
    // The own row and the field's marks of fleeing civilians (M5-T16).
    own_row: usize,
    fleeing: &'a [bool],
    alarmed: &'a [bool],
    relations: &'a [u8],
    contacts: &'a [i32],
    broadcasts: &'a [i32],
    lists: &'a pilot::Lists,
    p: Percept,
    d: Derived,
    // The context's wing fields the behaviours read, copied so a behaviour needs no borrow of the brain.
    ctx_guard_radius_sq: f64,
    ctx_slot_offset: Vector3,
    ctx_link: Option<[f64; 3]>,
    ctx_link_velocity: Vector3,
}

impl Tick<'_> {
    // Contact `k`'s row.
    fn row(&self, k: usize) -> usize {
        self.contacts[k] as usize
    }

    fn relation(&self, row: usize) -> u8 {
        self.relations
            .get(self.rows.faction_ix[row] as usize)
            .copied()
            .unwrap_or(pilot::NEUTRAL)
    }

    // `Contact.forward` and `up`: the nose and the top, unit, as the scan stamps them.
    fn forward_of(&self, row: usize) -> Vector3 {
        neg(normalized(col_c(&self.rows.bases[row])))
    }

    fn up_of(&self, row: usize) -> Vector3 {
        normalized(col_b(&self.rows.bases[row]))
    }

    // Whether the thinking ship is a civilian hull (M5-T16).
    fn own_civilian(&self) -> bool {
        self.rows.is_civilian(self.own_row)
    }

    // The civilian flight's view of this think (M5-T16).
    fn civilian_view(&self, radius: f64, speed_mps: f64) -> civilian::View<'_> {
        civilian::View {
            rows: self.rows,
            contacts: self.contacts,
            own_row: self.own_row,
            radius,
            speed_mps,
            fleeing: self.fleeing,
        }
    }

    // How far from its centre a target's surface lies (M5-T16): a civilian hull's radius, so an attack's ranges are
    // measured to a 260 m freighter's skin; 0 for any other target, whose ranges stay centre to centre.
    fn surface_of(&self, target_id: i64) -> f64 {
        let r = self.rows.row_of_id(target_id);
        match usize::try_from(r) {
            Ok(j) if self.rows.is_civilian(j) => self.rows.radii[j],
            _ => 0.0,
        }
    }

    // Hostile `h` (a place in the hostile list) as a row.
    fn hostile_row(&self, h: usize) -> usize {
        self.row(self.lists.hostiles[h] as usize)
    }

    // `AiContext.in_guard_zone`.
    fn in_guard_zone(&self, row: usize) -> bool {
        if self.d.guarded >= 0
            && self.rows.target_ids[row] == self.rows.ids[self.d.guarded as usize]
        {
            return true;
        }
        f64::from(dist_sq(self.rows.positions[row], self.d.guard_point)) <= self.ctx_guard_radius_sq
    }
}

impl<'a> Tick<'a> {
    #[allow(clippy::too_many_arguments)]
    fn new(
        rows: &'a Rows,
        field: &'a Field,
        own_row: usize,
        relations: &'a [u8],
        contacts: &'a [i32],
        broadcasts: &'a [i32],
        lists: &'a pilot::Lists,
        p: Percept,
        d: Derived,
        ctx: &Context,
    ) -> Self {
        Tick {
            rows,
            own_row,
            fleeing: &field.fleeing,
            alarmed: &field.alarmed,
            relations,
            contacts,
            broadcasts,
            lists,
            p,
            d,
            ctx_guard_radius_sq: ctx.guard_radius_m * ctx.guard_radius_m,
            ctx_slot_offset: ctx.slot_offset,
            ctx_link: ctx.link,
            ctx_link_velocity: ctx.link_velocity,
        }
    }
}

// --- the brain ---------------------------------------------------------------------------------------------------------

/// A pilot's brain: `AiPilot` with its behaviours and their states.
pub struct Brain {
    pub base: Profile,
    pub temperament: Temperament,
    pub profile: Profile,
    pub ship: Ship,
    pub ctx: Context,
    pub behaviours: Vec<u8>,
    weights: Vec<f64>,
    pub raw: Vec<f64>,
    pub weighted: Vec<f64>,
    pub current: i32,
    pub dwell_s: f64,
    pub switches: i64,
    reacted_hit_s: f64,
    pub wanted_target_id: i64,
    pub avoid_exempt_id: i64,
    pub has_desired_velocity: bool,
    pub desired_velocity: Vector3,
    pub desired_all_axes: bool,
    pub avoiding: bool,
    pub avoiding_urgent: bool,
    pub contacts_seen: i64,
    ram: RamState,
    retreat: RetreatState,
    evade: EvadeState,
    attack: AttackState,
    guard: GuardState,
    formation: FormationState,
    rally: RallyState,
    path: PathState,
}

/// What one think gives back: the command and the mirrored state.
#[derive(Clone, Copy, Debug, Default)]
pub struct Output {
    pub flight: FlightCmd,
    pub fire: bool,
}

impl Brain {
    /// `AiPilot._init`: the profile scaled by the temperament, the behaviours given (in tie order), each retuned.
    pub fn new(base: Profile, temperament: Temperament, seed: i64, kinds: &[u8]) -> Self {
        let profile = base.scaled(&temperament);
        let mut brain = Brain {
            base,
            temperament,
            profile,
            ship: Ship::default(),
            ctx: Context::new(),
            behaviours: Vec::new(),
            weights: Vec::new(),
            raw: Vec::new(),
            weighted: Vec::new(),
            current: -1,
            dwell_s: 0.0,
            switches: 0,
            reacted_hit_s: f64::NEG_INFINITY,
            wanted_target_id: TARGET_NONE,
            avoid_exempt_id: 0,
            has_desired_velocity: false,
            desired_velocity: Vector3::ZERO,
            desired_all_axes: false,
            avoiding: false,
            avoiding_urgent: false,
            contacts_seen: 0,
            ram: RamState::new(hash_seed(seed, "ram")),
            retreat: RetreatState::new(&profile),
            evade: EvadeState::new(hash_seed(seed, "evade")),
            attack: AttackState::new(&profile, hash_seed(seed, "attack")),
            guard: GuardState::new(&profile),
            formation: FormationState::new(&profile),
            rally: RallyState::new(&profile),
            path: PathState::default(),
        };
        for &kind in kinds {
            brain.add_behaviour(kind);
        }
        brain
    }

    /// `AiPilot.add_behaviour`: at its tie-order place, retuned, weighted by the profile.
    pub fn add_behaviour(&mut self, kind: u8) -> bool {
        if usize::from(kind) >= KINDS || self.behaviours.contains(&kind) {
            return false;
        }
        let at = self
            .behaviours
            .iter()
            .position(|&k| k > kind)
            .unwrap_or(self.behaviours.len());
        if self.current >= at as i32 {
            self.current += 1;
        }
        self.behaviours.insert(at, kind);
        self.weights
            .insert(at, self.profile.weights[usize::from(kind)]);
        self.raw.insert(at, 0.0);
        self.weighted.insert(at, 0.0);
        self.retune_one(kind);
        true
    }

    /// `AiPilot.set_temperament`: skill and aggression change live and every behaviour retunes.
    pub fn set_temperament(&mut self, temperament: Temperament) {
        self.temperament = temperament;
        self.profile = self.base.scaled(&temperament);
        let kinds: Vec<u8> = self.behaviours.clone();
        for (i, kind) in kinds.iter().enumerate() {
            self.retune_one(*kind);
            self.weights[i] = self.profile.weights[usize::from(*kind)];
        }
    }

    fn retune_one(&mut self, kind: u8) {
        match kind {
            KIND_RAM => self.ram.retune(&self.temperament),
            KIND_RETREAT => self.retreat.retune(&self.profile),
            KIND_EVADE => self.evade.retune(&self.temperament),
            KIND_ATTACK => self.attack.retune(&self.profile, &self.temperament),
            _ => {}
        }
    }

    /// `AiPilot.reset`: back to the starting state, every behaviour's too.
    pub fn reset(&mut self) {
        self.current = -1;
        self.dwell_s = 0.0;
        self.switches = 0;
        self.reacted_hit_s = f64::NEG_INFINITY;
        self.avoid_exempt_id = 0;
        for v in self.raw.iter_mut() {
            *v = 0.0;
        }
        for v in self.weighted.iter_mut() {
            *v = 0.0;
        }
        self.wanted_target_id = TARGET_NONE;
        self.ram.reset();
        self.retreat.reset();
        self.evade.reset();
        self.attack.reset();
        self.guard.reset();
        self.formation.reset();
        self.rally.reset();
        self.path.reset();
    }

    /// The place of `kind` among the behaviours, or -1.
    pub fn index_of(&self, kind: u8) -> i32 {
        self.behaviours
            .iter()
            .position(|&k| k == kind)
            .map_or(-1, |i| i as i32)
    }

    pub fn current_kind(&self) -> i32 {
        if self.current < 0 {
            -1
        } else {
            i32::from(self.behaviours[self.current as usize])
        }
    }

    /// `BehaviourRam.commit` from outside (a test seam the facade mirrors).
    pub fn ram_commit(&mut self, target_id: i64) {
        self.ram.committed = true;
        self.ram.target_id_value = target_id;
    }

    /// What the last think left of a civilian's flight (M5-T16): fleeing (running from a threat or an alarm, or dodging
    /// fire) and alarmed (doing so from a threat it saw itself, whose alarm spreads to its people, Q25).
    pub fn flight_flags(&self) -> (bool, bool) {
        match u8::try_from(self.current_kind()) {
            Ok(KIND_RETREAT) => (true, self.retreat.threatened),
            Ok(KIND_EVADE) => (true, true),
            _ => (false, false),
        }
    }

    /// Whether the ram is committed now (the facade's GDScript flag follows it every think).
    pub fn ram_committed(&self) -> bool {
        self.ram.committed
    }

    /// `BehaviourRam.commit` called between thinks: commits to the target the last think would have picked (the attack's
    /// target, else the nearest hostile) and returns its id, 0 when there was none.
    pub fn ram_commit_now(&mut self) -> i64 {
        if self.ram.pick != 0 {
            self.ram.committed = true;
            self.ram.target_id_value = self.ram.pick;
        }
        self.ram.pick
    }

    /// `AiPilot.keep_ids`: the contacts kept beyond the nearest k.
    fn keep_ids(&self, out: &mut Vec<i64>) {
        out.clear();
        out.extend_from_slice(&self.ctx.wing_ids);
        for id in [
            self.ctx.leader_id,
            self.ctx.leader_target_id,
            self.ctx.current_target_id,
            self.ctx.attack_target_id,
        ] {
            if id > 0 {
                out.push(id);
            }
        }
        if let Some(route) = &self.ctx.route
            && route.pace_id != 0
        {
            out.push(route.pace_id);
        }
        if self.wanted_target_id > 0 {
            out.push(self.wanted_target_id);
        }
    }

    /// One think (`AiPilotDriver.step` from the perception to the command): the lists picked from the rows as the driver
    /// picks them, `AiContext.refresh`, the selection, the behaviour in control, the avoidance filter and the re-seek.
    /// None when the ship has no row this tick.
    #[allow(clippy::too_many_arguments)]
    pub fn think(
        &mut self,
        rows: &Rows,
        bolts: &Bolts,
        work: &mut contact::Work<'_>,
        field: &Field,
        own_row: usize,
        scratch: &mut Scratch,
        keep_scratch: &mut Vec<i64>,
        inputs: &Inputs,
    ) -> Output {
        // The perception of the own row.
        let basis = rows.bases[own_row];
        let p = Percept {
            now_s: inputs.now_s,
            position: rows.positions[own_row],
            basis,
            velocity: rows.velocities[own_row],
            angular: rows.angular[own_row],
            forward: neg(col_c(&basis)),
            hull_fraction: inputs.hull_fraction,
            muzzle_offset: xform(&basis, self.ship.muzzle_local),
            incoming_fire: 0,
            last_hit_s: inputs.last_hit_s,
            last_bolt_hit_s: inputs.last_bolt_hit_s,
            last_attacker_id: inputs.last_attacker_id,
            friendly_fire: inputs.friendly_fire,
            origin: inputs.origin,
        };
        // The lists, as `ContactScan` picks them: the nearest k (the nearest hostile and the keeps when the cut left any
        // out), the nearest statics, the incoming fire and the broadcasts.
        let view = contact::View {
            body_ids: &rows.body_ids,
            positions: &rows.positions,
            body_faction: &rows.faction_ix,
            is_ship: &rows.rigid,
            reach: &rows.reach,
            is_static: &rows.is_static,
            is_mine: &rows.is_mine,
            radii: &rows.radii,
            bolt_positions: &bolts.positions,
            bolt_velocities: &bolts.velocities,
            bolt_faction: &bolts.faction_ix,
            bolt_shooters: &bolts.shooters,
        };
        scratch.hostile_row.clear();
        scratch.friendly_row.clear();
        for &r in inputs.relations {
            scratch.hostile_row.push(r == pilot::HOSTILE);
            scratch.friendly_row.push(r == pilot::FRIENDLY);
        }
        contact::nearest_among(
            &view,
            work.query,
            &field.ship_rows,
            Some(&scratch.hostile_row),
            inputs.own_body_id,
            p.position,
            inputs.nearest_k,
            SENSOR_RANGE_M,
            &mut scratch.contacts,
        );
        if scratch.contacts.last() == Some(&-1) {
            scratch.contacts.pop();
            self.keep_ids(keep_scratch);
            if inputs.selected_id != 0 {
                keep_scratch.push(inputs.selected_id);
            }
            if inputs.last_attacker_id != 0 && inputs.now_s - inputs.last_hit_s <= KEEP_ATTACKER_S {
                keep_scratch.push(inputs.last_attacker_id);
            }
            let range_sq = SENSOR_RANGE_M * SENSOR_RANGE_M;
            for &id in keep_scratch.iter() {
                if id > 0 {
                    keep(
                        rows,
                        &mut scratch.contacts,
                        rows.row_of_id(id),
                        inputs.own_body_id,
                        p.position,
                        range_sq,
                    );
                }
            }
            // Every row with the objective's or the guarded ship's name, as `ContactScan._keep_named` keeps them: from the
            // tick's name index, or matched now for a name pushed since it was built.
            for key in [&self.ctx.objective_key, &self.ctx.guard_key] {
                if key.is_empty() {
                    continue;
                }
                scratch.named.clear();
                match field.named.iter().find(|(k, _)| k == key) {
                    Some((_, list)) => scratch.named.extend_from_slice(list),
                    None => {
                        let wanted = rows.name_id(key);
                        if wanted != 0 {
                            scratch.named.extend(
                                rows.name_ids
                                    .iter()
                                    .enumerate()
                                    .filter(|(_, n)| **n == wanted)
                                    .map(|(r, _)| r as u32),
                            );
                        }
                    }
                }
                for i in 0..scratch.named.len() {
                    keep(
                        rows,
                        &mut scratch.contacts,
                        scratch.named[i] as i32,
                        inputs.own_body_id,
                        p.position,
                        range_sq,
                    );
                }
            }
            scratch.contacts.sort_unstable();
        }
        if inputs.lean {
            scratch.statics.clear();
        } else {
            contact::statics_into(
                &view,
                work,
                &scratch.friendly_row,
                inputs.own_body_id,
                p.position,
                inputs.static_k,
                SENSOR_RANGE_M,
                &mut scratch.statics,
            );
        }
        let mut p = p;
        // No bolt can be incoming from farther than the fastest bolt and the ship's own speed carry in the horizon, plus
        // the miss distance: the grid gives the same count as the loop over every bolt.
        let reach_max = (field.max_bolt_speed + f64::from(length(p.velocity))) * 2.0 + 15.0 + 1.0;
        p.incoming_fire = if inputs.lean {
            0
        } else {
            contact::incoming_near(
                &view,
                &scratch.hostile_row,
                inputs.own_body_id,
                p.position,
                p.velocity,
                &field.bolt_cells,
                work.grid.cell_m,
                reach_max,
                &mut scratch.bolt_candidates,
            )
        };
        contact::broadcasts_among(
            &view,
            &field.broadcasters,
            inputs.own_body_id,
            p.position,
            SENSOR_RANGE_M,
            &mut scratch.broadcasts,
        );
        self.contacts_seen = scratch.contacts.len() as i64;
        // `AiContext.refresh`.
        pilot::context_lists(
            rows,
            inputs.relations,
            &scratch.contacts,
            p.position,
            inputs.self_id,
            self.ctx.leader_id,
            &mut scratch.lists,
        );
        let mut tick = Tick::new(
            rows,
            field,
            own_row,
            inputs.relations,
            &scratch.contacts,
            &scratch.broadcasts,
            &scratch.lists,
            p,
            Derived {
                leader: -1,
                objective: -1,
                objective_range_m: f64::INFINITY,
                guarding: false,
                guard_point: Vector3::ZERO,
                guard_velocity: Vector3::ZERO,
                guarded: -1,
            },
            &self.ctx,
        );
        let mut d = tick.d;
        if scratch.lists.leader >= 0 {
            d.leader = scratch.contacts[scratch.lists.leader as usize];
        }
        if !self.ctx.guard_key.is_empty() {
            let guarded = first_named(rows, &scratch.contacts, &self.ctx.guard_key);
            self.ctx.guard_id = if guarded >= 0 {
                rows.ids[guarded as usize]
            } else {
                0
            };
            if guarded >= 0 {
                let g = guarded as usize;
                let forward = tick.forward_of(g);
                let up = tick.up_of(g);
                let right = cross(forward, up);
                let o = self.ctx.guard_offset;
                d.guard_point = sub(
                    add(add(rows.positions[g], scale(right, o.x)), scale(up, o.y)),
                    scale(forward, o.z),
                );
                d.guard_velocity = rows.velocities[g];
                d.guarding = true;
                d.guarded = guarded;
            }
        } else if let Some(post) = self.ctx.guard_post {
            d.guard_point = p.local_of(post);
            d.guard_velocity = Vector3::ZERO;
            d.guarding = true;
        }
        if !self.ctx.objective_key.is_empty() {
            let mut objective = first_named(rows, &scratch.contacts, &self.ctx.objective_key);
            if objective < 0 {
                objective = first_named(rows, &scratch.broadcasts, &self.ctx.objective_key);
            }
            self.ctx.objective_id = if objective >= 0 {
                rows.ids[objective as usize]
            } else {
                0
            };
            if objective >= 0 {
                d.objective = objective;
                d.objective_range_m =
                    f64::from(distance(rows.positions[objective as usize], p.position));
            }
        }
        tick.d = d;
        // `AiPilot.think`.
        self.select(&tick, inputs.dt);
        let mut out = Output::default();
        self.has_desired_velocity = false;
        self.desired_all_axes = false;
        if self.current < 0 {
            self.wanted_target_id = TARGET_NONE;
        } else {
            let kind = self.behaviours[self.current as usize];
            let mut cmd = FlightCmd::default();
            let mut fire = false;
            let mut wish = Wish::default();
            match kind {
                KIND_RAM => self.ram.think(&tick, &self.ship, &mut cmd, &mut wish),
                KIND_RETREAT => self.retreat.think(&tick, &self.ship, &mut cmd, &mut wish),
                KIND_EVADE => self
                    .evade
                    .think(&tick, &self.ship, inputs.dt, &mut cmd, &mut wish),
                KIND_ATTACK => {
                    fire = self
                        .attack
                        .think(&tick, &self.ship, inputs.dt, &mut cmd, &mut wish)
                }
                KIND_GUARD => self.guard.think(&tick, &self.ship, &mut cmd, &mut wish),
                KIND_FORMATION => self
                    .formation
                    .think(&tick, &self.ship, inputs.dt, &mut cmd, &mut wish),
                KIND_RALLY => self.rally.think(&tick, &self.ship, &mut cmd, &mut wish),
                KIND_FOLLOW_PATH => self.path.think(
                    &tick,
                    &self.ship,
                    &self.ctx.route,
                    inputs.dt,
                    &mut cmd,
                    &mut wish,
                ),
                _ => cmd.brake = self.profile.idle_hold,
            }
            self.desired_velocity = wish.velocity;
            self.has_desired_velocity = wish.has;
            self.desired_all_axes = wish.all_axes;
            self.wanted_target_id = match kind {
                KIND_ATTACK => self.attack.target_id(),
                KIND_RAM => self.ram.target_id(),
                KIND_FOLLOW_PATH => self.path.target_id(&self.ctx.route),
                _ => TARGET_NONE,
            };
            self.ctx.current_target_id = self.wanted_target_id.max(0);
            if kind == KIND_ATTACK && self.wanted_target_id > 0 {
                self.ctx.attack_target_id = self.wanted_target_id;
            }
            self.avoid_exempt_id = if kind == KIND_RAM && self.ram.committed {
                self.ram.target_id_value
            } else {
                0
            };
            if !self.profile.fires {
                fire = false;
            }
            out.flight = cmd;
            out.fire = fire;
        }
        self.ram.remember_pick(&tick, &self.ctx);
        // `AiPilotDriver._avoid`: the brain's wish through the avoidance filter, re-sought when it changed.
        self.avoiding = false;
        self.avoiding_urgent = false;
        if !inputs.lean
            && !out.flight.brake
            && !(scratch.contacts.is_empty() && scratch.statics.is_empty())
        {
            let wish = if self.has_desired_velocity {
                self.desired_velocity
            } else {
                p.velocity
            };
            let cap = &self.ship.capability;
            let avoided = pilot::avoid(
                rows,
                &pilot::Ship {
                    position: p.position,
                    velocity: p.velocity,
                    radius: self.ship.radius,
                    a_retro: cap.a_retro,
                    rate_max_x: f64::from(cap.rate_max.x),
                    rate_max_y: f64::from(cap.rate_max.y),
                    a_rcs_x: cap.a_rcs_x,
                    a_rcs_y: cap.a_rcs_y,
                    tie_hash: self.ship.tie_hash,
                },
                &scratch.contacts,
                &scratch.statics,
                self.avoid_exempt_id,
                wish,
            );
            if avoided.v_des != wish {
                self.avoiding = true;
                self.avoiding_urgent = avoided.urgent;
                let horizon = if avoided.urgent {
                    URGENT_SEEK_HORIZON_S
                } else {
                    brain_maths::HORIZON_S
                };
                brain_maths::apply_seek(
                    &mut out.flight,
                    &brain_maths::seek(
                        p.velocity,
                        avoided.v_des,
                        &p.basis,
                        cap,
                        horizon,
                        self.has_desired_velocity && self.desired_all_axes,
                    ),
                );
            }
        }
        out
    }

    // `AiPilot.select`: scores the behaviours and hands control over by the rule.
    fn select(&mut self, tick: &Tick, dt: f64) {
        self.dwell_s += dt;
        let mut best: i32 = -1;
        let mut best_score = 0.0;
        for i in 0..self.behaviours.len() {
            let weight = self.weights[i];
            let raw = if weight > 0.0 {
                clampf(self.score(self.behaviours[i], tick), 0.0, 1.0)
            } else {
                0.0
            };
            let weighted = raw * weight;
            self.raw[i] = raw;
            self.weighted[i] = weighted;
            if weighted > best_score {
                best_score = weighted;
                best = i as i32;
            }
        }
        let evade_index = self.index_of(KIND_EVADE);
        if evade_index >= 0 && self.weights[evade_index as usize] > 0.0 {
            let hit_s = tick.p.last_bolt_hit_s;
            let committed = self.current_kind() == i32::from(KIND_RAM) && self.ram.committed;
            if hit_s > self.reacted_hit_s
                && !committed
                && tick.p.now_s + dt - hit_s >= self.temperament.reaction_s() - 1e-6
            {
                self.reacted_hit_s = hit_s;
                if self.current != evade_index {
                    self.switch_to(evade_index);
                }
                self.evade.on_hit();
                return;
            }
            if self.current == evade_index && self.evade.locked() {
                return;
            }
        }
        if best < 0 {
            let idle = self.index_of(KIND_IDLE);
            if idle >= 0 && idle != self.current {
                self.switch_to(idle);
            }
            return;
        }
        if best == self.current {
            return;
        }
        if self.current < 0 {
            self.switch_to(best);
            return;
        }
        let current_score = self.weighted[self.current as usize];
        let lead_needed = if self.dwell_s < self.profile.min_dwell_s {
            self.profile.emergency_margin
        } else {
            self.profile.stickiness
        };
        if current_score <= 0.0 || best_score > current_score + lead_needed {
            self.switch_to(best);
        }
    }

    fn score(&mut self, kind: u8, tick: &Tick) -> f64 {
        match kind {
            KIND_RAM => self.ram.score(tick, &self.ctx),
            KIND_RETREAT => self.retreat.score(tick, &self.ctx),
            KIND_EVADE => self.evade.score(tick, &self.ctx),
            KIND_ATTACK => self.attack.score(tick, &self.ctx),
            KIND_GUARD => self.guard.score(tick, &self.ctx),
            KIND_FORMATION => self.formation.score(tick, &self.ctx),
            KIND_RALLY => self.rally.score(tick, &self.ctx),
            KIND_FOLLOW_PATH => self.path.score(tick, &self.ctx),
            _ => IDLE_SCORE,
        }
    }

    fn switch_to(&mut self, index: i32) {
        self.current = index;
        self.dwell_s = 0.0;
        self.switches += 1;
        match self.behaviours[index as usize] {
            KIND_ATTACK => self.attack.enter(),
            KIND_EVADE => self.evade.enter(),
            KIND_FORMATION => self.formation.enter(),
            KIND_FOLLOW_PATH => self.path.enter(),
            _ => {}
        }
    }

    // --- the mirrored state and the console ---------------------------------------------------------------------

    /// The behaviour in control's state the facade mirrors into its GDScript objects, up to `MIRROR` numbers.
    pub fn mirror(&self, out: &mut [f64; MIRROR]) {
        *out = [0.0; MIRROR];
        match self.current_kind() {
            k if k == i32::from(KIND_ATTACK) => {
                let a = &self.attack;
                out[0] = f64::from(u8::from(a.uses_slash));
                out[1] = f64::from(a.brain.state);
                out[2] = f64::from(u8::from(a.brain.firing));
                out[3] = a.brain.on_target_s;
                out[4] = a.brain.state_time_s;
                out[5] = f64::from(a.slash.state);
                out[6] = f64::from(u8::from(a.slash.firing));
                out[7] = f64::from(u8::from(a.slash.in_gate));
                out[8] = a.slash.passes as f64;
                out[9] = a.slash.time_on_target_s;
                out[10] = a.slash.state_time_s;
                out[11] = f64::from(u8::from(a.transit));
            }
            k if k == i32::from(KIND_EVADE) => {
                out[0] = self.evade.jinks as f64;
                out[1] = self.evade.jink_left_s;
                out[2] = self.evade.lock_until_jinks as f64;
            }
            k if k == i32::from(KIND_RAM) => {
                out[0] = f64::from(u8::from(self.ram.committed));
                out[1] = self.ram.rolls as f64;
                out[2] = self.ram.max_friends_seen as f64;
                let (hi, lo) = split_id(self.ram.target_id_value);
                out[3] = hi;
                out[4] = lo;
            }
            k if k == i32::from(KIND_FORMATION) => {
                out[0] = self.formation.slot_error_m;
                out[1] = f64::from(u8::from(self.formation.on_link));
            }
            k if k == i32::from(KIND_GUARD) => out[0] = self.guard.post_error_m,
            k if k == i32::from(KIND_FOLLOW_PATH) => {
                out[0] = self.path.index as f64;
                out[1] = f64::from(self.path.phase);
                out[2] = self.path.lag_m;
                out[3] = self.path.visited.len() as f64;
                out[4] = self.path.results.len() as f64;
                out[5] = self.path.hold_left_s;
            }
            _ => {}
        }
    }

    /// The console's `describe()` for the behaviour in control (`behaviour`, `state`, `for_s` and its own fields); the
    /// shell adds the scores and resolves the ids to names.
    pub fn describe(&self) -> Describe {
        let mut d = Describe::default();
        let kind = self.current_kind();
        d.behaviour = if kind < 0 {
            "none".to_string()
        } else {
            KIND_NAMES[kind as usize].to_string()
        };
        d.for_s = if kind < 0 {
            0.0
        } else {
            snappedf(self.dwell_s, 0.1)
        };
        d.state = "none".to_string();
        if kind < 0 {
            return d;
        }
        match kind as u8 {
            KIND_ATTACK => self.attack.describe(&mut d),
            KIND_EVADE => self.evade.describe(&mut d),
            KIND_RETREAT => self.retreat.describe(&mut d),
            KIND_RAM => self.ram.describe(&mut d),
            KIND_FORMATION => self.formation.describe(&mut d),
            KIND_GUARD => self.guard.describe(&mut d),
            KIND_RALLY => self.rally.describe(&mut d),
            KIND_FOLLOW_PATH => self.path.describe(&self.ctx.route, &mut d),
            _ => {
                d.state = if self.profile.idle_hold {
                    "hold"
                } else {
                    "coast"
                }
                .to_string()
            }
        }
        d
    }

    /// `BehaviourFollowPath.visited` and the finished demos' results, for the facade's mirror.
    pub fn path_visited(&self) -> &[i32] {
        &self.path.visited
    }

    pub fn path_results(&self) -> &[PathResult] {
        &self.path.results
    }
}

/// `MIRROR` numbers of behaviour state ride on every think's output.
pub const MIRROR: usize = 12;
const IDLE_SCORE: f64 = 0.05;

/// A `describe()` in plain data: the fields a behaviour reports, ids for the shell to name.
#[derive(Clone, Debug, Default)]
pub struct Describe {
    pub behaviour: String,
    pub state: String,
    pub for_s: f64,
    pub numbers: Vec<(&'static str, f64)>,
    pub flags: Vec<(&'static str, bool)>,
    pub ints: Vec<(&'static str, i64)>,
    pub texts: Vec<(&'static str, String)>,
    /// Fields that name a contact by its id (the shell looks the name up).
    pub names: Vec<(&'static str, i64)>,
}

/// One finished demo's result (`BehaviourFollowPath.results`): the manoeuvre's outcome, its kind and the waypoint.
#[derive(Clone, Debug)]
pub struct PathResult {
    pub outcome: brain_maths::Outcome,
    pub demo: u8,
    pub index: i64,
}

/// The id as two non-negative halves that fit a double exactly (the facade puts them back together).
pub fn split_id(id: i64) -> (f64, f64) {
    if id <= 0 {
        return (id as f64, 0.0);
    }
    let u = id as u64;
    ((u >> 32) as f64, (u & 0xffff_ffff) as f64)
}

// A behaviour's wish this tick (`seek_velocity`).
#[derive(Clone, Copy, Default)]
struct Wish {
    velocity: Vector3,
    has: bool,
    all_axes: bool,
}

// `AiBehaviour.seek_velocity`: the thrust toward `v_des` into `cmd` and the wish recorded.
fn seek_velocity(
    cmd: &mut FlightCmd,
    p: &Percept,
    cap: &Capability,
    v_des: Vector3,
    all_axes: bool,
    wish: &mut Wish,
) {
    wish.velocity = v_des;
    wish.has = true;
    wish.all_axes = all_axes;
    brain_maths::apply_seek(
        cmd,
        &brain_maths::seek(
            p.velocity,
            v_des,
            &p.basis,
            cap,
            brain_maths::HORIZON_S,
            all_axes,
        ),
    );
}


// The first row of `list` named `wanted`, as `AiContext._named` finds it among the contacts every tick (M4-T18: a parked
// or far row with the same name earlier in the rows never hides the listed one); -1 for none.
fn first_named(rows: &Rows, list: &[i32], wanted: &str) -> i32 {
    // An empty wanted name, or one no row was ever given, matches nothing.
    let wanted = rows.name_id(wanted);
    if wanted == 0 {
        return -1;
    }
    list.iter()
        .copied()
        .find(|&r| r >= 0 && rows.name_ids[r as usize] == wanted)
        .unwrap_or(-1)
}

// `ContactScan._keep`: adds row `i` to a nearest-k selection when it is in range, not the ship's own and not in it yet.
fn keep(rows: &Rows, chosen: &mut Vec<i32>, i: i32, own_body_id: i64, at: Vector3, range_sq: f64) {
    if i < 0 {
        return;
    }
    let j = i as usize;
    if rows.body_ids[j] != own_body_id
        && !chosen.contains(&i)
        && f64::from(dist_sq(rows.positions[j], at)) <= range_sq
        && !rows.is_static[j]
    {
        chosen.push(i);
    }
}

// `AiContext.may_attack` for hostile `h` (a place in the hostile list).
fn may_attack(tick: &Tick, ctx: &Context, h: usize) -> bool {
    let row = tick.hostile_row(h);
    if tick.d.guarding && !tick.in_guard_zone(row) {
        return false;
    }
    match ctx.order {
        ORDER_FORM_ON_ME => false,
        ORDER_ATTACK_MY_TARGET => {
            ctx.leader_target_id != 0 && tick.rows.ids[row] == ctx.leader_target_id
        }
        ORDER_COVER_ME => {
            if tick.d.leader < 0 {
                return ctx.link.is_none();
            }
            let leader_at = tick.rows.positions[tick.d.leader as usize];
            if f64::from(dist_sq(tick.p.position, leader_at)) > COVER_LEASH_M * COVER_LEASH_M {
                return false;
            }
            f64::from(dist_sq(tick.rows.positions[row], leader_at))
                <= ctx.engage_radius_m * ctx.engage_radius_m
        }
        _ => true,
    }
}

// `AiContext.has_attackable`.
fn has_attackable(tick: &Tick, ctx: &Context) -> bool {
    match ctx.order {
        ORDER_FORM_ON_ME => return false,
        ORDER_ENGAGE_AT_WILL if !tick.d.guarding => return !tick.lists.hostiles.is_empty(),
        _ => {}
    }
    (0..tick.lists.hostiles.len()).any(|h| may_attack(tick, ctx, h))
}

fn may_retreat(ctx: &Context) -> bool {
    ctx.order != ORDER_FORM_ON_ME
}

// --- ram ---------------------------------------------------------------------------------------------------------------

struct RamState {
    may_ram: bool,
    seed: i64,
    rng: Pcg,
    committed: bool,
    target_id_value: i64,
    rolls: i64,
    max_friends_seen: i64,
    eligible_since_s: f64,
    target: i32,
    // The target `commit` would take as of the last think (the attack's target, else the nearest hostile), for a commit
    // from outside between thinks; 0 for none.
    pick: i64,
}

impl RamState {
    const HULL_BELOW: f64 = 0.25;
    const ALLIES_LEFT_SHARE: f64 = 0.25;
    const ROLL_EVERY_S: f64 = 5.0;
    const COMMIT_CHANCE: f64 = 0.35;
    const CLOSURE_MPS: f64 = 200.0;

    fn new(seed: i64) -> Self {
        let mut s = RamState {
            may_ram: false,
            seed,
            rng: Pcg::seeded(seed),
            committed: false,
            target_id_value: 0,
            rolls: 0,
            max_friends_seen: 0,
            eligible_since_s: f64::NEG_INFINITY,
            target: -1,
            pick: 0,
        };
        s.reset();
        s
    }

    // Remembers the target a commit from outside would take now.
    fn remember_pick(&mut self, tick: &Tick, ctx: &Context) {
        let mut pick = Self::hostile(tick, ctx.current_target_id);
        if pick < 0 {
            let mut best = f64::INFINITY;
            for h in 0..tick.lists.hostiles.len() {
                if tick.lists.ranges[h] < best {
                    best = tick.lists.ranges[h];
                    pick = tick.hostile_row(h) as i32;
                }
            }
        }
        self.pick = if pick >= 0 {
            tick.rows.ids[pick as usize]
        } else {
            0
        };
    }

    fn retune(&mut self, t: &Temperament) {
        self.may_ram = t.may_ram();
        if !self.may_ram {
            self.committed = false;
        }
    }

    fn reset(&mut self) {
        self.rng = Pcg::seeded(self.seed);
        self.committed = false;
        self.target_id_value = 0;
        self.rolls = 0;
        self.max_friends_seen = 0;
        self.eligible_since_s = f64::NEG_INFINITY;
        self.target = -1;
    }

    // `BehaviourRam._hostile`: the hostile with this id, as a row, or -1.
    fn hostile(tick: &Tick, wanted: i64) -> i32 {
        if wanted == 0 {
            return -1;
        }
        for h in 0..tick.lists.hostiles.len() {
            let row = tick.hostile_row(h);
            if tick.rows.ids[row] == wanted {
                return row as i32;
            }
        }
        -1
    }

    fn score(&mut self, tick: &Tick, ctx: &Context) -> f64 {
        if !self.may_ram {
            return 0.0;
        }
        if self.committed {
            self.target = Self::hostile(tick, self.target_id_value);
            if self.target < 0 {
                self.committed = false;
                self.target_id_value = 0;
                self.eligible_since_s = f64::NEG_INFINITY;
                return 0.0;
            }
            return 1.0;
        }
        let mut friends: i64 = 0;
        for k in 0..tick.contacts.len() {
            let row = tick.row(k);
            if tick.rows.rigid[row] && tick.relation(row) == pilot::FRIENDLY {
                friends += 1;
            }
        }
        self.max_friends_seen = self.max_friends_seen.max(friends);
        let eligible = tick.p.hull_fraction < Self::HULL_BELOW
            && friends as f64 <= Self::ALLIES_LEFT_SHARE * self.max_friends_seen as f64
            && !tick.lists.hostiles.is_empty();
        if !eligible {
            self.eligible_since_s = f64::NEG_INFINITY;
            return 0.0;
        }
        if self.eligible_since_s == f64::NEG_INFINITY {
            self.eligible_since_s = tick.p.now_s - Self::ROLL_EVERY_S;
        }
        while tick.p.now_s - self.eligible_since_s >= Self::ROLL_EVERY_S {
            self.eligible_since_s += Self::ROLL_EVERY_S;
            self.rolls += 1;
            if f64::from(self.rng.randf()) < Self::COMMIT_CHANCE {
                self.commit(tick, ctx);
                break;
            }
        }
        if self.committed { 1.0 } else { 0.0 }
    }

    // `BehaviourRam.commit`: the attack's target, else the nearest hostile ship.
    fn commit(&mut self, tick: &Tick, ctx: &Context) -> bool {
        let mut pick = Self::hostile(tick, ctx.current_target_id);
        if pick < 0 {
            let mut best = f64::INFINITY;
            for h in 0..tick.lists.hostiles.len() {
                if tick.lists.ranges[h] < best {
                    best = tick.lists.ranges[h];
                    pick = tick.hostile_row(h) as i32;
                }
            }
        }
        if pick < 0 {
            return false;
        }
        self.committed = true;
        self.target_id_value = tick.rows.ids[pick as usize];
        self.target = pick;
        true
    }

    fn think(&mut self, tick: &Tick, ship: &Ship, cmd: &mut FlightCmd, wish: &mut Wish) {
        if self.target < 0 {
            return;
        }
        let p = &tick.p;
        let t = self.target as usize;
        let los = sub(tick.rows.positions[t], p.position);
        let los_dir = if f64::from(length(los)) > 1e-3 {
            normalized(los)
        } else {
            p.forward
        };
        let v_des = add(
            tick.rows.velocities[t],
            scale(los_dir, Self::CLOSURE_MPS as f32),
        );
        let dv = sub(v_des, p.velocity);
        cmd.rot = brain_maths::face(
            &p.basis,
            if f64::from(length(dv)) > 5.0 {
                dv
            } else {
                los_dir
            },
            ship.capability.rate_max,
            brain_maths::K_FACE,
        );
        seek_velocity(cmd, p, &ship.capability, v_des, true, wish);
    }

    fn target_id(&self) -> i64 {
        if self.committed {
            self.target_id_value
        } else {
            TARGET_NONE
        }
    }

    fn describe(&self, d: &mut Describe) {
        d.state = if self.committed {
            "committed"
        } else {
            "not committed"
        }
        .to_string();
        d.names.push((
            "target",
            if self.committed {
                self.target_id_value
            } else {
                0
            },
        ));
        d.ints.push(("rolls", self.rolls));
    }
}

// --- retreat -----------------------------------------------------------------------------------------------------------

struct RetreatState {
    retreat_below: f64,
    speed_mps: f64,
    retreat_within_m: f64,
    from_id: i64,
    from_range_m: f64,
    // The civilian flight (M5-T16): whether the last think saw a threat (its alarm spreads), until when an alarm keeps it
    // running, the alarm the last score heard (a row, -1 none), and the ship it runs to and whether it shelters there.
    threatened: bool,
    panic_until_s: f64,
    alarm_row: i32,
    goal_id: i64,
    shelter: bool,
}

impl RetreatState {
    const EXTRA_MPS: f64 = 50.0;
    const SCORE_MIN: f64 = 0.85;

    fn new(profile: &Profile) -> Self {
        RetreatState {
            retreat_below: profile.retreat_below,
            speed_mps: profile.cruise_mps + Self::EXTRA_MPS,
            retreat_within_m: 0.0,
            from_id: 0,
            from_range_m: -1.0,
            threatened: false,
            panic_until_s: f64::NEG_INFINITY,
            alarm_row: -1,
            goal_id: 0,
            shelter: false,
        }
    }

    fn retune(&mut self, profile: &Profile) {
        self.retreat_below = profile.retreat_below;
        self.speed_mps = profile.cruise_mps + Self::EXTRA_MPS;
        self.retreat_within_m = profile.retreat_within_m;
    }

    fn reset(&mut self) {
        self.threatened = false;
        self.panic_until_s = f64::NEG_INFINITY;
        self.alarm_row = -1;
        self.goal_id = 0;
        self.shelter = false;
    }

    fn score(&mut self, tick: &Tick, ctx: &Context) -> f64 {
        if !may_retreat(ctx) {
            return 0.0;
        }
        // A civilian runs on its people's alarm too (Q25), with no threat of its own in sight.
        let panicked = tick.own_civilian() && self.panicked(tick);
        if tick.lists.hostiles.is_empty() {
            return if panicked { Self::SCORE_MIN } else { 0.0 };
        }
        let hull = tick.p.hull_fraction;
        let mut low = 0.0;
        if self.retreat_below > 0.0 && hull < self.retreat_below {
            low = Self::SCORE_MIN + (1.0 - Self::SCORE_MIN) * (1.0 - hull / self.retreat_below);
        }
        if self.retreat_within_m > 0.0 && low < Self::SCORE_MIN {
            for &d in &tick.lists.ranges {
                if d <= self.retreat_within_m {
                    return Self::SCORE_MIN;
                }
            }
        }
        if panicked && low < Self::SCORE_MIN {
            return Self::SCORE_MIN;
        }
        low
    }

    // Whether an alarm keeps this civilian running: one heard now (it holds `PANIC_HOLD_S` on), or one heard lately.
    fn panicked(&mut self, tick: &Tick) -> bool {
        self.alarm_row = civilian::nearest_alarm(&tick.civilian_view(0.0, self.speed_mps), tick.alarmed);
        if self.alarm_row >= 0 {
            self.panic_until_s = tick.p.now_s + civilian::PANIC_HOLD_S;
        }
        tick.p.now_s < self.panic_until_s
    }

    fn think(&mut self, tick: &Tick, ship: &Ship, cmd: &mut FlightCmd, wish: &mut Wish) {
        let p = &tick.p;
        let mut away = Vector3::ZERO;
        let mut threat: i32 = -1;
        self.from_id = 0;
        self.from_range_m = f64::INFINITY;
        self.goal_id = 0;
        self.shelter = false;
        for h in 0..tick.lists.hostiles.len() {
            let row = tick.hostile_row(h);
            let off = sub(p.position, tick.rows.positions[row]);
            let d = maxf(f64::from(length(off)), 1.0);
            away = add(away, div_s(off, (d * d) as f32));
            if d < self.from_range_m {
                self.from_range_m = d;
                self.from_id = tick.rows.ids[row];
                threat = row as i32;
            }
        }
        self.threatened = threat >= 0;
        if f64::from(length_squared(away)) < 1e-18 {
            away = p.forward;
        }
        let dir = normalized(away);
        // A civilian runs to its people (Q24, Q25); every other ship, and a civilian with nobody to run to, straight away.
        let flight = if !tick.own_civilian() {
            None
        } else if let Ok(t) = usize::try_from(threat) {
            civilian::flee_from(
                &tick.civilian_view(ship.radius, self.speed_mps),
                dir,
                tick.rows.positions[t],
            )
        } else {
            Some(civilian::flee_alarm(
                &tick.civilian_view(ship.radius, self.speed_mps),
                self.alarm_row,
            ))
        };
        let Some(flight) = flight else {
            cmd.rot =
                brain_maths::face(&p.basis, dir, ship.capability.rate_max, brain_maths::K_FACE);
            seek_velocity(
                cmd,
                p,
                &ship.capability,
                scale(dir, self.speed_mps as f32),
                false,
                wish,
            );
            return;
        };
        if let Ok(g) = usize::try_from(flight.goal) {
            self.goal_id = tick.rows.ids[g];
            self.shelter = flight.shelter;
        }
        let face_dir = if f64::from(length(flight.velocity)) > 1.0 {
            normalized(flight.velocity)
        } else {
            dir
        };
        cmd.rot = brain_maths::face(&p.basis, face_dir, ship.capability.rate_max, brain_maths::K_FACE);
        seek_velocity(cmd, p, &ship.capability, flight.velocity, false, wish);
    }

    fn describe(&self, d: &mut Describe) {
        d.state = if self.shelter {
            "shelter".to_string()
        } else if self.goal_id != 0 {
            "to_kin".to_string()
        } else {
            "extend".to_string()
        };
        d.names.push(("from", self.from_id));
        if self.goal_id != 0 {
            d.names.push(("goal", self.goal_id));
        }
        d.numbers.push((
            "range_m",
            if self.from_range_m < f64::INFINITY && self.from_range_m >= 0.0 {
                snappedf(self.from_range_m, 1.0)
            } else {
                -1.0
            },
        ));
    }
}

// --- evade -------------------------------------------------------------------------------------------------------------

struct EvadeState {
    seed: i64,
    rng: Pcg,
    side: Vector3,
    jink_left_s: f64,
    jinks: i64,
    threat: i32,
    threat_id: i64,
    reason: u8,
    base_velocity: Vector3,
    fresh: bool,
    lock_until_jinks: i64,
    jink_scale: f64,
    spread_deg: f64,
    reaction_s: f64,
    awareness: f64,
    threat_since_s: f64,
    cos_cone: f64,
}

impl EvadeState {
    const RANGE_M: f64 = 1200.0;
    const NOSE_CONE_DEG: f64 = 15.0;
    const HIT_MEMORY_S: f64 = 2.0;
    const TAIL_SCORE_MIN: f64 = 0.75;
    const INCOMING_SCORE: f64 = 0.6;
    const HIT_SCORE: f64 = 0.5;
    const JINK_MIN_S: f32 = 2.0;
    const JINK_MAX_S: f32 = 4.0;
    const JINK_SPEED_MPS: f32 = 100.0;
    const REVERSAL_SPREAD_DEG: f64 = 45.0;
    const REASON_NAMES: [&'static str; 4] = ["", "tail", "fire", "hit"];

    fn new(seed: i64) -> Self {
        let mut s = EvadeState {
            seed,
            rng: Pcg::seeded(seed),
            side: Vector3::ZERO,
            jink_left_s: 0.0,
            jinks: 0,
            threat: -1,
            threat_id: 0,
            reason: 0,
            base_velocity: Vector3::ZERO,
            fresh: true,
            lock_until_jinks: 0,
            jink_scale: 1.0,
            spread_deg: Self::REVERSAL_SPREAD_DEG,
            reaction_s: 0.0,
            awareness: 1.0,
            threat_since_s: f64::NEG_INFINITY,
            cos_cone: deg_to_rad(Self::NOSE_CONE_DEG).cos(),
        };
        s.reset();
        s
    }

    fn reset(&mut self) {
        self.rng = Pcg::seeded(self.seed);
        self.side = Vector3::ZERO;
        self.jink_left_s = 0.0;
        self.jinks = 0;
        self.threat = -1;
        self.threat_id = 0;
        self.reason = 0;
        self.fresh = true;
        self.lock_until_jinks = 0;
        self.threat_since_s = f64::NEG_INFINITY;
    }

    fn retune(&mut self, t: &Temperament) {
        self.jink_scale = t.jink_factor();
        self.spread_deg = t.reversal_spread_deg();
        self.reaction_s = t.reaction_s();
        self.awareness = t.awareness();
    }

    fn score(&mut self, tick: &Tick, ctx: &Context) -> f64 {
        let p = &tick.p;
        self.threat = -1;
        self.threat_id = 0;
        self.reason = 0;
        let mut best = 0.0;
        for h in 0..tick.lists.hostiles.len() {
            let d = tick.lists.ranges[h];
            if d > Self::RANGE_M || d < 1e-3 {
                continue;
            }
            let off = neg(tick.lists.offsets[h]);
            if dot(p.forward, off) <= 0.0 {
                continue;
            }
            let row = tick.hostile_row(h);
            if f64::from(dot(tick.forward_of(row), div_s(off, d as f32))) < self.cos_cone {
                continue;
            }
            let s = Self::TAIL_SCORE_MIN + (1.0 - Self::TAIL_SCORE_MIN) * (1.0 - d / Self::RANGE_M);
            if s > best {
                best = s;
                self.threat = row as i32;
                self.reason = 1;
            }
        }
        if best < Self::INCOMING_SCORE && p.incoming_fire > 0 {
            best = Self::INCOMING_SCORE;
            self.reason = 2;
        }
        if best > 0.0 {
            if self.threat_since_s == f64::NEG_INFINITY {
                self.threat_since_s = p.now_s;
            }
            if p.now_s - self.threat_since_s < self.reaction_s - 1e-6 {
                best = 0.0;
                self.threat = -1;
                self.reason = 0;
            }
        } else {
            self.threat_since_s = f64::NEG_INFINITY;
        }
        if best < Self::HIT_SCORE && p.now_s - p.last_hit_s < Self::HIT_MEMORY_S {
            best = Self::HIT_SCORE;
            self.reason = 3;
        }
        if best > 0.0 && self.threat < 0 {
            self.threat = Self::likely_shooter(tick);
        }
        if self.threat >= 0 {
            self.threat_id = tick.rows.ids[self.threat as usize];
        }
        if best > 0.0
            && self.reason != 3
            && self.threat >= 0
            && self.threat_id != ctx.attack_target_id
        {
            best = clampf(best * self.awareness, 0.0, 1.0);
        }
        best
    }

    fn enter(&mut self) {
        self.fresh = true;
        self.lock_until_jinks = 0;
    }

    fn on_hit(&mut self) {
        self.lock_until_jinks = if self.fresh { 2 } else { self.jinks + 2 };
    }

    fn locked(&self) -> bool {
        self.jinks < self.lock_until_jinks
    }

    fn think(&mut self, tick: &Tick, ship: &Ship, dt: f64, cmd: &mut FlightCmd, wish: &mut Wish) {
        let p = &tick.p;
        let mut line_of_fire = p.forward;
        if self.threat >= 0 {
            let at = tick.rows.positions[self.threat as usize];
            if f64::from(dist_sq(at, p.position)) > 1e-6 {
                line_of_fire = normalized(sub(p.position, at));
            }
        }
        if self.fresh {
            self.fresh = false;
            self.base_velocity = p.velocity;
            self.jinks = 0;
            self.new_jink(line_of_fire);
        } else {
            self.jink_left_s -= dt;
            if self.jink_left_s <= 0.0 {
                self.new_jink(line_of_fire);
            }
        }
        let across = self.across(line_of_fire);
        let v_des = add(self.base_velocity, scale(across, Self::JINK_SPEED_MPS));
        let dv = sub(v_des, p.velocity);
        cmd.rot = brain_maths::face(
            &p.basis,
            if f64::from(length(dv)) > 1.0 {
                dv
            } else {
                across
            },
            ship.capability.rate_max,
            brain_maths::K_FACE,
        );
        seek_velocity(cmd, p, &ship.capability, v_des, false, wish);
    }

    // `BehaviourEvade._likely_shooter`: the nearest hostile aiming at us, else the one pointing closest.
    fn likely_shooter(tick: &Tick) -> i32 {
        let mut aiming: i32 = -1;
        let mut aiming_d2 = f64::INFINITY;
        let mut closest: i32 = -1;
        let mut closest_dot = f64::NEG_INFINITY;
        for h in 0..tick.lists.hostiles.len() {
            let row = tick.hostile_row(h);
            let off = sub(tick.p.position, tick.rows.positions[row]);
            let d2 = f64::from(length_squared(off));
            if d2 < 1e-6 {
                continue;
            }
            let d = f64::from(dot(tick.forward_of(row), div_s(off, d2.sqrt() as f32)));
            if d >= deg_to_rad(Self::NOSE_CONE_DEG).cos() && d2 < aiming_d2 {
                aiming_d2 = d2;
                aiming = row as i32;
            }
            if d > closest_dot {
                closest_dot = d;
                closest = row as i32;
            }
        }
        if aiming >= 0 { aiming } else { closest }
    }

    fn new_jink(&mut self, line_of_fire: Vector3) {
        if self.jinks == 0 {
            let angle = self.rng.randf_range(0.0, std::f32::consts::TAU);
            self.side = rotated(Self::perpendicular(line_of_fire), line_of_fire, angle);
        } else {
            let spread = self.spread_deg as f32;
            let angle = deg_to_rad(f64::from(self.rng.randf_range(-spread, spread)));
            self.side = rotated(neg(self.across(line_of_fire)), line_of_fire, angle as f32);
        }
        self.jink_left_s =
            f64::from(self.rng.randf_range(Self::JINK_MIN_S, Self::JINK_MAX_S)) * self.jink_scale;
        self.jinks += 1;
    }

    fn across(&self, line_of_fire: Vector3) -> Vector3 {
        let s = sub(self.side, scale(line_of_fire, dot(self.side, line_of_fire)));
        if f64::from(length_squared(s)) < 0.01 {
            return Self::perpendicular(line_of_fire);
        }
        normalized(s)
    }

    fn perpendicular(v: Vector3) -> Vector3 {
        let helper = if f64::from(dot(v, UP)).abs() < 0.95 {
            UP
        } else {
            RIGHT
        };
        normalized(cross(v, helper))
    }

    fn describe(&self, d: &mut Describe) {
        d.state = format!(
            "jink {} ({})",
            self.jinks,
            Self::REASON_NAMES[usize::from(self.reason)]
        );
        d.names.push(("threat", self.threat_id));
        d.numbers
            .push(("jink_left_s", snappedf(self.jink_left_s, 0.1)));
    }
}

// --- attack ------------------------------------------------------------------------------------------------------------

const ATTACK_W_NEAR: f64 = 0.4;
const ATTACK_W_CLOSING: f64 = 0.2;
const ATTACK_W_ATTACKING_FRIEND: f64 = 0.3;
const ATTACK_W_DAMAGED: f64 = 0.1;
const ATTACK_KEEP_BONUS: f64 = 0.1;
const ATTACK_CLOSING_FULL_MPS: f64 = 200.0;
const ATTACK_SCORE_BASE: f64 = 0.3;
const ATTACK_SCORE_SPAN: f64 = 0.5;
const ATTACK_INV_SENSOR_RANGE: f64 = 1.0 / SENSOR_RANGE_M;
const ATTACK_OBJECTIVE_VALUE: f64 = 1.0;
const ATTACK_TRANSIT_MAX_MPS: f64 = 1000.0;
const ATTACK_TRANSIT_BRAKE_FRACTION: f64 = 0.5;

struct AttackState {
    seed: i64,
    aim_error_rad: f64,
    target: i32,
    target_id: i64,
    target_is_objective: bool,
    engaged_id: i64,
    time_s: f64,
    transit: bool,
    passive: bool,
    uses_slash: bool,
    slash_chance: f64,
    close_pass_chance: f64,
    run_rng: Pcg,
    last_brain_state: u8,
    last_slash_state: u8,
    wander: [f64; 8],
    brain: AttackBrainState,
    slash: SlashState,
}

impl AttackState {
    fn new(profile: &Profile, seed: i64) -> Self {
        let mut s = AttackState {
            seed,
            aim_error_rad: deg_to_rad(profile.aim_error_deg),
            target: -1,
            target_id: 0,
            target_is_objective: false,
            engaged_id: 0,
            time_s: 0.0,
            transit: false,
            passive: false,
            uses_slash: false,
            slash_chance: 0.0,
            close_pass_chance: 0.0,
            run_rng: Pcg::seeded(0),
            last_brain_state: 0,
            last_slash_state: 0,
            wander: [0.0; 8],
            brain: AttackBrainState::new(profile.tactics, hash_seed(seed, "attack brain")),
            slash: SlashState::new(profile.tactics),
        };
        s.reset();
        s
    }

    fn retune(&mut self, profile: &Profile, t: &Temperament) {
        self.brain.tactics = profile.tactics;
        self.aim_error_rad = deg_to_rad(profile.aim_error_deg);
        self.passive = t.never_starts();
        self.slash.tactics = profile.tactics;
        self.slash_chance = if profile.slashing {
            t.slash_chance()
        } else {
            0.0
        };
        self.close_pass_chance = t.close_pass_chance();
        self.roll_run();
    }

    fn reset(&mut self) {
        self.brain.reset();
        self.slash.reset();
        self.run_rng = Pcg::seeded(hash_seed(self.seed, "runs"));
        self.roll_run();
        self.target = -1;
        self.target_id = 0;
        self.target_is_objective = false;
        self.engaged_id = 0;
        self.time_s = 0.0;
        self.transit = false;
        let mut rng = Pcg::seeded(hash_seed(self.seed, "aim"));
        for axis in 0..2 {
            let k = axis * 4;
            self.wander[k] = f64::from(rng.randf_range(0.05, 0.15));
            self.wander[k + 1] = f64::from(rng.randf_range(0.15, 0.35));
            self.wander[k + 2] = f64::from(rng.randf_range(0.0, std::f32::consts::TAU));
            self.wander[k + 3] = f64::from(rng.randf_range(0.0, std::f32::consts::TAU));
        }
    }

    fn roll_run(&mut self) {
        self.uses_slash =
            self.slash_chance > 0.0 && f64::from(self.run_rng.randf()) < self.slash_chance;
        self.slash.pass_offset_m = if f64::from(self.run_rng.randf()) < self.close_pass_chance {
            SlashState::CLOSE_PASS_OFFSET_M
        } else {
            SlashState::PASS_OFFSET_M
        };
    }

    fn score(&mut self, tick: &Tick, ctx: &Context) -> f64 {
        let p = &tick.p;
        let keep_id = if self.target_id != 0 {
            self.target_id
        } else {
            self.engaged_id
        };
        self.target = -1;
        self.target_id = 0;
        self.target_is_objective = false;
        let mut best = f64::NEG_INFINITY;
        let mut at_will = ctx.order == ORDER_ENGAGE_AT_WILL && !tick.d.guarding;
        let mut provoker: i64 = 0;
        if self.passive {
            at_will = false;
            if p.last_attacker_id != 0 && p.now_s - p.last_hit_s <= brain_maths::PROVOKED_S {
                provoker = p.last_attacker_id;
            }
        }
        for h in 0..tick.lists.hostiles.len() {
            let row = tick.hostile_row(h);
            let id = tick.rows.ids[row];
            if self.passive && id != provoker {
                continue;
            }
            if !at_will && !may_attack(tick, ctx, h) {
                continue;
            }
            let los = tick.lists.offsets[h];
            // A big civilian hull is as near as its skin (M5-T16): a raider picks a freighter by how close it really is.
            let d = if tick.rows.is_civilian(row) {
                maxf(tick.lists.ranges[h] - tick.rows.radii[row], 1e-3)
            } else {
                tick.lists.ranges[h]
            };
            let mut value = ATTACK_W_NEAR * clampf(1.0 - d * ATTACK_INV_SENSOR_RANGE, 0.0, 1.0);
            if d > 1e-3 {
                let closing = f64::from(dot(sub(p.velocity, tick.rows.velocities[row]), los));
                value +=
                    ATTACK_W_CLOSING * clampf(closing / (d * ATTACK_CLOSING_FULL_MPS), 0.0, 1.0);
            }
            if tick.lists.friendly_ids.contains(&tick.rows.target_ids[row]) {
                value += ATTACK_W_ATTACKING_FRIEND;
            }
            let hull = tick.rows.hull_fraction[row];
            if hull >= 0.0 {
                value += ATTACK_W_DAMAGED * (1.0 - hull);
            }
            if id == keep_id {
                value += ATTACK_KEEP_BONUS;
            }
            if value > best {
                best = value;
                self.target = row as i32;
                self.target_id = id;
            }
        }
        if self.target < 0 {
            if tick.d.objective >= 0 && ctx.order != ORDER_FORM_ON_ME && !self.passive {
                self.target = tick.d.objective;
                self.target_id = tick.rows.ids[tick.d.objective as usize];
                self.target_is_objective = true;
                return clampf(
                    ATTACK_SCORE_BASE + ATTACK_SCORE_SPAN * ATTACK_OBJECTIVE_VALUE,
                    0.0,
                    1.0,
                );
            }
            return 0.0;
        }
        // The same body as the objective is the objective's contact too (the GDScript compares the one object).
        self.target_is_objective = self.target == tick.d.objective;
        clampf(ATTACK_SCORE_BASE + ATTACK_SCORE_SPAN * best, 0.0, 1.0)
    }

    fn enter(&mut self) {
        self.engaged_id = 0;
    }

    // Returns whether the trigger is held.
    fn think(
        &mut self,
        tick: &Tick,
        ship: &Ship,
        dt: f64,
        cmd: &mut FlightCmd,
        wish: &mut Wish,
    ) -> bool {
        self.transit = false;
        if self.target < 0 {
            self.brain.firing = false;
            return false;
        }
        if self.target_is_objective && tick.d.objective_range_m > SENSOR_RANGE_M {
            self.transit_to(tick, ship, tick.d.objective_range_m, cmd, wish);
            return false;
        }
        if self.target_id != self.engaged_id {
            self.engaged_id = self.target_id;
            self.roll_run();
            self.slash.restart();
            self.brain.restart();
        } else if self.uses_slash
            && self.slash.state == SlashState::PASS
            && self.last_slash_state != SlashState::PASS
        {
            self.roll_run();
            if !self.uses_slash {
                self.brain.restart();
            }
        } else if !self.uses_slash
            && self.brain.state == AttackBrainState::APPROACH
            && self.last_brain_state == AttackBrainState::EXTEND
        {
            self.roll_run();
            if self.uses_slash {
                self.slash.restart();
            }
        }
        self.last_slash_state = self.slash.state;
        self.last_brain_state = self.brain.state;
        self.time_s += dt;
        let aim = self.aim_offset_at(self.time_s);
        self.brain.aim_offset_rad = aim;
        self.slash.aim_offset_rad = aim;
        let t = self.target as usize;
        let target_position = tick.rows.positions[t];
        let target_velocity = tick.rows.velocities[t];
        let surface_m = tick.surface_of(self.target_id);
        if self.uses_slash {
            self.slash.engage(
                tick,
                ship,
                self.target_id,
                target_position,
                target_velocity,
                surface_m,
                dt,
                cmd,
                wish,
            )
        } else {
            self.brain.engage(
                tick,
                ship,
                self.target_id,
                target_position,
                target_velocity,
                surface_m,
                dt,
                cmd,
                wish,
            )
        }
    }

    fn target_id(&self) -> i64 {
        if self.target >= 0 {
            self.target_id
        } else {
            TARGET_NONE
        }
    }

    // `BehaviourAttack._transit_to`: closes on a far objective as fast as the ship can still stop by the near scan's edge.
    fn transit_to(
        &mut self,
        tick: &Tick,
        ship: &Ship,
        range_m: f64,
        cmd: &mut FlightCmd,
        wish: &mut Wish,
    ) {
        self.transit = true;
        self.engaged_id = 0;
        self.brain.firing = false;
        let p = &tick.p;
        let t = self.target as usize;
        let los_dir = div_s(sub(tick.rows.positions[t], p.position), range_m as f32);
        let brake = ATTACK_TRANSIT_BRAKE_FRACTION * ship.capability.a_main;
        let arrive = (2.0 * brake * maxf(range_m - SENSOR_RANGE_M, 0.0)).sqrt();
        let v_des = add(
            tick.rows.velocities[t],
            scale(
                los_dir,
                clampf(
                    arrive,
                    self.brain.tactics.closing_far_mps,
                    ATTACK_TRANSIT_MAX_MPS,
                ) as f32,
            ),
        );
        let dv = sub(v_des, p.velocity);
        cmd.rot = brain_maths::face(
            &p.basis,
            if f64::from(length(dv)) > 1.0 {
                normalized(dv)
            } else {
                los_dir
            },
            ship.capability.rate_max,
            brain_maths::K_FACE,
        );
        seek_velocity(cmd, p, &ship.capability, v_des, false, wish);
    }

    // `BehaviourAttack.aim_offset_at`: the slowly wandering lead offset, radians right and up, as a Vector2.
    fn aim_offset_at(&self, t_s: f64) -> (f32, f32) {
        if self.aim_error_rad <= 0.0 {
            return (0.0, 0.0);
        }
        let mut out = [0.0f32; 2];
        for (axis, slot) in out.iter_mut().enumerate() {
            let k = axis * 4;
            let w = &self.wander;
            *slot = (self.aim_error_rad
                * (0.6 * (TAU * w[k] * t_s + w[k + 2]).sin()
                    + 0.4 * (TAU * w[k + 1] * t_s + w[k + 3]).sin())) as f32;
        }
        (out[0], out[1])
    }

    fn describe(&self, d: &mut Describe) {
        if self.target < 0 && self.target_id == 0 {
            d.state = "no target".to_string();
            return;
        }
        d.names.push(("target", self.target_id));
        if self.transit {
            d.state = "transit".to_string();
            d.flags.push(("firing", false));
            return;
        }
        let (state, range_m, firing) = if self.uses_slash {
            (
                SlashState::STATE_NAMES[usize::from(self.slash.state)],
                self.slash.last_range_m,
                self.slash.firing,
            )
        } else {
            (
                AttackBrainState::STATE_NAMES[usize::from(self.brain.state)],
                self.brain.last_range_m,
                self.brain.firing,
            )
        };
        d.state = state.to_string();
        d.numbers.push((
            "range_m",
            if range_m < f64::INFINITY {
                snappedf(range_m, 1.0)
            } else {
                -1.0
            },
        ));
        d.flags.push(("firing", firing));
    }
}

// The lead turned by the aim error (`AttackBrain._offset`, `AttackSlash._offset`).
fn aim_offset(lead_dir: Vector3, aim: (f32, f32)) -> Vector3 {
    let helper = if f64::from(dot(lead_dir, UP)).abs() < 0.95 {
        UP
    } else {
        RIGHT
    };
    let right = normalized(cross(lead_dir, helper));
    let up = cross(right, lead_dir);
    normalized(add(
        add(lead_dir, scale(right, f64::from(aim.0).tan() as f32)),
        scale(up, f64::from(aim.1).tan() as f32),
    ))
}

// `FireLane.clear_seen` along the nose.
fn lane_clear(tick: &Tick, range_m: f64, target_id: i64) -> bool {
    pilot::fire_lane(
        tick.rows,
        tick.relations,
        tick.contacts,
        tick.p.position,
        tick.p.forward,
        range_m,
        target_id,
        tick.p.friendly_fire,
    )
}

struct AttackBrainState {
    tactics: Tactics,
    state: u8,
    state_time_s: f64,
    on_target_s: f64,
    firing: bool,
    lead_error_deg: f64,
    aim_offset_rad: (f32, f32),
    seed: i64,
    side: f64,
    rng: Pcg,
    last_range_m: f64,
}

impl AttackBrainState {
    const APPROACH: u8 = 0;
    const BREAK: u8 = 1;
    const EXTEND: u8 = 2;
    const STATE_NAMES: [&'static str; 3] = ["approach", "break", "extend"];

    fn new(tactics: Tactics, seed: i64) -> Self {
        let mut s = AttackBrainState {
            tactics,
            state: Self::APPROACH,
            state_time_s: 0.0,
            on_target_s: 0.0,
            firing: false,
            lead_error_deg: 0.0,
            aim_offset_rad: (0.0, 0.0),
            seed,
            side: 1.0,
            rng: Pcg::seeded(seed),
            last_range_m: f64::INFINITY,
        };
        s.reset();
        s
    }

    fn reset(&mut self) {
        self.state = Self::APPROACH;
        self.state_time_s = 0.0;
        self.on_target_s = 0.0;
        self.firing = false;
        self.rng = Pcg::seeded(self.seed);
        self.side = if f64::from(self.rng.randf()) < 0.5 {
            1.0
        } else {
            -1.0
        };
        self.last_range_m = f64::INFINITY;
    }

    fn restart(&mut self) {
        self.enter(Self::APPROACH);
        self.firing = false;
        self.last_range_m = f64::INFINITY;
    }

    fn enter(&mut self, next: u8) {
        self.state = next;
        self.state_time_s = 0.0;
        if next == Self::APPROACH {
            self.on_target_s = 0.0;
        }
        if next == Self::BREAK {
            self.side = if f64::from(self.rng.randf()) < 0.5 {
                1.0
            } else {
                -1.0
            };
        }
    }

    // Perpendicular to the line of sight, on the seeded side.
    fn across(&self, los_dir: Vector3) -> Vector3 {
        let up = if f64::from(dot(los_dir, UP)).abs() < 0.95 {
            UP
        } else {
            RIGHT
        };
        scale(normalized(cross(los_dir, up)), self.side as f32)
    }

    // `AttackBrain.engage`: one tick of the gun run. Returns whether the trigger is held.
    #[allow(clippy::too_many_arguments)]
    fn engage(
        &mut self,
        tick: &Tick,
        ship: &Ship,
        target_id: i64,
        target_position: Vector3,
        target_velocity: Vector3,
        surface_m: f64,
        dt: f64,
        cmd: &mut FlightCmd,
        wish: &mut Wish,
    ) -> bool {
        let p = &tick.p;
        self.firing = false;
        let los = sub(target_position, p.position);
        let range_m = f64::from(length(los));
        if range_m < 1e-3 {
            return false;
        }
        // The run's ranges and miss gate to a big hull's skin (M5-T16); centre to centre for every other target.
        let (gap_m, miss_m) = if surface_m > 0.0 {
            (maxf(range_m - surface_m, 1.0), self.tactics.fire_miss_m + 0.5 * surface_m)
        } else {
            (range_m, self.tactics.fire_miss_m)
        };
        self.last_range_m = range_m;
        let los_dir = div_s(los, range_m as f32);
        self.state_time_s += dt;
        let lead = brain_maths::solve(
            add(p.position, p.muzzle_offset),
            p.velocity,
            target_position,
            target_velocity,
            ship.muzzle_speed_mps,
            ship.weapon_lifetime_s,
        );
        let mut lead_dir = if lead.ok { lead.aim_dir } else { los_dir };
        if self.aim_offset_rad != (0.0, 0.0) {
            lead_dir = aim_offset(lead_dir, self.aim_offset_rad);
        }
        let mut v_des = Vector3::ZERO;
        let mut face_dir = lead_dir;
        let t = self.tactics;
        let mut cap = t.max_speed_mps;
        match self.state {
            Self::APPROACH => {
                if gap_m < t.fire_range_m {
                    self.on_target_s += dt;
                }
                if gap_m < t.break_range_m || self.on_target_s >= t.max_time_on_target_s {
                    self.enter(Self::BREAK);
                } else {
                    let closing = if gap_m > t.near_range_m {
                        t.closing_far_mps
                    } else {
                        t.closing_near_mps
                    };
                    v_des = add(target_velocity, scale(los_dir, closing as f32));
                    cap = maxf(cap, f64::from(length(target_velocity))) + closing;
                    let dv = sub(v_des, p.velocity);
                    face_dir = if f64::from(length(dv)) < t.face_lead_delta_v_mps {
                        lead_dir
                    } else {
                        normalized(dv)
                    };
                    self.lead_error_deg = rad_to_deg(brain_maths::angle_to(&p.basis, lead_dir));
                    let cone_deg = minf(
                        t.fire_cone_deg,
                        rad_to_deg((miss_m / gap_m).atan()),
                    );
                    self.firing = gap_m < t.fire_range_m
                        && self.lead_error_deg < cone_deg
                        && lane_clear(tick, range_m, target_id);
                }
            }
            Self::BREAK => {
                if self.state_time_s >= t.break_duration_s {
                    self.enter(Self::EXTEND);
                } else {
                    v_des = add(
                        target_velocity,
                        scale(self.across(los_dir), t.break_speed_mps as f32),
                    );
                    let dv = sub(v_des, p.velocity);
                    face_dir = if f64::from(length(dv)) > 1.0 {
                        normalized(dv)
                    } else {
                        p.forward
                    };
                }
            }
            _ => {
                if self.state_time_s >= t.extend_min_s && gap_m > t.extend_range_m {
                    self.enter(Self::APPROACH);
                } else {
                    v_des = sub(target_velocity, scale(los_dir, t.closing_far_mps as f32));
                    let dv = sub(v_des, p.velocity);
                    face_dir = if f64::from(length(dv)) > 1.0 {
                        normalized(dv)
                    } else {
                        p.forward
                    };
                }
            }
        }
        if t.max_speed_mps > 0.0 && f64::from(length(v_des)) > cap {
            v_des = scale(normalized(v_des), cap as f32);
        }
        cmd.rot = brain_maths::face(
            &p.basis,
            face_dir,
            ship.capability.rate_max,
            brain_maths::K_FACE,
        );
        seek_velocity(cmd, p, &ship.capability, v_des, false, wish);
        self.firing
    }
}

struct SlashState {
    tactics: Tactics,
    state: u8,
    state_time_s: f64,
    firing: bool,
    in_gate: bool,
    lead_error_deg: f64,
    time_on_target_s: f64,
    passes: i64,
    pass_offset_m: f64,
    aim_offset_rad: (f32, f32),
    last_range_m: f64,
    last_lead_dir: Vector3,
}

impl SlashState {
    const PASS: u8 = 0;
    const TURN: u8 = 1;
    const CHASE: u8 = 2;
    const STATE_NAMES: [&'static str; 3] = ["pass", "turn", "chase"];
    const PASS_OFFSET_M: f64 = 200.0;
    const CLOSE_PASS_OFFSET_M: f64 = 100.0;
    const CHASE_RANGE_M: f64 = 500.0;
    const CHASE_CLOSING_MPS: f64 = 60.0;
    const CHASE_OPENING_MPS: f64 = 30.0;
    const CHASE_GAIN: f64 = 0.1;
    const LOST_RANGE_FACTOR: f64 = 1.5;
    const ON_TARGET_DEG: f64 = 10.0;

    fn new(tactics: Tactics) -> Self {
        SlashState {
            tactics,
            state: Self::PASS,
            state_time_s: 0.0,
            firing: false,
            in_gate: false,
            lead_error_deg: 0.0,
            time_on_target_s: 0.0,
            passes: 0,
            pass_offset_m: Self::PASS_OFFSET_M,
            aim_offset_rad: (0.0, 0.0),
            last_range_m: f64::INFINITY,
            last_lead_dir: Vector3::ZERO,
        }
    }

    fn reset(&mut self) {
        self.state = Self::PASS;
        self.state_time_s = 0.0;
        self.firing = false;
        self.in_gate = false;
        self.time_on_target_s = 0.0;
        self.passes = 0;
        self.last_range_m = f64::INFINITY;
        self.last_lead_dir = Vector3::ZERO;
    }

    fn restart(&mut self) {
        self.enter(Self::PASS);
        self.last_range_m = f64::INFINITY;
        self.last_lead_dir = Vector3::ZERO;
        self.firing = false;
    }

    fn enter(&mut self, next: u8) {
        self.state = next;
        self.state_time_s = 0.0;
    }

    // `AttackSlash.engage`. Returns whether the trigger is held.
    #[allow(clippy::too_many_arguments)]
    fn engage(
        &mut self,
        tick: &Tick,
        ship: &Ship,
        target_id: i64,
        target_position: Vector3,
        target_velocity: Vector3,
        surface_m: f64,
        dt: f64,
        cmd: &mut FlightCmd,
        wish: &mut Wish,
    ) -> bool {
        let p = &tick.p;
        self.firing = false;
        self.in_gate = false;
        let los = sub(target_position, p.position);
        let range_m = f64::from(length(los));
        if range_m < 1e-3 {
            return false;
        }
        // The pass's ranges and miss gate to a big hull's skin (M5-T16); centre to centre for every other target.
        let (gap_m, miss_m) = if surface_m > 0.0 {
            (maxf(range_m - surface_m, 1.0), self.tactics.fire_miss_m + 0.5 * surface_m)
        } else {
            (range_m, self.tactics.fire_miss_m)
        };
        let los_dir = div_s(los, range_m as f32);
        self.state_time_s += dt;
        let lead = brain_maths::solve(
            add(p.position, p.muzzle_offset),
            p.velocity,
            target_position,
            target_velocity,
            ship.muzzle_speed_mps,
            ship.weapon_lifetime_s,
        );
        let mut lead_dir = if lead.ok { lead.aim_dir } else { los_dir };
        if self.aim_offset_rad != (0.0, 0.0) {
            lead_dir = aim_offset(lead_dir, self.aim_offset_rad);
        }
        self.lead_error_deg = rad_to_deg(brain_maths::angle_to(&p.basis, lead_dir));
        let mut lead_omega = Vector3::ZERO;
        if self.last_lead_dir != Vector3::ZERO && dt > 0.0 {
            lead_omega = div_s(cross(self.last_lead_dir, lead_dir), dt as f32);
        }
        self.last_lead_dir = lead_dir;
        let t = self.tactics;
        let cone_deg = minf(
            t.fire_cone_deg,
            rad_to_deg((miss_m / gap_m).atan()),
        );
        self.in_gate = gap_m < t.fire_range_m && self.lead_error_deg < cone_deg;
        if self.in_gate {
            self.time_on_target_s += dt;
        }
        let opening = range_m > self.last_range_m;
        let closing_rate = -f64::from(dot(sub(target_velocity, p.velocity), los_dir));
        self.last_range_m = range_m;
        let mut v_des: Vector3;
        let mut face_dir = lead_dir;
        let mut tracking = true;
        let mut all_axes = false;
        let mut cap = t.max_speed_mps;
        match self.state {
            Self::PASS => {
                if opening && gap_m < t.fire_range_m {
                    self.passes += 1;
                    self.enter(Self::TURN);
                }
            }
            Self::TURN => {
                if self.lead_error_deg < Self::ON_TARGET_DEG && closing_rate > 0.0 {
                    self.enter(Self::CHASE);
                }
            }
            _ => {
                if gap_m > t.fire_range_m * Self::LOST_RANGE_FACTOR {
                    self.enter(Self::PASS);
                }
            }
        }
        match self.state {
            Self::PASS => {
                v_des = add(
                    target_velocity,
                    scale(
                        self.pass_dir(p, target_velocity, los, los_dir),
                        t.closing_far_mps as f32,
                    ),
                );
                cap = maxf(cap, f64::from(length(target_velocity))) + t.closing_far_mps;
                let dv = sub(v_des, p.velocity);
                if f64::from(length(dv)) >= t.face_lead_delta_v_mps && gap_m >= t.fire_range_m {
                    face_dir = normalized(dv);
                    tracking = false;
                }
            }
            Self::TURN => {
                v_des = add(
                    target_velocity,
                    scale(los_dir, Self::CHASE_CLOSING_MPS as f32),
                );
                cap = maxf(cap, f64::from(length(target_velocity))) + Self::CHASE_CLOSING_MPS;
                all_axes = true;
            }
            _ => {
                let closure = clampf(
                    (gap_m - Self::CHASE_RANGE_M) * Self::CHASE_GAIN,
                    -Self::CHASE_OPENING_MPS,
                    Self::CHASE_CLOSING_MPS,
                );
                v_des = add(target_velocity, scale(los_dir, closure as f32));
                cap = maxf(cap, f64::from(length(target_velocity))) + Self::CHASE_CLOSING_MPS;
                all_axes = true;
            }
        }
        if t.max_speed_mps > 0.0 && f64::from(length(v_des)) > cap {
            v_des = scale(normalized(v_des), cap as f32);
        }
        self.firing = self.in_gate && lane_clear(tick, range_m, target_id);
        cmd.rot = if tracking {
            brain_maths::face_tracking(
                &p.basis,
                face_dir,
                lead_omega,
                ship.capability.rate_max,
                brain_maths::K_FACE,
            )
        } else {
            brain_maths::face(
                &p.basis,
                face_dir,
                ship.capability.rate_max,
                brain_maths::K_FACE,
            )
        };
        seek_velocity(cmd, p, &ship.capability, v_des, all_axes, wish);
        self.firing
    }

    // `AttackSlash._pass_dir`: a course by the target on the side the ship is already moving to.
    fn pass_dir(
        &self,
        p: &Percept,
        target_velocity: Vector3,
        los: Vector3,
        los_dir: Vector3,
    ) -> Vector3 {
        let rel_v = sub(p.velocity, target_velocity);
        let mut side = sub(rel_v, scale(los_dir, dot(rel_v, los_dir)));
        if f64::from(length_squared(side)) < 1.0 {
            let up = col_b(&p.basis);
            side = sub(up, scale(los_dir, dot(up, los_dir)));
        }
        if f64::from(length_squared(side)) < 1e-6 {
            return los_dir;
        }
        normalized(add(los, scale(normalized(side), self.pass_offset_m as f32)))
    }
}

// --- guard -------------------------------------------------------------------------------------------------------------

struct GuardState {
    cruise_mps: f64,
    post_error_m: f64,
}

impl GuardState {
    const SCORE: f64 = 0.25;
    const STAND_BY_SCORE: f64 = 0.1;
    const K_PER_S: f64 = 0.4;
    const NEAR_RANGE_M: f64 = 300.0;
    const NEAR_CLOSURE_MPS: f64 = 40.0;
    const FACE_DV_MPS: f64 = 20.0;
    const ON_POST_M: f64 = 50.0;

    fn new(profile: &Profile) -> Self {
        GuardState {
            cruise_mps: profile.cruise_mps,
            post_error_m: -1.0,
        }
    }

    fn reset(&mut self) {
        self.post_error_m = -1.0;
    }

    fn score(&mut self, tick: &Tick, ctx: &Context) -> f64 {
        if !tick.d.guarding {
            return 0.0;
        }
        if has_attackable(tick, ctx) {
            Self::STAND_BY_SCORE
        } else {
            Self::SCORE
        }
    }

    fn think(&mut self, tick: &Tick, ship: &Ship, cmd: &mut FlightCmd, wish: &mut Wish) {
        let p = &tick.p;
        let error = sub(tick.d.guard_point, p.position);
        self.post_error_m = f64::from(length(error));
        let cap = if self.post_error_m <= Self::NEAR_RANGE_M {
            Self::NEAR_CLOSURE_MPS
        } else {
            self.cruise_mps
        };
        let mut closure = scale(error, Self::K_PER_S as f32);
        if f64::from(length(closure)) > cap {
            closure = scale(normalized(closure), cap as f32);
        }
        let v_des = add(tick.d.guard_velocity, closure);
        let dv = sub(v_des, p.velocity);
        if f64::from(length(dv)) > Self::FACE_DV_MPS {
            cmd.rot =
                brain_maths::face(&p.basis, dv, ship.capability.rate_max, brain_maths::K_FACE);
        }
        seek_velocity(cmd, p, &ship.capability, v_des, false, wish);
    }

    fn describe(&self, d: &mut Describe) {
        d.state = if self.post_error_m >= 0.0 && self.post_error_m <= Self::ON_POST_M {
            "on post"
        } else {
            "return"
        }
        .to_string();
        d.numbers.push(("post_m", snappedf(self.post_error_m, 1.0)));
    }
}

// --- formation ---------------------------------------------------------------------------------------------------------

struct FormationState {
    far_closure_mps: f64,
    slot_error_m: f64,
    on_link: bool,
    last_leader_id: i64,
    last_leader_velocity: Vector3,
    last_s: f64,
    cos_slow_down: f64,
    max_lean_rad: f64,
}

impl FormationState {
    const SCORE: f64 = 0.25;
    const STAND_BY_SCORE: f64 = 0.1;
    const K_PER_S: f32 = 0.4;
    const LEAD_S: f32 = 0.5;
    const NEAR_CLOSURE_MPS: f64 = 60.0;
    const FAR_RANGE_M: f64 = 1500.0;
    const FAR_EXTRA_MPS: f64 = 100.0;
    const ALIGN_RANGE_M: f64 = 150.0;
    const IN_SLOT_M: f64 = 25.0;
    const FACE_DV_MPS: f64 = 30.0;
    const MAX_LEAN_DEG: f64 = 40.0;
    const MAX_PATH_RATE_RAD_S: f32 = 0.35;
    const FEED_FORWARD_FULL_MPS: f64 = 30.0;

    fn new(profile: &Profile) -> Self {
        FormationState {
            far_closure_mps: profile.cruise_mps + Self::FAR_EXTRA_MPS,
            slot_error_m: -1.0,
            on_link: false,
            last_leader_id: 0,
            last_leader_velocity: Vector3::ZERO,
            last_s: f64::NEG_INFINITY,
            cos_slow_down: deg_to_rad(180.0 - brain_maths::RETRO_CONE_DEG).cos(),
            max_lean_rad: deg_to_rad(Self::MAX_LEAN_DEG),
        }
    }

    fn reset(&mut self) {
        self.slot_error_m = -1.0;
        self.on_link = false;
        self.last_leader_id = 0;
        self.last_s = f64::NEG_INFINITY;
    }

    fn enter(&mut self) {
        self.last_s = f64::NEG_INFINITY;
    }

    fn score(&mut self, tick: &Tick, ctx: &Context) -> f64 {
        if !ctx.has_slot || (tick.d.leader < 0 && ctx.link.is_none()) {
            return 0.0;
        }
        if has_attackable(tick, ctx) {
            Self::STAND_BY_SCORE
        } else {
            Self::SCORE
        }
    }

    fn think(&mut self, tick: &Tick, ship: &Ship, dt: f64, cmd: &mut FlightCmd, wish: &mut Wish) {
        let p = &tick.p;
        let leader = tick.d.leader;
        let slot;
        let mut slot_velocity;
        let mut slot_accel = Vector3::ZERO;
        self.on_link = false;
        if leader >= 0 {
            let l = leader as usize;
            let leader_position = tick.rows.positions[l];
            let leader_velocity = tick.rows.velocities[l];
            let leader_id = tick.rows.ids[l];
            let forward = tick.forward_of(l);
            let up = tick.up_of(l);
            slot = slot_point(leader_position, forward, up, tick.ctx_slot_offset);
            slot_velocity = leader_velocity;
            let since = p.now_s - self.last_s;
            let speed_sq = f64::from(length_squared(leader_velocity));
            if leader_id == self.last_leader_id
                && dt > 0.0
                && (since - dt).abs() < 0.5 * dt
                && speed_sq > 1.0
            {
                let leader_accel = div_s(
                    sub(leader_velocity, self.last_leader_velocity),
                    since as f32,
                );
                let mut path_rate = limit_length(
                    div_s(cross(leader_velocity, leader_accel), speed_sq as f32),
                    Self::MAX_PATH_RATE_RAD_S,
                );
                path_rate = scale(
                    path_rate,
                    minf(1.0, speed_sq.sqrt() / Self::FEED_FORWARD_FULL_MPS) as f32,
                );
                let arm = sub(slot, leader_position);
                slot_velocity = add(slot_velocity, cross(path_rate, arm));
                slot_accel = add(leader_accel, cross(path_rate, cross(path_rate, arm)));
            }
            self.last_leader_id = leader_id;
            self.last_leader_velocity = leader_velocity;
            self.last_s = p.now_s;
        } else if let Some(link) = tick.ctx_link {
            self.on_link = true;
            slot = p.local_of(link);
            slot_velocity = tick.ctx_link_velocity;
        } else {
            return;
        }
        let to_slot = sub(slot, p.position);
        self.slot_error_m = f64::from(length(to_slot));
        let error = add(to_slot, scale(sub(slot_velocity, p.velocity), Self::LEAD_S));
        let cap = if self.slot_error_m <= Self::FAR_RANGE_M {
            Self::NEAR_CLOSURE_MPS
        } else {
            self.far_closure_mps
        };
        let v_des = add(
            add(
                slot_velocity,
                limit_length(scale(error, Self::K_PER_S), cap as f32),
            ),
            scale(slot_accel, brain_maths::HORIZON_S as f32),
        );
        let rate = ship.capability.rate_max;
        if leader >= 0 && self.slot_error_m <= Self::ALIGN_RANGE_M {
            let l = leader as usize;
            let a_need = div_s(sub(v_des, p.velocity), brain_maths::HORIZON_S as f32);
            let nose = brain_maths::lean_toward(
                tick.forward_of(l),
                a_need,
                minf(ship.capability.a_rcs_x, ship.capability.a_rcs_y),
                self.max_lean_rad,
            );
            let mut rot = brain_maths::face(&p.basis, nose, rate, brain_maths::K_FACE);
            rot.z =
                brain_maths::align_roll(&p.basis, tick.up_of(l), rate, brain_maths::K_FACE) as f32;
            cmd.rot = rot;
            seek_velocity(cmd, p, &ship.capability, v_des, true, wish);
        } else {
            let leader_forward = if leader >= 0 {
                Some(tick.forward_of(leader as usize))
            } else {
                None
            };
            cmd.rot = brain_maths::face(
                &p.basis,
                self.heading(p.velocity, v_des, leader_forward),
                rate,
                brain_maths::K_FACE,
            );
            seek_velocity(cmd, p, &ship.capability, v_des, false, wish);
        }
    }

    // `BehaviourFormation._heading`.
    fn heading(
        &self,
        velocity: Vector3,
        v_des: Vector3,
        leader_forward: Option<Vector3>,
    ) -> Vector3 {
        let dv = sub(v_des, velocity);
        let dv_len = f64::from(length(dv));
        if f64::from(length_squared(v_des)) < 1.0 {
            if dv_len > Self::FACE_DV_MPS {
                return dv;
            }
            return leader_forward.unwrap_or(Vector3::ZERO);
        }
        let along = normalized(v_des);
        if dv_len > Self::FACE_DV_MPS && f64::from(dot(dv, along)) > -self.cos_slow_down * dv_len {
            return dv;
        }
        v_des
    }

    fn describe(&self, d: &mut Describe) {
        let mut state = "in slot";
        if self.slot_error_m < 0.0 || self.slot_error_m > Self::ALIGN_RANGE_M {
            state = "joining";
        } else if self.slot_error_m > Self::IN_SLOT_M {
            state = "closing";
        }
        if self.on_link {
            state = "joining (link)";
        }
        d.state = state.to_string();
        d.numbers
            .push(("slot_error_m", snappedf(self.slot_error_m, 0.1)));
    }
}

// `Formation.slot_point`: the World point of a body-frame offset from a leader.
fn slot_point(position: Vector3, forward: Vector3, up: Vector3, body_offset: Vector3) -> Vector3 {
    let right = cross(forward, up);
    sub(
        add(
            add(position, scale(right, body_offset.x)),
            scale(up, body_offset.y),
        ),
        scale(forward, body_offset.z),
    )
}

// --- rally -------------------------------------------------------------------------------------------------------------

struct RallyState {
    closure_mps: f64,
    to: i32,
    to_id: i64,
}

impl RallyState {
    const SCORE: f64 = 0.2;
    const ARRIVE_M: f64 = 1500.0;
    const EXTRA_MPS: f64 = 100.0;
    const FACE_DV_MPS: f64 = 20.0;

    fn new(profile: &Profile) -> Self {
        RallyState {
            closure_mps: profile.cruise_mps + Self::EXTRA_MPS,
            to: -1,
            to_id: 0,
        }
    }

    fn reset(&mut self) {}

    fn score(&mut self, tick: &Tick, ctx: &Context) -> f64 {
        self.to = -1;
        self.to_id = 0;
        if ctx.wing_ids.is_empty() || has_attackable(tick, ctx) {
            return 0.0;
        }
        let mut nearest = f64::INFINITY;
        for list in [tick.contacts, tick.broadcasts] {
            for &r in list {
                let row = r as usize;
                if tick.rows.target_ids[row] > 0 && ctx.wing_ids.contains(&tick.rows.ids[row]) {
                    let d2 = f64::from(dist_sq(tick.rows.positions[row], tick.p.position));
                    if d2 > Self::ARRIVE_M * Self::ARRIVE_M && d2 < nearest {
                        nearest = d2;
                        self.to = r;
                        self.to_id = tick.rows.ids[row];
                    }
                }
            }
        }
        if self.to >= 0 { Self::SCORE } else { 0.0 }
    }

    fn think(&mut self, tick: &Tick, ship: &Ship, cmd: &mut FlightCmd, wish: &mut Wish) {
        if self.to < 0 {
            return;
        }
        let p = &tick.p;
        let t = self.to as usize;
        let los = sub(tick.rows.positions[t], p.position);
        let v_des = add(
            tick.rows.velocities[t],
            scale(normalized(los), self.closure_mps as f32),
        );
        let dv = sub(v_des, p.velocity);
        cmd.rot = brain_maths::face(
            &p.basis,
            if f64::from(length(dv)) > Self::FACE_DV_MPS {
                dv
            } else {
                los
            },
            ship.capability.rate_max,
            brain_maths::K_FACE,
        );
        seek_velocity(cmd, p, &ship.capability, v_des, false, wish);
    }

    fn describe(&self, d: &mut Describe) {
        if self.to_id != 0 {
            d.names.push(("state", self.to_id));
        } else {
            d.state = "none".to_string();
        }
    }
}

// --- follow path -------------------------------------------------------------------------------------------------------

#[derive(Default)]
struct PathState {
    index: usize,
    phase: u8,
    lag_m: f64,
    manoeuvre: Option<Manoeuvre>,
    visited: Vec<i32>,
    results: Vec<PathResult>,
    demo_due: bool,
    hold_left_s: f64,
}

impl PathState {
    const SCORE: f64 = 0.5;
    const STAND_BY_SCORE: f64 = 0.1;
    const RUN_UP_FRACTION: f64 = 0.9;
    const LEAD: u8 = 0;
    const WAIT: u8 = 1;
    const RUN_UP: u8 = 2;
    const DEMO: u8 = 3;
    const HOLD: u8 = 4;
    const DONE: u8 = 5;
    const PHASE_NAMES: [&'static str; 6] = ["lead", "wait", "run_up", "demo", "hold", "done"];
    const ARRIVAL_M: f64 = 150.0;

    fn reset(&mut self) {
        self.index = 0;
        self.phase = Self::LEAD;
        self.lag_m = 0.0;
        self.manoeuvre = None;
        self.visited.clear();
        self.results.clear();
        self.demo_due = false;
        self.hold_left_s = 0.0;
    }

    fn enter(&mut self) {
        if self.phase == Self::DEMO
            && let Some(m) = &self.manoeuvre
        {
            self.manoeuvre = Manoeuvre::create(m.kind);
        }
    }

    fn score(&mut self, tick: &Tick, ctx: &Context) -> f64 {
        let Some(route) = &ctx.route else {
            return 0.0;
        };
        if route.points.is_empty() || self.phase == Self::DONE {
            return 0.0;
        }
        if route.yield_to_attack && has_attackable(tick, ctx) {
            return Self::STAND_BY_SCORE;
        }
        Self::SCORE
    }

    // `Route.lag_to`: the distance to the pace ship, INF out of sight, 0 without pacing.
    fn lag_to(tick: &Tick, route: &Route) -> f64 {
        if route.pace_id == 0 {
            return 0.0;
        }
        for k in 0..tick.contacts.len() {
            let row = tick.row(k);
            if tick.rows.ids[row] == route.pace_id {
                return f64::from(distance(tick.p.position, tick.rows.positions[row]));
            }
        }
        f64::INFINITY
    }

    #[allow(clippy::too_many_arguments)]
    fn think(
        &mut self,
        tick: &Tick,
        ship: &Ship,
        route: &Option<Route>,
        dt: f64,
        cmd: &mut FlightCmd,
        wish: &mut Wish,
    ) {
        let Some(route) = route else {
            return;
        };
        if route.points.is_empty() {
            return;
        }
        let p = &tick.p;
        self.lag_m = Self::lag_to(tick, route);
        self.settle(p, route);
        match self.phase {
            Self::LEAD => {
                let to = sub(p.local_of(route.points[self.index]), p.position);
                self.fly(cmd, p, ship, to, route.pace_speed(self.lag_m), wish);
            }
            Self::RUN_UP => {
                let dir = self.run_up_direction(p, route);
                self.fly(cmd, p, ship, dir, route.cruise_mps, wish);
            }
            Self::DEMO => {
                let Some(m) = self.manoeuvre.as_mut() else {
                    return;
                };
                *cmd = m.step(&p.pose(), &ship.capability, dt);
                wish.velocity = m.desired_velocity;
                wish.has = m.has_desired_velocity;
                wish.all_axes = false;
                if m.done {
                    self.finish_demo(route);
                }
            }
            Self::HOLD => {
                cmd.brake = true;
                self.hold_left_s -= dt;
            }
            _ => cmd.brake = true,
        }
    }

    fn target_id(&self, route: &Option<Route>) -> i64 {
        if self.phase == Self::WAIT
            && let Some(r) = route
            && r.pace_id != 0
        {
            return r.pace_id;
        }
        TARGET_NONE
    }

    // `BehaviourFollowPath._settle`: through the phases until one has something to fly this tick.
    fn settle(&mut self, p: &Percept, route: &Route) {
        for _ in 0..Self::PHASE_NAMES.len() {
            let before = self.phase;
            match self.phase {
                Self::LEAD => {
                    if Route::should_wait(self.lag_m, false) {
                        self.phase = Self::WAIT;
                    } else if f64::from(length(sub(
                        p.local_of(route.points[self.index]),
                        p.position,
                    ))) < Self::ARRIVAL_M
                    {
                        self.arrive(route);
                    }
                }
                Self::WAIT => {
                    if !Route::should_wait(self.lag_m, true) {
                        self.phase = if self.demo_due {
                            Self::RUN_UP
                        } else {
                            Self::LEAD
                        };
                    }
                }
                Self::RUN_UP => {
                    if Route::should_wait(self.lag_m, true) {
                        self.phase = Self::WAIT;
                    } else if !self.manoeuvre.as_ref().is_some_and(Manoeuvre::needs_speed)
                        || f64::from(length(p.velocity)) >= Self::RUN_UP_FRACTION * route.cruise_mps
                    {
                        self.phase = Self::DEMO;
                    }
                }
                Self::HOLD if self.hold_left_s <= 0.0 => self.advance(route),
                _ => {}
            }
            if self.phase == before {
                return;
            }
        }
    }

    fn arrive(&mut self, route: &Route) {
        self.visited.push(self.index as i32);
        let demo = route.demos[self.index];
        if demo != 0 {
            self.demo_due = true;
            self.manoeuvre = Manoeuvre::create(demo - 1);
            self.phase = Self::RUN_UP;
        } else if route.holds[self.index] > 0.0 {
            self.hold_left_s = route.holds[self.index];
            self.phase = Self::HOLD;
        } else {
            self.advance(route);
        }
    }

    fn finish_demo(&mut self, route: &Route) {
        if let Some(m) = &self.manoeuvre {
            self.results.push(PathResult {
                outcome: m.result(),
                demo: m.kind,
                index: self.index as i64,
            });
        }
        self.demo_due = false;
        let hold = route.holds[self.index];
        if hold > 0.0 {
            self.hold_left_s = hold;
            self.phase = Self::HOLD;
        } else {
            self.advance(route);
        }
    }

    fn advance(&mut self, route: &Route) {
        self.demo_due = false;
        let next = route.next_index(self.index);
        if next < 0 {
            self.phase = Self::DONE;
            return;
        }
        self.index = next as usize;
        self.phase = Self::LEAD;
    }

    fn run_up_direction(&self, p: &Percept, route: &Route) -> Vector3 {
        let next = route.next_index(self.index);
        if next >= 0 {
            let to = sub(p.local_of(route.points[next as usize]), p.position);
            if f64::from(length(to)) > Self::ARRIVAL_M {
                return to;
            }
        }
        if f64::from(length(p.velocity)) > 1.0 {
            p.velocity
        } else {
            p.forward
        }
    }

    // `BehaviourFollowPath._fly`: nose along `to`, velocity toward it at `speed`.
    fn fly(
        &mut self,
        cmd: &mut FlightCmd,
        p: &Percept,
        ship: &Ship,
        to: Vector3,
        speed: f64,
        wish: &mut Wish,
    ) {
        let d = f64::from(length(to));
        let dir = if d > 1e-6 {
            div_s(to, d as f32)
        } else {
            p.forward
        };
        cmd.rot = brain_maths::face(&p.basis, dir, ship.capability.rate_max, brain_maths::K_FACE);
        seek_velocity(
            cmd,
            p,
            &ship.capability,
            scale(dir, speed as f32),
            false,
            wish,
        );
    }

    fn describe(&self, route: &Option<Route>, d: &mut Describe) {
        d.state = Self::PHASE_NAMES[usize::from(self.phase)].to_string();
        match route {
            Some(r) => d
                .texts
                .push(("nav", format!("NAV {}/{}", self.index + 1, r.points.len()))),
            None => d.texts.push(("nav", "none".to_string())),
        }
        d.numbers.push((
            "lag_m",
            if self.lag_m < f64::INFINITY {
                snappedf(self.lag_m, 1.0)
            } else {
                -1.0
            },
        ));
        let demo = match route {
            Some(r)
                if self.phase != Self::DONE
                    && self.index < r.points.len()
                    && r.demos[self.index] != 0 =>
            {
                brain_maths::MANOEUVRE_NAMES[usize::from(r.demos[self.index] - 1)].to_string()
            }
            _ => "none".to_string(),
        };
        d.texts.push(("demo", demo));
        if self.phase == Self::DEMO
            && let Some(m) = &self.manoeuvre
        {
            d.texts.push(("step", m.state_name()));
        }
    }
}
