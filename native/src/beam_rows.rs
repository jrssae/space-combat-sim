// The core's shell around the capital beams (M10-T12, D12.9): GDScript registers each capital's beam emitters once, tells
// the rows when a mount stops working or the rate of fire changes, and steps them once a tick on the main thread after the
// core's sync; the tick's hits then land in one batch on the damage store (M10-T75, Q70, Q94, `land`) and GDScript draws the
// lines in one batch per kind. The maths is `beam_kernels` and `damage_store::landing`, engine-free.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use std::collections::HashMap;

use crate::beam_kernels::{self as bk, Beam, BeamDraw, BeamHit, BeamSpec, BeamWorld, Owner};
use crate::damage_rows::ScsDamageStore;
use crate::damage_store::landing::{self as dl, Ctx, LandHit, LandOut};
use crate::sim_core::ScsSimCore;

/// Numbers a weapon packs into for `add_beam`: kind, damage, dps, on_s, cycle_s, charge_s, range_m, turn_deg_s.
const SPEC_LEN: usize = 8;

/// Every capital's beam emitters as rows with no node per shot, stepped once a tick over the core's rows. Never calls the
/// engine or `Factions`: the caller passes the hostility table (by the core's faction indices) and lands what the step
/// returns.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsBeamRows {
    base: Base<RefCounted>,
    core: Option<Gd<ScsSimCore>>,
    beams: Vec<Beam>,
    owner_of: Vec<u32>,
    owners: Vec<Owner>,
    hostile: Vec<bool>,
    relation: Vec<u8>,
    factions: usize,
    // The damage store the hits land on, and each owner's faction (by `owners`' order).
    store: Option<Gd<ScsDamageStore>>,
    owner_factions: Vec<StringName>,
    // Per-step scratch, kept between ticks: the step's hits with their hulls (the `Damageable`s) and bodies.
    owner_rows: Vec<i32>,
    hits: Vec<BeamHit>,
    hit_hulls: Vec<i64>,
    hit_bodies: Vec<i64>,
    draws: Vec<BeamDraw>,
    land_out: LandOut,
    land_hits: Vec<LandHit>,
    // The landed hits since `set_hit_log(true)`, for the tests: summary target, body, shooter, damage, points removed, point.
    log_on: bool,
    hit_log: Vec<dl::Landed>,
    last_us: f64,
    kernel_us: f64,
    land_us: f64,
}

#[godot_api]
impl ScsBeamRows {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Reads the core's rows from now on.
    #[func]
    fn attach_core(&mut self, core: Gd<ScsSimCore>) -> bool {
        self.core = Some(core);
        true
    }

    /// The hostility table, row-major by the core's faction indices (1 hostile): `count` factions square.
    #[func]
    fn set_hostility(&mut self, count: i64, matrix: PackedByteArray) -> bool {
        let n = usize::try_from(count).unwrap_or(0);
        if matrix.len() != n * n {
            godot_error!(
                "ScsBeamRows.set_hostility: {} entries for {n} factions",
                matrix.len()
            );
            return false;
        }
        self.factions = n;
        self.hostile = matrix.as_slice().iter().map(|&b| b == 1).collect();
        self.relation = matrix.as_slice().to_vec();
        true
    }

    /// The damage store the hits land on (M10-T75).
    #[func]
    fn attach_store(&mut self, store: Gd<ScsDamageStore>) -> bool {
        self.store = Some(store);
        true
    }

    /// Ship `body`'s faction (its true one): who its beams may hurt, and what its hits' summaries say of it.
    #[func]
    fn set_owner_faction(&mut self, body: i64, faction: StringName) {
        if let Some(o) = self.owners.iter().position(|w| w.body == body) {
            if self.owner_factions.len() < self.owners.len() {
                self.owner_factions.resize(self.owners.len(), StringName::default());
            }
            self.owner_factions[o] = faction;
        }
    }

    /// How many factions the core knows now (the hostility table must cover them all).
    #[func]
    fn faction_count(&self) -> i64 {
        self.core
            .as_ref()
            .map_or(0, |c| c.bind().factions.len() as i64)
    }

    /// Ship `body` and its own bodies (hull and rotating sections), which its beams pass through. Again: the bodies change.
    #[func]
    fn add_owner(&mut self, body: i64, bodies: PackedInt64Array) {
        let list = bodies.as_slice().to_vec();
        match self.owners.iter_mut().find(|o| o.body == body) {
            Some(o) => o.bodies = list,
            None => {
                self.owners.push(Owner {
                    body,
                    bodies: list,
                    order: 0,
                    order_aim: None,
                });
                self.owner_factions.push(StringName::default());
            }
        }
    }

    /// One emitter of ship `owner` (`add_owner` first): where it sits and looks in the ship's frame, its arc's half angle,
    /// and its weapon (`SPEC_LEN` numbers). Its index, or -1 when refused.
    #[func]
    fn add_beam(
        &mut self,
        owner: i64,
        local_at: Vector3,
        local_fwd: Vector3,
        arc_half_deg: f64,
        spec: PackedFloat64Array,
    ) -> i64 {
        let s = spec.as_slice();
        let Some(o) = self.owners.iter().position(|w| w.body == owner) else {
            godot_error!("ScsBeamRows.add_beam: ship {owner} has no add_owner");
            return -1;
        };
        if s.len() != SPEC_LEN || s.iter().any(|x| !x.is_finite()) {
            godot_error!(
                "ScsBeamRows.add_beam: {} numbers (want {SPEC_LEN}, all finite)",
                s.len()
            );
            return -1;
        }
        let made = BeamSpec {
            kind: if s[0] as i64 == i64::from(bk::SUSTAINED) {
                bk::SUSTAINED
            } else {
                bk::PULSED
            },
            damage: s[1],
            dps: s[2],
            on_s: s[3],
            cycle_s: s[4],
            charge_s: s[5],
            range_m: s[6],
            turn_rad_s: s[7].to_radians(),
        };
        let mut beam = Beam::new(owner, local_at, local_fwd, arc_half_deg.to_radians(), made);
        beam.pick_wait = (self.beams.len() as u32) % bk::PICK_EVERY;
        self.beams.push(beam);
        self.owner_of.push(o as u32);
        (self.beams.len() - 1) as i64
    }

    /// Ship `body` leaves: its emitters go, the rest keep their order (GDScript drops the same entries).
    #[func]
    fn remove_owner(&mut self, body: i64) {
        let Some(o) = self.owners.iter().position(|w| w.body == body) else {
            return;
        };
        self.beams.retain(|b| b.owner != body);
        self.owners.remove(o);
        if o < self.owner_factions.len() {
            self.owner_factions.remove(o);
        }
        let owners = &self.owners;
        self.owner_of = self
            .beams
            .iter()
            .map(|b| owners.iter().position(|w| w.body == b.owner).unwrap_or(0) as u32)
            .collect();
    }

    /// Whether emitter `index`'s mount works, and its ship's rate of fire (0 to 1).
    #[func]
    fn set_works(&mut self, index: i64, works: bool, rate: f64) {
        if let Some(b) = usize::try_from(index)
            .ok()
            .and_then(|i| self.beams.get_mut(i))
        {
            b.works = works;
            b.rate = if rate.is_finite() {
                rate.clamp(0.0, 1.0)
            } else {
                0.0
            };
        }
    }

    /// The target ship `body`'s brain gives its beams (0: they pick their own).
    #[func]
    fn set_order(&mut self, body: i64, target: i64) {
        self.set_order_at(body, target, Vector3::ZERO, false);
    }

    /// `set_order` with the point the beams sweep on the target, in its frame, when `has_aim` (M10-T16: a subsystem).
    #[func]
    fn set_order_at(&mut self, body: i64, target: i64, aim: Vector3, has_aim: bool) {
        if let Some(o) = self.owners.iter_mut().find(|w| w.body == body) {
            o.order = target;
            o.order_aim = has_aim.then_some(aim);
        }
    }

    /// Ship `body`'s cooling emitters ready at once and looking for a target now (the console's test shot).
    #[func]
    fn ready_now(&mut self, body: i64) -> i64 {
        let mut n = 0;
        for b in self.beams.iter_mut().filter(|b| b.owner == body) {
            if b.phase == bk::COOLING {
                b.phase = bk::READY;
                b.timer = 0.0;
            }
            b.pick_wait = 0;
            n += 1;
        }
        n
    }

    #[func]
    fn count(&self) -> i64 {
        self.beams.len() as i64
    }

    /// Emitter `index`'s state: `[phase, seconds left in it, target body, aim (ship frame), works, rate]`; empty when none.
    #[func]
    fn state(&self, index: i64) -> VarArray {
        let mut out = VarArray::new();
        if let Some(b) = usize::try_from(index).ok().and_then(|i| self.beams.get(i)) {
            out.push(&i64::from(b.phase).to_variant());
            out.push(&b.timer.to_variant());
            out.push(&b.target.to_variant());
            out.push(&b.aim.to_variant());
            out.push(&b.works.to_variant());
            out.push(&b.rate.to_variant());
        }
        out
    }

    /// Wall-clock microseconds of the last step, and of its kernel alone (readouts, never gameplay).
    #[func]
    fn last_us(&self) -> f64 {
        self.last_us
    }

    #[func]
    fn kernel_us(&self) -> f64 {
        self.kernel_us
    }

    /// Wall-clock microseconds of the tick's landing so far (every `land` call since the step).
    #[func]
    fn land_us(&self) -> f64 {
        self.land_us
    }

    /// Keeps every landed hit from now on (true) or stops and forgets them (false): the tests' native hit log.
    #[func]
    fn set_hit_log(&mut self, on: bool) {
        self.log_on = on;
        self.hit_log.clear();
    }

    /// How many hits the log holds.
    #[func]
    fn hit_log_size(&self) -> i64 {
        self.hit_log.len() as i64
    }

    /// The hits landed since `set_hit_log(true)`: `[summary targets, bodies, shooters, damage, points removed, points]`.
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

    /// Lands the step's hits from `start` on the damage store in one batch (M10-T75), at sim time `now_s` with the friendly
    /// fire setting and god mode as they are: until the end, or a hit that raises an event GDScript must answer first.
    /// Returns `[next hit, coalesced writes (grouped by ledger), events (each six numbers: about, ledger, code, three values),
    /// summaries (one a damaged ship, as columns: `summary_columns`), the kill (a dictionary, empty for none), shooters
    /// revealed, the hit GDScript must land itself (-1 for none), hits landed, damage landed]`.
    #[func]
    fn land(&mut self, start: i64, now_s: f64, friendly_fire: bool, god_mode: bool) -> VarArray {
        let started = std::time::Instant::now();
        let mut out = VarArray::new();
        let (Some(core), Some(mut store)) = (self.core.clone(), self.store.clone()) else {
            return out;
        };
        let start = usize::try_from(start).unwrap_or(0).min(self.hits.len());
        self.gather(&core, &store, start);
        let next = {
            let mut guard = store.bind_mut();
            let s = &mut *guard;
            let ctx = Ctx {
                friendly_fire,
                god_mode,
                relation: &self.relation,
                factions: self.factions,
            };
            start + dl::land(&mut s.store, &s.targets, &self.land_hits, 0, &ctx, &mut self.land_out)
        };
        let o = &self.land_out;
        if !o.attackers.is_empty() {
            core.clone().bind_mut().note_attacker_pairs(&o.attackers, now_s);
        }
        if self.log_on {
            self.hit_log.extend_from_slice(&o.landed);
        }
        let summaries = Self::summary_columns(&o.summaries);
        let mut kill = VarDictionary::new();
        if let Some((k, applied, section)) = o.kill {
            let h = &self.land_hits[k];
            kill.set("beam", i64::from(self.hits[start + k].beam));
            kill.set("target", h.target);
            kill.set("body", h.body);
            kill.set("shooter", h.shooter);
            kill.set("damage", h.damage);
            kill.set("applied", applied);
            kill.set("point", h.point);
            kill.set("volume", i64::from(h.volume));
            kill.set("section", i64::from(section));
        }
        out.push(&(next as i64).to_variant());
        out.push(&PackedFloat64Array::from(o.sync.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(o.events.as_slice()).to_variant());
        out.push(&summaries.to_variant());
        out.push(&kill.to_variant());
        out.push(&PackedInt64Array::from(o.reveals.as_slice()).to_variant());
        out.push(&o.deferred.map_or(-1, |d| (start + d) as i64).to_variant());
        out.push(&i64::from(o.hits).to_variant());
        out.push(&o.damage.to_variant());
        self.land_us += started.elapsed().as_secs_f64() * 1e6;
        out
    }

    /// One tick of every emitter over the core's rows (after its sync). Returns `[hits' emitters, their hull ids (the
    /// Damageables), body ids, points, surface volumes (-1 for a sphere), damage, lines' emitters, their phases (charging,
    /// firing for a sustained beam, cooling for a pulse just fired), starts, ends, whether each ends on a hull]`.
    #[func]
    fn step(&mut self, delta: f64) -> VarArray {
        let started = std::time::Instant::now();
        self.hits.clear();
        self.draws.clear();
        let mut out = VarArray::new();
        let Some(core) = self.core.clone() else {
            return out;
        };
        let guard = core.bind();
        self.owner_rows.clear();
        self.owner_rows
            .extend(self.owners.iter().map(|o| guard.row_of_id(o.body) as i32));
        let world = BeamWorld {
            rows: &guard.rows,
            hull_rows: &guard.sweep_rows,
            owner_rows: &self.owner_rows,
            hostile: &self.hostile,
            factions: self.factions,
            row_of: |id: i64| usize::try_from(guard.row_of_id(id)).ok(),
        };
        let kernel_started = std::time::Instant::now();
        if delta.is_finite() && delta > 0.0 {
            bk::step(
                &mut self.beams,
                &self.owners,
                &self.owner_of,
                &world,
                delta,
                &mut self.hits,
                &mut self.draws,
            );
        }
        self.kernel_us = kernel_started.elapsed().as_secs_f64() * 1e6;
        let rows = &guard.rows;
        let n = self.hits.len();
        let mut emitters = Vec::with_capacity(n);
        let mut hulls = Vec::with_capacity(n);
        let mut bodies = Vec::with_capacity(n);
        let mut points = Vec::with_capacity(n);
        let mut volumes = Vec::with_capacity(n);
        let mut damage = Vec::with_capacity(n);
        self.hit_hulls.clear();
        self.hit_bodies.clear();
        self.land_us = 0.0;
        for h in &self.hits {
            let j = h.row as usize;
            emitters.push(h.beam as i32);
            hulls.push(rows.hull_ids[j]);
            bodies.push(rows.body_ids[j]);
            self.hit_hulls.push(rows.hull_ids[j]);
            self.hit_bodies.push(rows.body_ids[j]);
            points.push(h.point);
            volumes.push(h.volume);
            damage.push(h.damage);
        }
        let m = self.draws.len();
        let mut lines = Vec::with_capacity(m);
        let mut phases = Vec::with_capacity(m);
        let mut starts = Vec::with_capacity(m);
        let mut ends = Vec::with_capacity(m);
        let mut ended = Vec::with_capacity(m);
        for d in &self.draws {
            lines.push(d.beam as i32);
            phases.push(d.phase);
            starts.push(d.from);
            ends.push(d.to);
            ended.push(u8::from(d.hit));
        }
        out.push(&PackedInt32Array::from(emitters.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(hulls.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(bodies.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(points.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(volumes.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(damage.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(lines.as_slice()).to_variant());
        out.push(&PackedByteArray::from(phases.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(starts.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(ends.as_slice()).to_variant());
        out.push(&PackedByteArray::from(ended.as_slice()).to_variant());
        drop(guard);
        self.last_us = started.elapsed().as_secs_f64() * 1e6;
        out
    }
}

impl ScsBeamRows {
    // The summaries as columns, one row a damaged ship: `[Damageables, bodies hit last, last shooters, hits, damage, points
    // removed, last points, attacker offsets, attackers, their faction indices (the core's), section offsets, sections, zone
    // offsets, zones, zone amounts]`; a ship's ragged lists run from its offset to the next.
    fn summary_columns(list: &[dl::Summary]) -> VarArray {
        let mut att_at = vec![0i32];
        let mut sec_at = vec![0i32];
        let mut zone_at = vec![0i32];
        let (mut att, mut facs, mut secs, mut zones, mut amounts) = (vec![], vec![], vec![], vec![], vec![]);
        for sm in list {
            att.extend_from_slice(&sm.attackers);
            facs.extend(sm.attacker_factions.iter().map(|&f| f as i32));
            secs.extend_from_slice(&sm.sections);
            zones.extend(sm.zones.iter().map(|z| z.0));
            amounts.extend(sm.zones.iter().map(|z| z.1));
            att_at.push(att.len() as i32);
            sec_at.push(secs.len() as i32);
            zone_at.push(zones.len() as i32);
        }
        let col_i64 = |f: &dyn Fn(&dl::Summary) -> i64| PackedInt64Array::from(list.iter().map(f).collect::<Vec<_>>().as_slice()).to_variant();
        let col_f64 = |f: &dyn Fn(&dl::Summary) -> f64| PackedFloat64Array::from(list.iter().map(f).collect::<Vec<_>>().as_slice()).to_variant();
        let mut out = VarArray::new();
        out.push(&col_i64(&|s| s.target));
        out.push(&col_i64(&|s| s.body));
        out.push(&col_i64(&|s| s.last_shooter));
        out.push(&PackedInt32Array::from(list.iter().map(|s| s.hits as i32).collect::<Vec<_>>().as_slice()).to_variant());
        out.push(&col_f64(&|s| s.damage));
        out.push(&col_f64(&|s| s.applied));
        out.push(&PackedVector3Array::from(list.iter().map(|s| s.point).collect::<Vec<_>>().as_slice()).to_variant());
        out.push(&PackedInt32Array::from(att_at.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(att.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(facs.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(sec_at.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(secs.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(zone_at.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(zones.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(amounts.as_slice()).to_variant());
        out
    }

    // The hits from `start` as the batch takes them: each one's target, shooter and their factions, the shooter's disguise,
    // and the point in the hit body's frame (read from the engine once a body, on the main thread) when its target needs it.
    fn gather(&mut self, core: &Gd<ScsSimCore>, store: &Gd<ScsDamageStore>, start: usize) {
        self.land_hits.clear();
        let core = core.bind();
        let store = store.bind();
        let index_of: HashMap<&StringName, u32> = core.factions.iter().enumerate().map(|(i, f)| (f, i as u32)).collect();
        let mut frames: HashMap<i64, Option<(Basis, Vector3)>> = HashMap::new();
        for k in start..self.hits.len() {
            let h = self.hits[k];
            let o = self.owner_of[h.beam as usize] as usize;
            let shooter = self.owners[o].body;
            let target = self.hit_hulls[k];
            let body = self.hit_bodies[k];
            let needs_frame = store.targets.get(&target).is_some_and(|t| t.route != dl::ROUTE_PLAIN || t.layout != 0);
            let local = if needs_frame {
                let frame = *frames.entry(body).or_insert_with(|| {
                    let node = InstanceId::try_from_i64(body).and_then(|id| Gd::<Node3D>::try_from_instance_id(id).ok());
                    node.filter(|n| n.is_inside_tree()).map(|n| {
                        let x = n.get_global_transform();
                        (x.basis, x.origin)
                    })
                });
                frame.map(|(b, origin)| crate::v3::affine_inverse_xform(&b, origin, h.point))
            } else {
                None
            };
            self.land_hits.push(LandHit {
                target,
                body,
                shooter,
                shooter_faction: self.owner_factions.get(o).and_then(|f| index_of.get(f)).copied().unwrap_or(u32::MAX),
                target_faction: store.target_factions.get(&target).and_then(|f| index_of.get(f)).copied(),
                disguise: core.disguised.get(&shooter).copied(),
                damage: h.damage,
                point: h.point,
                volume: h.volume,
                local,
            });
        }
    }
}
