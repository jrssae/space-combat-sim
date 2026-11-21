// The core's shell around the blast model's reach (M10-T09, D12.6): GDScript asks once per explosion which hulls it touches,
// on the rows the main thread holds after the tick's sync (never the AI job's snapshot), and lands the damage and the push
// itself. The maths is `blast_kernels`, engine-free.
use godot::prelude::*;

use crate::blast_kernels as bk;
use crate::sim_core::ScsSimCore;

#[godot_api(secondary)]
impl ScsSimCore {
    /// The hulls a blast of `radius_m` at `centre` (World frame) reaches, near hulls then tier rows in the sweep's order:
    /// `[hull ids (the Damageables), body ids, distances to the nearest hit volume, those nearest points, the surface volume
    /// each lies on (-1 for a hull measured by its sphere), the bodies' places, their bases (three axes a hull)]`.
    #[func]
    fn blast_reach(&self, centre: Vector3, radius_m: f64) -> VarArray {
        let mut found = Vec::new();
        bk::reach(&self.rows, &self.sweep_rows, centre, radius_m, &mut found);
        let r = &self.rows;
        let mut hulls = Vec::with_capacity(found.len());
        let mut bodies = Vec::with_capacity(found.len());
        let mut distances = Vec::with_capacity(found.len());
        let mut points = Vec::with_capacity(found.len());
        let mut volumes = Vec::with_capacity(found.len());
        let mut places = Vec::with_capacity(found.len());
        let mut axes = Vec::with_capacity(found.len() * 3);
        for f in &found {
            let j = f.row as usize;
            hulls.push(r.hull_ids[j]);
            bodies.push(r.body_ids[j]);
            distances.push(f.distance);
            points.push(f.point);
            volumes.push(f.volume);
            places.push(r.positions[j]);
            let b = r.bases[j];
            axes.extend([b.col_a(), b.col_b(), b.col_c()]);
        }
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(hulls.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(bodies.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(distances.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(points.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(volumes.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(places.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(axes.as_slice()).to_variant());
        out
    }
}
