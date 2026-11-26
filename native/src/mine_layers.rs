// The hulls that lay mines in battle (M10-T15, Q20): a layer is a mount on a ship that drops or launches mines at what it
// perceives as an enemy. The G'Quan's energy-mine launchers send a mine at a hostile capital 4 to 12 km away, aimed at where it
// will be; the Vorchan's mounts drop guided mines astern while a hostile is on its tail. Engine-free (`test_sim_core` reads this
// file); the decision is a pure function of the rows and the layer's own state, so every thread count lays the same mines.
// Hostility here is what the ship PERCEIVES (a disguise fools it, Q55), unlike the mines' own triggers, which read true factions.
#![allow(clippy::too_many_arguments)]

use godot::builtin::Vector3;

use crate::capital_gun_kernels::is_capital;
use crate::mine_kernels::{self as mk, ENERGY, GUIDED, KINDS, Mines, Spec};
use crate::rows::{FLAG_DISABLED, FLAG_HULL_ACTIVE, FLAG_TIER, Rows};
use crate::surface::path_entry;
use crate::v3::{add, col_a, dist_sq, dot, normalized, scale, sub, xform};

/// A target is looked for this often at most, s: a mount with nothing to shoot at does not search every tick.
pub const SEARCH_EVERY_S: f64 = 0.5;
/// An energy mine stops this far off its target's surface, m (inside its trigger, outside its hull).
const STAND_OFF_M: f64 = 100.0;
/// Mines of one drop sit this far apart, m, and leave the ship this much slower each, m/s.
const DROP_SPACING_M: f32 = 25.0;
const DROP_STAGGER_MPS: f32 = 1.5;
/// Seconds past its flight an energy mine's path is followed for the hull it meets.
const FLIGHT_MARGIN_S: f64 = 2.0;

/// One mount that lays mines: where it sits on its ship, the way a mine leaves, and its numbers.
#[derive(Clone, Debug)]
pub struct Layer {
    pub owner: i64,
    pub local: Vector3,
    pub forward: Vector3,
    pub kind: u8,
    /// False once its section is lost or the ship is disabled by the caller.
    pub works: bool,
    pub range_min_m: f64,
    pub range_m: f64,
    pub cycle_s: f64,
    /// Mines a drop lays (an energy mount launches one).
    pub count: u32,
    /// Mines of this kind this ship may have in play at once.
    pub max_in_play: u32,
    /// The cone a target must lie in about `forward`, as the cosine of its half angle.
    pub cone_cos: f64,
    /// The speed a dropped mine leaves the ship at, along `forward`, m/s.
    pub drop_mps: f64,
    /// How far in front of the mount the mine appears, m (clear of its own hull).
    pub clearance_m: f64,
    pub next_at: f64,
    pub search_at: f64,
}

/// One mine a layer lays this tick, positions in the World frame and velocities against the anchor's rest.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Lay {
    pub layer: u32,
    pub kind: u8,
    pub owner: i64,
    pub faction_ix: u32,
    pub from: Vector3,
    pub vel: Vector3,
    /// An energy mine's lead point.
    pub dest: Vector3,
}

/// What the decision reads of the world.
pub struct View<'a> {
    pub rows: &'a Rows,
    pub hull_rows: &'a [u32],
    /// Each layer's owner's row (-1: gone from the rows).
    pub owner_rows: &'a [i32],
    pub hostile: &'a [bool],
    pub factions: usize,
    pub frame_velocity: Vector3,
    pub now_s: f64,
}

fn hostile(v: &View, a: u32, b: u32) -> bool {
    let (a, b) = (a as usize, b as usize);
    a < v.factions && b < v.factions && v.hostile[a * v.factions + b]
}

/// Whether row `j` is a ship that can lay: a hull in play, with its brain and power.
fn can_lay(rows: &Rows, j: usize) -> bool {
    let f = rows.flags[j];
    f & FLAG_HULL_ACTIVE != 0 && f & FLAG_TIER == 0 && f & FLAG_DISABLED == 0
}

/// The mines the layers lay this tick, appended to `out` in layer order. A layer that lays sets its next time; one that finds
/// nothing looks again after `SEARCH_EVERY_S`.
pub fn decide(layers: &mut [Layer], mines: &Mines, specs: &[Spec; KINDS], v: &View, out: &mut Vec<Lay>) {
    for (k, layer) in layers.iter_mut().enumerate() {
        let Some(row) = usize::try_from(v.owner_rows.get(k).copied().unwrap_or(-1)).ok() else {
            continue;
        };
        if !layer.works || !can_lay(v.rows, row) || v.now_s < layer.next_at || v.now_s < layer.search_at {
            continue;
        }
        let spec = &specs[layer.kind as usize];
        let basis = &v.rows.bases[row];
        let axis = normalized(xform(basis, layer.forward));
        let from = add(add(v.rows.positions[row], xform(basis, layer.local)), scale(axis, layer.clearance_m as f32));
        let observer = v.rows.faction_ix[row];
        let rest = add(v.rows.velocities[row], v.frame_velocity);
        let before = out.len();
        match layer.kind {
            ENERGY => out.extend(energy(layer, k as u32, spec, v, row, from, axis, observer)),
            GUIDED => guided(layer, k as u32, v, row, from, axis, observer, rest, mines, out),
            _ => {}
        }
        // A mount that laid waits out its cycle; one that found nothing looks again soon.
        if out.len() > before {
            layer.next_at = v.now_s + layer.cycle_s;
        } else {
            layer.search_at = v.now_s + SEARCH_EVERY_S;
        }
    }
}

// An energy mount's launch: the nearest hostile capital (as the ship perceives it) in range and in the cone, the mine aimed at
// where it will be when it gets there.
fn energy(layer: &Layer, k: u32, spec: &Spec, v: &View, row: usize, from: Vector3, axis: Vector3, observer: u32) -> Option<Lay> {
    if spec.speed_mps <= 0.0 {
        return None;
    }
    let mut best: Option<(f64, usize)> = None;
    for &r in v.hull_rows {
        let j = r as usize;
        if j == row || !mk::can_trigger(v.rows.flags[j]) || !is_capital(v.rows, j) || !hostile(v, observer, v.rows.seen_ix(j, observer)) {
            continue;
        }
        let d = f64::from(dist_sq(from, v.rows.positions[j])).sqrt();
        if d < layer.range_min_m || d > layer.range_m || !in_cone(layer, from, axis, v.rows.positions[j]) {
            continue;
        }
        if best.is_none_or(|(b, _)| d < b) {
            best = Some((d, j));
        }
    }
    let (_, j) = best?;
    // The meeting point, found by walking the target on at the mine's speed (three passes settle it for a slow target).
    let target_v = add(v.rows.velocities[j], v.frame_velocity);
    let mut dest = v.rows.positions[j];
    for _ in 0..3 {
        let t = f64::from(dist_sq(from, dest)).sqrt() / spec.speed_mps;
        dest = add(v.rows.positions[j], scale(target_v, t as f32));
    }
    let heading = normalized(sub(dest, from));
    let velocity = scale(heading, spec.speed_mps as f32);
    // It stops where its path first comes within `STAND_OFF_M` of the hull's surface (the hull's own motion taken out); a hull
    // with no surface of its own is stood off from by its sphere.
    let flight_s = f64::from(dist_sq(from, dest)).sqrt() / spec.speed_mps + FLIGHT_MARGIN_S;
    let arrive = match path_entry(v.rows, j, from, sub(velocity, target_v), flight_s, STAND_OFF_M) {
        Some((t, _)) => add(from, scale(velocity, t as f32)),
        None => sub(dest, scale(heading, (v.rows.radii[j] + STAND_OFF_M) as f32)),
    };
    Some(Lay {
        layer: k,
        kind: ENERGY,
        owner: layer.owner,
        faction_ix: v.rows.faction_ix[row],
        from,
        vel: velocity,
        dest: arrive,
    })
}

// A guided mount's drop: while a hostile hull (as perceived) is in range and in the cone astern, up to `count` mines leave in a
// row, never past the ship's `max_in_play`.
fn guided(
    layer: &Layer,
    k: u32,
    v: &View,
    row: usize,
    from: Vector3,
    axis: Vector3,
    observer: u32,
    rest: Vector3,
    mines: &Mines,
    out: &mut Vec<Lay>,
) {
    let in_play = (0..mines.len()).filter(|&i| mines.alive[i] && mines.kind[i] == GUIDED && mines.owner[i] == layer.owner).count() as u32;
    if in_play >= layer.max_in_play {
        return;
    }
    let seen = v.hull_rows.iter().any(|&r| {
        let j = r as usize;
        j != row
            && mk::can_trigger(v.rows.flags[j])
            && hostile(v, observer, v.rows.seen_ix(j, observer))
            && {
                let d = f64::from(dist_sq(from, v.rows.positions[j])).sqrt();
                d >= layer.range_min_m && d <= layer.range_m && in_cone(layer, from, axis, v.rows.positions[j])
            }
    });
    if !seen {
        return;
    }
    let basis = &v.rows.bases[row];
    let side = normalized(col_a(basis));
    let n = layer.count.min(layer.max_in_play - in_play);
    for m in 0..n {
        let offset = (m as f32 - 0.5 * (n as f32 - 1.0)) * DROP_SPACING_M;
        let slower = m as f32 * DROP_STAGGER_MPS;
        out.push(Lay {
            layer: k,
            kind: GUIDED,
            owner: layer.owner,
            faction_ix: v.rows.faction_ix[row],
            from: add(from, scale(side, offset)),
            vel: add(rest, scale(axis, layer.drop_mps as f32 + slower)),
            dest: from,
        });
    }
}

fn in_cone(layer: &Layer, from: Vector3, axis: Vector3, at: Vector3) -> bool {
    let to = normalized(sub(at, from));
    f64::from(dot(to, axis)) >= layer.cone_cos
}

#[cfg(test)]
mod tests;
