// The core's shell around the mines (M10-T15, Q20, D12.9): one `ScsMineRows` for each minefield, holding its mines as rows with
// no node, stepped once a tick from `SimCore.step_now` after the capital guns (so an interceptor's pulses have met the mines
// in flight) and before the bolts move. GDScript lays the placed mines, draws them and answers what the step names; the mines
// set off wait here for the field's landing, which the native blast batch runs with their blasts (M10-T76, `blast_batch.rs`).
// The core decides who goes off, which mines take off, how the homing ones steer and which mines the battle's layers lay. The maths is `mine_kernels` and `mine_layers`,
// engine-free. A mine in flight is an owned bolt row of the missile kind with no damage and no look, so the interceptor
// batteries shoot it down like any missile (toughness from its kind) while the field's own draw shows it.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::grid_kernels::KIND_MISSILE;
use crate::mine_kernels::{self as mk, KINDS, Mines, SPEC_LEN, Spec, StepOut, World};
use crate::mine_layers::{self as ml, Lay, Layer};
use crate::rows::LOOK_NONE;
use crate::sim_core::ScsSimCore;

/// A mine's bolt row is this big, m: it needs no hit radius of its own (its trigger fires long before it touches a hull).
const BOLT_RADIUS_M: f64 = 1.0;
/// The flash tint of a mine shot down.
const BOLT_COLOR: [f32; 4] = [2.0, 1.2, 0.4, 1.0];
/// How long a mine's bolt row may fly, s: a guided mine homes for a minute at most, an energy mine's flight plus slack.
const HOMING_LIFE_S: f64 = 60.0;
/// A layer takes `LAYER_LEN` numbers: nearest and farthest target (m), cycle (s), mines a drop, most in play, cone half angle
/// (deg), the speed a dropped mine leaves at (m/s) and how far in front of the mount it appears (m).
const LAYER_LEN: usize = 8;

/// One field's mines, its layers and the step's scratch.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsMineRows {
    base: Base<RefCounted>,
    core: Option<Gd<ScsSimCore>>,
    mines: Mines,
    specs: Option<[Spec; KINDS]>,
    hostile: Vec<bool>,
    factions: usize,
    out: StepOut,
    layers: Vec<Layer>,
    lays: Vec<Lay>,
    owner_rows: Vec<i32>,
    detonations: i64,
    shot_on_flight: i64,
    last_us: f64,
    // The mines set off and waiting for the field's next landing (M10-T76): in the order they were set off, with why, and
    // which slots are among them; a blast landed in that loop adds more, so it runs the chain out.
    queued: Vec<bool>,
    going: Vec<(u32, u8)>,
    going_at: usize,
}

impl ScsMineRows {
    fn specs_or_none(&self) -> [Spec; KINDS] {
        self.specs.unwrap_or([Spec::NONE; KINDS])
    }

    /// The mines in play a blast of `radius_m` at `centre` reaches, the field's node at `origin` (ascending slots).
    pub(crate) fn reached(&self, origin: Vector3, centre: Vector3, radius_m: f64, out: &mut Vec<u32>) {
        mk::in_blast(&self.mines, &self.specs_or_none(), origin, centre, radius_m, out);
    }

    /// Mine `slot` goes off in the field's next landing, for `cause`; false when it is out of range or already set off.
    pub(crate) fn queue_slot(&mut self, slot: i64, cause: u8) -> bool {
        match usize::try_from(slot).ok().filter(|&i| i < self.queued.len() && !self.queued[i]) {
            Some(i) => {
                self.queued[i] = true;
                self.going.push((i as u32, cause));
                true
            }
            None => false,
        }
    }

    /// How many mines wait for the field's next landing.
    pub(crate) fn waiting(&self) -> usize {
        self.going.len() - self.going_at
    }

    /// The next mine of the landing in progress and why it goes off; None when the chain has run out (the list is emptied).
    pub(crate) fn next_going(&mut self) -> Option<(usize, u8)> {
        if self.going_at >= self.going.len() {
            self.going.clear();
            self.going_at = 0;
            return None;
        }
        let (slot, cause) = self.going[self.going_at];
        self.going_at += 1;
        let i = slot as usize;
        self.queued[i] = false;
        Some((i, cause))
    }

    /// Mine `slot` goes off now: its kind, faction index, owner and offset from the node, or None when it was not in play.
    pub(crate) fn go_off(&mut self, slot: usize) -> Option<(u8, u32, i64, Vector3)> {
        let m = &self.mines;
        if slot >= m.len() || !m.alive[slot] {
            return None;
        }
        let info = (m.kind[slot], m.faction_ix[slot], m.owner[slot], m.local[slot]);
        self.detonate(slot as i64).then_some(info)
    }
}

#[godot_api]
impl ScsMineRows {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Reads the core's rows, and adds the mines in flight to the core's bolts, from now on.
    #[func]
    fn attach_core(&mut self, core: Gd<ScsSimCore>) -> bool {
        self.core = Some(core);
        true
    }

    /// The relations table, row-major by the core's faction indices (1 hostile, anything else not): `count` factions square.
    #[func]
    fn set_hostility(&mut self, count: i64, matrix: PackedByteArray) -> bool {
        let n = usize::try_from(count).unwrap_or(0);
        if matrix.len() != n * n {
            godot_error!("ScsMineRows.set_hostility: {} entries for {n} factions", matrix.len());
            return false;
        }
        self.factions = n;
        self.hostile = matrix.as_slice().iter().map(|&b| b == 1).collect();
        true
    }

    /// How many factions the core knows now (the hostility table must cover them all).
    #[func]
    fn faction_count(&self) -> i64 {
        self.core.as_ref().map_or(0, |c| c.bind().factions.len() as i64)
    }

    /// Kind `kind`'s numbers (`mine_kernels::SPEC_LEN` of them: trigger, body, arm, dormant, speed, home range, fuse, capitals
    /// only, turn rate, blast radius, toughness, radar range). False for a kind or numbers it refuses.
    #[func]
    fn set_spec(&mut self, kind: i64, numbers: PackedFloat64Array) -> bool {
        let Some(spec) = Spec::from_slice(numbers.as_slice()) else {
            godot_error!("ScsMineRows.set_spec: want {SPEC_LEN} finite numbers, got {}", numbers.len());
            return false;
        };
        let Some(k) = usize::try_from(kind).ok().filter(|&k| k < KINDS) else {
            return false;
        };
        let mut all = self.specs_or_none();
        all[k] = spec;
        self.specs = Some(all);
        true
    }

    /// Makes room for `slots` mines (the field's draw has that many instances).
    #[func]
    fn reserve(&mut self, slots: i64) {
        let n = usize::try_from(slots).unwrap_or(0);
        self.mines.reserve_slots(n);
        self.queued.resize(n, false);
    }

    /// Mine `slot` goes off at the field's next landing (M10-T76), for `cause` (`mine_kernels::CAUSE_*`); false when it is out
    /// of range or already set off.
    #[func]
    fn queue(&mut self, slot: i64, cause: i64) -> bool {
        self.queue_slot(slot, cause as u8)
    }

    /// Whether mine `slot` waits to go off at the next landing.
    #[func]
    fn is_queued(&self, slot: i64) -> bool {
        usize::try_from(slot).ok().and_then(|i| self.queued.get(i)).copied().unwrap_or(false)
    }

    /// Mine `slot` no longer counts as set off (it left play another way); a place it holds in the list is skipped.
    #[func]
    fn unqueue(&mut self, slot: i64) {
        if let Some(q) = usize::try_from(slot).ok().and_then(|i| self.queued.get_mut(i)) {
            *q = false;
        }
    }

    /// How many mines wait for the next landing.
    #[func]
    fn going_count(&self) -> i64 {
        self.waiting() as i64
    }

    /// Lays a mine of `kind` (0 proximity, 1 energy, 2 guided) and `faction`'s at `local` (an offset from the field's node),
    /// drifting at `vel` (against the anchor's rest), `armed` or not, at sim time `now_s`; `slot` -1 takes the first free one.
    /// Returns its slot, or -1 when the table is full.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn lay(&mut self, slot: i64, kind: i64, faction: StringName, local: Vector3, vel: Vector3, armed: bool, now_s: f64, owner: i64) -> i64 {
        let Some(core) = self.core.as_mut() else {
            return -1;
        };
        let faction_ix = core.bind_mut().faction_index(faction);
        let specs = self.specs.unwrap_or([Spec::NONE; KINDS]);
        let k = usize::try_from(kind).unwrap_or(0).min(KINDS - 1);
        let at = usize::try_from(slot).ok();
        let state = if armed { mk::ARMED } else { mk::DORMANT };
        self.mines
            .lay(at, k as u8, faction_ix, local, vel, state, now_s, &specs[k], owner)
            .map_or(-1, |s| s as i64)
    }

    /// Mine `slot` goes off (or is taken out): true when it was in play. A mine in flight gives up its bolt row.
    #[func]
    fn detonate(&mut self, slot: i64) -> bool {
        let Ok(i) = usize::try_from(slot) else {
            return false;
        };
        let bolt = self.mines.bolt.get(i).copied().unwrap_or(0);
        if !self.mines.retire(i) {
            return false;
        }
        if bolt != 0 {
            self.spend_bolt(bolt);
        }
        self.detonations += 1;
        true
    }

    /// Mine `slot` belongs to `faction`'s side from now on (a bench's own sides go when its run ends). False for a free slot.
    #[func]
    fn set_faction(&mut self, slot: i64, faction: StringName) -> bool {
        let Some(core) = self.core.as_mut() else {
            return false;
        };
        let ix = core.bind_mut().faction_index(faction);
        match usize::try_from(slot).ok().filter(|&i| i < self.mines.len() && self.mines.alive[i]) {
            Some(i) => {
                self.mines.faction_ix[i] = ix;
                true
            }
            None => false,
        }
    }

    /// Whether mine `slot` is in play.
    #[func]
    fn is_alive(&self, slot: i64) -> bool {
        usize::try_from(slot).ok().and_then(|i| self.mines.alive.get(i)).copied().unwrap_or(false)
    }

    /// How many mines are in play.
    #[func]
    fn alive_count(&self) -> i64 {
        self.mines.in_play() as i64
    }

    /// Mine `slot`'s `[kind, faction index, state, owner body, offset from the node, velocity, whether it is fixed]`, or an
    /// empty array for a free slot.
    #[func]
    fn info(&self, slot: i64) -> VarArray {
        let mut out = VarArray::new();
        let m = &self.mines;
        let Some(i) = usize::try_from(slot).ok().filter(|&i| i < m.len() && m.alive[i]) else {
            return out;
        };
        out.push(&i64::from(m.kind[i]).to_variant());
        out.push(&i64::from(m.faction_ix[i]).to_variant());
        out.push(&i64::from(m.state[i]).to_variant());
        out.push(&m.owner[i].to_variant());
        out.push(&m.local[i].to_variant());
        out.push(&m.vel[i].to_variant());
        out.push(&m.fixed[i].to_variant());
        out
    }

    /// One tick at tick `tick`, sim time `now_s`, the field's node at `origin`: `[the mines that go off (slots), why each
    /// (`mine_kernels::CAUSE_*`, bytes), the slots that moved, their offsets, the slots an interceptor shot down (already out
    /// of play), the slots the layers laid this tick, the kind of each]`. A mine that goes off stays in play until the caller
    /// `detonate`s it (a blast may set off more first).
    #[func]
    fn step(&mut self, tick: i64, now_s: f64, delta: f64, origin: Vector3) -> VarArray {
        let started = std::time::Instant::now();
        let mut out = VarArray::new();
        let Some(mut core) = self.core.clone() else {
            return out;
        };
        let specs = self.specs_or_none();
        let live = delta.is_finite() && delta > 0.0;
        let mut applied = Applied::default();
        if !self.mines.is_empty() || !self.layers.is_empty() {
            let guard = core.bind();
            let world = World {
                rows: &guard.rows,
                bolts: &guard.bolts,
                hull_rows: &guard.sweep_rows,
                hostile: &self.hostile,
                factions: self.factions,
                origin,
                frame_velocity: guard.frame_velocity(),
                tick,
                now_s,
                delta,
            };
            if live {
                mk::step(&mut self.mines, &specs, &world, &mut self.out);
            } else {
                self.out.clear();
            }
            self.lays.clear();
            if !self.layers.is_empty() && live {
                self.owner_rows.clear();
                self.owner_rows.extend(self.layers.iter().map(|l| guard.row_for_kernel(l.owner) as i32));
                let view = ml::View {
                    rows: &guard.rows,
                    hull_rows: &guard.sweep_rows,
                    owner_rows: &self.owner_rows,
                    hostile: &self.hostile,
                    factions: self.factions,
                    frame_velocity: world.frame_velocity,
                    now_s,
                };
                ml::decide(&mut self.layers, &self.mines, &specs, &view, &mut self.lays);
            }
            applied.frame_velocity = world.frame_velocity;
        } else {
            self.out.clear();
        }
        self.apply(&mut core, &specs, origin, now_s, &mut applied);
        let dets: Vec<i32> = self.out.dets.iter().map(|d| d.0 as i32).collect();
        let causes: Vec<u8> = self.out.dets.iter().map(|d| d.1).collect();
        let moved: Vec<i32> = self.out.moved.iter().map(|&s| s as i32).collect();
        let places: Vec<Vector3> = self.out.moved.iter().map(|&s| self.mines.local[s as usize]).collect();
        let downed: Vec<i32> = self.out.downed.iter().map(|&s| s as i32).collect();
        out.push(&PackedInt32Array::from(dets.as_slice()).to_variant());
        out.push(&PackedByteArray::from(causes.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(moved.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(places.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(downed.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(applied.laid.as_slice()).to_variant());
        out.push(&PackedByteArray::from(applied.laid_kinds.as_slice()).to_variant());
        self.last_us = started.elapsed().as_secs_f64() * 1e6;
        out
    }

    /// The mines in play whose body a blast of `radius_m` at World point `centre` reaches (the field's node at `origin`),
    /// ascending, flying ones left out.
    #[func]
    fn in_blast(&self, origin: Vector3, centre: Vector3, radius_m: f64) -> PackedInt32Array {
        let mut found: Vec<u32> = Vec::new();
        mk::in_blast(&self.mines, &self.specs_or_none(), origin, centre, radius_m, &mut found);
        let ids: Vec<i32> = found.iter().map(|&s| s as i32).collect();
        PackedInt32Array::from(ids.as_slice())
    }

    /// What a viewer of `faction` at `from` sees of the field on its radar within `range_m` (the field's node at `origin`):
    /// `[slots, their places in the World, each one's faction index]`. A mine hostile to it shows only within its kind's radar
    /// range, its own and its friends' always.
    #[func]
    fn radar(&self, origin: Vector3, from: Vector3, faction: StringName, range_m: f64) -> VarArray {
        let mut out = VarArray::new();
        let Some(core) = self.core.as_ref() else {
            return out;
        };
        let guard = core.bind();
        let viewer = guard.factions.iter().position(|f| *f == faction).map_or(u32::MAX, |k| k as u32);
        let world = World {
            rows: &guard.rows,
            bolts: &guard.bolts,
            hull_rows: &guard.sweep_rows,
            hostile: &self.hostile,
            factions: self.factions,
            origin,
            frame_velocity: guard.frame_velocity(),
            tick: 0,
            now_s: 0.0,
            delta: 0.0,
        };
        let mut found: Vec<u32> = Vec::new();
        mk::radar(&self.mines, &self.specs_or_none(), &world, from, viewer, range_m, &mut found);
        let slots: Vec<i32> = found.iter().map(|&s| s as i32).collect();
        let places: Vec<Vector3> = found.iter().map(|&s| crate::v3::add(origin, self.mines.local[s as usize])).collect();
        let sides: Vec<i32> = found.iter().map(|&s| self.mines.faction_ix[s as usize] as i32).collect();
        out.push(&PackedInt32Array::from(slots.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(places.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(sides.as_slice()).to_variant());
        out
    }

    /// One mount of ship `owner` (a body id) that lays mines of `kind`, `local` on the ship, mines leaving along `forward`:
    /// `numbers` are `LAYER_LEN`. Returns the layer's index, or -1 when refused.
    #[func]
    fn add_layer(&mut self, owner: i64, local: Vector3, forward: Vector3, kind: i64, numbers: PackedFloat64Array) -> i64 {
        let s = numbers.as_slice();
        let k = usize::try_from(kind).ok().filter(|&k| k == mk::ENERGY as usize || k == mk::GUIDED as usize);
        let Some(k) = k.filter(|_| s.len() == LAYER_LEN && s.iter().all(|x| x.is_finite())) else {
            godot_error!("ScsMineRows.add_layer: kind 1 or 2 and {LAYER_LEN} finite numbers, got kind {kind} and {}", s.len());
            return -1;
        };
        self.layers.push(Layer {
            owner,
            local,
            forward: if forward.length() > 1e-6 { forward.normalized() } else { Vector3::new(0.0, 0.0, -1.0) },
            kind: k as u8,
            works: true,
            range_min_m: s[0].max(0.0),
            range_m: s[1].max(0.0),
            cycle_s: s[2].max(0.1),
            count: s[3].max(1.0) as u32,
            max_in_play: s[4].max(1.0) as u32,
            cone_cos: s[5].clamp(0.0, 180.0).to_radians().cos(),
            drop_mps: s[6],
            clearance_m: s[7].max(0.0),
            next_at: 0.0,
            search_at: 0.0,
        });
        (self.layers.len() - 1) as i64
    }

    /// Layer `index` lays again (true), or stops (its section is lost). Layers keep their indices.
    #[func]
    fn set_layer_works(&mut self, index: i64, works: bool) {
        if let Some(l) = usize::try_from(index).ok().and_then(|i| self.layers.get_mut(i)) {
            l.works = works;
        }
    }

    /// Ship `owner` is gone: its layers stop for good (their indices stay).
    #[func]
    fn remove_owner(&mut self, owner: i64) {
        for l in self.layers.iter_mut().filter(|l| l.owner == owner) {
            l.works = false;
            l.owner = 0;
        }
    }

    /// How many layers there are.
    #[func]
    fn layer_count(&self) -> i64 {
        self.layers.len() as i64
    }

    /// Hostile shots that met a mine in flight since the rows were made.
    #[func]
    fn shots_on_flight(&self) -> i64 {
        self.shot_on_flight
    }

    /// Mines gone off through `detonate` since the rows were made.
    #[func]
    fn detonations(&self) -> i64 {
        self.detonations
    }

    /// The last step's cost, microseconds (wall clock; a readout).
    #[func]
    fn step_us(&self) -> f64 {
        self.last_us
    }

    /// A hash of every mine's state and place and every layer's clock, to compare runs byte for byte.
    #[func]
    fn digest(&self) -> i64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut word = |w: u64| {
            for b in w.to_le_bytes() {
                h ^= u64::from(b);
                h = h.wrapping_mul(0x0000_0100_0000_01b3);
            }
        };
        let m = &self.mines;
        for i in 0..m.len() {
            word(u64::from(m.alive[i]));
            if !m.alive[i] {
                continue;
            }
            word(u64::from(m.kind[i]));
            word(u64::from(m.state[i]));
            for c in [m.local[i].x, m.local[i].y, m.local[i].z, m.vel[i].x, m.vel[i].y, m.vel[i].z] {
                word(u64::from(c.to_bits()));
            }
            word(m.fuse_at[i].to_bits());
        }
        for l in &self.layers {
            word(l.next_at.to_bits());
            word(l.search_at.to_bits());
        }
        h as i64
    }
}

// What `apply` leaves for the step's answer.
#[derive(Default)]
struct Applied {
    frame_velocity: Vector3,
    laid: Vec<i32>,
    laid_kinds: Vec<u8>,
}

impl ScsMineRows {
    // The step's bolt work on the core: homing mines take off as bolt rows, steered ones turn, finished ones give theirs up,
    // shot-down ones leave play; then the layers' mines are laid (an energy mine as a bolt row in flight, a guided one dormant).
    fn apply(&mut self, core: &mut Gd<ScsSimCore>, specs: &[Spec; KINDS], origin: Vector3, now_s: f64, applied: &mut Applied) {
        let fv = applied.frame_velocity;
        let mut c = core.bind_mut();
        for &(slot, at, v) in &self.out.launches {
            let i = slot as usize;
            let toughness = specs[self.mines.kind[i] as usize].toughness;
            let id = c.add_owned_bolt(at, v, self.mines.faction_ix[i], self.mines.owner[i], KIND_MISSILE, BOLT_RADIUS_M, 0.0, BOLT_COLOR, LOOK_NONE, now_s + HOMING_LIFE_S);
            c.bolts.set_newest_owned_hits(toughness);
            self.mines.bolt[i] = id;
        }
        for &(id, v) in &self.out.steers {
            if let Some(p) = (0..c.bolts.owned).rev().find(|&p| c.bolts.ids[p] == id) {
                c.bolts.velocities[p] = v;
            }
        }
        for &id in &self.out.spends {
            if let Some(p) = (0..c.bolts.owned).rev().find(|&p| c.bolts.ids[p] == id) {
                c.bolts.spent[p] = true;
            }
        }
        // Shots that met a mine in flight: each is spent and takes a hit off the mine's row; at none left the mine is shot down.
        for &(shot, slot, left) in &self.out.shot_hits {
            if (shot as usize) < c.bolts.spent.len() {
                c.bolts.spent[shot as usize] = true;
            }
            let id = self.mines.bolt[slot as usize];
            if let Some(b) = (0..c.bolts.owned).rev().find(|&b| c.bolts.ids[b] == id) {
                c.bolts.set_hits_left(b, left);
                if left == 0 {
                    c.bolts.spent[b] = true;
                    self.out.downed.push(slot);
                }
            }
        }
        self.shot_on_flight += self.out.shot_hits.len() as i64;
        for &slot in &self.out.downed {
            self.mines.retire(slot as usize);
        }
        for lay in &self.lays {
            let spec = &specs[lay.kind as usize];
            let local = crate::v3::sub(lay.from, origin);
            // `lay.vel` is against the anchor's rest; a bolt row flies in the World, which moves against it by `fv`.
            let rest_vel = lay.vel;
            let flying = lay.kind == mk::ENERGY;
            let state = if flying { mk::FLYING } else { mk::DORMANT };
            let Some(slot) = self.mines.lay(None, lay.kind, lay.faction_ix, local, if flying { Vector3::ZERO } else { rest_vel }, state, now_s, spec, lay.owner) else {
                continue;
            };
            if flying {
                self.mines.dest[slot] = crate::v3::sub(lay.dest, origin);
                let life = f64::from(crate::v3::distance(lay.from, lay.dest)) / spec.speed_mps.max(1.0) + mk::FLIGHT_SLACK_S;
                let id = c.add_owned_bolt(lay.from, crate::v3::sub(lay.vel, fv), lay.faction_ix, lay.owner, KIND_MISSILE, BOLT_RADIUS_M, 0.0, BOLT_COLOR, LOOK_NONE, now_s + life);
                c.bolts.set_newest_owned_hits(spec.toughness);
                self.mines.bolt[slot] = id;
                self.mines.vel[slot] = rest_vel;
            }
            applied.laid.push(slot as i32);
            applied.laid_kinds.push(lay.kind);
        }
    }

    // Marks the bolt row `id` spent (a mine that went off or was taken out gives up its row).
    fn spend_bolt(&mut self, id: i64) {
        let Some(core) = self.core.as_mut() else {
            return;
        };
        let mut c = core.bind_mut();
        if let Some(p) = (0..c.bolts.owned).rev().find(|&p| c.bolts.ids[p] == id) {
            c.bolts.spent[p] = true;
        }
    }
}
