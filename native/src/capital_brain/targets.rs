// A capital's target (D12.10, Q17): the hostile warship in sensor range that best repays its heavy weapons, by threat
// times value over the time it takes to kill (getting there included), weighed by the faction's doctrine; the part of it
// to aim at is `aim`'s.
use godot::builtin::Vector3;

use crate::rows::{FLAG_DISABLED, FLAG_HULK, Rows};
use crate::v3::{length, sub};

use super::aim::aim;
use super::{CapitalJob, CapitalSpec, Memory, ignored, is_warship_row, range_sq};

// A hull the brain has no entry for (a station, a stand-in): its threat in dps, its worth and hull points per metre of
// radius.
const UNKNOWN_DPS: f64 = 50.0;
const UNKNOWN_VALUE_PER_M: f64 = 1.0 / 150.0;
const UNKNOWN_HP_PER_M: f64 = 100.0;
// A disabled or drifting hull is worth only this share of a live one (it fights no more).
const DISABLED_SHARE: f64 = 0.05;

/// The target a think picked: its body and row, how far it is, and the point to aim at in its frame (none: its centre).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pick {
    pub body: i64,
    pub row: usize,
    pub range_m: f64,
    pub aim: Option<Vector3>,
}

/// The best hostile warship for capital `spec` at row `r`, or none.
pub fn choose<F: Fn(i64) -> i64>(
    job: &CapitalJob,
    spec: &CapitalSpec,
    memory: &Memory,
    rows: &Rows,
    row_of: &F,
    r: usize,
    own_ix: u32,
) -> Option<Pick> {
    let t = &job.tuning;
    let sensor_sq = (t.sensor_m * t.sensor_m) as f32;
    let own_dps = spec.dps().max(1.0);
    let main_range = spec.main_range_m();
    let mut best: Option<(f64, Pick)> = None;
    for j in 0..rows.positions.len() {
        if j == r || ignored(rows, j) || rows.is_part_of(j, spec.body) || !is_warship_row(rows, j) {
            continue;
        }
        if !job.hostile(rows, own_ix, j) || range_sq(rows, r, j) > sensor_sq {
            continue;
        }
        // A rotor's row stands in for its hull's (both are rows); the hull's own row is the target.
        if row_of(rows.body_ids[j]) != j as i64 {
            continue;
        }
        let range_m = f64::from(length(sub(rows.positions[j], rows.positions[r])));
        let other = job.entry_of(rows.body_ids[j]);
        let (threat, value, hull_max) = match other {
            Some(o) => (o.spec.dps(), o.spec.value, o.spec.hull_max),
            None => (UNKNOWN_DPS, rows.radii[j] * UNKNOWN_VALUE_PER_M, rows.radii[j] * UNKNOWN_HP_PER_M),
        };
        let hp_left = rows.hull_fraction[j].max(0.0) * hull_max.max(1.0);
        let travel_s = (range_m - main_range).max(0.0) / t.approach_mps.max(1.0);
        let ttk = (hp_left / own_dps + travel_s).max(1.0);
        let mut score = (threat + 1.0).powf(spec.doctrine.threat_w) * value.max(0.01).powf(spec.doctrine.value_w) / ttk;
        if rows.flags[j] & (FLAG_DISABLED | FLAG_HULK) != 0 {
            score *= DISABLED_SHARE;
        }
        if rows.body_ids[j] == memory.target {
            score *= t.keep_bonus;
        }
        if best.is_none_or(|(b, _)| score > b) {
            best = Some((
                score,
                Pick {
                    body: rows.body_ids[j],
                    row: j,
                    range_m,
                    aim: None,
                },
            ));
        }
    }
    let (_, mut pick) = best?;
    if let Some(other) = job.entry_of(pick.body) {
        pick.aim = aim(spec, &other.spec, other.memory.state, rows, r, pick.row, t.outgunned_ratio);
    }
    Some(pick)
}
