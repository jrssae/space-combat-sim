// The core's shell around the engine voices' ship query (M5-T28, D60): reads the rows the main thread holds after the
// tick's sync, never the AI job's snapshot (M4-T24), and hands GDScript the ships to rank. The maths is `voice_kernels`.
use godot::prelude::*;

use crate::sim_core::ScsSimCore;
use crate::voice_kernels as vk;

#[godot_api(secondary)]
impl ScsSimCore {
    /// The ships with a node within `radius_m` of `centre` (the listener, in the World's frame), nearest first, as
    /// `[body_ids, squared_distances]`. Tier rows, rocks and mines are never listed. Reads the rows as of the tick's last
    /// sync, so a ship that left play since may still be there (the caller checks the nodes it grants).
    #[func]
    fn ships_near(&self, centre: Vector3, radius_m: f64) -> VarArray {
        let mut found = Vec::new();
        vk::ships_near(&self.rows, centre, radius_m, &mut found);
        let ids: Vec<i64> = found
            .iter()
            .map(|&(_, row)| self.rows.body_ids[row as usize])
            .collect();
        let distances: Vec<f64> = found.iter().map(|&(d_sq, _)| f64::from(d_sq)).collect();
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(distances.as_slice()).to_variant());
        out
    }
}
