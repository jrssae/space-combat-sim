// The ephemeris's unit tests (M6-T02), beside the kernel and outside its engine-free guard (test builds only).
use super::*;

use std::f64::consts::FRAC_PI_2;

const GM_EARTH: f64 = 3.986e14;
const GM_STAR: f64 = 1.088e20;
const LOW_ORBIT_M: f64 = 6.771e6;

fn length(v: V3) -> f64 {
    (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt()
}

fn dot(a: V3, b: V3) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross(a: V3, b: V3) -> V3 {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}

fn assert_near(got: V3, want: V3, tolerance: f64, what: &str) {
    let miss = length(sub(got, want));
    assert!(miss <= tolerance, "{what}: {got:?} against {want:?}, off by {miss:e}");
}

fn elliptic(a: f64, e: f64) -> Elements {
    Elements { eccentricity: e, ..Elements::circular(a, GM_EARTH) }
}

// A star, a planet with a moon and a rock around the planet, and a second planet with its own moon.
fn system() -> System {
    let mut system = System::new();
    let star = system.add_root(Kind::Star, GM_STAR).unwrap();
    let planet = system.add_body(Kind::Planet, GM_EARTH, star, Elements::circular(9.0e10, GM_STAR)).unwrap();
    let orbit = Elements { inclination: 0.09, mean_anomaly_at_epoch: 1.0, ..elliptic(3.844e8, 0.05) };
    system.add_body(Kind::Moon, 4.9e12, planet, orbit).unwrap();
    system.add_body(Kind::Minor, 1.0e3, planet, Elements::circular(5.0e7, GM_EARTH)).unwrap();
    let outer = system.add_body(Kind::Planet, 1.2e17, star, Elements::circular(4.0e11, GM_STAR)).unwrap();
    system.add_body(Kind::Moon, 8.0e12, outer, Elements::circular(1.0e9, 1.2e17)).unwrap();
    system
}

#[test]
fn keplers_equation_is_solved_for_every_orbit_accepted() {
    for e in [0.0, 0.1, 0.3, 0.7, 0.9, 0.97, MAX_ECCENTRICITY] {
        for step in -2000..=2000 {
            let mean = f64::from(step) * PI / 2000.0;
            let anomaly = solve_kepler(mean, e);
            let back = anomaly - e * anomaly.sin();
            let miss = (back - mean + PI).rem_euclid(TAU) - PI;
            assert!(miss.abs() < 4e-15, "e {e}, M {mean}: E {anomaly} gives M {back}");
        }
        // The awkward corner: almost at periapsis on an eccentric orbit.
        for mean in [1e-12, 1e-9, 1e-6, 1e-3] {
            let anomaly = solve_kepler(mean, e);
            assert!((anomaly - e * anomaly.sin() - mean).abs() < 1e-15, "e {e}, M {mean}");
        }
    }
    // Whole turns change nothing but rounding.
    assert!((solve_kepler(1.0 + 40.0 * TAU, 0.3) - solve_kepler(1.0, 0.3)).abs() < 1e-12);
    assert_eq!(solve_kepler(-1.0, 0.3), -solve_kepler(1.0, 0.3));
}

#[test]
fn a_circular_orbit_matches_its_closed_form() {
    let orbit = Elements::circular(LOW_ORBIT_M, GM_EARTH);
    let speed = (GM_EARTH / LOW_ORBIT_M).sqrt();
    assert!((speed - 7672.6).abs() < 0.1, "T01's low orbit: {speed} m/s");
    assert!((orbit.period_s() - 5545.0).abs() < 1.0, "T01's period: {}", orbit.period_s());
    let start = orbit.state_at(0.0);
    assert_near(start.position, [LOW_ORBIT_M, 0.0, 0.0], 1e-8, "start");
    assert_near(start.velocity, [0.0, speed, 0.0], 1e-11, "start speed");
    let quarter = orbit.state_at(orbit.period_s() / 4.0);
    assert_near(quarter.position, [0.0, LOW_ORBIT_M, 0.0], 1e-8, "a quarter on");
    assert_near(quarter.velocity, [-speed, 0.0, 0.0], 1e-11, "a quarter on, speed");
    for step in 0..360 {
        let angle = f64::from(step).to_radians();
        let state = orbit.state_at(angle / orbit.mean_motion());
        let want = [LOW_ORBIT_M * angle.cos(), LOW_ORBIT_M * angle.sin(), 0.0];
        assert_near(state.position, want, 1e-7, "on the circle");
    }
}

#[test]
fn an_elliptic_orbit_matches_its_closed_form() {
    let (a, e) = (9.6729e6, 0.3);
    let orbit = elliptic(a, e);
    let periapsis = orbit.state_at(0.0);
    assert_near(periapsis.position, [a * (1.0 - e), 0.0, 0.0], 1e-8, "periapsis");
    assert_near(periapsis.velocity, [0.0, (GM_EARTH * (1.0 + e) / (a * (1.0 - e))).sqrt(), 0.0], 1e-11, "periapsis speed");
    let apoapsis = orbit.state_at(orbit.period_s() / 2.0);
    assert_near(apoapsis.position, [-a * (1.0 + e), 0.0, 0.0], 1e-7, "apoapsis");
    assert_near(apoapsis.velocity, [0.0, -(GM_EARTH * (1.0 - e) / (a * (1.0 + e))).sqrt(), 0.0], 1e-10, "apoapsis speed");
    // The end of the minor axis: eccentric anomaly a quarter turn, so the mean anomaly is known exactly.
    let side = orbit.state_at((FRAC_PI_2 - e) / orbit.mean_motion());
    let minor = a * (1.0 - e * e).sqrt();
    assert_near(side.position, [-a * e, minor, 0.0], 1e-7, "the minor axis");
    assert_near(side.velocity, [-(GM_EARTH / a).sqrt(), 0.0, 0.0], 1e-10, "the minor axis, speed");
    // Energy and angular momentum hold all the way round.
    let momentum = (GM_EARTH * a * (1.0 - e * e)).sqrt();
    for step in 0..500 {
        let state = orbit.state_at(orbit.period_s() * f64::from(step) / 500.0);
        let r = length(state.position);
        let energy = dot(state.velocity, state.velocity) / 2.0 - GM_EARTH / r;
        assert!((energy / (-GM_EARTH / (2.0 * a)) - 1.0).abs() < 1e-13, "energy at step {step}");
        assert_near(cross(state.position, state.velocity), [0.0, 0.0, momentum], momentum * 1e-13, "momentum");
    }
}

#[test]
fn an_inclined_orbit_matches_its_closed_form() {
    // A polar orbit that crosses the plane on the x axis climbs straight up z.
    let polar = Elements { inclination: FRAC_PI_2, ..Elements::circular(LOW_ORBIT_M, GM_EARTH) };
    let speed = (GM_EARTH / LOW_ORBIT_M).sqrt();
    let top = polar.state_at(polar.period_s() / 4.0);
    assert_near(top.position, [0.0, 0.0, LOW_ORBIT_M], 1e-8, "over the pole");
    assert_near(top.velocity, [-speed, 0.0, 0.0], 1e-11, "over the pole, speed");
    // The crossing's longitude turns the whole orbit about z; the periapsis argument turns it in its plane.
    let turned = Elements { ascending_longitude: FRAC_PI_2, periapsis_argument: FRAC_PI_2, ..elliptic(9.6729e6, 0.3) };
    assert_near(turned.state_at(0.0).position, [-9.6729e6 * 0.7, 0.0, 0.0], 1e-8, "periapsis turned half round");
    // A general orbit: the plane's normal is fixed by the tilt and the crossing, and periapsis by all three angles.
    let (i, node, peri) = (0.4_f64, 1.1_f64, 2.3_f64);
    let orbit = Elements { inclination: i, ascending_longitude: node, periapsis_argument: peri, ..elliptic(9.6729e6, 0.3) };
    let normal = [node.sin() * i.sin(), -node.cos() * i.sin(), i.cos()];
    let momentum = (GM_EARTH * 9.6729e6 * (1.0 - 0.09)).sqrt();
    for step in 0..100 {
        let state = orbit.state_at(orbit.period_s() * f64::from(step) / 100.0);
        let h = cross(state.position, state.velocity);
        assert_near(h, [normal[0] * momentum, normal[1] * momentum, normal[2] * momentum], momentum * 1e-13, "the plane");
    }
    let first = orbit.state_at(0.0).position;
    let want = [
        node.cos() * peri.cos() - node.sin() * peri.sin() * i.cos(),
        node.sin() * peri.cos() + node.cos() * peri.sin() * i.cos(),
        peri.sin() * i.sin(),
    ];
    assert_near(first, want.map(|c| c * 9.6729e6 * 0.7), 1e-8, "periapsis");
}

#[test]
fn the_velocity_is_the_rate_of_the_position() {
    let orbit = Elements { inclination: 0.4, ascending_longitude: 1.1, periapsis_argument: 2.3, ..elliptic(9.6729e6, 0.7) };
    for step in 0..50 {
        let t = orbit.period_s() * f64::from(step) / 50.0;
        let (before, after) = (orbit.state_at(t - 0.01).position, orbit.state_at(t + 0.01).position);
        let rate = sub(after, before).map(|c| c / 0.02);
        assert_near(orbit.state_at(t).velocity, rate, 1e-4, "velocity");
    }
}

#[test]
fn the_epoch_and_mean_anomaly_place_the_body() {
    let base = elliptic(9.6729e6, 0.3);
    let shifted = Elements { mean_anomaly_at_epoch: 0.8, epoch_s: 500.0, ..base };
    let want = base.state_at(0.8 / base.mean_motion() + 250.0);
    assert_near(shifted.state_at(750.0).position, want.position, 1e-6, "position");
    assert_near(shifted.state_at(750.0).velocity, want.velocity, 1e-9, "velocity");
}

#[test]
fn a_moon_orbits_its_planet() {
    let system = system();
    let moon_orbit = system.body(2).elements;
    for t in [0.0, 86_400.0, 4.0e6, -3.0e5] {
        let seen = system.relative_state(2, 1, t);
        assert_eq!(seen, moon_orbit.state_at(t), "from its planet, the moon is on its own orbit");
        let r = length(seen.position);
        assert!((3.844e8 * 0.95 - 1.0..=3.844e8 * 1.05 + 1.0).contains(&r), "within its apsides: {r}");
        // Against the star it is the planet's place plus that orbit.
        let (planet, moon) = (system.state(1, t), system.state(2, t));
        assert_near(sub(moon.position, planet.position), seen.position, 1e-4, "barycentric position");
        assert_near(sub(moon.velocity, planet.velocity), seen.velocity, 1e-11, "barycentric velocity");
        assert!((length(planet.position) - 9.0e10).abs() < 1e-3);
    }
    // Seen the other way round, and across two planets through the star.
    let (there, back) = (system.relative_state(2, 1, 5.0e5), system.relative_state(1, 2, 5.0e5));
    assert_eq!(there.position, back.position.map(|c| -c));
    let across = system.relative_state(2, 5, 5.0e5);
    let want = sub(system.state(2, 5.0e5).position, system.state(5, 5.0e5).position);
    assert_near(across.position, want, 1e-3, "moon to moon");
    assert_eq!(system.relative_state(4, 4, 1.0), State::default());
}

#[test]
fn seeking_carries_no_state() {
    let system = system();
    let direct = system.relative_state(2, 1, 7.25e6);
    let fresh = self::system();
    for t in [0.0, 1.0e9, -4.0e7, 7.25e6 + 1.0 / 60.0, 3.0e3] {
        let _ = system.state(2, t);
        let _ = system.relative_state(5, 2, t);
    }
    assert_eq!(system.relative_state(2, 1, 7.25e6), direct, "forward and back, then the same time again");
    assert_eq!(fresh.relative_state(2, 1, 7.25e6), direct, "a system that was never asked anything else");
    // Stepping to a time tick by tick is the same question as jumping there.
    let mut last = State::default();
    for tick in 0..=600 {
        last = system.relative_state(2, 1, f64::from(tick) / 60.0);
    }
    assert_eq!(last, system.relative_state(2, 1, 10.0));
    // A whole period later the body is back.
    let orbit = system.body(2).elements;
    assert_near(orbit.state_at(1.0e5 + orbit.period_s()).position, orbit.state_at(1.0e5).position, 1e-4, "one period on");
}

#[test]
fn the_sample_is_relative_to_the_point_given() {
    let system = system();
    let offset = [6.771e6, -2.0e3, 5.0e2];
    let mut system = system;
    assert!(system.set_influence_radius(2, Some(6.6e7)));
    let (mut positions, mut gms, mut reaches) = (vec![[9.0; 3]], vec![9.0], vec![9.0]);
    system.sample(2.0e6, 1, offset, &mut positions, &mut gms, &mut reaches);
    let far = f64::INFINITY;
    assert_eq!(reaches, vec![far, far, 6.6e7, far, far, far], "a body pulls without limit unless it is given one");
    assert!(system.set_influence_radius(2, None) && system.body(2).influence_radius == far);
    assert!(!system.set_influence_radius(2, Some(-1.0)) && !system.set_influence_radius(9, Some(1.0)));
    assert!(system.set_influence_radius(2, Some(6.6e7)));
    assert_eq!(positions.len(), system.len());
    assert_eq!(positions[1], offset.map(|c| -c), "the planet is exactly behind the offset: nothing of 1e11 m is subtracted");
    assert_eq!(positions[2], sub(system.body(2).elements.state_at(2.0e6).position, offset));
    assert!((length(positions[0]) - 9.0e10).abs() < 1.0e7, "the star is one orbit's radius away");
    assert_eq!(gms, vec![GM_STAR, GM_EARTH, 4.9e12, 0.0, 1.2e17, 8.0e12], "nothing smaller than a moon pulls");
    let (mut again, mut again_gms, mut again_reaches) = (Vec::new(), Vec::new(), Vec::new());
    system.sample(2.0e6, 1, offset, &mut again, &mut again_gms, &mut again_reaches);
    assert_eq!((again, again_gms, again_reaches), (positions, gms, reaches), "same inputs, same bits");
}

#[test]
fn bad_bodies_are_refused() {
    let mut system = System::new();
    assert_eq!(system.add_body(Kind::Planet, 1.0, 0, Elements::circular(1.0e9, GM_STAR)), None, "no parent yet");
    assert_eq!(system.add_root(Kind::Star, GM_STAR), Some(0));
    assert_eq!(system.add_root(Kind::Star, GM_STAR), None, "one root");
    assert_eq!(system.add_body(Kind::Planet, 1.0, 0, elliptic(1.0e9, 1.0)), None, "not an ellipse");
    assert_eq!(system.add_body(Kind::Planet, 1.0, 0, elliptic(-1.0e9, 0.1)), None);
    assert_eq!(system.add_body(Kind::Planet, 1.0, 0, Elements::circular(1.0e9, 0.0)), None);
    assert_eq!(system.add_body(Kind::Planet, 1.0, 3, Elements::circular(1.0e9, GM_STAR)), None);
    assert_eq!(system.len(), 1);
}

#[test]
fn a_point_rides_an_orbit_at_a_phase_offset() {
    // A station on a circular orbit of the planet, its jumpgate a sixth of a turn behind and a marker as far ahead.
    let mut system = System::new();
    let star = system.add_root(Kind::Star, GM_STAR).unwrap();
    let planet = system.add_body(Kind::Planet, GM_EARTH, star, Elements::circular(9.0e10, GM_STAR)).unwrap();
    let station = system.add_body(Kind::Minor, 0.0, planet, Elements::circular(4.0e7, GM_EARTH)).unwrap();
    let gate = system.add_on_orbit(station, -PI / 3.0).unwrap();
    let ahead = system.add_on_orbit(station, PI / 3.0).unwrap();
    assert_eq!(system.body(gate).parent, Some(planet));
    assert_eq!((system.pull_gm(gate), system.body(gate).kind), (0.0, Kind::Minor), "a point pulls nothing");
    for t in [0.0, 7.0e3, 3.0e5, -2.0e4] {
        let (leader, behind) = (system.relative_state(station, planet, t), system.relative_state(gate, planet, t));
        assert!((length(behind.position) - 4.0e7).abs() < 1e-6, "on the same circle");
        let chord = length(sub(behind.position, leader.position));
        assert!((chord - 4.0e7).abs() < 1e-6, "a sixth of a turn away is one radius away: {chord}");
        assert!((length(sub(system.relative_state(ahead, gate, t).position, [0.0; 3])) - 4.0e7 * 3.0_f64.sqrt()).abs() < 1e-6);
        // Behind: the leader gets to where the point is now, later.
        assert!(cross(behind.position, leader.position)[2] > 0.0);
        // The two keep their distance: nothing between them drifts.
        assert!(length(sub(behind.velocity, leader.velocity)) - (GM_EARTH / 4.0e7).sqrt() < 1e-9);
    }
    // On an eccentric orbit the point is the leader at another time.
    let orbit = Elements { inclination: 0.2, periapsis_argument: 0.5, ..elliptic(9.6729e6, 0.3) };
    let shifted = orbit.at_phase(-0.7);
    let want = orbit.state_at(1.0e3 - 0.7 / orbit.mean_motion());
    assert_near(shifted.state_at(1.0e3).position, want.position, 1e-7, "the same orbit, earlier");
    assert_near(shifted.state_at(1.0e3).velocity, want.velocity, 1e-10, "and its velocity");
    assert_eq!(orbit.at_phase(0.0), orbit);
    // The root has no orbit to share.
    assert_eq!(system.add_on_orbit(star, 1.0), None);
    assert_eq!(system.add_on_orbit(99, 1.0), None);
    assert_eq!(system.add_on_orbit(station, f64::NAN), None);
}
