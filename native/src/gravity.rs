// Gravity on test particles (M6-T02, D64 and D66): the pull of the tick's frozen bodies, the part of it a free-falling
// frame still feels, and the step that moves a 64-bit particle. Ships, bolts and the frame's anchor weigh nothing here:
// bodies pull them, they pull nothing. The game's rule is one body at a time: each body has a zone, and only the
// strongest pull among the zones that hold a point counts there (`pull_at`, `residual`). The sum over every body
// (`accel_at`, `tidal`) is kept beside it. Pure functions over plain slices, with a fixed order of sums, so a worker
// and the main thread get the same bits. Engine-free by construction (test_sim_core reads this
// file): plain numbers in, plain numbers out, no statics.
#![allow(dead_code)] // partly wired in by M6-T04 (the frame); the rest by M6-T07

pub type V3 = [f64; 3];

fn dot(a: V3, b: V3) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

/// No limit on how far a body pulls: the default influence radius.
pub const UNBOUNDED: f64 = f64::INFINITY;

// Whether a body pulls at a squared distance: on or inside its influence radius, and not at its own centre.
fn pulls(gm: f64, r2: f64, reach: f64) -> bool {
    gm > 0.0 && r2 > 0.0 && r2 <= reach * reach
}

/// The acceleration at a point from every body, summed (not the game's rule: see `pull_at`). `positions` and the
/// point share one origin, and `reaches` holds one influence radius per body: beyond it the body adds nothing.
/// A body with no GM (anything smaller than a moon) is skipped, and so is one the point sits exactly on.
pub fn accel_at(point: V3, positions: &[V3], gms: &[f64], reaches: &[f64]) -> V3 {
    let mut sum = [0.0; 3];
    for ((body, &gm), &reach) in positions.iter().zip(gms).zip(reaches) {
        let r = [body[0] - point[0], body[1] - point[1], body[2] - point[2]];
        let r2 = dot(r, r);
        if !pulls(gm, r2, reach) {
            continue;
        }
        let k = gm / (r2 * r2.sqrt());
        sum[0] += k * r[0];
        sum[1] += k * r[1];
        sum[2] += k * r[2];
    }
    sum
}

/// The weakest pull that still counts, m/s^2: a body's zone ends where its pull falls to this.
pub const A_MIN_DEFAULT: f64 = 0.5;
/// Where a zone's fade starts, as a part of its radius. From here to the edge the pull is eased to nothing, so
/// crossing the edge is no jolt. At 0.8 the pull is full wherever it is above 1.56 times the floor, which covers
/// every orbit worth flying, and the band is wide enough (5 600 km at an Earth, 600 km at a Moon) that a ship at
/// full speed takes minutes to cross it.
pub const FADE_START: f64 = 0.8;

/// How far a body's zone reaches: where its pull is down to `a_min`. No floor means no edge.
pub fn zone_radius(gm: f64, a_min: f64) -> f64 {
    if gm <= 0.0 {
        0.0
    } else if a_min <= 0.0 {
        UNBOUNDED
    } else {
        (gm / a_min).sqrt()
    }
}

/// Every body's zone for the tick: its radius from the floor, or its own influence radius where that is smaller.
pub fn zones(gms: &[f64], limits: &[f64], a_min: f64, out: &mut Vec<f64>) {
    out.clear();
    for (&gm, &limit) in gms.iter().zip(limits) {
        out.push(zone_radius(gm, a_min).min(limit));
    }
}

/// How much of a body's pull counts at a distance: all of it up to the fade, none from the edge on.
pub fn zone_weight(distance: f64, zone: f64) -> f64 {
    let part = distance / zone;
    if part <= FADE_START {
        1.0
    } else if part < 1.0 {
        let t = (part - FADE_START) / (1.0 - FADE_START);
        1.0 - t * t * (3.0 - 2.0 * t)
    } else {
        0.0
    }
}

// One body's pull at a point under the zone rule, and how strong it is.
fn zone_pull(point: V3, body: V3, gm: f64, zone: f64) -> (V3, f64) {
    let r = [body[0] - point[0], body[1] - point[1], body[2] - point[2]];
    let r2 = dot(r, r);
    if gm <= 0.0 || zone <= 0.0 || r2 == 0.0 {
        return ([0.0; 3], 0.0);
    }
    let distance = r2.sqrt();
    let weight = zone_weight(distance, zone);
    // The same arithmetic as the sum's, so a full pull is the same bits under either rule.
    let k = weight * (gm / (r2 * distance));
    ([k * r[0], k * r[1], k * r[2]], weight * gm / r2)
}

// The strongest pull at a point and whose it is. The first body wins a tie.
fn strongest(point: V3, positions: &[V3], gms: &[f64], zones: &[f64]) -> (Option<usize>, V3) {
    let (mut best, mut most, mut pull) = (None, 0.0, [0.0; 3]);
    for (index, ((body, &gm), &zone)) in positions.iter().zip(gms).zip(zones).enumerate() {
        let (one, strength) = zone_pull(point, *body, gm, zone);
        if strength > most {
            (best, most, pull) = (Some(index), strength, one);
        }
    }
    (best, pull)
}

/// The body that pulls hardest at a point, among those whose zone holds the point. None where nothing pulls:
/// outside every zone, or exactly on a body's centre.
pub fn dominant(point: V3, positions: &[V3], gms: &[f64], zones: &[f64]) -> Option<usize> {
    strongest(point, positions, gms, zones).0
}

/// The game's gravity at a point: the dominant body's pull alone, eased to nothing at its zone's edge. Inside a
/// moon's zone the moon has taken over from its planet; far from everything there is no pull at all.
pub fn pull_at(point: V3, positions: &[V3], gms: &[f64], zones: &[f64]) -> V3 {
    strongest(point, positions, gms, zones).1
}

// The residual at an offset, given what the reference point itself gets.
fn residual_from(offset: V3, anchor: (Option<usize>, V3), positions: &[V3], gms: &[f64], zones: &[f64]) -> V3 {
    let (here, pull) = strongest(offset, positions, gms, zones);
    if let (Some(index), true) = (here, here == anchor.0) {
        let d = positions[index];
        let r = [d[0] - offset[0], d[1] - offset[1], d[2] - offset[2]];
        let (r2, d2) = (dot(r, r), dot(d, d));
        // Both ends under one body's full pull, the usual case: build the difference without subtracting.
        if zone_weight(r2.sqrt(), zones[index]) == 1.0 && zone_weight(d2.sqrt(), zones[index]) == 1.0 {
            let q = (dot(offset, offset) - 2.0 * dot(offset, d)) / d2;
            let f = q * (3.0 + q * (3.0 + q)) / (1.0 + (1.0 + q) * (1.0 + q).sqrt());
            let k = gms[index] / (r2 * r2.sqrt());
            return [-k * (offset[0] + f * d[0]), -k * (offset[1] + f * d[1]), -k * (offset[2] + f * d[2])];
        }
    }
    [pull[0] - anchor.1[0], pull[1] - anchor.1[1], pull[2] - anchor.1[2]]
}

/// What a frame falling with its reference point still feels at `offset` from it, under the game's rule:
/// pull(reference + offset) - pull(reference). `positions` are the bodies against the reference. It is exactly
/// zero at the reference, zero everywhere around a reference outside every zone, and beside a reference in orbit
/// it keeps its digits (the two pulls agree to nine of them there, so they are never subtracted).
pub fn residual(offset: V3, positions: &[V3], gms: &[f64], zones: &[f64]) -> V3 {
    residual_from(offset, strongest([0.0; 3], positions, gms, zones), positions, gms, zones)
}

/// The residual for many rows at once. Each row depends on nothing but itself, so any split of the rows over
/// threads gives the bits of one pass.
pub fn residual_rows(offsets: &[V3], positions: &[V3], gms: &[f64], zones: &[f64], out: &mut [V3]) {
    let anchor = strongest([0.0; 3], positions, gms, zones);
    for (slot, &offset) in out.iter_mut().zip(offsets) {
        *slot = residual_from(offset, anchor, positions, gms, zones);
    }
}

/// The residual under the sum over every body: accel_at(reference + offset) - accel_at(reference), built without
/// subtracting, with each pull stopping at its body's influence radius as in `accel_at`. A body the reference
/// sits on does not pull its own centre, so there the full pull is returned.
pub fn tidal(offset: V3, positions: &[V3], gms: &[f64], reaches: &[f64]) -> V3 {
    let mut sum = [0.0; 3];
    for ((body, &gm), &reach) in positions.iter().zip(gms).zip(reaches) {
        let d = *body;
        let r = [d[0] - offset[0], d[1] - offset[1], d[2] - offset[2]];
        let (r2, d2) = (dot(r, r), dot(d, d));
        let (here, there) = (pulls(gm, r2, reach), pulls(gm, d2, reach));
        if here && there {
            // f = (|r| / |d|)^3 - 1, written so that a small offset loses no digits.
            let q = (dot(offset, offset) - 2.0 * dot(offset, d)) / d2;
            let f = q * (3.0 + q * (3.0 + q)) / (1.0 + (1.0 + q) * (1.0 + q).sqrt());
            let k = gm / (r2 * r2.sqrt());
            sum[0] -= k * (offset[0] + f * d[0]);
            sum[1] -= k * (offset[1] + f * d[1]);
            sum[2] -= k * (offset[2] + f * d[2]);
        } else if here {
            let k = gm / (r2 * r2.sqrt());
            sum[0] += k * r[0];
            sum[1] += k * r[1];
            sum[2] += k * r[2];
        } else if there {
            let k = gm / (d2 * d2.sqrt());
            sum[0] -= k * d[0];
            sum[1] -= k * d[1];
            sum[2] -= k * d[2];
        }
    }
    sum
}

/// `tidal` for many rows at once.
pub fn tidal_rows(offsets: &[V3], positions: &[V3], gms: &[f64], reaches: &[f64], out: &mut [V3]) {
    for (slot, &offset) in out.iter_mut().zip(offsets) {
        *slot = tidal(offset, positions, gms, reaches);
    }
}

/// The first half of a step: the velocity takes the pull.
pub fn kick(velocity: &mut V3, accel: V3, dt: f64) {
    velocity[0] += accel[0] * dt;
    velocity[1] += accel[1] * dt;
    velocity[2] += accel[2] * dt;
}

/// The second half: the position takes the new velocity.
pub fn drift(position: &mut V3, velocity: V3, dt: f64) {
    position[0] += velocity[0] * dt;
    position[1] += velocity[1] * dt;
    position[2] += velocity[2] * dt;
}

/// One tick of a particle: kick, then drift, the step Jolt and the tier take, so a body moves the same whichever
/// frame carries it. `accel` is sampled at the position before the step.
pub fn step(position: &mut V3, velocity: &mut V3, accel: V3, dt: f64) {
    kick(velocity, accel, dt);
    drift(position, *velocity, dt);
}

/// The velocity to start an orbit with: the true one moved half a kick back, which is where the step holds it.
/// Without this an orbit starts hundreds of metres off its path.
pub fn half_kick_back(velocity: V3, accel: V3, dt: f64) -> V3 {
    let mut held = velocity;
    kick(&mut held, accel, -0.5 * dt);
    held
}

/// The true velocity at a tick, from the held one and the pull at the particle's place now.
pub fn velocity_at_tick(held: V3, accel: V3, dt: f64) -> V3 {
    let mut velocity = held;
    kick(&mut velocity, accel, 0.5 * dt);
    velocity
}

#[cfg(test)]
mod tests;
