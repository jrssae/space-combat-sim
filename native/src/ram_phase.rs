// The ram resolver's broad phase on the core's rows (M4-T15, docs/architecture.md 17.13); `RamBroadPhase` (GDScript,
// M4-T03, in tests/fixtures/ since M4-T42) stays the reference. The pass itself is `kernels::ram`; this class only
// binds the core and hands the keys over.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::classes::PhysicsServer3D;
use godot::prelude::*;

use crate::kernels::ram;
use crate::sim_core::ScsSimCore;

/// Which pairs of the core's hull rows could come near each other in the coming tick: each hull's bounding sphere swept
/// along its path through the tick, boxed; the boxes sorted along x and swept once. Repeats `RamBroadPhase.pairs` step
/// for step (32-bit vectors, the same box, the same sort and the same keys), so both give the same pairs in the same
/// order. Reads the rows, never the engine.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsRamPhase {
    base: Base<RefCounted>,
    scratch: ram::Scratch,
}

#[godot_api]
impl ScsRamPhase {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// `RamBroadPhase.pairs` over the core's hull rows (in their order), `always` (the same form) added.
    #[func]
    fn pairs(
        &mut self,
        core: Gd<ScsSimCore>,
        delta: f64,
        always: PackedInt64Array,
    ) -> PackedInt64Array {
        let core = core.bind();
        let keys = ram::pairs(
            &mut self.scratch,
            &core.rows,
            &core.hull_rows,
            delta,
            always.as_slice(),
        );
        PackedInt64Array::from(keys)
    }

    /// The ram stage's contact read in one call (M4-T35): every rigid hull row's body id, velocity and acceleration (what
    /// the flight step wrote for it this tick; `known` 0 where it did not, so GDScript asks the ship), and for the hulls
    /// Jolt reports touching something, the contacts: `[rows, ids, velocities, accels, known, touched_rows, starts,
    /// other_ids, points, normals]`. `rows` are the hulls' indices in the core's hull order; `starts` holds each touched
    /// hull's first contact in the contact arrays and, last, their count. Points are shifted by `shift` (what the World
    /// was rebased by since Jolt's last step) and the normals point out of the hull, as `RamResolver` read them. A hull
    /// whose body left the physics space is left out.
    #[func]
    fn contacts(&mut self, core: Gd<ScsSimCore>, shift: Vector3) -> VarArray {
        let core = core.bind();
        let mut server = PhysicsServer3D::singleton();
        let mut rows: Vec<i32> = Vec::new();
        let mut ids: Vec<i64> = Vec::new();
        let mut velocities: Vec<Vector3> = Vec::new();
        let mut accels: Vec<Vector3> = Vec::new();
        let mut known: Vec<u8> = Vec::new();
        let mut touched: Vec<i32> = Vec::new();
        let mut starts: Vec<i32> = Vec::new();
        let mut others: Vec<i64> = Vec::new();
        let mut points: Vec<Vector3> = Vec::new();
        let mut normals: Vec<Vector3> = Vec::new();
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
            rows.push(k as i32);
            ids.push(body_id);
            velocities.push(core.rows.velocities[j]);
            match core.accels.get(&body_id) {
                Some(&a) => {
                    accels.push(a);
                    known.push(1);
                }
                None => {
                    accels.push(Vector3::ZERO);
                    known.push(0);
                }
            }
            let count = state.get_contact_count();
            if count <= 0 {
                continue;
            }
            touched.push(k as i32);
            starts.push(others.len() as i32);
            for c in 0..count {
                others.push(state.get_contact_collider_id(c) as i64);
                let p = state.get_contact_local_position(c);
                points.push(Vector3::new(p.x - shift.x, p.y - shift.y, p.z - shift.z));
                let n = state.get_contact_local_normal(c);
                normals.push(Vector3::new(-n.x, -n.y, -n.z));
            }
        }
        starts.push(others.len() as i32);
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(rows.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(velocities.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(accels.as_slice()).to_variant());
        out.push(&PackedByteArray::from(known.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(touched.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(starts.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(others.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(points.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(normals.as_slice()).to_variant());
        out
    }
}
