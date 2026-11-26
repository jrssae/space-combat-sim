// The mines (M10-T15, Q20, D12.9): what a mine does each tick over the core's rows, with no engine type in this file
// (`test_sim_core` reads it and fails on one). A mine is a slot of the `Mines` table in its field's frame: offsets from the
// field's node, which rides the anchor, so a mine at rest moves with the anchor and a rebase moves the node. Three kinds:
//
// - **Proximity** (`PROX`): armed from the start in a minefield, goes off on a hull hostile to its layer within its trigger of
//   the hull's surface.
// - **Energy** (`ENERGY`): flies straight to a lead point as a bolt row the interceptors can shoot (toughness 3), arms there,
//   goes off on a hostile capital within its trigger or when its fuse runs out.
// - **Guided** (`GUIDED`): dormant after it is laid, then homes on a hostile within range, again a bolt row while it flies.
//
// A hull of any side that touches a mine's body sets it off. The kernel names who goes off; the blast itself is T09's
// (`BlastResolver`), landed by the caller, and a blast sets off the mines it reaches (`in_blast`). Hostility is the layer's
// against a hull's TRUE faction: a disguised ship is still an enemy to a mine (Q55). Run on the main thread in slot order,
// no randomness: the same answer however many threads the core runs.
#![allow(clippy::too_many_arguments)]

use godot::builtin::Vector3;

use crate::capital_gun_kernels::is_capital;
use crate::rows::{Bolts, FLAG_HULL_ACTIVE, FLAG_RIGID, FLAG_SHELTERED, FLAG_TIER, Rows};
use crate::surface::{into_body, nearest};
use crate::v3::{add, dist_sq, dot, length, normalized, scale, sub};

pub const PROX: u8 = 0;
pub const ENERGY: u8 = 1;
pub const GUIDED: u8 = 2;
pub const KINDS: usize = 3;

/// Numbers a kind takes, in the order `Spec::from_slice` reads them.
pub const SPEC_LEN: usize = 12;

/// Waiting to arm (a laid proximity mine) or dormant (a guided one just dropped): nothing triggers it, a touch still does.
pub const DORMANT: u8 = 0;
/// Armed: its trigger works.
pub const ARMED: u8 = 1;
/// Under its own power as a bolt row: an energy mine on its way, a guided mine homing.
pub const FLYING: u8 = 2;

/// What set a mine off, as the caller reports it.
pub const CAUSE_TRIGGER: u8 = 0;
pub const CAUSE_TOUCH: u8 = 1;
// The caller's own causes (a shot, a blast reaching the mine): the step never names them, `MineField` does.
#[allow(dead_code)]
pub const CAUSE_SHOT: u8 = 2;
#[allow(dead_code)]
pub const CAUSE_BLAST: u8 = 3;
pub const CAUSE_FUSE: u8 = 4;
/// A flying mine that left its bolt row (it struck something, or its time ran out).
pub const CAUSE_FLIGHT: u8 = 5;

/// A hull this small or smaller is touched as a sphere; a bigger one by its hit volumes.
pub const FIGHTER_RADIUS_MAX_M: f64 = 50.0;
/// The trigger and acquisition checks of a mine run one tick in this many (a slot's turn is its index modulo this).
pub const CHECK_TICKS: i64 = 3;
/// A laid mine ignores the touch of its own layer's ship this long, s: the mount it leaves is on that hull.
pub const OWN_GRACE_S: f64 = 6.0;
// The grid's cell, m, and the room added round a search so a mine the exact test takes is never missed.
const CELL_M: f64 = 200.0;
const PAD_REL: f64 = 1e-6;
const PAD_M: f64 = 1.0;
/// An energy mine's bolt lives this much longer than its flight needs, s.
pub const FLIGHT_SLACK_S: f64 = 5.0;

/// One kind's numbers: what `data/capitals/mines.json` holds.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Spec {
    /// How close to a hull's surface a hostile sets it off, m.
    pub trigger_m: f64,
    /// The mine's body, what a touch must reach, m.
    pub body_m: f64,
    /// Seconds after it is laid before the trigger works.
    pub arm_s: f64,
    /// Seconds a guided mine lies dormant after it is laid (then it can home).
    pub dormant_s: f64,
    /// The speed it flies or homes at, m/s.
    pub speed_mps: f64,
    /// A guided mine homes on a hostile this near, m.
    pub home_m: f64,
    /// Seconds after an energy mine arrives before it goes off whatever is near (0: never).
    pub fuse_s: f64,
    /// Whether only a hostile capital sets it off.
    pub capitals_only: bool,
    /// A guided mine's turn rate, rad/s.
    pub turn_rad_s: f64,
    /// Its blast's radius, m (the chain: the mines this reaches go off with it).
    pub blast_m: f64,
    /// Interceptor pulses a flying one takes.
    pub toughness: u8,
    /// A hostile mine shows on the radar this close, m (own and friendly always).
    pub radar_m: f64,
}

impl Spec {
    /// The numbers of `s` (`SPEC_LEN` of them), or none when it has the wrong length or a number that is not finite.
    pub fn from_slice(s: &[f64]) -> Option<Spec> {
        if s.len() != SPEC_LEN || s.iter().any(|x| !x.is_finite()) {
            return None;
        }
        Some(Spec {
            trigger_m: s[0].max(0.0),
            body_m: s[1].max(0.0),
            arm_s: s[2].max(0.0),
            dormant_s: s[3].max(0.0),
            speed_mps: s[4].max(0.0),
            home_m: s[5].max(0.0),
            fuse_s: s[6].max(0.0),
            capitals_only: s[7] != 0.0,
            turn_rad_s: s[8].max(0.0),
            blast_m: s[9].max(0.0),
            toughness: s[10].clamp(1.0, 4.0) as u8,
            radar_m: s[11].max(0.0),
        })
    }

    /// The numbers of a kind nobody described.
    pub const NONE: Spec = Spec {
        trigger_m: 0.0,
        body_m: 3.0,
        arm_s: 0.0,
        dormant_s: 0.0,
        speed_mps: 0.0,
        home_m: 0.0,
        fuse_s: 0.0,
        capitals_only: false,
        turn_rad_s: 0.0,
        blast_m: 0.0,
        toughness: 1,
        radar_m: 1000.0,
    };
}

/// The mines of one field, a slot each (a slot is reused once its mine is gone), column by column.
#[derive(Default)]
pub struct Mines {
    pub alive: Vec<bool>,
    pub kind: Vec<u8>,
    pub state: Vec<u8>,
    /// On the grid and never moving: a placed mine, or an energy mine that has arrived.
    pub fixed: Vec<bool>,
    pub faction_ix: Vec<u32>,
    /// Offset from the field's node, in the node's frame (it rides the anchor), m.
    pub local: Vec<Vector3>,
    /// Velocity in that frame, m/s.
    pub vel: Vec<Vector3>,
    /// An energy mine's lead point, in the same frame.
    pub dest: Vec<Vector3>,
    /// When it was laid, s.
    pub born_s: Vec<f64>,
    /// When it arms (proximity) or wakes (guided), s.
    pub ready_at: Vec<f64>,
    /// When it goes off whatever is near, s (infinite for none).
    pub fuse_at: Vec<f64>,
    /// The body of the ship that laid it, 0 for a placed mine.
    pub owner: Vec<i64>,
    /// The bolt row it flies as (negative owned id), 0 for none.
    pub bolt: Vec<i64>,
    /// The grid of the fixed mines, sorted by cell then slot; rebuilt when `dirty`.
    pub cells: Vec<((i32, i32, i32), u32)>,
    pub dirty: bool,
    /// The most slots there may be (a field's draw has that many instances); none: the table grows as needed.
    pub limit: Option<usize>,
}

impl Mines {
    pub fn len(&self) -> usize {
        self.alive.len()
    }

    pub fn is_empty(&self) -> bool {
        self.alive.is_empty()
    }

    /// How many mines are in play.
    pub fn in_play(&self) -> usize {
        self.alive.iter().filter(|&&a| a).count()
    }

    /// Makes room for `n` slots, all empty.
    pub fn reserve_slots(&mut self, n: usize) {
        self.limit = Some(n);
        while self.alive.len() < n {
            self.push_empty();
        }
    }

    fn push_empty(&mut self) {
        self.alive.push(false);
        self.kind.push(PROX);
        self.state.push(DORMANT);
        self.fixed.push(false);
        self.faction_ix.push(0);
        self.local.push(Vector3::ZERO);
        self.vel.push(Vector3::ZERO);
        self.dest.push(Vector3::ZERO);
        self.born_s.push(0.0);
        self.ready_at.push(0.0);
        self.fuse_at.push(f64::INFINITY);
        self.owner.push(0);
        self.bolt.push(0);
    }

    /// Lays a mine in the first free slot (or `at_slot`, when it is free) and returns the slot, or none when the table is
    /// full. `state` is `ARMED` for a placed proximity mine, `DORMANT` for a guided one just dropped; `vel` is its velocity.
    pub fn lay(
        &mut self,
        at_slot: Option<usize>,
        kind: u8,
        faction_ix: u32,
        local: Vector3,
        vel: Vector3,
        state: u8,
        now_s: f64,
        spec: &Spec,
        owner: i64,
    ) -> Option<usize> {
        let slot = match at_slot {
            Some(s) if s < self.len() && !self.alive[s] => s,
            Some(_) => return None,
            None => match self.alive.iter().position(|&a| !a) {
                Some(free) => free,
                None if self.limit.is_none_or(|n| self.alive.len() < n) => {
                    self.push_empty();
                    self.alive.len() - 1
                }
                None => return None,
            },
        };
        let still = vel == Vector3::ZERO;
        self.alive[slot] = true;
        self.kind[slot] = kind;
        self.state[slot] = state;
        self.fixed[slot] = still && state != FLYING;
        self.faction_ix[slot] = faction_ix;
        self.local[slot] = local;
        self.vel[slot] = vel;
        self.dest[slot] = local;
        self.born_s[slot] = now_s;
        self.ready_at[slot] = now_s + if kind == GUIDED { spec.dormant_s } else { spec.arm_s };
        self.fuse_at[slot] = f64::INFINITY;
        self.owner[slot] = owner;
        self.bolt[slot] = 0;
        self.dirty = true;
        Some(slot)
    }

    /// Takes the mine out of play (it went off, or was shot down).
    pub fn retire(&mut self, slot: usize) -> bool {
        if slot >= self.len() || !self.alive[slot] {
            return false;
        }
        self.alive[slot] = false;
        if self.fixed[slot] {
            self.dirty = true;
        }
        self.fixed[slot] = false;
        self.bolt[slot] = 0;
        true
    }

    /// Builds the grid of the fixed mines again.
    pub fn rebuild_grid(&mut self) {
        self.cells.clear();
        for i in 0..self.len() {
            if self.alive[i] && self.fixed[i] {
                let p = self.local[i];
                self.cells.push(((cell_of(f64::from(p.x)), cell_of(f64::from(p.y)), cell_of(f64::from(p.z))), i as u32));
            }
        }
        self.cells.sort_unstable();
        self.dirty = false;
    }
}

/// What a step reads of the world, all of it from this tick's sync.
pub struct World<'a> {
    pub rows: &'a Rows,
    pub bolts: &'a Bolts,
    /// The hull rows (the sweep's order: near hulls, then tier rows).
    pub hull_rows: &'a [u32],
    /// The relations table by the core's faction indices, `factions` square (true: hostile).
    pub hostile: &'a [bool],
    pub factions: usize,
    /// The field's node in the World frame.
    pub origin: Vector3,
    /// The local frame's velocity against its anchor (the mines drift with the anchor).
    pub frame_velocity: Vector3,
    pub tick: i64,
    pub now_s: f64,
    pub delta: f64,
}

/// What a step decided: the mines that go off (ascending, with their cause), the bolt rows to add, steer or spend, the mines
/// that flew into the table's own fate (shot down), and the slots whose place changed this tick.
#[derive(Default)]
pub struct StepOut {
    pub dets: Vec<(u32, u8)>,
    /// `(slot, position in the World, velocity in the World)`: a mine takes off as a bolt row of the shell's making.
    pub launches: Vec<(u32, Vector3, Vector3)>,
    /// `(bolt id, velocity in the World)`: a homing mine's new heading.
    pub steers: Vec<(i64, Vector3)>,
    /// Bolt rows to spend: a mine that arrived or lost its target.
    pub spends: Vec<i64>,
    /// Mines an interceptor shot down: gone without a blast.
    pub downed: Vec<u32>,
    /// Slots that moved (their draw is updated).
    pub moved: Vec<u32>,
    fired: Vec<u8>,
    // The mines not on the grid this tick, so a hull's search does not walk every slot.
    mobile: Vec<u32>,
}

impl StepOut {
    pub fn clear(&mut self) {
        self.dets.clear();
        self.launches.clear();
        self.steers.clear();
        self.spends.clear();
        self.downed.clear();
        self.moved.clear();
    }
}

fn cell_of(v: f64) -> i32 {
    (v / CELL_M).floor() as i32
}

/// Whether a hull can set a mine off and be hurt by it: a rigid active hull in play or a low-attention tier row, never a ship
/// sheltered inside a station.
pub fn can_trigger(flags: u32) -> bool {
    flags & FLAG_SHELTERED == 0 && (flags & FLAG_TIER != 0 || (flags & FLAG_RIGID != 0 && flags & FLAG_HULL_ACTIVE != 0))
}

fn is_hostile(w: &World, a: u32, b: u32) -> bool {
    let (a, b) = (a as usize, b as usize);
    a < w.factions && b < w.factions && w.hostile[a * w.factions + b]
}

fn wide(p: Vector3) -> [f64; 3] {
    [f64::from(p.x), f64::from(p.y), f64::from(p.z)]
}

/// How far hull row `j` is from World point `p`, measured to its nearest hit volume (its surface when it has one, its
/// bounding sphere else; 0 inside); infinite when it is `limit` or more away (nothing of a hull is nearer than its sphere).
pub fn hull_gap(rows: &Rows, j: usize, p: Vector3, limit: f64) -> f64 {
    let d = wide(sub(p, rows.positions[j]));
    let centre = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
    let sphere = centre - rows.radii[j];
    if sphere.is_nan() || sphere >= limit {
        return f64::INFINITY;
    }
    if let Some(s) = rows.surface(j) {
        return nearest(s, into_body(&rows.bases[j], rows.positions[j], p)).map_or(f64::INFINITY, |(g, _, _)| g);
    }
    sphere.max(0.0)
}

// The squared distance from `p` to the move from `end - step` to `end`, in 64 bits.
fn segment_point_dist_sq(end: Vector3, step: [f64; 3], p: Vector3) -> f64 {
    let e = wide(end);
    let a = [e[0] - step[0], e[1] - step[1], e[2] - step[2]];
    let q = wide(p);
    let rel = [q[0] - a[0], q[1] - a[1], q[2] - a[2]];
    let len_sq = step[0] * step[0] + step[1] * step[1] + step[2] * step[2];
    let t = if len_sq > 0.0 {
        ((rel[0] * step[0] + rel[1] * step[1] + rel[2] * step[2]) / len_sq).clamp(0.0, 1.0)
    } else {
        0.0
    };
    let d = [rel[0] - t * step[0], rel[1] - t * step[1], rel[2] - t * step[2]];
    d[0] * d[0] + d[1] * d[1] + d[2] * d[2]
}

// Calls `f` with every fixed mine whose grid cell lies in the box `reach` round World point `centre` (padded so the exact test
// never misses one).
fn each_fixed_near(mines: &Mines, origin: Vector3, centre: Vector3, reach: f64, mut f: impl FnMut(usize)) {
    let pad = reach.abs() * (1.0 + PAD_REL) + PAD_M;
    let rel = [
        f64::from(centre.x) - f64::from(origin.x),
        f64::from(centre.y) - f64::from(origin.y),
        f64::from(centre.z) - f64::from(origin.z),
    ];
    if !(rel.iter().all(|c| c.is_finite()) && pad.is_finite()) {
        return;
    }
    let (lx, ly, lz) = (cell_of(rel[0] - pad), cell_of(rel[1] - pad), cell_of(rel[2] - pad));
    let (hx, hy, hz) = (cell_of(rel[0] + pad), cell_of(rel[1] + pad), cell_of(rel[2] + pad));
    // One slab of cells per x, its rows within the box's y, then the box's z: a capital's wide box costs a few slabs.
    let cells = &mines.cells;
    for cx in lx..=hx {
        let start = cells.partition_point(|e| e.0 < (cx, ly, i32::MIN));
        let end = cells.partition_point(|e| e.0 <= (cx, hy, i32::MAX));
        for e in &cells[start..end] {
            if e.0.2 >= lz && e.0.2 <= hz && mines.alive[e.1 as usize] {
                f(e.1 as usize);
            }
        }
    }
}

// The mines in play that are not on the grid (flying ones excluded: their bolt row is their body), in slot order.
fn mobile_slots(mines: &Mines, out: &mut Vec<u32>) {
    out.clear();
    for i in 0..mines.len() {
        if mines.alive[i] && !mines.fixed[i] && mines.state[i] != FLYING {
            out.push(i as u32);
        }
    }
}

// Calls `f` with every mine in play and not flying that a search round World point `centre` could reach: the grid's, then the
// `mobile` ones.
fn each_near(mines: &Mines, mobile: &[u32], origin: Vector3, centre: Vector3, reach: f64, mut f: impl FnMut(usize)) {
    each_fixed_near(mines, origin, centre, reach, &mut f);
    for &i in mobile {
        f(i as usize);
    }
}

fn world_of(mines: &Mines, origin: Vector3, i: usize) -> Vector3 {
    add(origin, mines.local[i])
}

fn flag(out: &mut StepOut, slot: usize, cause: u8) {
    if out.fired[slot] == 0 {
        out.fired[slot] = cause + 1;
    }
}

/// One tick of the mines in `mines` (call after the interceptors have fired and before the bolts move): flights are followed
/// and finished, mines wake and arm, homing mines are steered, the triggers and touches are checked over the hulls, fuses
/// run out. Fills `out`; the caller goes off with `out.dets`, retiring each, and applies the bolt operations.
pub fn step(mines: &mut Mines, specs: &[Spec; KINDS], w: &World, out: &mut StepOut) {
    out.clear();
    if mines.dirty {
        mines.rebuild_grid();
    }
    let n = mines.len();
    out.fired.clear();
    out.fired.resize(n, 0);
    follow_flights(mines, specs, w, out);
    wake_and_arm(mines, specs, w);
    steer_guided(mines, specs, w, out);
    let mut mobile = std::mem::take(&mut out.mobile);
    mobile_slots(mines, &mut mobile);
    triggers_and_touches(mines, &mobile, specs, w, out);
    out.mobile = mobile;
    for i in 0..n {
        if mines.alive[i] && mines.state[i] == ARMED && mines.fuse_at[i] <= w.now_s {
            flag(out, i, CAUSE_FUSE);
        }
    }
    for (i, &f) in out.fired.iter().enumerate() {
        if f > 0 {
            out.dets.push((i as u32, f - 1));
        }
    }
}

// The index of the bolt row with id `id`, among the owned rows (owned bolts hold negative ids, newest last).
fn bolt_index(bolts: &Bolts, id: i64) -> Option<usize> {
    (0..bolts.owned).rev().find(|&p| bolts.ids[p] == id)
}

// Every mine under its own power: its place and velocity are its bolt row's. An interceptor's last pulse took it down, the
// row has been dropped (it hit something, or its time ran out), or an energy mine reached its lead point and arms.
fn follow_flights(mines: &mut Mines, specs: &[Spec; KINDS], w: &World, out: &mut StepOut) {
    for i in 0..mines.len() {
        if !mines.alive[i] || mines.state[i] != FLYING {
            continue;
        }
        let spec = &specs[mines.kind[i] as usize];
        let Some(p) = bolt_index(w.bolts, mines.bolt[i]) else {
            // The row is gone: it struck a hull (the hit sweep spent it) or its life ran out; it goes off where it was.
            flag(out, i, CAUSE_FLIGHT);
            continue;
        };
        if w.bolts.spent[p] {
            // Pulses of an interceptor met it (the only thing that spends a row before this step): shot down.
            out.downed.push(i as u32);
            mines.bolt[i] = 0;
            continue;
        }
        let at = sub(w.bolts.positions[p], w.origin);
        mines.local[i] = at;
        mines.vel[i] = add(w.bolts.velocities[p], w.frame_velocity);
        out.moved.push(i as u32);
        if mines.kind[i] == ENERGY {
            let to = wide(sub(mines.dest[i], at));
            let left = (to[0] * to[0] + to[1] * to[1] + to[2] * to[2]).sqrt();
            let step_m = spec.speed_mps * w.delta;
            // Reached the lead point (this tick's move would carry it past): it stops there and arms.
            if left <= step_m.max(1e-3) {
                mines.local[i] = mines.dest[i];
                mines.vel[i] = Vector3::ZERO;
                mines.state[i] = ARMED;
                mines.fixed[i] = true;
                mines.dirty = true;
                mines.fuse_at[i] = if spec.fuse_s > 0.0 { w.now_s + spec.fuse_s } else { f64::INFINITY };
                out.spends.push(mines.bolt[i]);
                mines.bolt[i] = 0;
            }
        }
    }
}

// A laid proximity mine arms and a dormant guided mine wakes when its time comes; a dormant mine that still drifts keeps its
// velocity, and a moving mine's place is advanced.
fn wake_and_arm(mines: &mut Mines, _specs: &[Spec; KINDS], w: &World) {
    let dt = w.delta as f32;
    for i in 0..mines.len() {
        if !mines.alive[i] || mines.state[i] == FLYING {
            continue;
        }
        if !mines.fixed[i] && mines.vel[i] != Vector3::ZERO {
            mines.local[i] = add(mines.local[i], scale(mines.vel[i], dt));
        }
        if mines.state[i] == DORMANT && mines.ready_at[i] <= w.now_s {
            mines.state[i] = ARMED;
        }
    }
}

// Armed guided mines look for a hostile hull within their homing range (nearest first, the lower row on a tie) and take off
// toward it as a bolt row; a homing mine keeps turning onto its nearest hostile and stops where it is when none is left.
fn steer_guided(mines: &mut Mines, specs: &[Spec; KINDS], w: &World, out: &mut StepOut) {
    let phase = w.tick.rem_euclid(CHECK_TICKS) as usize;
    for i in 0..mines.len() {
        if !mines.alive[i] || mines.kind[i] != GUIDED {
            continue;
        }
        let spec = &specs[GUIDED as usize];
        let flying = mines.state[i] == FLYING;
        if !flying && (mines.state[i] != ARMED || i % CHECK_TICKS as usize != phase) {
            continue;
        }
        let at = world_of(mines, w.origin, i);
        let mut best: Option<(f64, usize)> = None;
        for &r in w.hull_rows {
            let j = r as usize;
            if !can_trigger(w.rows.flags[j]) || !is_hostile(w, mines.faction_ix[i], w.rows.faction_ix[j]) {
                continue;
            }
            let g = hull_gap(w.rows, j, at, spec.home_m);
            if g < spec.home_m && best.is_none_or(|(d, _)| g < d) {
                best = Some((g, j));
            }
        }
        if !flying {
            if let Some((_, j)) = best {
                // Takes off toward the hull it found, at its homing speed (it is a bolt row from now on).
                let heading = normalized(sub(w.rows.positions[j], at));
                let v = scale(heading, spec.speed_mps as f32);
                mines.state[i] = FLYING;
                mines.fixed[i] = false;
                mines.dirty = true;
                mines.vel[i] = v;
                out.launches.push((i as u32, at, sub(v, w.frame_velocity)));
            }
            continue;
        }
        match best {
            Some((gap, _)) if gap <= spec.trigger_m => flag(out, i, CAUSE_TRIGGER),
            Some((_, j)) => {
                // Turns toward the hull no faster than its turn rate allows, at a steady speed.
                let p = bolt_index(w.bolts, mines.bolt[i]);
                let now = p.map_or(Vector3::ZERO, |p| add(w.bolts.velocities[p], w.frame_velocity));
                let want = normalized(sub(w.rows.positions[j], at));
                let heading = turn_toward(normalized(now), want, spec.turn_rad_s * w.delta);
                let v = scale(heading, spec.speed_mps as f32);
                out.steers.push((mines.bolt[i], sub(v, w.frame_velocity)));
            }
            None => {
                // Nothing left to chase: it stops here and lies dormant again.
                out.spends.push(mines.bolt[i]);
                mines.bolt[i] = 0;
                mines.state[i] = ARMED;
                mines.vel[i] = Vector3::ZERO;
                mines.fixed[i] = true;
                mines.dirty = true;
            }
        }
    }
}

// `from` turned toward `to` by at most `max_rad` (unit vectors; `to` when `from` has no direction).
fn turn_toward(from: Vector3, to: Vector3, max_rad: f64) -> Vector3 {
    let c = f64::from(dot(from, to)).clamp(-1.0, 1.0);
    if length(from) < 0.5 || c.acos() <= max_rad {
        return to;
    }
    // The in-plane blend that is `max_rad` off `from`; straight back (c = -1) turns about any axis, so it takes the plane's x.
    let angle = c.acos();
    let k = (max_rad / angle).clamp(0.0, 1.0);
    let sin_a = angle.sin().max(1e-9);
    let (a, b) = (((1.0 - k) * angle).sin() / sin_a, (k * angle).sin() / sin_a);
    normalized(add(scale(from, a as f32), scale(to, b as f32)))
}

// Each hull of the tick against the mines near it: a hostile within a mine's trigger of its surface, or any hull whose body
// touches a mine's, sets the mine off.
fn triggers_and_touches(mines: &Mines, mobile: &[u32], specs: &[Spec; KINDS], w: &World, out: &mut StepOut) {
    let phase = w.tick.rem_euclid(CHECK_TICKS) as usize;
    let widest = specs.iter().map(|s| s.trigger_m.max(s.body_m)).fold(0.0, f64::max);
    for &r in w.hull_rows {
        let j = r as usize;
        if !can_trigger(w.rows.flags[j]) {
            continue;
        }
        let radius = w.rows.radii[j];
        let hull_at = w.rows.positions[j];
        let faction = w.rows.faction_ix[j];
        let capital = is_capital(w.rows, j);
        let v = if w.frame_velocity == Vector3::ZERO { w.rows.velocities[j] } else { add(w.rows.velocities[j], w.frame_velocity) };
        let step = [f64::from(v.x) * w.delta, f64::from(v.y) * w.delta, f64::from(v.z) * w.delta];
        let half = 0.5 * (step[0] * step[0] + step[1] * step[1] + step[2] * step[2]).sqrt();
        if !half.is_finite() {
            continue;
        }
        let mid = Vector3::new(
            (f64::from(hull_at.x) - 0.5 * step[0]) as f32,
            (f64::from(hull_at.y) - 0.5 * step[1]) as f32,
            (f64::from(hull_at.z) - 0.5 * step[2]) as f32,
        );
        let owner_body = w.rows.body_ids[j];
        each_near(mines, mobile, w.origin, mid, radius + widest + half, |i| {
            if out.fired[i] != 0 {
                return;
            }
            let spec = &specs[mines.kind[i] as usize];
            let at = world_of(mines, w.origin, i);
            // A touch: any side's hull whose body reaches the mine's, along this tick's move.
            let grace = mines.owner[i] != 0 && mines.owner[i] == owner_body && w.now_s - mines.born_s[i] < OWN_GRACE_S;
            let touched = if grace {
                false
            } else if radius <= FIGHTER_RADIUS_MAX_M {
                let reach = spec.body_m + radius;
                segment_point_dist_sq(hull_at, step, at) <= reach * reach
            } else {
                hull_gap(w.rows, j, at, spec.body_m + 1.0) <= spec.body_m
            };
            if touched {
                flag(out, i, CAUSE_TOUCH);
                return;
            }
            if mines.state[i] != ARMED || i % CHECK_TICKS as usize != phase {
                return;
            }
            if (spec.capitals_only && !capital) || !is_hostile(w, mines.faction_ix[i], faction) {
                return;
            }
            let near = if radius <= FIGHTER_RADIUS_MAX_M {
                ((f64::from(dist_sq(hull_at, at))).sqrt() - radius).max(0.0)
            } else {
                hull_gap(w.rows, j, at, spec.trigger_m + 1.0)
            };
            if near <= spec.trigger_m {
                flag(out, i, CAUSE_TRIGGER);
            }
        });
    }
}

/// The mines in play (flying ones excluded) whose body a blast of `radius_m` at World point `centre` reaches, ascending.
pub fn in_blast(mines: &Mines, specs: &[Spec; KINDS], origin: Vector3, centre: Vector3, radius_m: f64, out: &mut Vec<u32>) {
    let first = out.len();
    let reach = radius_m + specs.iter().map(|s| s.body_m).fold(0.0, f64::max);
    let mut mobile = Vec::new();
    mobile_slots(mines, &mut mobile);
    each_near(mines, &mobile, origin, centre, reach, |i| {
        let r = radius_m + specs[mines.kind[i] as usize].body_m;
        if f64::from(dist_sq(centre, world_of(mines, origin, i))) <= r * r {
            out.push(i as u32);
        }
    });
    out[first..].sort_unstable();
}

/// The mines a viewer of faction `viewer` sees on its radar from World point `from`: every mine within `range_m` that is not
/// hostile to it (its own and its friends', always) and every hostile one within its kind's radar range. Flying mines are
/// listed too, at their bolt row's place. Appends slots to `out` in ascending order.
pub fn radar(mines: &Mines, specs: &[Spec; KINDS], w: &World, from: Vector3, viewer: u32, range_m: f64, out: &mut Vec<u32>) {
    for i in 0..mines.len() {
        if !mines.alive[i] {
            continue;
        }
        let at = if mines.state[i] == FLYING {
            bolt_index(w.bolts, mines.bolt[i]).map_or(world_of(mines, w.origin, i), |p| w.bolts.positions[p])
        } else {
            world_of(mines, w.origin, i)
        };
        let d = f64::from(length(sub(at, from)));
        let own = !is_hostile(w, viewer, mines.faction_ix[i]);
        let reach = if own { range_m } else { range_m.min(specs[mines.kind[i] as usize].radar_m) };
        if d <= reach {
            out.push(i as u32);
        }
    }
}

#[cfg(test)]
mod tests;
