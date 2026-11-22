// The core's shell around the capital beams (M10-T12, D12.9): GDScript registers each capital's beam emitters once, tells
// the rows when a mount stops working or the rate of fire changes, and steps them once a tick on the main thread after the
// core's sync; it lands the hits through each target's `Damageable` and draws the lines in one batch per kind. The maths is
// `beam_kernels`, engine-free.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::beam_kernels::{self as bk, Beam, BeamDraw, BeamHit, BeamSpec, BeamWorld, Owner};
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
    factions: usize,
    // Per-step scratch, kept between ticks.
    owner_rows: Vec<i32>,
    hits: Vec<BeamHit>,
    draws: Vec<BeamDraw>,
    last_us: f64,
    kernel_us: f64,
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
        true
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
            None => self.owners.push(Owner {
                body,
                bodies: list,
                order: 0,
            }),
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
        if let Some(o) = self.owners.iter_mut().find(|w| w.body == body) {
            o.order = target;
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
        for h in &self.hits {
            let j = h.row as usize;
            emitters.push(h.beam as i32);
            hulls.push(rows.hull_ids[j]);
            bodies.push(rows.body_ids[j]);
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
