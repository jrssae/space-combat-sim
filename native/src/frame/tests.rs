// The free-falling frame's unit tests (M6-T04): AC1's frame half, flown as the game flies it (sample, then step).
use super::*;

use crate::ephemeris::{Elements, Kind};

const DT: f64 = 1.0 / 60.0;
const GM_EARTH: f64 = 3.986e14;
const GM_STAR: f64 = 1.088e20;
const GM_EPSILON_III: f64 = 1.68e14;
const LOW_ORBIT_M: f64 = 6.771e6;
// D64's budget for an empty frame against the analytic orbit, at every tick of one low orbit.
const BUDGET_M: f64 = 0.05;

fn length(v: V3) -> f64 {
    (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt()
}

fn sub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

// A planet alone, at the system's root.
fn planet_alone(gm: f64) -> System {
    let mut s = System::new();
    s.add_root(Kind::Planet, gm);
    s
}

// The Epsilon system as the data holds it: the star, Epsilon III, the station's place on its 27 500 km rail.
fn epsilon() -> (System, usize, usize) {
    let mut s = System::new();
    s.add_root(Kind::Star, GM_STAR);
    let planet = s.add_body(Kind::Planet, GM_EPSILON_III, 0, Elements::circular(8.976e10, GM_STAR)).unwrap();
    let station = s.add_body(Kind::Minor, 0.0, planet, Elements::circular(2.75e7, GM_EPSILON_III)).unwrap();
    (s, planet, station)
}

// Flies an empty frame's anchor along `orbit` around `home` for one period, as the tick does, and gives the worst distance
// from the analytic orbit and the distance at the end.
fn fly(system: System, home: usize, orbit: Elements) -> (f64, f64) {
    let mut frame = Frame::default();
    frame.set_system(system, gravity::A_MIN_DEFAULT);
    let start = orbit.state_at(0.0);
    assert!(frame.anchor_in_orbit(home, start.position, start.velocity, 0.0, DT));
    let ticks = (orbit.period_s() / DT).ceil() as u64;
    let (mut worst, mut end) = (0.0_f64, 0.0);
    for tick in 0..ticks {
        frame.sample(tick as f64 * DT);
        frame.step(DT);
        let Anchor::Particle { position, .. } = frame.anchor() else { panic!("the anchor stays a particle") };
        end = length(sub(position, orbit.state_at((tick + 1) as f64 * DT).position));
        worst = worst.max(end);
    }
    (worst, end)
}

#[test]
fn an_empty_frame_follows_a_low_circular_orbit_within_the_budget() {
    let (worst, _) = fly(planet_alone(GM_EARTH), 0, Elements::circular(LOW_ORBIT_M, GM_EARTH));
    assert!(worst < BUDGET_M, "worst {worst} m");
}

#[test]
fn an_empty_frame_ends_an_eccentric_orbit_within_a_tenth_of_a_metre() {
    let orbit = Elements { eccentricity: 0.3, ..Elements::circular(LOW_ORBIT_M / 0.7, GM_EARTH) };
    let (_, end) = fly(planet_alone(GM_EARTH), 0, orbit);
    assert!(end < 0.1, "end {end} m");
}

#[test]
fn a_frame_round_a_planet_that_circles_its_star_keeps_the_budget() {
    // Held against the planet's centre: the star is far outside its zone, and its 35 km/s never enters the sums.
    let (system, planet, _) = epsilon();
    let radius = 5.2e6;
    let (worst, _) = fly(system, planet, Elements::circular(radius, GM_EPSILON_III));
    assert!(worst < BUDGET_M, "worst {worst} m");
}

#[test]
fn the_station_rail_lies_outside_every_zone_so_the_frame_is_quiet() {
    let (system, _, station) = epsilon();
    let mut frame = Frame::default();
    frame.set_system(system, gravity::A_MIN_DEFAULT);
    assert!(frame.anchor_on_rail(station));
    assert!(!frame.sample(1234.0));
    assert_eq!(frame.pull(), [0.0; 3]);
    assert_eq!(frame.residual([5000.0, -300.0, 20.0]), [0.0; 3]);
    let (home, state) = frame.anchor_state(DT).unwrap();
    assert_eq!(home, 1, "the rail is measured from the planet it circles");
    assert!((length(state.position) - 2.75e7).abs() < 1e-3);
}

#[test]
fn a_rail_inside_a_zone_feels_the_tidal_residual_and_none_at_its_own_point() {
    let mut system = planet_alone(GM_EARTH);
    let place = system.add_body(Kind::Minor, 0.0, 0, Elements::circular(LOW_ORBIT_M, GM_EARTH)).unwrap();
    let mut frame = Frame::default();
    frame.set_system(system, gravity::A_MIN_DEFAULT);
    assert!(frame.anchor_on_rail(place));
    assert!(frame.sample(100.0));
    assert_eq!(frame.residual([0.0; 3]), [0.0; 3]);
    // 1 km straight up from the planet: the pull weakens by twice the tidal gradient times the height.
    let (_, state) = frame.anchor_state(DT).unwrap();
    let r = length(state.position);
    let up = [state.position[0] / r * 1000.0, state.position[1] / r * 1000.0, state.position[2] / r * 1000.0];
    let felt = frame.residual(up);
    let expected = 2.0 * GM_EARTH / (r * r * r) * 1000.0;
    assert!((length(felt) - expected).abs() < expected * 1e-3, "felt {} expected {expected}", length(felt));
}

#[test]
fn the_local_origin_is_where_the_residual_is_measured_from() {
    let mut system = planet_alone(GM_EARTH);
    let place = system.add_body(Kind::Minor, 0.0, 0, Elements::circular(LOW_ORBIT_M, GM_EARTH)).unwrap();
    let mut frame = Frame::default();
    frame.set_system(system, gravity::A_MIN_DEFAULT);
    frame.anchor_on_rail(place);
    frame.sample(0.0);
    let far = frame.residual([4000.0, 2500.0, -700.0]);
    frame.set_origin([3000.0, 2000.0, -500.0]);
    frame.sample(0.0);
    assert_eq!(frame.residual([1000.0, 500.0, -200.0]), far);
}

#[test]
fn a_frame_starts_its_particle_half_a_kick_back() {
    let mut frame = Frame::default();
    frame.set_system(planet_alone(GM_EARTH), gravity::A_MIN_DEFAULT);
    let start = Elements::circular(LOW_ORBIT_M, GM_EARTH).state_at(0.0);
    assert!(frame.anchor_in_orbit(0, start.position, start.velocity, 0.0, DT));
    let Anchor::Particle { velocity, .. } = frame.anchor() else { panic!("a particle") };
    assert_ne!(velocity, start.velocity, "held behind the tick");
    let (_, state) = frame.anchor_state(DT).unwrap();
    for axis in 0..3 {
        assert!((state.velocity[axis] - start.velocity[axis]).abs() < 1e-9);
    }
}

#[test]
fn no_system_or_a_bad_anchor_leaves_the_frame_without_pull() {
    let mut frame = Frame::default();
    assert!(!frame.sample(0.0));
    assert_eq!(frame.residual([1.0, 2.0, 3.0]), [0.0; 3]);
    assert!(frame.anchor_state(DT).is_none());
    frame.set_system(planet_alone(GM_EARTH), gravity::A_MIN_DEFAULT);
    assert!(!frame.anchor_on_rail(3));
    assert!(!frame.anchor_in_orbit(1, [LOW_ORBIT_M, 0.0, 0.0], [0.0; 3], 0.0, DT));
    assert!(!frame.anchor_in_orbit(0, [f64::NAN, 0.0, 0.0], [0.0; 3], 0.0, DT));
    assert_eq!(frame.anchor(), Anchor::None);
}
