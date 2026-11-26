// Every blast lands here in one native batch (M10-T76, Q70, D12.6): a death, a section blowing, a missile's warhead, a mine.
// `BlastResolver` queues each blast; the batch lands the queue in order on the damage store: the mines a blast reaches are set
// off in their field's next landing, the core names the hulls it reaches (`blast_kernels`), each hull once by its nearest piece
// (`damage_store::blasts`), then the falloff damage through the store (`damage_store::landing`, friend or foe alike) and the
// push on the body or its tier row. A minefield's landing (its step's mines going off) runs here too, so a field and the deaths
// its blasts cause go off as one chain, in the order GDScript landed them. GDScript gets the events once each: the store's
// writes and events, one summary a damaged ship, each mine that went off, and a kill (or a hit it must land itself) ends a
// batch so it is answered, death blast and all, before the next hull is hit. Main thread only, in the tick, on the rows of the
// tick's sync, so one thread and six give the same.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
// A blast's numbers are tested as GDScript tests them, `not (x > 0.0)`, so NaN is nothing.
#![allow(clippy::neg_cmp_op_on_partial_ord)]
use godot::classes::{Node, Node3D, RigidBody3D};
use godot::prelude::*;

use crate::beam_rows::ScsBeamRows;
use crate::blast_kernels as bk;
use crate::damage_rows::ScsDamageStore;
use crate::damage_store::blasts::{self as db, Reach, Spec};
use crate::damage_store::landing::{self as dl, Ctx, LandHit, LandOut};
use crate::mine_kernels::{CAUSE_BLAST, KINDS};
use crate::mine_rows::ScsMineRows;
use crate::sim_core::ScsSimCore;
use crate::v3;

/// The meta a body carries while it flies as a tier row (`TierDirector.TIER_META`).
const TIER_META: &str = "_scs_tier_row";

/// A blast waiting to land.
#[derive(Clone)]
struct Queued {
    spec: Spec,
    source: StringName,
    centre: Vector3,
    faction: StringName,
    shooter: i64,
}

/// A minefield whose mines blasts set off (`MineField`, by its number: the order GDScript keeps them in).
struct Field {
    number: i64,
    node: i64,
    rows: Gd<ScsMineRows>,
}

/// The blast being landed: its hulls in order (with their `Damageable` and ship nodes), the next one, whether that one's hit
/// has landed (only its push is left).
struct Current {
    blast: Queued,
    faction_ix: u32,
    picks: Vec<Reach>,
    nodes: Vec<(Gd<Node>, Gd<Node3D>)>,
    at: usize,
    hit_done: bool,
    hurt: u32,
}

/// What ends a batch for GDScript beyond the store's events: a kill to announce, or a hit to land itself.
struct Yielded {
    kill: bool,
    hull: i64,
    body: i64,
    shooter: i64,
    damage: f64,
    applied: f64,
    point: Vector3,
    volume: i32,
    section: i32,
}

/// The mines that went off in a batch, in order.
#[derive(Default)]
struct MinesOut {
    fields: Vec<i64>,
    slots: Vec<i32>,
    causes: Vec<i32>,
    kinds: Vec<i32>,
    places: Vec<Vector3>,
}

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsBlastBatch {
    base: Base<RefCounted>,
    store: Option<Gd<ScsDamageStore>>,
    mine_specs: [Option<(Spec, StringName)>; KINDS],
    fields: Vec<Field>,
    queue: Vec<Queued>,
    queue_at: usize,
    field_loop: Option<(i64, Vector3)>,
    current: Option<Current>,
    out: LandOut,
    mines: MinesOut,
    yielded: Option<Yielded>,
    reached: Vec<bk::Reached>,
    found: Vec<Reach>,
    found_nodes: Vec<(Gd<Node>, Gd<Node3D>)>,
    tier_meta: Option<StringName>,
    slots: Vec<u32>,
    // Readouts since `reset_stats`.
    blasts: i64,
    hulls_hurt: i64,
    pushed: i64,
    reach_us: f64,
    run_us: f64,
    last_source: StringName,
    last_centre: Vector3,
    last_reached: i64,
    last_hurt: i64,
    // The landed hits since `set_hit_log(true)`, for the tests.
    log_on: bool,
    hit_log: Vec<dl::Landed>,
}

#[godot_api]
impl ScsBlastBatch {
    /// The damage store the blasts land on.
    #[func]
    fn attach_store(&mut self, store: Gd<ScsDamageStore>) -> bool {
        self.store = Some(store);
        true
    }

    /// Mine kind `kind`'s blast: `[d0, radius, impulse, push cap]` and its row's name.
    #[func]
    fn set_mine_blast(&mut self, kind: i64, numbers: PackedFloat64Array, source: StringName) -> bool {
        let n = numbers.as_slice();
        match usize::try_from(kind).ok().filter(|&k| k < KINDS && n.len() >= 4) {
            Some(k) => {
                self.mine_specs[k] = Some((spec_of(n), source));
                true
            }
            None => false,
        }
    }

    /// Minefield `number` (its node `node`) is in play with its mines in `rows`; a blast sets off the mines it reaches.
    #[func]
    fn add_field(&mut self, number: i64, node: i64, rows: Gd<ScsMineRows>) {
        self.fields.retain(|f| f.number != number);
        let at = self.fields.partition_point(|f| f.number < number);
        self.fields.insert(at, Field { number, node, rows });
    }

    #[func]
    fn remove_field(&mut self, number: i64) {
        self.fields.retain(|f| f.number != number);
    }

    /// Queues a blast (`[d0, radius, impulse, push cap]`, its row's name) at World point `centre`, its hits carrying `faction`
    /// and `shooter` (0: none). `run` lands it.
    #[func]
    fn set_off(&mut self, numbers: PackedFloat64Array, source: StringName, centre: Vector3, faction: StringName, shooter: i64) {
        let n = numbers.as_slice();
        if n.len() < 4 {
            return;
        }
        self.queue.push(Queued {
            spec: spec_of(n),
            source,
            centre,
            faction,
            shooter,
        });
    }

    /// Minefield `number`'s landing, its node at `origin`: its mines waiting to go off, one blast each, after the blasts queued
    /// before it. False when it has none waiting.
    #[func]
    fn begin_field(&mut self, number: i64, origin: Vector3) -> bool {
        let waiting = self.fields.iter().find(|f| f.number == number).is_some_and(|f| f.rows.bind().waiting() > 0);
        if waiting {
            self.field_loop = Some((number, origin));
        }
        waiting
    }

    /// Lands the queue (and a field's landing begun) in order with `core`'s rows and god mode as it is, until it is all landed
    /// or GDScript must answer first. Returns `[done, coalesced writes (grouped by ledger), events (six numbers each), summaries
    /// (`ScsBeamRows`' columns), the kill (a dictionary, empty for none), the hit to land in GDScript (likewise), the mines that
    /// went off (fields, slots, causes, kinds, World places), hits landed, damage landed]`.
    #[func]
    fn run(&mut self, core: Option<Gd<ScsSimCore>>, god_mode: bool) -> VarArray {
        let started = std::time::Instant::now();
        self.out.clear();
        self.mines = MinesOut::default();
        self.yielded = None;
        let mut done = false;
        if let Some(store) = self.store.clone() {
            loop {
                if self.current.is_some() {
                    if self.step_current(&core, &store, god_mode) {
                        break;
                    }
                    continue;
                }
                if self.queue_at < self.queue.len() {
                    let q = self.queue[self.queue_at].clone();
                    self.queue_at += 1;
                    self.begin(&core, &store, q);
                    continue;
                }
                self.queue.clear();
                self.queue_at = 0;
                if self.field_loop.is_some() && self.next_mine(&core) {
                    continue;
                }
                done = true;
                break;
            }
        } else {
            self.queue.clear();
            self.queue_at = 0;
            self.field_loop = None;
            done = true;
        }
        self.out.finish();
        let o = &self.out;
        let mut out = VarArray::new();
        out.push(&done.to_variant());
        out.push(&PackedFloat64Array::from(o.sync.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(o.events.as_slice()).to_variant());
        out.push(&ScsBeamRows::summary_columns(&o.summaries).to_variant());
        let (mut kill, mut left) = (VarDictionary::new(), VarDictionary::new());
        if let (Some(y), Some(cur)) = (&self.yielded, &self.current) {
            let d = if y.kill { &mut kill } else { &mut left };
            d.set("target", y.hull);
            d.set("body", y.body);
            d.set("shooter", y.shooter);
            d.set("faction", &cur.blast.faction);
            d.set("damage", y.damage);
            d.set("applied", y.applied);
            d.set("point", y.point);
            d.set("volume", i64::from(y.volume));
            d.set("section", i64::from(y.section));
            d.set("centre", cur.blast.centre);
            d.set("place", cur.picks[cur.at].place);
        }
        out.push(&kill.to_variant());
        out.push(&left.to_variant());
        let m = &self.mines;
        out.push(&PackedInt64Array::from(m.fields.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(m.slots.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(m.causes.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(m.kinds.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(m.places.as_slice()).to_variant());
        out.push(&i64::from(o.hits).to_variant());
        out.push(&o.damage.to_variant());
        self.run_us += started.elapsed().as_secs_f64() * 1e6;
        out
    }

    /// Whether blasts wait to land (or a field's landing is under way).
    #[func]
    fn pending(&self) -> bool {
        self.current.is_some() || self.queue_at < self.queue.len() || self.field_loop.is_some()
    }

    /// The readouts: `[blasts landed, hulls hurt, hulls pushed, the core's reach (us, all blasts), the batch's own time (us,
    /// every run)]`.
    #[func]
    fn stats(&self) -> PackedFloat64Array {
        PackedFloat64Array::from([self.blasts as f64, self.hulls_hurt as f64, self.pushed as f64, self.reach_us, self.run_us].as_slice())
    }

    /// The last blast landed: `[its row's name, centre, hulls reached, hulls hurt]`.
    #[func]
    fn last(&self) -> VarArray {
        let mut out = VarArray::new();
        out.push(&self.last_source.to_variant());
        out.push(&self.last_centre.to_variant());
        out.push(&self.last_reached.to_variant());
        out.push(&self.last_hurt.to_variant());
        out
    }

    #[func]
    fn reset_stats(&mut self) {
        self.blasts = 0;
        self.hulls_hurt = 0;
        self.pushed = 0;
        self.reach_us = 0.0;
        self.run_us = 0.0;
        self.last_source = StringName::default();
        self.last_centre = Vector3::ZERO;
        self.last_reached = 0;
        self.last_hurt = 0;
    }

    /// Keeps every landed blast hit from now on (true) or stops and forgets them (false): the tests' native hit log.
    #[func]
    fn set_hit_log(&mut self, on: bool) {
        self.log_on = on;
        self.hit_log.clear();
    }

    /// The hits landed since `set_hit_log(true)`: `[Damageables (a rotor's capital's), bodies, shooters, damage, points
    /// removed, points]`.
    #[func]
    fn hit_log(&self) -> VarArray {
        let l = &self.hit_log;
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(l.iter().map(|h| h.target).collect::<Vec<_>>().as_slice()).to_variant());
        out.push(&PackedInt64Array::from(l.iter().map(|h| h.body).collect::<Vec<_>>().as_slice()).to_variant());
        out.push(&PackedInt64Array::from(l.iter().map(|h| h.shooter).collect::<Vec<_>>().as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(l.iter().map(|h| h.damage).collect::<Vec<_>>().as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(l.iter().map(|h| h.applied).collect::<Vec<_>>().as_slice()).to_variant());
        out.push(&PackedVector3Array::from(l.iter().map(|h| h.point).collect::<Vec<_>>().as_slice()).to_variant());
        out
    }
}

fn spec_of(n: &[f64]) -> Spec {
    Spec {
        d0: n[0],
        radius: n[1],
        impulse: n[2],
        cap: n[3],
    }
}

fn node_of(id: i64) -> Option<Gd<Node>> {
    InstanceId::try_from_i64(id).and_then(|i| Gd::<Node>::try_from_instance_id(i).ok())
}

// A `Damageable`'s ship: its parent, a 3D node.
fn body_of(hull: &Gd<Node>) -> Option<Gd<Node3D>> {
    hull.get_parent().and_then(|p| p.try_cast::<Node3D>().ok())
}

impl ScsBlastBatch {
    // A blast begins: the mines it reaches wait for their field's landing, and the hulls it reaches are measured and picked.
    fn begin(&mut self, core: &Option<Gd<ScsSimCore>>, store: &Gd<ScsDamageStore>, q: Queued) {
        if !(q.spec.radius > 0.0) {
            return;
        }
        for f in &mut self.fields {
            let Some(node) = node_of(f.node).and_then(|n| n.try_cast::<Node3D>().ok()) else {
                continue;
            };
            if !node.is_inside_tree() {
                continue;
            }
            self.slots.clear();
            f.rows.bind().reached(node.get_global_position(), q.centre, q.spec.radius, &mut self.slots);
            let mut rows = f.rows.bind_mut();
            for &s in &self.slots {
                rows.queue_slot(i64::from(s), CAUSE_BLAST);
            }
        }
        let mut faction_ix = u32::MAX;
        self.found.clear();
        if let Some(core) = core {
            let c = core.bind();
            faction_ix = c.factions.iter().position(|f| *f == q.faction).map_or(u32::MAX, |i| i as u32);
            let started = std::time::Instant::now();
            self.reached.clear();
            bk::reach(&c.rows, &c.sweep_rows, q.centre, q.spec.radius, &mut self.reached);
            self.reach_us += started.elapsed().as_secs_f64() * 1e6;
            let s = store.bind();
            let tier_meta = self.tier_meta.get_or_insert_with(|| StringName::from(TIER_META)).clone();
            self.found_nodes.clear();
            for r in &self.reached {
                let j = r.row as usize;
                let hull = c.rows.hull_ids[j];
                let Some(nodes) = hurtable(&s, hull, &tier_meta) else {
                    continue;
                };
                let target = s.blast_targets.get(&hull);
                let (mut distance, mut point) = (r.distance, r.point);
                if r.volume < 0 {
                    if let Some((d, p)) = target.and_then(|t| db::nearest_on(&t.shapes, &c.rows.bases[j], c.rows.positions[j], q.centre)) {
                        distance = d;
                        point = p;
                    }
                    if !(distance < q.spec.radius) {
                        continue;
                    }
                }
                self.found.push(Reach {
                    index: self.found_nodes.len() as u32,
                    hull,
                    owner: target.map_or(hull, |t| t.owner),
                    distance,
                    point,
                    volume: r.volume,
                    place: c.rows.positions[j],
                });
                self.found_nodes.push(nodes);
            }
        }
        let mut picks = Vec::new();
        db::pick(&self.found, &mut picks);
        let nodes = picks.iter().map(|p| self.found_nodes[p.index as usize].clone()).collect();
        self.current = Some(Current {
            blast: q,
            faction_ix,
            picks,
            nodes,
            at: 0,
            hit_done: false,
            hurt: 0,
        });
    }

    // Lands the current blast's hulls from where it stopped; true when it stopped again for GDScript to answer.
    fn step_current(&mut self, core: &Option<Gd<ScsSimCore>>, store: &Gd<ScsDamageStore>, god_mode: bool) -> bool {
        let Some(mut cur) = self.current.take() else {
            return false;
        };
        while cur.at < cur.picks.len() {
            let p = cur.picks[cur.at];
            if !cur.hit_done {
                cur.hit_done = true;
                let damage = cur.blast.spec.damage_at(p.distance);
                if damage > 0.0 {
                    cur.hurt += 1;
                    if self.land(store, &cur, damage, god_mode) {
                        self.current = Some(cur);
                        return true;
                    }
                }
            }
            self.push(core, store, &cur);
            cur.at += 1;
            cur.hit_done = false;
        }
        self.blasts += 1;
        self.hulls_hurt += i64::from(cur.hurt);
        self.last_source = cur.blast.source.clone();
        self.last_centre = cur.blast.centre;
        self.last_reached = cur.picks.len() as i64;
        self.last_hurt = i64::from(cur.hurt);
        false
    }

    // One hull's damage through the store; true when the batch stopped on it (an event, a kill, a hit GDScript lands).
    fn land(&mut self, store: &Gd<ScsDamageStore>, cur: &Current, damage: f64, god_mode: bool) -> bool {
        let p = &cur.picks[cur.at];
        let (hull, body) = &cur.nodes[cur.at];
        if !hull.is_instance_valid() || !body.is_instance_valid() {
            return false;
        }
        let target_id = body.instance_id().to_i64();
        let shooter = if cur.blast.shooter != target_id { cur.blast.shooter } else { 0 };
        let p = *p;
        let mut guard = store.clone();
        let mut s = guard.bind_mut();
        let needs_frame = s.targets.get(&p.hull).is_some_and(|t| t.route != dl::ROUTE_PLAIN || t.layout != 0);
        let local = if needs_frame && body.is_inside_tree() {
            let x = body.get_global_transform();
            Some(v3::affine_inverse_xform(&x.basis, x.origin, p.point))
        } else {
            None
        };
        let hit = LandHit {
            target: p.hull,
            body: target_id,
            shooter,
            shooter_faction: cur.faction_ix,
            target_faction: None,
            disguise: None,
            damage,
            point: p.point,
            volume: p.volume,
            local,
        };
        let ctx = Ctx {
            blast: true,
            friendly_fire: false,
            god_mode,
            relation: &[],
            factions: 0,
        };
        let logged = self.out.landed.len();
        let sm = &mut *s;
        dl::land_more(&mut sm.store, &sm.targets, std::slice::from_ref(&hit), 0, &ctx, &mut self.out);
        if self.log_on {
            self.hit_log.extend_from_slice(&self.out.landed[logged..]);
        }
        if !self.out.stopped {
            return false;
        }
        let kill = self.out.kill.take();
        let left = self.out.deferred.take().is_some();
        if kill.is_some() || left {
            let (applied, section) = kill.map_or((0.0, -1), |(_, a, s)| (a, s));
            self.yielded = Some(Yielded {
                kill: kill.is_some(),
                hull: p.hull,
                body: target_id,
                shooter,
                damage,
                applied,
                point: p.point,
                volume: p.volume,
                section,
            });
        }
        true
    }

    // One hull's push away from the blast: on its body (a rotor's on its capital), or on its tier row.
    fn push(&mut self, core: &Option<Gd<ScsSimCore>>, store: &Gd<ScsDamageStore>, cur: &Current) {
        let (q, p) = (&cur.blast, &cur.picks[cur.at]);
        let (hull, own) = &cur.nodes[cur.at];
        if !hull.is_instance_valid() || !own.is_instance_valid() {
            return;
        }
        let (push_body, area) = match store.bind().blast_targets.get(&p.hull) {
            Some(t) => (t.push_body, t.area),
            None => return,
        };
        let body = if push_body == own.instance_id().to_i64() {
            own.clone()
        } else {
            match node_of(push_body).and_then(|n| n.try_cast::<Node3D>().ok()) {
                Some(b) => b,
                None => return,
            }
        };
        let away = v3::sub(p.place, q.centre);
        if f64::from(v3::length_squared(away)) < 1e-12 {
            return;
        }
        // `Damageable.ram_mass()`: its rigid body's mass, else the mass it was given (read now: it may be set late).
        let mass = match own.clone().try_cast::<RigidBody3D>() {
            Ok(rigid) => f64::from(rigid.get_mass()),
            Err(_) => hull.get("ram_mass_kg").try_to::<f64>().unwrap_or(0.0),
        };
        let dv = q.spec.push_at(p.distance, area, mass);
        if !(dv > 0.0) {
            return;
        }
        let kick = v3::scale(v3::normalized(away), dv as f32);
        let tier_meta = self.tier_meta.get_or_insert_with(|| StringName::from(TIER_META)).clone();
        if body.has_meta(&tier_meta) {
            if let Some(core) = core {
                let mut c = core.clone();
                let mut c = c.bind_mut();
                if let Some(i) = c.tier.index_of(push_body) {
                    c.tier.velocities[i] = v3::add(c.tier.velocities[i], kick);
                    self.pushed += 1;
                }
            }
            return;
        }
        if let Ok(mut rigid) = body.try_cast::<RigidBody3D>()
            && !rigid.is_freeze_enabled()
        {
            let v = rigid.get_linear_velocity();
            rigid.set_linear_velocity(v3::add(v, kick));
            self.pushed += 1;
        }
    }

    // The field's next mine goes off and its blast is queued; false once the field's landing has run out.
    fn next_mine(&mut self, core: &Option<Gd<ScsSimCore>>) -> bool {
        let Some((number, origin)) = self.field_loop else {
            return false;
        };
        let Some(f) = self.fields.iter_mut().find(|f| f.number == number) else {
            self.field_loop = None;
            return false;
        };
        let mut rows = f.rows.bind_mut();
        loop {
            let Some((slot, cause)) = rows.next_going() else {
                self.field_loop = None;
                return false;
            };
            let Some((kind, faction_ix, owner, local)) = rows.go_off(slot) else {
                continue;
            };
            let at = v3::add(origin, local);
            self.mines.fields.push(number);
            self.mines.slots.push(slot as i32);
            self.mines.causes.push(i32::from(cause));
            self.mines.kinds.push(i32::from(kind));
            self.mines.places.push(at);
            if let Some((spec, source)) = self.mine_specs.get(kind as usize).cloned().flatten() {
                let faction = core
                    .as_ref()
                    .and_then(|c| c.bind().factions.get(faction_ix as usize).cloned())
                    .unwrap_or_default();
                self.queue.push(Queued {
                    spec,
                    source,
                    centre: at,
                    faction,
                    shooter: owner,
                });
            }
            return true;
        }
    }
}

// `Damageable` `hull` and its ship when a blast can still hurt it: in play, or flying in the tier, and not yet destroyed.
fn hurtable(s: &ScsDamageStore, hull: i64, tier_meta: &StringName) -> Option<(Gd<Node>, Gd<Node3D>)> {
    let t = s.targets.get(&hull)?;
    if s.store.hulls.get(t.hull).is_none_or(|h| h.destroyed) {
        return None;
    }
    let node = node_of(hull)?;
    let body = body_of(&node)?;
    let active = node.is_inside_tree() && body.is_visible_in_tree() && body.can_process();
    (active || body.has_meta(tier_meta)).then_some((node, body))
}
