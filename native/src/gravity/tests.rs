// The gravity kernel's unit tests (M6-T02), beside the kernel and outside its engine-free guard (test builds only).
use super::*;

use crate::ephemeris::{Elements, Kind, System};

const DT: f64 = 1.0 / 60.0;
const GM_EARTH: f64 = 3.986e14;
const GM_STAR: f64 = 1.088e20;
const LOW_ORBIT_M: f64 = 6.771e6;
// Unbounded influence for as many bodies as a test has.
const ANY: [f64; 8] = [UNBOUNDED; 8];

fn length(v: V3) -> f64 {
    dot(v, v).sqrt()
}

fn sub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

// A station's point in low orbit: the planet below, a moon and the star far off, and a rock that must not pull.
fn bodies() -> (Vec<V3>, Vec<f64>) {
    let positions = vec![[-LOW_ORBIT_M, 0.0, 0.0], [2.1e8, 3.2e8, -4.0e7], [5.0e10, -7.0e10, 1.0e9], [300.0, 50.0, -20.0]];
    (positions, vec![GM_EARTH, 4.9e12, GM_STAR, 0.0])
}

// A seeded scatter of offsets up to `reach` metres.
fn offsets(count: usize, reach: f64) -> Vec<V3> {
    let mut state: u64 = 0x9E37_79B9_7F4A_7C15;
    let mut next = move || {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        ((state >> 11) as f64 / (1u64 << 53) as f64 * 2.0 - 1.0) * reach
    };
    (0..count).map(|_| [next(), next(), next()]).collect()
}

struct Flight {
    worst_m: f64,
    end_m: f64,
    energy_drift: f64,
    energy_trend: f64,
}

// Flies a particle once round the planet with the game's pull and step and measures it against the analytic orbit.
fn fly_one_orbit(orbit: Elements) -> Flight {
    let (planet, gms) = ([[0.0; 3]], [orbit.parent_gm]);
    let mut zone = Vec::new();
    zones(&gms, &ANY, A_MIN_DEFAULT, &mut zone);
    let start = orbit.state_at(0.0);
    let mut position = start.position;
    let mut held = half_kick_back(start.velocity, pull_at(position, &planet, &gms, &zone), DT);
    let energy_of = |x: V3, v: V3| dot(v, v) / 2.0 - orbit.parent_gm / length(x);
    let first = energy_of(start.position, start.velocity);
    let ticks = (orbit.period_s() / DT).ceil() as u64;
    let mut flight = Flight { worst_m: 0.0, end_m: 0.0, energy_drift: 0.0, energy_trend: 0.0 };
    let (mut early, mut late) = (0.0, 0.0);
    for tick in 1..=ticks {
        let g = pull_at(position, &planet, &gms, &zone);
        step(&mut position, &mut held, g, DT);
        flight.end_m = length(sub(position, orbit.state_at(tick as f64 * DT).position));
        flight.worst_m = flight.worst_m.max(flight.end_m);
        if tick % 64 == 0 {
            let velocity = velocity_at_tick(held, pull_at(position, &planet, &gms, &zone), DT);
            let drift = energy_of(position, velocity) / first - 1.0;
            flight.energy_drift = flight.energy_drift.max(drift.abs());
            if tick < ticks / 2 {
                early = drift.abs().max(early);
            } else {
                late = drift.abs().max(late);
            }
        }
    }
    flight.energy_trend = late - early;
    flight
}

#[test]
fn the_pull_is_newtons() {
    let (positions, gms) = bodies();
    let alone = accel_at([0.0; 3], &positions[..1], &gms[..1], &ANY);
    let surface = GM_EARTH / (LOW_ORBIT_M * LOW_ORBIT_M);
    assert!((alone[0] + surface).abs() < 1e-14 && alone[1] == 0.0 && alone[2] == 0.0, "towards the planet, GM over r squared");
    let mut by_hand = [0.0; 3];
    for body in 0..3 {
        let r = length(positions[body]);
        for axis in 0..3 {
            by_hand[axis] += gms[body] * positions[body][axis] / (r * r * r);
        }
    }
    let all = accel_at([0.0; 3], &positions, &gms, &ANY);
    assert!(length(sub(all, by_hand)) < 1e-14, "the sum over bodies");
}

#[test]
fn nothing_smaller_than_a_moon_pulls() {
    let (positions, gms) = bodies();
    let near_rock = [299.0, 50.0, -20.0];
    assert_eq!(accel_at(near_rock, &positions, &gms, &ANY), accel_at(near_rock, &positions[..3], &gms[..3], &ANY));
    assert_eq!(tidal(near_rock, &positions, &gms, &ANY), tidal(near_rock, &positions[..3], &gms[..3], &ANY));
    assert_eq!(accel_at([1.0, 2.0, 3.0], &positions[3..], &gms[3..], &ANY), [0.0; 3]);
    // Standing exactly on a body is not a division by zero.
    assert_eq!(accel_at(positions[0], &positions[..1], &gms[..1], &ANY), [0.0; 3]);
    let back = accel_at([0.0; 3], &positions[..1], &gms[..1], &ANY).map(|c| -c);
    assert_eq!(tidal(positions[0], &positions[..1], &gms[..1], &ANY), back, "only the reference's pull is left");
}

#[test]
fn the_residual_is_zero_at_the_reference() {
    let (positions, gms) = bodies();
    assert_eq!(tidal([0.0; 3], &positions, &gms, &ANY), [0.0; 3]);
}

#[test]
fn the_residual_is_the_difference_of_two_pulls() {
    let (positions, gms) = bodies();
    let here = accel_at([0.0; 3], &positions, &gms, &ANY);
    for reach in [1.0e2, 3.0e3, 5.0e4, 2.0e6] {
        for offset in offsets(200, reach) {
            let plain = sub(accel_at(offset, &positions, &gms, &ANY), here);
            let got = tidal(offset, &positions, &gms, &ANY);
            // The plain difference is only good to the last digits of a 9 m/s^2 pull.
            assert!(length(sub(got, plain)) < 2e-14 + length(plain) * 1e-12, "at {offset:?}: {got:?} against {plain:?}");
        }
    }
}

#[test]
fn the_residual_matches_the_tidal_gradient() {
    let (positions, gms) = bodies();
    // T01's number: 2 GM / r^3 along the line to the planet, half that and inward across it.
    let gradient = 2.0 * GM_EARTH / (LOW_ORBIT_M * LOW_ORBIT_M * LOW_ORBIT_M);
    assert!((gradient - 2.57e-6).abs() < 1e-8);
    let up = tidal([100.0, 0.0, 0.0], &positions[..1], &gms[..1], &ANY);
    assert!((up[0] / 100.0 / gradient - 1.0).abs() < 1e-4, "stretched along the line: {up:?}");
    let across = tidal([0.0, 100.0, 0.0], &positions[..1], &gms[..1], &ANY);
    assert!((across[1] / 100.0 / (-gradient / 2.0) - 1.0).abs() < 1e-4, "squeezed across it: {across:?}");
    // A finite difference of the pull itself: the gradient it gives, times the offset, is the residual at 1 km.
    for offset in offsets(100, 1.0e3) {
        let mut linear = [0.0; 3];
        for axis in 0..3 {
            let mut ahead = [0.0; 3];
            ahead[axis] = 1.0e3;
            let behind = ahead.map(|c: f64| -c);
            let rise = sub(accel_at(ahead, &positions, &gms, &ANY), accel_at(behind, &positions, &gms, &ANY));
            let slope = rise.map(|c| c / 2.0e3);
            for row in 0..3 {
                linear[row] += slope[row] * offset[axis];
            }
        }
        let got = tidal(offset, &positions, &gms, &ANY);
        assert!(length(sub(got, linear)) < 1e-3 * length(got), "at {offset:?}: {got:?} against {linear:?}");
    }
    // Small offsets keep their digits: a millimetre is a thousandth of a metre's pull.
    let (metre, milli) = (tidal([1.0, 0.0, 0.0], &positions, &gms, &ANY), tidal([1.0e-3, 0.0, 0.0], &positions, &gms, &ANY));
    assert!((metre[0] / milli[0] / 1.0e3 - 1.0).abs() < 1e-6, "{metre:?} against {milli:?}");
}

#[test]
fn around_a_bodys_centre_the_residual_is_the_bodys_pull() {
    let system = {
        let mut system = System::new();
        let star = system.add_root(Kind::Star, GM_STAR).unwrap();
        let planet = system.add_body(Kind::Planet, GM_EARTH, star, Elements::circular(9.0e10, GM_STAR)).unwrap();
        system.add_body(Kind::Moon, 4.9e12, planet, Elements::circular(3.844e8, GM_EARTH)).unwrap();
        system
    };
    let (mut positions, mut gms) = (Vec::new(), Vec::new());
    let mut reaches = Vec::new();
    system.sample(1.0e5, 1, [0.0; 3], &mut positions, &mut gms, &mut reaches);
    assert_eq!(reaches, vec![UNBOUNDED; 3]);
    let at = [0.0, LOW_ORBIT_M, 0.0];
    let got = tidal(at, &positions, &gms, &ANY);
    let pull = accel_at(at, &positions[1..2], &gms[1..2], &ANY);
    assert!((pull[1] + GM_EARTH / (LOW_ORBIT_M * LOW_ORBIT_M)).abs() < 1e-14);
    // What is left over is the star's and the moon's tide, far below the planet's pull.
    let rest = length(sub(got, pull));
    assert!(rest > 1e-9 && rest < 1e-5, "the others' tide: {rest:e}");
    assert_eq!(tidal(at, &positions[1..2], &gms[1..2], &ANY), pull);
}

#[test]
fn a_particle_follows_a_circular_orbit_within_the_budget() {
    let flight = fly_one_orbit(Elements::circular(LOW_ORBIT_M, GM_EARTH));
    println!(
        "circular: worst {:.5} m, end {:.5} m, energy {:.3e}, trend {:.3e}",
        flight.worst_m, flight.end_m, flight.energy_drift, flight.energy_trend
    );
    assert!(flight.worst_m < 0.05, "AC1's budget is 0.05 m at every tick: {} m", flight.worst_m);
    assert!(flight.energy_drift < 1e-8, "energy within 1e-8: {:e}", flight.energy_drift);
    assert!(flight.energy_trend.abs() < 1e-9, "and no trend: {:e}", flight.energy_trend);
}

#[test]
fn a_particle_follows_an_elliptic_orbit_within_the_budget() {
    let orbit = Elements { eccentricity: 0.3, ..Elements::circular(LOW_ORBIT_M / 0.7, GM_EARTH) };
    let flight = fly_one_orbit(orbit);
    println!(
        "e 0.3: worst {:.5} m, end {:.5} m, energy {:.3e}, trend {:.3e}",
        flight.worst_m, flight.end_m, flight.energy_drift, flight.energy_trend
    );
    assert!(flight.end_m < 0.1, "AC1's budget is 0.1 m at the end: {} m", flight.end_m);
    assert!(flight.energy_drift < 1e-8, "energy within 1e-8: {:e}", flight.energy_drift);
}

#[test]
fn without_the_half_kick_an_orbit_starts_off_its_path() {
    let orbit = Elements::circular(LOW_ORBIT_M, GM_EARTH);
    let (planet, gms) = ([[0.0; 3]], [GM_EARTH]);
    let start = orbit.state_at(0.0);
    let (mut position, mut velocity) = (start.position, start.velocity);
    let half = (orbit.period_s() / DT / 2.0) as u64;
    for _ in 0..half {
        let g = accel_at(position, &planet, &gms, &ANY);
        step(&mut position, &mut velocity, g, DT);
    }
    let miss = length(sub(position, orbit.state_at(half as f64 * DT).position));
    assert!(miss > 100.0, "T01 measured 256 m mid-orbit: {miss}");
    // The half kick and its inverse are each other's undo.
    let g = accel_at(start.position, &planet, &gms, &ANY);
    let round = velocity_at_tick(half_kick_back(start.velocity, g, DT), g, DT);
    assert!(length(sub(round, start.velocity)) < 1e-12);
}

#[test]
fn a_body_adds_no_pull_beyond_its_influence_radius() {
    let (positions, gms) = bodies();
    // The moon reaches 60 000 km; the planet and the star reach everywhere.
    let reaches = [UNBOUNDED, 6.0e7, UNBOUNDED, UNBOUNDED];
    let moon = positions[1];
    let away = [0.6, 0.0, 0.8];
    let at = |distance: f64| [moon[0] + away[0] * distance, moon[1], moon[2] + away[2] * distance];
    let (inside, outside) = (at(6.0e7 - 1.0), at(6.0e7 + 1.0));
    let without = |point: V3| accel_at(point, &[positions[0], positions[2]], &[gms[0], gms[2]], &ANY);
    assert_eq!(accel_at(outside, &positions, &gms, &reaches), without(outside), "just outside: the moon adds nothing");
    assert_eq!(accel_at(inside, &positions, &gms, &ANY), accel_at(inside, &positions, &gms, &reaches), "just inside: all of it");
    let moons = length(sub(accel_at(inside, &positions, &gms, &reaches), without(inside)));
    assert!((moons / (gms[1] / 3.6e15) - 1.0).abs() < 1e-6, "which is GM over r squared: {moons:e}");
    // The residual is still the difference of the two pulls, whichever side of the edge each end is on.
    let residual = |reference: V3, point: V3| {
        let seen: Vec<V3> = positions.iter().map(|body| sub(*body, reference)).collect();
        let plain = sub(accel_at(point, &positions, &gms, &reaches), accel_at(reference, &positions, &gms, &reaches));
        let got = tidal(sub(point, reference), &seen, &gms, &reaches);
        assert!(length(sub(got, plain)) < 1e-13, "from {reference:?} to {point:?}: {got:?} against {plain:?}");
        got
    };
    let both_out = residual(at(6.0e7 + 500.0), outside);
    let both_in = residual(at(6.0e7 - 500.0), inside);
    let crossing_out = residual(inside, outside);
    let crossing_in = residual(outside, inside);
    assert!(length(sub(both_in, both_out)) > 1e-10, "inside, the moon's tide is in the residual");
    assert!((length(crossing_out) / (gms[1] / 3.6e15) - 1.0).abs() < 1e-2, "across the edge the moon's whole pull shows");
    assert!(length([0, 1, 2].map(|axis| crossing_out[axis] + crossing_in[axis])) < 1e-13);
    // A particle beyond every radius is not pulled: the step leaves it coasting in a straight line.
    let (mut x, mut v) = (outside, [10.0, -4.0, 2.0]);
    for _ in 0..600 {
        let g = accel_at(x, &positions[1..2], &gms[1..2], &reaches[1..2]);
        step(&mut x, &mut v, g, DT);
    }
    assert_eq!(v, [10.0, -4.0, 2.0]);
    assert!(length(sub(x, [outside[0] + 100.0, outside[1] - 40.0, outside[2] + 20.0])) < 1e-3);
    // The edge itself is inside.
    assert_ne!(accel_at([3.0, 0.0, 0.0], &[[0.0; 3]], &[1.0], &[3.0]), [0.0; 3]);
    assert_eq!(accel_at([3.0, 0.0, 0.0], &[[0.0; 3]], &[1.0], &[2.999]), [0.0; 3]);
}

// A planet with a far moon and a near one, the star, and a station's point: the game's zones at the default floor.
fn zoned() -> (Vec<V3>, Vec<f64>, Vec<f64>) {
    let positions = vec![[0.0; 3], [3.844e8, 0.0, 0.0], [0.0, 1.5e7, 0.0], [5.0e10, -7.0e10, 1.0e9], [0.0, 0.0, 9.0e6]];
    let gms = vec![GM_EARTH, 4.9e12, 4.9e12, GM_STAR, 0.0];
    let mut zone = Vec::new();
    zones(&gms, &ANY, A_MIN_DEFAULT, &mut zone);
    (positions, gms, zone)
}

#[test]
fn a_zone_ends_where_the_pull_falls_to_the_floor() {
    let earth = zone_radius(GM_EARTH, A_MIN_DEFAULT);
    assert!((earth - 2.8235e7).abs() < 1.0e3, "about 28 000 km for an Earth: {earth}");
    assert!((zone_radius(4.9e12, A_MIN_DEFAULT) - 3.130e6).abs() < 1.0e3, "about 3 100 km for a Moon");
    assert!((GM_EARTH / (earth * earth) - A_MIN_DEFAULT).abs() < 1e-12);
    assert!((zone_radius(GM_EARTH, 2.0) - earth / 2.0).abs() < 1e-6, "the floor is a parameter");
    assert_eq!(zone_radius(GM_EARTH, 0.0), UNBOUNDED, "no floor, no edge");
    assert_eq!(zone_radius(0.0, A_MIN_DEFAULT), 0.0, "a rock has no zone");
    // A body's own influence radius wins where it is the smaller.
    let mut zone = vec![7.0];
    zones(&[GM_EARTH, GM_EARTH, 0.0], &[UNBOUNDED, 1.0e7, UNBOUNDED], A_MIN_DEFAULT, &mut zone);
    assert_eq!(zone, vec![earth, 1.0e7, 0.0]);
}

#[test]
fn the_pull_fades_to_nothing_at_the_zones_edge() {
    let (planet, gms) = ([[0.0; 3]], [GM_EARTH]);
    let zone = [zone_radius(GM_EARTH, A_MIN_DEFAULT)];
    let pull = |part: f64| -pull_at([zone[0] * part, 0.0, 0.0], &planet, &gms, &zone)[0];
    let newton = |part: f64| GM_EARTH / (zone[0] * part * zone[0] * part);
    // Inside the band's start the pull is Newton's, to the bit; from the edge on there is none.
    for part in [0.01, 0.24, 0.5, 0.79, FADE_START - 1e-9] {
        let at = [zone[0] * part, 0.0, 0.0];
        assert_eq!(pull_at(at, &planet, &gms, &zone), accel_at(at, &planet, &gms, &ANY), "full at {part}");
    }
    for part in [1.0, 1.0 + 1e-9, 1.5, 40.0] {
        assert_eq!(pull_at([0.0, zone[0] * part, 0.0], &planet, &gms, &zone), [0.0; 3], "none at {part}");
        assert_eq!(dominant([0.0, zone[0] * part, 0.0], &planet, &gms, &zone), None);
    }
    // Across the band it only falls, with no step anywhere (the ends included) and half of it left mid-band.
    let steps = 20_000;
    let mut last = pull(FADE_START - 0.01);
    for step in 0..=steps {
        let part = FADE_START - 0.01 + 0.22 * f64::from(step) / f64::from(steps);
        let now = pull(part);
        assert!(now <= last && last - now < 2e-4, "no jolt at {part}: {last} then {now}");
        assert!(now <= newton(part) * (1.0 + 1e-14) && now >= 0.0);
        last = now;
    }
    assert_eq!(last, 0.0);
    assert!((pull(0.9) / newton(0.9) - 0.5).abs() < 1e-12);
    assert_eq!((zone_weight(0.8, 1.0), zone_weight(1.0, 1.0), zone_weight(5.0, UNBOUNDED)), (1.0, 0.0, 1.0));
    // The slope is eased at both ends too: a metre either side of them changes almost nothing more than Newton does.
    let near_start = (pull(FADE_START) - pull(FADE_START + 1.0 / zone[0])) / newton(FADE_START);
    let near_edge = pull(1.0 - 1.0 / zone[0]) / newton(1.0);
    assert!(near_start < 1e-6 && near_edge < 1e-10, "{near_start:e}, {near_edge:e}");
}

#[test]
fn only_the_dominant_body_pulls() {
    let (positions, gms, zone) = zoned();
    let alone = |body: usize, at: V3| accel_at(at, &positions[body..=body], &gms[body..=body], &ANY);
    // In low orbit the planet, and nothing of the star or the moons.
    let low = [LOW_ORBIT_M, 0.0, 0.0];
    assert_eq!(dominant(low, &positions, &gms, &zone), Some(0));
    assert_eq!(pull_at(low, &positions, &gms, &zone), alone(0, low), "the star is ignored near a planet");
    // Inside the far moon's zone the moon, and the planet is out of reach there.
    let by_moon = [3.844e8 - 2.0e6, 1.0e5, 0.0];
    assert_eq!(dominant(by_moon, &positions, &gms, &zone), Some(1));
    assert_eq!(pull_at(by_moon, &positions, &gms, &zone), alone(1, by_moon));
    // A moon inside its planet's zone takes over where its pull is the stronger, and hands back where it is not.
    let near = |gap: f64| [0.0, 1.5e7 - gap, 0.0];
    let balance = 1.5e7 / (1.0 + (GM_EARTH / 4.9e12).sqrt());
    assert_eq!(dominant(near(5.0e5), &positions, &gms, &zone), Some(2), "beside the near moon: the moon");
    assert_eq!(pull_at(near(5.0e5), &positions, &gms, &zone), alone(2, near(5.0e5)));
    assert_eq!(dominant(near(balance - 1.0e3), &positions, &gms, &zone), Some(2), "just moonward of the balance");
    assert_eq!(dominant(near(balance + 1.0e3), &positions, &gms, &zone), Some(0), "just planetward of it");
    assert_eq!(pull_at(near(balance + 1.0e3), &positions, &gms, &zone), alone(0, near(balance + 1.0e3)));
    // Between the worlds nothing pulls, and a rock never does.
    let between = [1.0e8, 0.0, 0.0];
    assert_eq!(dominant(between, &positions, &gms, &zone), None);
    assert_eq!(pull_at(between, &positions, &gms, &zone), [0.0; 3]);
    assert_eq!(dominant([0.0, 0.0, 9.0e6 + 5.0], &positions, &gms, &zone), Some(0), "a rock never dominates");
    assert_eq!(dominant([0.0, 5.0, 0.0], &[[0.0; 3], [0.0, 10.0, 0.0]], &[2.0, 2.0], &ANY), Some(0), "a tie: the first");
    // Near the star itself, the star.
    let by_star = [5.0e10 + 6.0e9, -7.0e10, 1.0e9];
    assert_eq!(dominant(by_star, &positions, &gms, &zone), Some(3));
}

#[test]
fn the_games_residual_is_the_difference_of_two_dominant_pulls() {
    let (bodies, gms, zone) = zoned();
    // Seen from a reference point, with the plain difference to compare against.
    let check = |reference: V3, reach: f64, tolerance: f64| {
        let seen: Vec<V3> = bodies.iter().map(|body| sub(*body, reference)).collect();
        assert_eq!(residual([0.0; 3], &seen, &gms, &zone), [0.0; 3], "zero at the reference");
        let offsets = offsets(300, reach);
        let mut rows = vec![[1.0; 3]; offsets.len()];
        residual_rows(&offsets, &seen, &gms, &zone, &mut rows);
        let anchor = pull_at(reference, &bodies, &gms, &zone);
        for (row, offset) in offsets.iter().enumerate() {
            let point = [reference[0] + offset[0], reference[1] + offset[1], reference[2] + offset[2]];
            let plain = sub(pull_at(point, &bodies, &gms, &zone), anchor);
            assert!(length(sub(rows[row], plain)) < tolerance, "at {offset:?}: {:?} against {plain:?}", rows[row]);
            assert_eq!(rows[row], residual(*offset, &seen, &gms, &zone));
        }
        rows
    };
    // A station in low orbit: the planet's tide, the same as the sum over that one body gives.
    let low = [LOW_ORBIT_M, 0.0, 0.0];
    let beside = check(low, 5.0e4, 2e-14 + 1e-9);
    let seen = [sub(bodies[0], low)];
    assert_eq!(beside[0], tidal(offsets(1, 5.0e4)[0], &seen, &gms[..1], &ANY));
    let (metre, milli) = (residual([1.0, 0.0, 0.0], &seen, &gms, &zone), residual([1.0e-3, 0.0, 0.0], &seen, &gms, &zone));
    assert!((metre[0] / milli[0] / 1.0e3 - 1.0).abs() < 1e-6, "small offsets keep their digits");
    // A station outside every zone: its frame feels nothing, and neither do the ships beside it.
    let far = [6.0e7, 0.0, 0.0];
    assert_eq!(pull_at(far, &bodies, &gms, &zone), [0.0; 3]);
    assert!(check(far, 5.0e4, 1e-300).iter().all(|row| *row == [0.0; 3]));
    // A station in a zone's fade, one where the near moon and the planet trade places, and one on a planet's centre.
    check([0.0, 0.0, 0.9 * zone[0]], 2.0e6, 1e-13);
    check([0.0, 1.5e7 - 1.5e7 / (1.0 + (GM_EARTH / 4.9e12).sqrt()), 0.0], 1.0e6, 1e-13);
    let about_centre = check([0.0; 3], 8.0e6, 1e-300);
    assert_ne!(about_centre[0], [0.0; 3]);
}

#[test]
fn a_step_is_a_kick_then_a_drift() {
    let (mut x, mut v) = ([1.0, 2.0, 3.0], [10.0, 0.0, -5.0]);
    step(&mut x, &mut v, [0.0, -6.0, 3.0], 0.5);
    assert_eq!(v, [10.0, -3.0, -3.5]);
    assert_eq!(x, [6.0, 0.5, 1.25], "the position takes the velocity after the kick");
}

#[test]
fn the_same_inputs_give_the_same_bits() {
    let (positions, gms) = bodies();
    let offsets = offsets(1001, 5.0e4);
    let mut whole = vec![[0.0; 3]; offsets.len()];
    tidal_rows(&offsets, &positions, &gms, &ANY, &mut whole);
    let mut again = vec![[0.0; 3]; offsets.len()];
    tidal_rows(&offsets, &positions, &gms, &ANY, &mut again);
    let bits = |rows: &[V3]| rows.iter().flatten().map(|c| c.to_bits()).collect::<Vec<u64>>();
    assert_eq!(bits(&whole), bits(&again));
    // Two halves, as two workers would take them, are the one pass.
    let mut split = vec![[0.0; 3]; offsets.len()];
    let (left, right) = split.split_at_mut(377);
    tidal_rows(&offsets[377..], &positions, &gms, &ANY, right);
    tidal_rows(&offsets[..377], &positions, &gms, &ANY, left);
    assert_eq!(bits(&whole), bits(&split));
    for (row, offset) in offsets.iter().enumerate() {
        assert_eq!(whole[row], tidal(*offset, &positions, &gms, &ANY));
    }
    // The game's rows, with zones, split the same way.
    let (seen, zoned_gms, zone) = zoned();
    let seen: Vec<V3> = seen.iter().map(|body| sub(*body, [0.0, 0.0, 2.2e7])).collect();
    let wide = self::offsets(1001, 4.0e6);
    let mut game = vec![[0.0; 3]; wide.len()];
    residual_rows(&wide, &seen, &zoned_gms, &zone, &mut game);
    let mut halves = vec![[0.0; 3]; wide.len()];
    let (left, right) = halves.split_at_mut(377);
    residual_rows(&wide[377..], &seen, &zoned_gms, &zone, right);
    residual_rows(&wide[..377], &seen, &zoned_gms, &zone, left);
    assert_eq!(bits(&game), bits(&halves));
    assert!(game.iter().any(|row| *row != [0.0; 3]));
    // A flight is the same flight twice.
    let fly = || {
        let (mut x, mut v) = ([LOW_ORBIT_M, 0.0, 0.0], [0.0, 7672.0, 10.0]);
        for _ in 0..5000 {
            let g = accel_at(x, &[[0.0; 3]], &[GM_EARTH], &ANY);
            step(&mut x, &mut v, g, DT);
        }
        bits(&[x, v])
    };
    assert_eq!(fly(), fly());
}
