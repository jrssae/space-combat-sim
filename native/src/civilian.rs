//! Civilian flight (M5-T16, Q24, Q25, docs/architecture.md 18.11): where a civilian under threat runs, how a fleeing group
//! closes up and how far panic reaches, as pure functions of the frozen rows and one ship's contact list. The brains' retreat
//! asks these for a ship with the civilian role; every answer costs work linear in that ship's contacts, never a walk of
//! every row. Engine-free (the guard in test_sim_core reads this file): plain rows and numbers in, plain numbers out.
use godot::builtin::Vector3;

use crate::rows::Rows;
use crate::v3::{add, dist_sq, dot, length, maxf, minf, normalized, scale, sub};

/// How far a fleeing civilian's alarm carries to its people's other civilians (Q25): about a radar range, the AI's sensors.
pub const PANIC_RANGE_M: f64 = 5000.0;
/// How long a civilian keeps running after it last heard an alarm.
pub const PANIC_HOLD_S: f64 = 20.0;
/// The shelter's standoff behind a warship (Q25): a few hull lengths of the larger of the two, at least `STANDOFF_MIN_M`.
pub const STANDOFF_RADII: f64 = 3.0;
pub const STANDOFF_MIN_M: f64 = 150.0;
/// The gap a fleeing group keeps between hulls, beyond their radii.
pub const GROUP_GAP_M: f64 = 150.0;
/// The time over which a civilian closes a gap: it slows into the shelter or the group rather than overshooting.
pub const ARRIVE_S: f64 = 10.0;
/// The share of the run's speed a civilian spends closing up with its group.
pub const COHESION_SHARE: f64 = 0.5;

/// Where a civilian runs this think: the velocity it seeks, the row it runs to (-1: none, straight away from the threat)
/// and whether that row is a warship it shelters behind.
#[derive(Clone, Copy, Debug)]
pub struct Flight {
    pub velocity: Vector3,
    pub goal: i32,
    pub shelter: bool,
}

/// One civilian's view this think: its row, its size, its contacts, the run's speed and which rows are fleeing.
pub struct View<'a> {
    pub rows: &'a Rows,
    pub contacts: &'a [i32],
    pub own_row: usize,
    pub radius: f64,
    pub speed_mps: f64,
    /// Fleeing civilians by row (running from a threat or from an alarm), as the job marked them from the last thinks.
    pub fleeing: &'a [bool],
    /// A row never run to though it is of the own people (M7-T29: the friend whose fire it flees); -1 for none.
    pub shun: i32,
}

impl View<'_> {
    fn flag(list: &[bool], r: usize) -> bool {
        list.get(r).copied().unwrap_or(false)
    }

    // Row `j` is a ship of this civilian's own people, not the civilian itself.
    fn kin(&self, j: usize) -> bool {
        let rows = self.rows;
        j != self.own_row
            && j as i32 != self.shun
            && rows.rigid[j]
            && !rows.is_static[j]
            && rows.body_ids[j] != rows.body_ids[self.own_row]
            && rows.faction_ix[j] == rows.faction_ix[self.own_row]
    }

    // The contacts as rows.
    fn rows_listed(&self) -> impl Iterator<Item = usize> + '_ {
        self.contacts
            .iter()
            .filter_map(|&r| usize::try_from(r).ok())
            .filter(|&j| j < self.rows.ids.len())
    }
}

/// The nearest ship of the civilian's own people among its contacts, of any kind (Q24); -1 for none.
pub fn nearest_kin(v: &View) -> i32 {
    let at = v.rows.positions[v.own_row];
    let mut best = -1;
    let mut best_sq = f32::INFINITY;
    for j in v.rows_listed() {
        if !v.kin(j) {
            continue;
        }
        let d_sq = dist_sq(v.rows.positions[j], at);
        if d_sq < best_sq {
            best_sq = d_sq;
            best = j as i32;
        }
    }
    best
}

/// The nearest civilian of the same people within `PANIC_RANGE_M` that is fleeing a threat it sees (an alarm, Q25); -1 none.
pub fn nearest_alarm(v: &View, alarmed: &[bool]) -> i32 {
    let at = v.rows.positions[v.own_row];
    let range_sq = (PANIC_RANGE_M * PANIC_RANGE_M) as f32;
    let mut best = -1;
    let mut best_sq = f32::INFINITY;
    for j in v.rows_listed() {
        if !v.kin(j) || !v.rows.is_civilian(j) || !View::flag(alarmed, j) {
            continue;
        }
        let d_sq = dist_sq(v.rows.positions[j], at);
        if d_sq <= range_sq && d_sq < best_sq {
            best_sq = d_sq;
            best = j as i32;
        }
    }
    best
}

/// The point beyond a warship on the line from the threat (Q25): the warship between the civilian and the attacker, a
/// standoff of a few hull lengths behind it.
pub fn shelter_point(warship_at: Vector3, threat_at: Vector3, standoff_m: f64) -> Vector3 {
    let from_threat = sub(warship_at, threat_at);
    let dir = if f64::from(length(from_threat)) > 1e-3 {
        normalized(from_threat)
    } else {
        Vector3::new(0.0, 0.0, 1.0)
    };
    add(warship_at, scale(dir, standoff_m as f32))
}

/// The standoff behind a warship for this pair of hulls.
pub fn standoff_m(own_radius: f64, warship_radius: f64) -> f64 {
    maxf(STANDOFF_RADII * maxf(own_radius, warship_radius), STANDOFF_MIN_M)
}

/// The centre and mean velocity of the same people's other fleeing civilians among the contacts, and how many there are.
pub fn fleeing_group(v: &View) -> (Vector3, Vector3, usize) {
    let mut centre = Vector3::ZERO;
    let mut velocity = Vector3::ZERO;
    let mut n = 0usize;
    for j in v.rows_listed() {
        if v.kin(j) && v.rows.is_civilian(j) && View::flag(v.fleeing, j) {
            centre = add(centre, v.rows.positions[j]);
            velocity = add(velocity, v.rows.velocities[j]);
            n += 1;
        }
    }
    if n > 0 {
        centre = scale(centre, 1.0 / n as f32);
        velocity = scale(velocity, 1.0 / n as f32);
    }
    (centre, velocity, n)
}

// A heading toward `to` at up to `speed`, slowing over `ARRIVE_S` as the gap past `stop_m` closes.
fn arrive(to: Vector3, stop_m: f64, speed: f64) -> Vector3 {
    let d = f64::from(length(to));
    if d < 1e-3 {
        return Vector3::ZERO;
    }
    let pace = clamp0(minf(speed, (d - stop_m) / ARRIVE_S));
    scale(normalized(to), pace as f32)
}

fn clamp0(v: f64) -> f64 {
    if v > 0.0 { v } else { 0.0 }
}

/// Where a civilian runs from a threat at `threat_at`, given `away` (unit, from the threats): to the far side of the
/// nearest warship of its people, to the nearest civilian of its people, or with none in its contacts straight away (`goal`
/// -1, the velocity `away` at the run's speed, as every ship retreats). Then it closes up with its people's other fleeing
/// civilians, so their turrets cover each other (Q24). None when the plain retreat stands (no kin, no group).
pub fn flee_from(v: &View, away: Vector3, threat_at: Vector3) -> Option<Flight> {
    let rows = v.rows;
    let at = rows.positions[v.own_row];
    let speed = v.speed_mps;
    let goal = nearest_kin(v);
    let mut shelter = false;
    let mut velocity = scale(away, speed as f32);
    if goal >= 0 {
        let g = goal as usize;
        if rows.is_civilian(g) {
            // Run to it, swinging away from the threat when it lies on the threat's side; together, run on away.
            let to = sub(rows.positions[g], at);
            let gap = v.radius + rows.radii[g] + GROUP_GAP_M;
            if f64::from(length(to)) > gap {
                let mut dir = normalized(to);
                if dot(dir, away) < 0.0 {
                    dir = normalized(add(dir, away));
                }
                velocity = scale(dir, speed as f32);
            }
        } else {
            shelter = true;
            let point = shelter_point(rows.positions[g], threat_at, standoff_m(v.radius, rows.radii[g]));
            velocity = add(rows.velocities[g], arrive(sub(point, at), 0.0, speed));
        }
    }
    let (velocity, grouped) = close_up(v, velocity);
    if goal < 0 && !grouped {
        return None;
    }
    Some(Flight {
        velocity,
        goal,
        shelter,
    })
}

/// Where a civilian runs on an alarm with no threat of its own in sight (Q25): with the alarmed ship (along its velocity, or
/// to it when it is still), closing up with the fleeing group.
pub fn flee_alarm(v: &View, alarm_row: i32) -> Flight {
    let rows = v.rows;
    let at = rows.positions[v.own_row];
    let speed = v.speed_mps;
    let mut velocity = Vector3::ZERO;
    if let Ok(a) = usize::try_from(alarm_row) {
        let along = rows.velocities[a];
        let dir = if f64::from(length(along)) > 1.0 {
            normalized(along)
        } else {
            normalized(sub(rows.positions[a], at))
        };
        velocity = scale(dir, speed as f32);
    } else if f64::from(length(rows.velocities[v.own_row])) > 1.0 {
        velocity = scale(normalized(rows.velocities[v.own_row]), speed as f32);
    }
    let (velocity, _) = close_up(v, velocity);
    Flight {
        velocity,
        goal: alarm_row,
        shelter: false,
    }
}

// Adds the pull toward the people's other fleeing civilians when the civilian is farther from their centre than a group's
// gap; true when there is a group.
fn close_up(v: &View, velocity: Vector3) -> (Vector3, bool) {
    let (centre, _, n) = fleeing_group(v);
    if n == 0 {
        return (velocity, false);
    }
    let at = v.rows.positions[v.own_row];
    let gap = 2.0 * v.radius + GROUP_GAP_M;
    let pull = arrive(sub(centre, at), gap, v.speed_mps * COHESION_SHARE);
    (add(velocity, pull), true)
}

#[cfg(test)]
mod tests;
