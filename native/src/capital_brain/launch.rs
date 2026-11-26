// A carrier's Launch (M10-T17, D12.10, Q73): what its hangar needs from the brain. The brain counts the hostiles within
// `launch_m` (fighters and warships apart) so GDScript can launch its wings on a threat, a second wing as the threat grows,
// and call them home once it is over; while the hangar is launching, the carrier holds its course so its craft leave the
// bays on a straight line.
use crate::rows::Rows;

use super::{CapitalJob, CapitalSpec, ignored, is_warship_row, range_sq};

// `BodyKind.SHIP`: a fighter or other small craft.
const KIND_SHIP: u8 = 0;

/// The hostile fighters and warships within the launch reach of carrier row `r`; none for a hull with no bays.
pub fn threats<F: Fn(i64) -> i64>(job: &CapitalJob, spec: &CapitalSpec, rows: &Rows, row_of: &F, r: usize, own_ix: u32) -> (u32, u32) {
    if !spec.carrier {
        return (0, 0);
    }
    let reach_sq = (job.tuning.launch_m * job.tuning.launch_m) as f32;
    let (mut fighters, mut warships) = (0u32, 0u32);
    for j in 0..rows.positions.len() {
        if j == r || ignored(rows, j) || rows.is_part_of(j, spec.body) || rows.is_civilian(j) {
            continue;
        }
        if !job.hostile(rows, own_ix, j) || range_sq(rows, r, j) > reach_sq {
            continue;
        }
        if is_warship_row(rows, j) {
            // A rotor's row stands in for its hull's: the hull is counted once.
            if row_of(rows.body_ids[j]) == j as i64 {
                warships += 1;
            }
        } else if rows.kinds.get(j).copied() == Some(KIND_SHIP) {
            fighters += 1; // turrets, missiles and mines are no reason to launch
        }
    }
    (fighters, warships)
}
