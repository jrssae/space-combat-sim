//! Civilian flight (M5-T16, Q24, Q25, docs/architecture.md 18.11): where a civilian under threat runs, how a fleeing group
//! closes up and how far panic reaches, as pure functions of the frozen rows and one ship's contact list. The brains' retreat
//! asks these for a ship with the civilian role; every answer costs work linear in that ship's contacts and the few big
//! hulls (a station of its people shelters it, M7-T55), never a walk of every row. Engine-free (the guard in test_sim_core
//! reads this file): plain rows and numbers in, plain numbers out.
use godot::builtin::Vector3;

use crate::rows::Rows;
use crate::surface;
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
/// How far from its skin a station of its own people draws a fleeing civilian (M7-T55): the station's traffic control.
pub const STATION_SIGHT_M: f64 = 20000.0;
/// Within this of a station of its own people a civilian is under its guns and keeps its course (a docking lane) (M7-T55).
pub const STATION_COVER_M: f64 = 1000.0;
/// How far off a station's skin a fleeing civilian waits, beyond the cover so it never flickers in and out of it.
pub const STATION_STANDOFF_M: f64 = 1500.0;
/// A shelter or kin whose straight way passes nearer the threat than this is not run to (M7-T55): about a raider's gun range.
pub const PASS_CLEAR_M: f64 = 800.0;
/// The share of the threat's range the way must come within to count as closing on it.
pub const PASS_CLOSING: f64 = 0.8;

/// Where a civilian runs this think: the velocity it seeks, the row it runs to (-1: none, straight away from the threat),
/// whether that row is a warship or a station it shelters behind, and the point it makes for there.
#[derive(Clone, Copy, Debug)]
pub struct Flight {
    pub velocity: Vector3,
    pub goal: i32,
    pub shelter: bool,
    pub point: Vector3,
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
    /// The big hulls' rows (the station's frame and drum), wherever they are: a station of its people shelters it (M7-T55).
    pub hulls: &'a [u32],
    /// How hard the ship can brake without turning (its retro), so it slows into a shelter in time; 0 for no limit.
    pub brake_mps2: f64,
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

/// The nearest ship of the civilian's own people among its contacts, of any kind (Q24), or a station of its people within
/// `STATION_SIGHT_M` of its skin (M7-T55: Babylon 5 for an Earth Alliance freighter); -1 for none. The station is a shelter
/// before any fellow civilian; against a warship the nearer wins, the station by its skin, a ship by its centre.
pub fn nearest_kin(v: &View) -> i32 {
    nearest_kin_from(v, None)
}

/// `nearest_kin`, leaving out any that lies beyond the threat at `threat_at` (M7-T55): the way there passes the attacker.
pub fn nearest_kin_from(v: &View, threat_at: Option<Vector3>) -> i32 {
    let at = v.rows.positions[v.own_row];
    let mut best = -1;
    let mut best_sq = f32::INFINITY;
    for j in v.rows_listed() {
        if !v.kin(j) || threat_at.is_some_and(|t| beyond(at, v.rows.positions[j], t)) {
            continue;
        }
        let d_sq = dist_sq(v.rows.positions[j], at);
        if d_sq < best_sq {
            best_sq = d_sq;
            best = j as i32;
        }
    }
    if let Some((j, d)) = nearest_station(v, STATION_SIGHT_M)
        && (best < 0 || v.rows.is_civilian(best as usize) || d * d < f64::from(best_sq))
        && !threat_at.is_some_and(|t| beyond(at, v.rows.positions[j], t))
    {
        best = j as i32;
    }
    best
}

// Whether `goal` lies beyond the threat as seen from `at`: farther off than the threat, on its side, the straight way there
// passing within `PASS_CLEAR_M` of it and closing on it on the way (a way that only leaves a threat already near is fine).
fn beyond(at: Vector3, goal: Vector3, threat: Vector3) -> bool {
    let to_goal = sub(goal, at);
    let to_threat = sub(threat, at);
    let g_sq = f64::from(dot(to_goal, to_goal));
    let toward = f64::from(dot(to_threat, to_goal));
    if g_sq <= f64::from(dot(to_threat, to_threat)) || toward <= 0.0 {
        return false;
    }
    let along = (toward / g_sq).min(1.0);
    let nearest = scale(to_goal, along as f32);
    let pass = f64::from(length(sub(to_threat, nearest)));
    pass < PASS_CLEAR_M && pass < PASS_CLOSING * f64::from(length(to_threat))
}

/// The station of the civilian's own people nearest its skin within `within` m, and how far that skin is.
pub fn nearest_station(v: &View, within: f64) -> Option<(usize, f64)> {
    let rows = v.rows;
    let at = rows.positions[v.own_row];
    let own = rows.faction_ix[v.own_row];
    let mut best: Option<(usize, f64)> = None;
    for &r in v.hulls {
        let j = r as usize;
        if j >= rows.ids.len() || j == v.own_row || rows.faction_ix[j] != own {
            continue;
        }
        // A bound first: the skin is never nearer than the centre less the hull's radius.
        if f64::from(length(sub(rows.positions[j], at))) - rows.radii[j] > within {
            continue;
        }
        if let Some((_, d)) = surface::nearest_of_row(rows, j, at)
            && d <= within
            && best.is_none_or(|(_, b)| d < b)
        {
            best = Some((j, d));
        }
    }
    best
}

/// Whether the civilian is under the guns of a station of its people (M7-T55): it keeps its course there rather than
/// turning in a docking lane.
pub fn under_cover(v: &View) -> bool {
    nearest_station(v, STATION_COVER_M).is_some()
}

/// The point off a station's skin on its far side from the threat (M7-T55), where a fleeing civilian waits.
pub fn station_point(v: &View, j: usize, threat_at: Vector3) -> Vector3 {
    let rows = v.rows;
    let centre = rows.positions[j];
    let from_threat = sub(centre, threat_at);
    let dir = if f64::from(length(from_threat)) > 1e-3 {
        normalized(from_threat)
    } else {
        normalized(sub(rows.positions[v.own_row], centre))
    };
    let far = add(centre, scale(dir, rows.radii[j] as f32));
    let Some((skin, _)) = surface::nearest_of_row(rows, j, far) else {
        return far;
    };
    let out = sub(far, skin);
    let out = if f64::from(length(out)) > 1e-3 { normalized(out) } else { dir };
    add(skin, scale(out, (STATION_STANDOFF_M + v.radius) as f32))
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

// A heading toward `to` at up to `speed`, slowing over `ARRIVE_S` as the gap past `stop_m` closes, and no faster than
// `brake_mps2` can stop it in that gap (a freighter brakes slowly).
fn arrive(to: Vector3, stop_m: f64, speed: f64, brake_mps2: f64) -> Vector3 {
    let d = f64::from(length(to));
    if d < 1e-3 {
        return Vector3::ZERO;
    }
    let mut pace = clamp0(minf(speed, (d - stop_m) / ARRIVE_S));
    if brake_mps2 > 0.0 {
        pace = minf(pace, (2.0 * brake_mps2 * clamp0(d - stop_m)).sqrt());
    }
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
    let goal = nearest_kin_from(v, Some(threat_at));
    let mut shelter = false;
    let mut velocity = scale(away, speed as f32);
    let mut point = add(at, scale(away, speed as f32));
    if goal >= 0 {
        let g = goal as usize;
        point = rows.positions[g];
        if rows.surface(g).is_some() {
            // A station of its people: round to its far side from the threat, under its guns (M7-T55).
            shelter = true;
            point = station_point(v, g, threat_at);
            velocity = add(rows.velocities[g], arrive(sub(point, at), 0.0, speed, v.brake_mps2));
        } else if rows.is_civilian(g) {
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
            point = shelter_point(rows.positions[g], threat_at, standoff_m(v.radius, rows.radii[g]));
            velocity = add(rows.velocities[g], arrive(sub(point, at), 0.0, speed, v.brake_mps2));
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
        point,
    })
}

/// Where a civilian runs on an alarm with no threat of its own in sight (Q25): to a station of its people when one is in
/// sight, round to its far side from the alarmed ship (M7-T55), else with the alarmed ship (along its velocity, or to it
/// when it is still); closing up with the fleeing group either way.
pub fn flee_alarm(v: &View, alarm_row: i32) -> Flight {
    let rows = v.rows;
    let at = rows.positions[v.own_row];
    let speed = v.speed_mps;
    let mut velocity = Vector3::ZERO;
    if let Ok(a) = usize::try_from(alarm_row)
        && let Some((j, _)) = nearest_station(v, STATION_SIGHT_M)
    {
        let point = station_point(v, j, rows.positions[a]);
        let velocity = add(rows.velocities[j], arrive(sub(point, at), 0.0, speed, v.brake_mps2));
        let (velocity, _) = close_up(v, velocity);
        return Flight {
            velocity,
            goal: j as i32,
            shelter: true,
            point,
        };
    }
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
        point: add(at, velocity),
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
    let pull = arrive(sub(centre, at), gap, v.speed_mps * COHESION_SHARE, v.brake_mps2);
    (add(velocity, pull), true)
}

#[cfg(test)]
mod tests;
