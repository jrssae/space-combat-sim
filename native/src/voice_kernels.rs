// Which ships the engine voices may be granted to (M5-T28, D60): the ships near the listener, nearest first, from the rows
// the main thread holds. Engine-free (test_sim_core reads this file): rows in, plain numbers out, no statics. The shell
// (`voice_rows.rs`) hands the result to GDScript, which owns the voices.
use godot::builtin::Vector3;

use crate::rows::{FLAG_RIGID, FLAG_TIER, Rows};
use crate::v3::dist_sq;

// `BodyKind.SHIP`: the only kind with thrusters to hear.
pub const KIND_SHIP: u8 = 0;

/// The rows of ships with a node, rigid and not in the low-attention tier, within `radius_m` of `centre`, as (squared
/// distance, row), nearest first (ties in row order). A tier row has no node to put a voice on, and the statics, bolts and
/// capital stand-ins have no engines, so none of them is ever listed. `out` is cleared first.
pub fn ships_near(rows: &Rows, centre: Vector3, radius_m: f64, out: &mut Vec<(f32, u32)>) {
    out.clear();
    let range_sq = radius_m * radius_m;
    for r in 0..rows.node_count.min(rows.positions.len()) {
        if rows.flags[r] & FLAG_TIER != 0
            || rows.flags[r] & FLAG_RIGID == 0
            || rows.is_static[r]
            || rows.kinds[r] != KIND_SHIP
        {
            continue;
        }
        let d_sq = dist_sq(rows.positions[r], centre);
        if f64::from(d_sq) <= range_sq {
            out.push((d_sq, r as u32));
        }
    }
    out.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
}

#[cfg(test)]
mod tests;
