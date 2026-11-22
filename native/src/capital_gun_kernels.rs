// Capital turrets and missile launchers as rows (M10-T14, D12.9): every gun turret and launcher of every capital in play is
// a row with no node. A gun picks a hostile by its role (anti-fighter guns take fighters first, anti-capital guns capitals
// first, dual guns the nearest), leads it, slews inside its mount's arc and fires bolts through the core's own bolt rows; a
// launcher fires guided missiles or torpedoes, which this file also steers until they meet something. Targets are judged by
// what the ship perceives (the renegades' disguise); a ship's own hull blocks its fire. Run once a tick on the main thread
// before the bolts move, in mount order with no randomness but a seeded hash, so 1 and 6 threads fire the same shots.
// Engine-free (test_sim_core reads this file): rows in, plain numbers out, no statics.
use godot::builtin::{Basis, Vector3};

use crate::brain_maths::solve;
use crate::rows::{Bolts, FLAG_HULK, FLAG_HULL_ACTIVE, FLAG_SHELTERED, FLAG_TIER, Rows};
use crate::surface::{enters_from_outside, into_body};
use crate::turret_kernels::{self as tk, Gun, LINE_LIFT_M};
use crate::v3::{add, cross, dist_sq, dot, length, normalized, scale, sub, xform, xform_inv};
use crate::weapon_kernels::steer;

/// A weapon's role (`loadouts.json`): anti-fighter, dual, anti-capital.
pub const ROLE_AF: u8 = 0;
pub const ROLE_DUAL: u8 = 1;
pub const ROLE_AC: u8 = 2;
/// A launched round's warhead: a bolt has none; a missile's and a torpedo's blast where they strike (T09's rows).
pub const WARHEAD_NONE: u8 = 0;
pub const WARHEAD_MISSILE: u8 = 1;
pub const WARHEAD_TORPEDO: u8 = 2;

/// The core's entity kinds a gun takes: ships and capitals.
const KIND_SHIP: u8 = 0;
const KIND_CAPITAL: u8 = 1;
/// Hulls up to this radius are fighters to a gun's pick; anything larger (and every capital) is a capital (as the grid's).
pub const FIGHTER_RADIUS_MAX_M: f64 = 50.0;
/// A mount with no target looks for one this many ticks apart, staggered by its index (as the beams do).
pub const PICK_EVERY: u32 = 15;
/// How much further than its range a gun picks a target, so it is already laid when the target comes in.
pub const PICK_REACH: f64 = 1.1;
// Score offsets that rank the pick's classes ahead of distance (a gun's own class first).
const CLASS_PENALTY: f64 = 16.0;
/// A capital is aimed at its centre; a gun fires when its miss there is within this share of the hull's radius (at least
/// `CAPITAL_AIM_MIN_M`), since a long hull is far thinner than its bounding sphere.
pub const CAPITAL_AIM_SHARE: f64 = 0.1;
pub const CAPITAL_AIM_MIN_M: f64 = 20.0;
/// How far from its cell a missile starts, m (clear of the launcher's own housing).
pub const CELL_CLEAR_M: f64 = 6.0;

/// One weapon's numbers, from its `WeaponSpec` (the hull's `damage_scale` already in `damage`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GunSpec {
    /// A launcher (missiles, torpedoes) rather than a gun.
    pub launcher: bool,
    pub role: u8,
    /// One bolt's or warhead impact's hull points.
    pub damage: f64,
    /// Bolts (or missiles) one shot fires together.
    pub barrels: u32,
    /// Shots a burst and the time between them; one shot a burst is a plain gun.
    pub burst_shots: u32,
    pub burst_spacing_s: f64,
    /// From one shot's (or burst's) start to the next, s.
    pub cycle_s: f64,
    pub speed_mps: f64,
    pub range_m: f64,
    pub lifetime_s: f64,
    pub hit_radius_m: f64,
    pub spread_rad: f64,
    pub traverse_rad_s: f64,
    pub elevation_rad_s: f64,
    /// A missile's guidance: proportional navigation's gain and its most turn, rad/s.
    pub nav_gain: f64,
    pub turn_rad_s: f64,
    pub warhead: u8,
    pub color: [f32; 4],
    pub look: u8,
}

impl GunSpec {
    // The turret kernels' gun for the lead, the slew and the gate.
    fn gun(&self) -> Gun {
        Gun {
            muzzle_speed: self.speed_mps,
            interval_s: self.cycle_s,
            lifetime_s: self.lifetime_s,
            damage: self.damage,
            hit_radius: self.hit_radius_m,
            range_m: self.range_m,
            spread_rad: self.spread_rad,
            traverse_rad_s: self.traverse_rad_s,
            elevation_rad_s: self.elevation_rad_s,
            color: self.color,
            look: self.look,
        }
    }
}

/// One mount: its ship, where it sits in the ship's frame, the cone it covers, its weapon, and its state.
#[derive(Clone, Debug, PartialEq)]
pub struct Mount {
    /// The ship's body id.
    pub owner: i64,
    /// What its spread is hashed from (stable for its life).
    pub id: i64,
    pub local_at: Vector3,
    /// The cone's axis in the ship's frame: a turret's base up, a fixed gun's or a launcher's forward.
    pub axis: Vector3,
    /// Azimuth 0 round the axis, in the ship's frame.
    pub zero: Vector3,
    /// The lowest elevation above the cone's base plane, rad (the cone's half angle is 90 deg less this).
    pub min_elevation: f64,
    pub barrel_m: f64,
    pub spec: GunSpec,
    /// Its mount works (alive, its section standing, the ship neither disabled nor destroyed).
    pub works: bool,
    /// Its ship's rate of fire, 0 to 1 (half on last orders with the bridge lost).
    pub rate: f64,
    pub azimuth: f64,
    pub elevation: f64,
    /// The body it holds, 0 none.
    pub target: i64,
    pub ready_at: f64,
    pub burst_fired: u32,
    pub burst_started_s: f64,
    /// Ticks until it looks for a target again.
    pub pick_wait: u32,
    pub shots: i64,
}

impl Mount {
    /// A mount at `local_at` covering a cone of `half_rad` round `axis` (ship frame), its barrel resting on the axis when
    /// `rest_on_axis` (a fixed gun, a launcher), else on the cone's edge toward `zero` (a turret lying on its base).
    pub fn new(
        owner: i64,
        id: i64,
        local_at: Vector3,
        axis: Vector3,
        zero_hint: Vector3,
        half_rad: f64,
        rest_on_axis: bool,
        barrel_m: f64,
        spec: GunSpec,
    ) -> Mount {
        let axis = unit_or(axis, Vector3::new(0.0, 1.0, 0.0));
        let zero = flat_on(axis, zero_hint);
        let half = half_rad.clamp(0.0, std::f64::consts::PI);
        let min_elevation = (std::f64::consts::FRAC_PI_2 - half).max(-std::f64::consts::FRAC_PI_2);
        Mount {
            owner,
            id,
            local_at,
            axis,
            zero,
            min_elevation,
            barrel_m: barrel_m.max(0.0),
            spec,
            works: true,
            rate: 1.0,
            azimuth: 0.0,
            elevation: if rest_on_axis {
                std::f64::consts::FRAC_PI_2
            } else {
                min_elevation.max(0.0)
            },
            target: 0,
            ready_at: f64::NEG_INFINITY,
            burst_fired: 0,
            burst_started_s: 0.0,
            pick_wait: 0,
            shots: 0,
        }
    }
}

/// A ship's own bodies (its hull and its rotating sections), which never block or take its fire, and the target its brain
/// gives its anti-capital mounts.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Owner {
    pub body: i64,
    pub bodies: Vec<i64>,
    pub order: i64,
}

/// A shot this tick: the mount, where it leaves and how fast (World), and for a missile the body it is guided at.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Shot {
    pub mount: u32,
    pub start: Vector3,
    pub velocity: Vector3,
    pub target: i64,
}

/// A missile or torpedo in flight: its bolt row's id, the body it flies at (0 lost: straight on), its mount and guidance.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Missile {
    pub bolt: i64,
    pub target: i64,
    pub mount: u32,
    pub nav_gain: f64,
    pub turn_rad_s: f64,
    pub warhead: u8,
}

/// What a step reads beside the rows: the hull rows in the sweep's order, each owner's row (-1: not in the rows this tick),
/// the hostility table by the core's faction indices (`factions` square), how to find a body's row, and the local frame's
/// own velocity against its anchor (missiles hold their speed against the anchor).
pub struct GunWorld<'a, F: Fn(i64) -> Option<usize>> {
    pub rows: &'a Rows,
    pub hull_rows: &'a [u32],
    pub owner_rows: &'a [i32],
    pub hostile: &'a [bool],
    pub factions: usize,
    pub row_of: F,
    pub rest: Vector3,
}

/// Counts a step adds to (readouts).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Tally {
    /// Shots the gate allowed but the ship's own hull was in the way.
    pub blocked: i64,
    /// Picks that found a target.
    pub picks: i64,
}

/// One tick of every mount, in order: targets kept or picked, guns laid and fired through their gate, launchers fired
/// when ready. Appends the shots (a gun's barrels one after the other).
#[allow(clippy::too_many_arguments)]
pub fn step<F: Fn(i64) -> Option<usize>>(
    mounts: &mut [Mount],
    owners: &[Owner],
    owner_of: &[u32],
    world: &GunWorld<'_, F>,
    now_s: f64,
    dt: f64,
    tick: i64,
    shots: &mut Vec<Shot>,
    tally: &mut Tally,
) {
    for (i, m) in mounts.iter_mut().enumerate() {
        let o = owner_of[i] as usize;
        let Some(owner) = owners.get(o) else {
            continue;
        };
        let Some(r) = usize::try_from(world.owner_rows[o]).ok() else {
            continue; // out of the rows this tick (parked, pooled, in the tier): it holds its state
        };
        if !m.works || m.rate <= 0.0 {
            m.target = 0;
            continue;
        }
        let basis = world.rows.bases[r];
        let origin = world.rows.positions[r];
        let pivot = add(origin, xform(&basis, m.local_at));
        if m.target != 0 && !bears(m, owner, world, r, &basis, pivot, m.target, PICK_REACH) {
            m.target = 0;
        }
        if m.target == 0 {
            m.target = choose(m, owner, world, r, &basis, pivot);
            if m.target != 0 {
                tally.picks += 1;
            }
        }
        let Some(j) = (m.target != 0).then(|| (world.row_of)(m.target)).flatten() else {
            continue;
        };
        if m.spec.launcher {
            launch(m, i, world, r, &basis, pivot, j, now_s, shots);
        } else {
            fire_gun(m, i, owner, world, r, &basis, pivot, j, now_s, dt, tick, shots, tally);
        }
    }
}

// A gun's tick at its target (row `j`): the lead and the slew, then its gate, its own hull, and the shot of every barrel.
#[allow(clippy::too_many_arguments)]
fn fire_gun<F: Fn(i64) -> Option<usize>>(
    m: &mut Mount,
    i: usize,
    owner: &Owner,
    world: &GunWorld<'_, F>,
    r: usize,
    basis: &Basis,
    pivot: Vector3,
    j: usize,
    now_s: f64,
    dt: f64,
    tick: i64,
    shots: &mut Vec<Shot>,
    tally: &mut Tally,
) {
    let rows = world.rows;
    let frame = tk::Frame {
        pivot,
        up: normalized(xform(basis, m.axis)),
        forward: normalized(xform(basis, m.zero)),
        side: normalized(xform(basis, cross(m.axis, m.zero))),
    };
    let ship_velocity = rows.velocities[r];
    let mut gun = m.spec.gun();
    let capital = is_capital(rows, j);
    // A capital is within reach while its near side is: its centre may lie up to its radius further.
    if capital {
        gun.range_m += rows.radii[j];
    }
    let a = tk::aim(
        &frame,
        ship_velocity,
        m.azimuth,
        m.elevation,
        m.min_elevation,
        &gun,
        rows.positions[j],
        target_velocity(world, j),
        dt,
    );
    m.azimuth = a.azimuth;
    m.elevation = a.elevation;
    let allowance = if capital {
        (rows.radii[j] * CAPITAL_AIM_SHARE).max(CAPITAL_AIM_MIN_M)
    } else {
        rows.radii[j]
    };
    if !tk::gate(&a, &gun, allowance, m.ready_at, now_s) {
        return;
    }
    let from = add(pivot, scale(frame.up, LINE_LIFT_M as f32));
    if own_hull_blocks(world, owner, from, a.lead_point) {
        tally.blocked += 1;
        return;
    }
    let next = tk::next_ready(
        m.spec.cycle_s,
        m.spec.burst_shots,
        m.spec.burst_spacing_s,
        &mut m.burst_fired,
        &mut m.burst_started_s,
        now_s,
    );
    m.ready_at = now_s + (next - now_s) / m.rate;
    m.shots += 1;
    for barrel in 0..m.spec.barrels.max(1) {
        // Each barrel its own lane of the hash, so two barrels never throw the same.
        let lane = m.id.wrapping_mul(8).wrapping_add(i64::from(barrel));
        let direction = tk::spread(a.axis, m.spec.spread_rad, lane, tick);
        let (start, velocity) = tk::shot(
            pivot,
            a.axis,
            direction,
            m.barrel_m,
            ship_velocity,
            m.spec.speed_mps,
        );
        shots.push(Shot {
            mount: i as u32,
            start,
            velocity,
            target: 0,
        });
    }
}

// A launcher's tick at its target (row `j`): when ready, a salvo of its barrels' missiles, each leaving its cell between the
// cell's own axis and the target's lead, so its guidance has a line to turn on.
#[allow(clippy::too_many_arguments)]
fn launch<F: Fn(i64) -> Option<usize>>(
    m: &mut Mount,
    i: usize,
    world: &GunWorld<'_, F>,
    r: usize,
    basis: &Basis,
    pivot: Vector3,
    j: usize,
    now_s: f64,
    shots: &mut Vec<Shot>,
) {
    if now_s + 1e-6 < m.ready_at {
        return;
    }
    let rows = world.rows;
    if f64::from(length(sub(rows.positions[j], pivot))) - rows.radii[j] > m.spec.range_m {
        return; // held from a little further out, launched once in range
    }
    let ship_velocity = rows.velocities[r];
    let lead = solve(
        pivot,
        ship_velocity,
        rows.positions[j],
        target_velocity(world, j),
        m.spec.speed_mps,
        m.spec.lifetime_s,
    );
    let toward = if lead.ok {
        lead.aim_dir
    } else {
        normalized(sub(rows.positions[j], pivot))
    };
    let cell = normalized(xform(basis, m.axis));
    let mut out = add(cell, toward);
    if f64::from(dot(out, out)) < 1e-6 {
        out = cell;
    }
    let out = normalized(out);
    let next = tk::next_ready(
        m.spec.cycle_s,
        m.spec.burst_shots,
        m.spec.burst_spacing_s,
        &mut m.burst_fired,
        &mut m.burst_started_s,
        now_s,
    );
    m.ready_at = now_s + (next - now_s) / m.rate;
    m.shots += 1;
    let side = normalized(cross(cell, out));
    for barrel in 0..m.spec.barrels.max(1) {
        // A salvo's rounds leave side by side across the launcher, a cell apart.
        let offset = (f64::from(barrel) - 0.5 * f64::from(m.spec.barrels.max(1) - 1)) * CELL_CLEAR_M;
        let start = add(
            add(pivot, scale(out, (CELL_CLEAR_M + m.barrel_m) as f32)),
            scale(side, offset as f32),
        );
        shots.push(Shot {
            mount: i as u32,
            start,
            velocity: add(ship_velocity, scale(out, m.spec.speed_mps as f32)),
            target: rows.body_ids[j],
        });
    }
}

/// One tick of every missile's guidance, in launch order: each bolt still in the table turned toward its target by
/// proportional navigation (straight on without one), against the anchor's frame. Missiles whose bolt is gone (spent,
/// shot down, expired) leave the list. Appends `(bolt index, new velocity)` for the caller to write.
pub fn steer_missiles<F: Fn(i64) -> Option<usize>>(
    missiles: &mut Vec<Missile>,
    bolts: &Bolts,
    world: &GunWorld<'_, F>,
    dt: f64,
    out: &mut Vec<(usize, Vector3)>,
) {
    let owned = &bolts.ids[..bolts.owned.min(bolts.ids.len())];
    missiles.retain_mut(|missile| {
        // Owned bolts are in launch order with falling ids, so a binary search finds one.
        let Ok(i) = owned.binary_search_by(|id| missile.bolt.cmp(id)) else {
            return false;
        };
        if bolts.spent[i] {
            return false;
        }
        if missile.target == 0 {
            return true;
        }
        let Some(j) = (world.row_of)(missile.target) else {
            return true; // not readable this tick (touched): straight on, still guided at it
        };
        let rows = world.rows;
        if j >= rows.flags.len() || rows.flags[j] & FLAG_SHELTERED != 0 || !live_hull(rows, j) {
            missile.target = 0;
            return true;
        }
        let rest = world.rest;
        let v = steer(
            bolts.positions[i],
            sub(bolts.velocities[i], rest),
            rows.positions[j],
            sub(target_velocity(world, j), rest),
            missile.nav_gain,
            missile.turn_rad_s,
            dt,
        );
        out.push((i, add(v, rest)));
        true
    });
}

/// Whether row `j` is a capital to a gun: a capital or any hull bigger than a fighter.
pub fn is_capital(rows: &Rows, j: usize) -> bool {
    rows.kinds.get(j).copied() == Some(KIND_CAPITAL) || rows.radii[j] > FIGHTER_RADIUS_MAX_M
}

// A row's velocity as a lead reads it: a moving hull's own, the frame's rest for one with no body of its own.
fn target_velocity<F: Fn(i64) -> Option<usize>>(world: &GunWorld<'_, F>, j: usize) -> Vector3 {
    if world.rows.rigid[j] {
        world.rows.velocities[j]
    } else {
        world.rest
    }
}

// Whether row `j` is a hull in play: active (not a tier row) and not a mine.
fn live_hull(rows: &Rows, j: usize) -> bool {
    let flags = rows.flags[j];
    flags & FLAG_HULL_ACTIVE != 0 && flags & FLAG_TIER == 0 && !rows.is_mine[j]
}

// Whether the line from `from` to `to` enters one of the ship's own hulls (its hull and rotating sections) from outside.
fn own_hull_blocks<F: Fn(i64) -> Option<usize>>(world: &GunWorld<'_, F>, owner: &Owner, from: Vector3, to: Vector3) -> bool {
    owner.bodies.iter().any(|&b| {
        let Some(k) = (world.row_of)(b) else {
            return false;
        };
        world.rows.surface(k).is_some_and(|s| {
            let (basis, origin) = (&world.rows.bases[k], world.rows.positions[k]);
            enters_from_outside(s, into_body(basis, origin, from), into_body(basis, origin, to))
        })
    })
}

// Whether mount `m` of the ship at row `r` can hold body `target`: a live hostile ship or capital its ship perceives as
// hostile, within `reach` times its range and inside its cone.
#[allow(clippy::too_many_arguments)]
fn bears<F: Fn(i64) -> Option<usize>>(
    m: &Mount,
    owner: &Owner,
    world: &GunWorld<'_, F>,
    r: usize,
    basis: &Basis,
    pivot: Vector3,
    target: i64,
    reach: f64,
) -> bool {
    (world.row_of)(target).is_some_and(|j| takes(m, owner, world, r, basis, pivot, j, reach))
}

// Whether row `j` is a target for mount `m` (see `bears`). A torpedo (an anti-capital launcher) takes capitals only.
#[allow(clippy::too_many_arguments)]
fn takes<F: Fn(i64) -> Option<usize>>(
    m: &Mount,
    owner: &Owner,
    world: &GunWorld<'_, F>,
    r: usize,
    basis: &Basis,
    pivot: Vector3,
    j: usize,
    reach: f64,
) -> bool {
    let rows = world.rows;
    if j >= rows.positions.len()
        || !live_hull(rows, j)
        || rows.flags[j] & (FLAG_HULK | FLAG_SHELTERED) != 0
        || rows.is_static[j]
    {
        return false;
    }
    let kind = rows.kinds[j];
    if (kind != KIND_SHIP && kind != KIND_CAPITAL) || owner.bodies.contains(&rows.body_ids[j]) {
        return false;
    }
    // Only a ship with a target marker is a target (its row's id is the marker's): a capital's rotating section is not.
    if rows.ids[j] == rows.body_ids[j] {
        return false;
    }
    if m.spec.launcher && m.spec.role == ROLE_AC && !is_capital(rows, j) {
        return false;
    }
    let observer = rows.faction_ix[r];
    let (a, s, n) = (observer as usize, rows.seen_ix(j, observer) as usize, world.factions);
    if a >= n || s >= n || !world.hostile[a * n + s] {
        return false;
    }
    let rel = sub(rows.positions[j], pivot);
    let d = f64::from(length(rel));
    if d - rows.radii[j] > m.spec.range_m * reach {
        return false;
    }
    d < 1e-6 || in_cone(m, basis, rel, d)
}

// Whether a World offset `rel` (length `d`) from the pivot lies inside the mount's cone.
fn in_cone(m: &Mount, basis: &Basis, rel: Vector3, d: f64) -> bool {
    let along = f64::from(dot(xform_inv(basis, rel), m.axis)) / d;
    along.clamp(-1.0, 1.0).asin() >= m.min_elevation
}

// The target mount `m` takes when it has none: its brain's order (an anti-capital or dual weapon) when that bears, else (on
// its staggered pick tick) the best hostile in reach and cone by its role, nearest first, that its own hull does not hide.
// 0: none; it looks again `PICK_EVERY` ticks later.
fn choose<F: Fn(i64) -> Option<usize>>(
    m: &mut Mount,
    owner: &Owner,
    world: &GunWorld<'_, F>,
    r: usize,
    basis: &Basis,
    pivot: Vector3,
) -> i64 {
    if m.spec.role != ROLE_AF
        && owner.order != 0
        && bears(m, owner, world, r, basis, pivot, owner.order, 1.0)
    {
        return owner.order;
    }
    if m.pick_wait > 0 {
        m.pick_wait -= 1;
        return 0;
    }
    m.pick_wait = PICK_EVERY - 1;
    let rows = world.rows;
    let reach = m.spec.range_m * PICK_REACH;
    let reach_sq = reach * reach;
    let from = add(pivot, scale(normalized(xform(basis, m.axis)), LINE_LIFT_M as f32));
    let mut best = 0;
    let mut best_score = f64::INFINITY;
    for &h in world.hull_rows {
        let j = h as usize;
        if !takes(m, owner, world, r, basis, pivot, j, PICK_REACH) {
            continue;
        }
        let mut score = f64::from(dist_sq(rows.positions[j], pivot));
        let capital = is_capital(rows, j);
        let off_class = match m.spec.role {
            ROLE_AF => capital,
            ROLE_AC => !capital,
            _ => false,
        };
        if off_class {
            score += CLASS_PENALTY * reach_sq;
        }
        // The hull is tested only for a candidate that would win, off the common path.
        if score < best_score && !own_hull_blocks(world, owner, from, rows.positions[j]) {
            best_score = score;
            best = rows.body_ids[j];
        }
    }
    best
}

// `hint` laid flat on the plane across unit `axis` (unit); any direction across it when `hint` runs along it.
fn flat_on(axis: Vector3, hint: Vector3) -> Vector3 {
    for h in [hint, Vector3::new(0.0, 0.0, -1.0), Vector3::new(0.0, 1.0, 0.0)] {
        let flat = sub(h, scale(axis, dot(axis, h)));
        if f64::from(dot(flat, flat)) > 1e-4 {
            return normalized(flat);
        }
    }
    normalized(cross(axis, Vector3::new(1.0, 0.0, 0.0)))
}

fn unit_or(v: Vector3, fallback: Vector3) -> Vector3 {
    if f64::from(dot(v, v)) < 1e-12 {
        fallback
    } else {
        normalized(v)
    }
}

#[cfg(test)]
mod tests;
