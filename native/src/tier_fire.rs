// The low-attention tier's fire (M4-T22, docs/architecture.md 17.14): a far fighter's shot resolved as a seeded to-hit
// roll from the shot's geometry and the shooter's skill, and a far capital's guns, beams and missiles as rolls. No bolt
// row and no node: the shells (`cannons.rs` for a fighter's shots, `weapon_rows.rs` for a capital's) hand the hits to
// GDScript, which lands them through each target's `Damageable`. Engine-free by construction (test_sim_core reads this
// file): plain numbers and rows in, plain numbers out, no statics.
use godot::builtin::Vector3;

use crate::rows::{FLAG_HULK, FLAG_RIGID, FLAG_TIER, Rows};
use crate::v3::{add, dist_sq, dot, length, scale, sub};

// The fighter shot's model (fitted to the shots of six seeded full-fidelity 12 against 12 melees, Cycle log M4-T22). A
// bolt hits when its miss at the target falls inside the disc the hull presents. The miss is spread by how far off the
// lead the fire gate lets the pilot shoot (its miss distance), by the nose's wander while the brain steers (an angle, so
// it grows with range), by the pilot's own aim error (its skill), and by the target's manoeuvres while the bolt flies.
// How much of a hull's bounding radius a bolt must cross to hit (hulls are thinner than their bounding spheres).
const SIZE_FACTOR: f64 = 0.7;
// The aim error's spread per axis: the brain's wander is 0.6 and 0.4 of the error on two sines.
const AIM_SPREAD: f64 = 0.51;
// The gate's spread: the nose may sit anywhere within the miss distance of the lead.
const GATE_SPREAD: f64 = 1.0;
// The nose's wander about where the brain points it, rad.
const NOSE_SPREAD_RAD: f64 = 0.007;
// What a target's unforeseen manoeuvres add, as a steady acceleration over the bolt's flight, m/s^2.
const DODGE_ACCEL_MPS2: f64 = 8.0;
// A floor on the miss (muzzle offsets, the convergence), m.
const MISS_FLOOR_M: f64 = 1.0;

/// The far capitals' weapons, as their stand-ins have them (`TurretStandin`, `BeamStandin`, `MissileStandin`).
pub const GUN_RANGE_M: f64 = 4000.0;
pub const GUN_DAMAGE: f64 = 10.0;
const GUN_MUZZLE_SPEED_MPS: f64 = 1000.0;
const GUN_GATE_RAD: f64 = 1.5 * std::f64::consts::PI / 180.0;
pub const BEAM_RANGE_M: f64 = 3000.0;
pub const BEAM_DAMAGE: f64 = 25.0;
/// A capital's strike reach (its missiles' and beams' target).
pub const STRIKE_RANGE_M: f64 = 6000.0;
/// An interceptor's reach (`TurretStandin.INTERCEPT_RANGE_M`).
pub const INTERCEPT_RANGE_M: f64 = 1500.0;
pub const MISSILE_SPEED_MPS: f64 = 350.0;
pub const MISSILE_DAMAGE: f64 = 40.0;
/// Hulls larger than this are capitals, not fighters, m.
pub const FIGHTER_RADIUS_MAX_M: f64 = 50.0;
// A beam is hitscan: it lands unless the target slipped out of the line in the tick it fired.
const BEAM_HIT: f64 = 0.95;
// A missile's chance: proportional navigation catches a fighter it can out-turn; a long chase gives it time to slip away.
const MISSILE_HIT_NEAR: f64 = 0.8;
const MISSILE_HIT_FALLOFF_M: f64 = 12000.0;
// What a fighter's manoeuvres add to a far gun's miss while its bolt flies, m/s^2.
const GUN_DODGE_ACCEL_MPS2: f64 = 10.0;

/// The chance one fighter shot hits: `range_m` to the target, the target's bounding radius, the bolt's hit radius, speed
/// and reach (speed times lifetime), how fast the two close (m/s, negative opening), the shooter's aim error (radians,
/// its skill), the miss distance its fire gate allows, and how far outside that gate the shot leaves (`gate_excess_m`).
/// 0 past the bolt's reach.
#[allow(clippy::too_many_arguments)]
pub fn hit_chance(
    range_m: f64,
    target_radius_m: f64,
    hit_radius_m: f64,
    muzzle_speed_mps: f64,
    closing_mps: f64,
    aim_error_rad: f64,
    miss_m: f64,
    reach_m: f64,
    excess_m: f64,
) -> f64 {
    if range_m.is_nan() || range_m < 0.0 || range_m > reach_m || muzzle_speed_mps <= 0.0 {
        return 0.0;
    }
    // The bolt's flight: it meets a closing target sooner, an opening one later.
    let flight_s = range_m / (muzzle_speed_mps + closing_mps).max(0.25 * muzzle_speed_mps);
    let aim = range_m * aim_error_rad.max(0.0) * AIM_SPREAD;
    let gate = miss_m.max(0.0) * GATE_SPREAD;
    let nose = range_m * NOSE_SPREAD_RAD;
    let dodge = 0.5 * DODGE_ACCEL_MPS2 * flight_s * flight_s;
    offset_disc_chance(
        target_radius_m * SIZE_FACTOR + hit_radius_m,
        aim * aim + gate * gate + nose * nose + dodge * dodge + MISS_FLOOR_M * MISS_FLOOR_M,
        excess_m.max(0.0),
    )
}

/// The chance a far capital's gun lands one shot on a fighter of `target_radius_m` at `range_m` (0 past its reach): the
/// gun fires once its aim is within its gate of the lead, and the fighter manoeuvres while the bolt flies.
pub fn turret_chance(range_m: f64, target_radius_m: f64) -> f64 {
    if range_m.is_nan() || range_m < 0.0 || range_m > GUN_RANGE_M {
        return 0.0;
    }
    let flight_s = range_m / GUN_MUZZLE_SPEED_MPS;
    let gate = range_m * GUN_GATE_RAD.tan() * GATE_SPREAD;
    let dodge = 0.5 * GUN_DODGE_ACCEL_MPS2 * flight_s * flight_s;
    disc_chance(
        target_radius_m * SIZE_FACTOR,
        gate * gate + dodge * dodge + MISS_FLOOR_M * MISS_FLOOR_M,
    )
}

/// The chance a far capital's beam lands on its strike target within reach.
pub fn beam_chance(range_m: f64) -> f64 {
    if range_m.is_nan() || range_m < 0.0 || range_m > BEAM_RANGE_M {
        return 0.0;
    }
    BEAM_HIT
}

/// The chance a far capital's missile reaches a fighter `range_m` away (0 past the strike reach).
pub fn missile_chance(range_m: f64) -> f64 {
    if range_m.is_nan() || range_m < 0.0 || range_m > STRIKE_RANGE_M {
        return 0.0;
    }
    MISSILE_HIT_NEAR * (1.0 - range_m / MISSILE_HIT_FALLOFF_M)
}

/// How far outside its pilot's fire gate a tier fighter's shot leaves, m at the target's range: 0 while the row's nose
/// (`forward`, unit) at `at` moving at `v` is within the gate of the lead on a target at `target_at` moving at
/// `target_v` (within `cone_rad` of it and within `miss_m` of it at that range), for bolts at `muzzle_speed_mps`. A near
/// pilot's gate closes when its nose swings off; a tier pilot's 4 Hz brain still holds the trigger, so its shot carries
/// the excess as a miss.
#[allow(clippy::too_many_arguments)]
pub fn gate_excess_m(
    at: Vector3,
    v: Vector3,
    forward: Vector3,
    target_at: Vector3,
    target_v: Vector3,
    muzzle_speed_mps: f64,
    cone_rad: f64,
    miss_m: f64,
) -> f64 {
    let line = sub(target_at, at);
    let range = f64::from(length(line));
    if range <= 1e-3 || muzzle_speed_mps <= 0.0 {
        return 0.0;
    }
    // The lead: where the target will be when a bolt reaches it (two passes of the flight time).
    let rel = sub(target_v, v);
    let mut flight_s = range / muzzle_speed_mps;
    let mut lead = line;
    for _ in 0..2 {
        lead = add(line, scale(rel, flight_s as f32));
        flight_s = f64::from(length(lead)) / muzzle_speed_mps;
    }
    let lead_len = f64::from(length(lead));
    if lead_len <= 1e-3 {
        return 0.0;
    }
    let off = (f64::from(dot(forward, lead)) / lead_len)
        .clamp(-1.0, 1.0)
        .acos();
    let allowed = cone_rad.max(0.0).min((miss_m.max(0.0) / range).atan());
    if off <= allowed {
        return 0.0;
    }
    // Off by more than a right angle, a shot never comes near.
    let excess = (off.min(std::f64::consts::FRAC_PI_2) - allowed).tan() * range;
    excess.min(1.0e6)
}

/// How fast a target at `target_at` moving at `target_v` closes on a shooter at `at` moving at `v`, m/s (negative when
/// they open).
pub fn closing_speed(at: Vector3, v: Vector3, target_at: Vector3, target_v: Vector3) -> f64 {
    let line = sub(target_at, at);
    let range = f64::from(length(line));
    if range <= 0.0 {
        return 0.0;
    }
    -f64::from(dot(sub(target_v, v), line)) / range
}

// `disc_chance` with the miss's centre `offset` from the target's (the same Gaussian overlap, exact at both ends).
fn offset_disc_chance(r: f64, sigma2: f64, offset: f64) -> f64 {
    let spread = r * r + 2.0 * sigma2;
    if spread <= 0.0 {
        return 0.0;
    }
    disc_chance(r, sigma2) * (-(offset * offset) / spread).exp()
}

// A circular Gaussian miss of variance `sigma2` per axis against a disc of radius `r`, the disc itself taken as a Gaussian
// of the same second moment: exact at both ends (a sure hit with no spread, `r^2 / 2 sigma2` when the spread is wide).
fn disc_chance(r: f64, sigma2: f64) -> f64 {
    let r2 = r * r;
    if r2 <= 0.0 {
        return 0.0;
    }
    r2 / (r2 + 2.0 * sigma2)
}

/// A seeded uniform draw in [0, 1) for one roll: the same `seed`, `tick` and keys give the same draw on every thread
/// count and every run (SplitMix64 over the four).
pub fn roll(seed: u64, tick: i64, a: i64, b: i64) -> f64 {
    let mut x = seed;
    for k in [tick as u64, a as u64, b as u64] {
        x = mix(x ^ k.wrapping_mul(0x9e37_79b9_7f4a_7c15));
    }
    (x >> 11) as f64 / (1u64 << 53) as f64
}

fn mix(mut z: u64) -> u64 {
    z = z.wrapping_add(0x9e37_79b9_7f4a_7c15);
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^ (z >> 31)
}

/// Hits drawn from `shots` tries at `chance` each, one seeded draw per try (`key` tells the rolls of one tick apart).
pub fn hits_of(seed: u64, tick: i64, key: i64, shots: i64, chance: f64) -> i64 {
    (0..shots)
        .filter(|&k| roll(seed, tick, key, k) < chance)
        .count() as i64
}

/// The nearest live fighter hostile to `hostile` (a flag per faction index) within `reach_m` of `at`, near (a rigid body)
/// or in the tier (not a hulk), `own_body` left out: its row, or none. Ties go to the earlier row.
pub fn nearest_hostile_fighter(
    rows: &Rows,
    hostile: &[bool],
    at: Vector3,
    reach_m: f64,
    own_body: i64,
) -> Option<usize> {
    let mut best: Option<usize> = None;
    let mut best_sq = reach_m * reach_m;
    for i in 0..rows.body_ids.len() {
        let flags = rows.flags[i];
        let flying = flags & FLAG_RIGID != 0 || (flags & FLAG_TIER != 0 && flags & FLAG_HULK == 0);
        if !flying
            || rows.is_static[i]
            || rows.radii[i] > FIGHTER_RADIUS_MAX_M
            || rows.body_ids[i] == own_body
            || !hostile
                .get(rows.faction_ix[i] as usize)
                .copied()
                .unwrap_or(false)
        {
            continue;
        }
        let d_sq = f64::from(dist_sq(rows.positions[i], at));
        if d_sq < best_sq {
            best_sq = d_sq;
            best = Some(i);
        }
    }
    best
}

/// How much of two hulls' bounding radii they must close to before a ram lands (the hull's disc, as a shot's).
pub const RAM_REACH: f64 = 0.7;

/// Whether two hulls at `a` and `b`, of bounding radii `ra` and `rb`, moving at `va` and `vb`, come within their ram reach
/// over the next `dt` seconds (the closest approach of their straight paths).
pub fn ram_touch(
    a: Vector3,
    va: Vector3,
    ra: f64,
    b: Vector3,
    vb: Vector3,
    rb: f64,
    dt: f64,
) -> bool {
    let p = sub(b, a);
    let v = sub(vb, va);
    let vv = f64::from(dot(v, v));
    let t = if vv > 0.0 {
        (-f64::from(dot(p, v)) / vv).clamp(0.0, dt.max(0.0))
    } else {
        0.0
    };
    let closest = add(p, scale(v, t as f32));
    let reach = (ra + rb) * RAM_REACH;
    f64::from(dot(closest, closest)) <= reach * reach
}

/// The fighters' rolled hits since GDScript last took them (M4-T22): each hit's target (body id), shooter (body id),
/// damage and the target's place, in the order they were rolled.
#[derive(Default)]
pub struct Hits {
    pub targets: Vec<i64>,
    pub shooters: Vec<i64>,
    pub damage: Vec<f64>,
    pub points: Vec<Vector3>,
}

impl Hits {
    pub fn push(&mut self, target: i64, shooter: i64, damage: f64, at: Vector3) {
        self.targets.push(target);
        self.shooters.push(shooter);
        self.damage.push(damage);
        self.points.push(at);
    }

    pub fn clear(&mut self) {
        self.targets.clear();
        self.shooters.clear();
        self.damage.clear();
        self.points.clear();
    }
}
