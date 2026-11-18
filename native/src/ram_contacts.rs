// The ram tracker's shell (M5-T33, docs/architecture.md 18.23): reads Jolt's contacts and the core's rows on the main
// thread and hands the columns to the engine-free tracker (`ram_tracker.rs`), so a quiet tick costs GDScript one call.
// The near pairs come from `kernels::ram`, with the columns of just the hulls they name.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::classes::PhysicsServer3D;
use godot::obj::InstanceId;
use godot::prelude::*;

use crate::kernels::ram;
use crate::ram_tracker::{Feed, Ram, Tracker};
use crate::rows::Rows;
use crate::sim_core::ScsSimCore;
use crate::surface;
use crate::v3::{col_a, col_b, col_c, sub};

/// What `RamResolver` keeps between ticks: contacts, windows and one ram per pair per collision. A tick is `contacts`
/// (then `set_accels` and `land` when it asks for them), `swept_pairs` with `swept_meeting` or `keep_touching` per
/// pair, and `end_tick`. `feed` is `contacts` from columns, for a caller with no Jolt.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsRamTracker {
    base: Base<RefCounted>,
    tracker: Tracker,
    scratch: ram::Scratch,
    // This tick's read: the rigid hulls and, beside each, its `Damageable`'s id.
    ids: Vec<i64>,
    hull_nodes: Vec<i64>,
    velocities: Vec<Vector3>,
    accels: Vec<Vector3>,
    touched: Vec<u32>,
    touched_hulls: Vec<u32>,
    starts: Vec<u32>,
    others: Vec<i64>,
    points: Vec<Vector3>,
    normals: Vec<Vector3>,
    // Per contact: the other body is a moving surface (M7-T06, the turning drum) and its skin's velocity there.
    on_surface: Vec<bool>,
    surface_velocities: Vec<Vector3>,
    // The hulls whose acceleration the flight step did not write, as indices into `ids`.
    unknown: Vec<u32>,
    // The pairs of hulls Jolt holds in contact, in the broad phase's form.
    in_contact: Vec<i64>,
    // Each row's index among the hull rows (-1 for none), and each hull's slot among the named ones.
    hull_of_row: Vec<i32>,
    slot_of_hull: Vec<i32>,
    names: Option<Names>,
}

// The `Damageable` properties the pair reject reads.
#[derive(Clone)]
struct Names {
    bounding_radius: StringName,
    ram_bounds: StringName,
}

impl Names {
    fn new() -> Self {
        Self {
            bounding_radius: StringName::from("bounding_radius"),
            ram_bounds: StringName::from("ram_bounds"),
        }
    }
}

// Whether the first hull's bounding sphere cannot reach the second's box this tick (`ram::cannot_reach`), from the two
// `Damageable`s as they are now. False whenever either cannot be read: the resolver then decides.
fn out_of_reach(names: &Names, rows: &Rows, a: usize, b: usize, delta: f64) -> bool {
    let node = |row: usize| {
        InstanceId::try_from_i64(rows.hull_ids[row])
            .and_then(|id| Gd::<Object>::try_from_instance_id(id).ok())
    };
    let (Some(first), Some(second)) = (node(a), node(b)) else {
        return false;
    };
    let radius = first.get(&names.bounding_radius).try_to::<f64>();
    let bounds = second.get(&names.ram_bounds).try_to::<Aabb>();
    let (Ok(radius), Ok(bounds)) = (radius, bounds) else {
        return false;
    };
    let low = bounds.position;
    let high = bounds.position + bounds.size;
    ram::cannot_reach(
        rows,
        a,
        b,
        delta,
        radius,
        [f64::from(low.x), f64::from(low.y), f64::from(low.z)],
        [f64::from(high.x), f64::from(high.y), f64::from(high.z)],
    )
}

#[godot_api]
impl ScsRamTracker {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Phase 1 over the core's rows: every rigid hull's velocity and acceleration (what the flight step wrote for it
    /// this tick) and Jolt's contacts, fed to the tracker. Contact points are shifted by `shift` (what the World was
    /// rebased by since Jolt's last step) and the normals point out of the hull. A hull whose body left the physics
    /// space is left out. Returns `[hull_count, unknown_ids, asked]`: the core's hull count; the bodies whose
    /// acceleration the flight step did not write (answer with `set_accels`); and the `Damageable` ids of the hulls
    /// with a measured window (answer with `land`, their limits in this order).
    #[func]
    fn contacts(&mut self, core: Gd<ScsSimCore>, shift: Vector3, delta: f64) -> VarArray {
        let core = core.bind();
        let mut server = PhysicsServer3D::singleton();
        self.clear_read();
        for (k, &j) in core.hull_rows.iter().enumerate() {
            let j = j as usize;
            if !core.rows.rigid[j] {
                continue;
            }
            let rid = core.row_rids[j];
            let Some(state) = rid
                .is_valid()
                .then(|| server.body_get_direct_state(rid))
                .flatten()
            else {
                continue;
            };
            let body_id = core.rows.body_ids[j];
            let at = self.ids.len() as u32;
            self.ids.push(body_id);
            self.hull_nodes.push(core.rows.hull_ids[j]);
            self.velocities.push(core.rows.velocities[j]);
            match core.accels.get(&body_id) {
                Some(&a) => self.accels.push(a),
                None => {
                    self.accels.push(Vector3::ZERO);
                    self.unknown.push(at);
                }
            }
            let count = state.get_contact_count();
            if count <= 0 {
                continue;
            }
            self.touched.push(at);
            self.touched_hulls.push(k as u32);
            self.starts.push(self.others.len() as u32);
            for c in 0..count {
                let other = state.get_contact_collider_id(c) as i64;
                let point = sub(state.get_contact_local_position(c), shift);
                self.others.push(other);
                self.points.push(point);
                let n = state.get_contact_local_normal(c);
                self.normals.push(Vector3::new(-n.x, -n.y, -n.z));
                // The turning drum's skin (M7-T06): its row's pose, its spin, and the World's rest under it.
                let skin = Self::moving_surface(&core, other).map(|j| {
                    let r = &core.rows;
                    let spin = r.surface(j).map_or(0.0, |s| s.spin_rad_s);
                    let at = surface::surface_velocity(&r.bases[j], r.positions[j], spin, point);
                    crate::v3::add(at, core.frame_rest().velocity)
                });
                self.on_surface.push(skin.is_some());
                self.surface_velocities.push(skin.unwrap_or(Vector3::ZERO));
            }
        }
        self.starts.push(self.others.len() as u32);
        self.note_pairs_in_contact(&core);
        self.tracker.rest = core.frame_rest().velocity;
        let asked = self.feed_read(delta);
        let unknown: Vec<i64> = self.unknown.iter().map(|&k| self.ids[k as usize]).collect();
        let nodes: Vec<i64> = asked.iter().map(|&k| self.hull_nodes[k as usize]).collect();
        let mut out = VarArray::new();
        out.push(&(core.hull_rows.len() as i64).to_variant());
        out.push(&PackedInt64Array::from(unknown.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(nodes.as_slice()).to_variant());
        out
    }

    /// `contacts` from columns, with no core and no Jolt: `ids`, `velocities` and `accels` of every rigid body read this
    /// tick; body `ids[touched[t]]` touches `others[starts[t]..starts[t + 1]]` at the matching `points` and `normals`
    /// (`starts` ends with the contact count). Returns the body ids of the hulls with a measured window (answer with
    /// `land`, their limits in this order).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn feed(
        &mut self,
        ids: PackedInt64Array,
        velocities: PackedVector3Array,
        accels: PackedVector3Array,
        touched: PackedInt32Array,
        starts: PackedInt32Array,
        others: PackedInt64Array,
        points: PackedVector3Array,
        normals: PackedVector3Array,
        delta: f64,
    ) -> PackedInt64Array {
        self.clear_read();
        let n = ids.len();
        let contacts = others.len();
        let lined_up = velocities.len() == n
            && accels.len() == n
            && points.len() == contacts
            && normals.len() == contacts
            && starts.len() == touched.len() + 1
            && touched
                .as_slice()
                .iter()
                .all(|&t| (t as usize) < n && t >= 0)
            && starts
                .as_slice()
                .windows(2)
                .all(|w| w[0] >= 0 && w[0] <= w[1])
            && starts
                .as_slice()
                .last()
                .is_some_and(|&s| s as usize == contacts);
        if !lined_up {
            godot_error!("ScsRamTracker.feed: the columns do not line up; nothing fed");
            return PackedInt64Array::new();
        }
        self.ids.extend_from_slice(ids.as_slice());
        self.velocities.extend_from_slice(velocities.as_slice());
        self.accels.extend_from_slice(accels.as_slice());
        self.touched
            .extend(touched.as_slice().iter().map(|&t| t as u32));
        self.starts
            .extend(starts.as_slice().iter().map(|&s| s as u32));
        self.others.extend_from_slice(others.as_slice());
        self.points.extend_from_slice(points.as_slice());
        self.normals.extend_from_slice(normals.as_slice());
        let asked = self.feed_read(delta);
        let bodies: Vec<i64> = asked.iter().map(|&k| self.ids[k as usize]).collect();
        PackedInt64Array::from(bodies.as_slice())
    }

    /// The accelerations of the bodies `contacts` listed as unknown, in its order.
    #[func]
    fn set_accels(&mut self, accels: PackedVector3Array) {
        for (&at, &accel) in self.unknown.iter().zip(accels.as_slice()) {
            self.tracker.set_accel(at as usize, accel);
        }
    }

    /// The contact rams that land now, given `[safe_dv, lethal_dv]` for each hull `contacts` (or `feed`) asked for, in
    /// its order: `[hull_ids, other_ids, dvs, severities, points, normals, relative_speeds]`, a ram an entry.
    #[func]
    fn land(&mut self, limits: PackedFloat64Array) -> VarArray {
        let rams: Vec<Ram> = self.tracker.land(limits.as_slice());
        let column = |f: fn(&Ram) -> f64| -> Variant {
            let values: Vec<f64> = rams.iter().map(f).collect();
            PackedFloat64Array::from(values.as_slice()).to_variant()
        };
        let ids = |f: fn(&Ram) -> i64| -> Variant {
            let values: Vec<i64> = rams.iter().map(f).collect();
            PackedInt64Array::from(values.as_slice()).to_variant()
        };
        let vectors = |f: fn(&Ram) -> Vector3| -> Variant {
            let values: Vec<Vector3> = rams.iter().map(f).collect();
            PackedVector3Array::from(values.as_slice()).to_variant()
        };
        let mut out = VarArray::new();
        out.push(&ids(|r| r.hull_id));
        out.push(&ids(|r| r.other_id));
        out.push(&column(|r| r.dv));
        out.push(&column(|r| r.severity));
        out.push(&vectors(|r| r.point));
        out.push(&vectors(|r| r.normal));
        out.push(&column(|r| r.relative_speed));
        out
    }

    /// The pairs of the core's hulls that could meet in the coming tick (`kernels::ram`), and those Jolt holds in
    /// contact, in the order of a pass over every pair. Left out: two props (they never ram each other), and a pair
    /// Jolt does not hold whose bounding spheres stay clearly apart through the tick, or whose first hull's sphere
    /// cannot reach the second's box (the swept test's own first two rejects, with room: only its sure noes). With
    /// the columns of just the hulls the pairs name: `[firsts, seconds, body_ids, hull_ids, rigid, positions, velocities,
    /// bases]`, where pair `p` is hulls `firsts[p]` and `seconds[p]` of those columns and the bases are three columns
    /// (the x, y and z axes) a hull.
    #[func]
    fn swept_pairs(&mut self, core: Gd<ScsSimCore>, delta: f64) -> VarArray {
        let core = core.bind();
        let r = &core.rows;
        let count = core.hull_rows.len() as i64;
        let keys = ram::pairs(
            &mut self.scratch,
            r,
            &core.hull_rows,
            delta,
            &self.in_contact,
        );
        self.slot_of_hull.clear();
        self.slot_of_hull.resize(core.hull_rows.len(), -1);
        let names = self.names.get_or_insert_with(Names::new).clone();
        let mut firsts: Vec<i32> = Vec::with_capacity(keys.len());
        let mut seconds: Vec<i32> = Vec::with_capacity(keys.len());
        let mut named: Vec<usize> = Vec::new();
        for &key in keys {
            let i = (key / count) as usize;
            let j = (key - i as i64 * count) as usize;
            let (row_i, row_j) = (core.hull_rows[i] as usize, core.hull_rows[j] as usize);
            if !(r.rigid[row_i] || r.rigid[row_j]) {
                continue;
            }
            // A big hull (M7-T06, the station) is never a prop to the swept test: Jolt's contacts with its own bodies ram.
            if r.surface(row_i).is_some() || r.surface(row_j).is_some() {
                continue;
            }
            // Jolt's pairs are always looked at; any other pair must come near enough to matter.
            let held = self
                .tracker
                .in_contact(r.body_ids[row_i], r.body_ids[row_j]);
            if !held
                && (ram::clearly_apart(r, row_i, row_j, delta)
                    || out_of_reach(&names, r, row_i, row_j, delta))
            {
                continue;
            }
            for (hull, row, out) in [(i, row_i, &mut firsts), (j, row_j, &mut seconds)] {
                if self.slot_of_hull[hull] < 0 {
                    self.slot_of_hull[hull] = named.len() as i32;
                    named.push(row);
                }
                out.push(self.slot_of_hull[hull]);
            }
        }
        let body_ids: Vec<i64> = named.iter().map(|&j| r.body_ids[j]).collect();
        let hull_ids: Vec<i64> = named.iter().map(|&j| r.hull_ids[j]).collect();
        let rigid: Vec<u8> = named.iter().map(|&j| u8::from(r.rigid[j])).collect();
        let positions: Vec<Vector3> = named.iter().map(|&j| r.positions[j]).collect();
        let velocities: Vec<Vector3> = named.iter().map(|&j| r.velocities[j]).collect();
        let mut bases: Vec<Vector3> = Vec::with_capacity(named.len() * 3);
        for &j in &named {
            let b = &r.bases[j];
            bases.extend([col_a(b), col_b(b), col_c(b)]);
        }
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(firsts.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(seconds.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(body_ids.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(hull_ids.as_slice()).to_variant());
        out.push(&PackedByteArray::from(rigid.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(positions.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(velocities.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(bases.as_slice()).to_variant());
        out
    }

    /// True when Jolt reported `a` and `b` touching this tick (valid after `contacts`).
    #[func]
    fn in_contact(&self, a: i64, b: i64) -> bool {
        self.tracker.in_contact(a, b)
    }

    /// How many contact windows are open.
    #[func]
    fn open_windows(&self) -> i64 {
        self.tracker.open_windows() as i64
    }

    /// Phase 2: the sweep found the volumes of `a` and `b` meeting this tick. True when that is a new ram.
    #[func]
    fn swept_meeting(&mut self, a: i64, b: i64) -> bool {
        self.tracker.swept_meeting(a, b)
    }

    /// Phase 2, for a rigid pair the resolver does not sweep this tick: a pair that met stays met while Jolt holds it.
    #[func]
    fn keep_touching(&mut self, a: i64, b: i64) {
        self.tracker.keep_touching(a, b);
    }

    /// Phase 3: the tick is over.
    #[func]
    fn end_tick(&mut self) {
        self.tracker.end_tick();
    }

    /// The World was rebased by `offset`: the open windows' points move with the hulls.
    #[func]
    fn shift(&mut self, offset: Vector3) {
        self.tracker.shift(offset);
    }

    /// A velocity rebase took `dv` off every velocity: the remembered ones follow.
    #[func]
    fn boost(&mut self, dv: Vector3) {
        self.tracker.boost(dv);
    }

    /// Forgets everything (ram damage switched off).
    #[func]
    fn reset(&mut self) {
        self.tracker.reset();
        self.clear_read();
    }
}

impl ScsRamTracker {
    fn clear_read(&mut self) {
        self.ids.clear();
        self.hull_nodes.clear();
        self.velocities.clear();
        self.accels.clear();
        self.touched.clear();
        self.touched_hulls.clear();
        self.starts.clear();
        self.others.clear();
        self.points.clear();
        self.normals.clear();
        self.on_surface.clear();
        self.surface_velocities.clear();
        self.unknown.clear();
        self.in_contact.clear();
    }

    fn feed_read(&mut self, delta: f64) -> Vec<u32> {
        self.tracker.feed(
            &Feed {
                ids: &self.ids,
                velocities: &self.velocities,
                accels: &self.accels,
                touched: &self.touched,
                starts: &self.starts,
                others: &self.others,
                points: &self.points,
                normals: &self.normals,
                on_surface: &self.on_surface,
                surface_velocities: &self.surface_velocities,
            },
            delta,
        )
    }

    // The row of body `other` when it is a big hull that turns (M7-T06), else none.
    fn moving_surface(core: &ScsSimCore, other: i64) -> Option<usize> {
        let row = usize::try_from(core.row_of_id(other)).ok()?;
        let spin = core.rows.surface(row)?.spin_rad_s;
        (spin != 0.0).then_some(row)
    }

    // Fills `in_contact`: each touched hull with each hull it touches (once a hull, in report order), as
    // `low * count + high` over the core's hull order. The broad phase always hands these pairs on.
    fn note_pairs_in_contact(&mut self, core: &ScsSimCore) {
        if self.touched.is_empty() {
            return;
        }
        self.hull_of_row.clear();
        self.hull_of_row.resize(core.rows.body_ids.len(), -1);
        for (k, &j) in core.hull_rows.iter().enumerate() {
            self.hull_of_row[j as usize] = k as i32;
        }
        let count = core.hull_rows.len() as i64;
        for (t, &hull) in self.touched_hulls.iter().enumerate() {
            let held = &self.others[self.starts[t] as usize..self.starts[t + 1] as usize];
            for (c, &other) in held.iter().enumerate() {
                if held[..c].contains(&other) {
                    continue;
                }
                let row = core.row_of_id(other);
                let k = if row >= 0 {
                    i64::from(self.hull_of_row[row as usize])
                } else {
                    -1
                };
                if k >= 0 {
                    let i = i64::from(hull);
                    self.in_contact.push(i.min(k) * count + i.max(k));
                }
            }
        }
    }
}
