// The ephemeris's seam to GDScript (M6-T03): builds the body tree from the loaded star system data and answers
// positions in 64-bit. All the maths stays in the engine-free kernels; this file only converts and indexes.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::ephemeris::{Elements, Kind, State, System, V3};
use crate::gravity;

/// Seven numbers per orbit, in this order: semi-major axis (m), eccentricity, inclination, ascending longitude,
/// periapsis argument, mean anomaly at epoch (rad), epoch (s).
const ORBIT_LEN: usize = 7;

fn kind_from(code: i64) -> Option<Kind> {
    match code {
        0 => Some(Kind::Star),
        1 => Some(Kind::Planet),
        2 => Some(Kind::Moon),
        3 => Some(Kind::Minor),
        _ => None,
    }
}

/// Elements around a parent of the given GM, or None for the wrong count of numbers.
fn elements_from(orbit: &[f64], parent_gm: f64) -> Option<Elements> {
    if orbit.len() != ORBIT_LEN {
        return None;
    }
    Some(Elements {
        semi_major_axis: orbit[0],
        eccentricity: orbit[1],
        inclination: orbit[2],
        ascending_longitude: orbit[3],
        periapsis_argument: orbit[4],
        mean_anomaly_at_epoch: orbit[5],
        epoch_s: orbit[6],
        parent_gm,
    })
}

fn flatten(state: State) -> Vec<f64> {
    let (p, v) = (state.position, state.velocity);
    vec![p[0], p[1], p[2], v[0], v[1], v[2]]
}

/// The body whose zone holds the point (given against `reference`'s centre) and pulls hardest there.
pub(crate) fn dominant_at(system: &System, point: V3, reference: usize, time_s: f64, a_min: f64) -> Option<usize> {
    let (mut positions, mut gms, mut reaches, mut zones) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    system.sample(time_s, reference, [0.0; 3], &mut positions, &mut gms, &mut reaches);
    gravity::zones(&gms, &reaches, a_min, &mut zones);
    gravity::dominant(point, &positions, &gms, &zones)
}

/// The star system's bodies and places for GDScript (`StarSystem` builds it from `data/star_systems.json`).
/// Bodies are addressed by the index their `add_*` call returned, or -1 when it was refused.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsEphemeris {
    base: Base<RefCounted>,
    system: System,
}

impl ScsEphemeris {
    /// The body tree, for the core's frame (M6-T04), which keeps its own copy.
    pub(crate) fn system(&self) -> &System {
        &self.system
    }
}

#[godot_api]
impl ScsEphemeris {
    /// The system's root (the star), at the origin. Kind codes: 0 star, 1 planet, 2 moon, 3 minor (a place).
    #[func]
    fn add_root(&mut self, kind: i64, gm: f64) -> i64 {
        let Some(kind) = kind_from(kind) else { return -1 };
        self.system.add_root(kind, gm).map_or(-1, |i| i as i64)
    }

    /// A body on an orbit around an earlier one; `orbit` holds the seven numbers of `ORBIT_LEN`.
    #[func]
    fn add_body(&mut self, kind: i64, gm: f64, parent: i64, orbit: PackedFloat64Array) -> i64 {
        let Some(kind) = kind_from(kind) else { return -1 };
        if parent < 0 || parent as usize >= self.system.len() {
            return -1;
        }
        let parent = parent as usize;
        let Some(elements) = elements_from(orbit.as_slice(), self.system.body(parent).gm) else { return -1 };
        self.system.add_body(kind, gm, parent, elements).map_or(-1, |i| i as i64)
    }

    /// A point with no pull on the orbit of body or place `of`, `phase_rad` ahead of it.
    #[func]
    fn add_place(&mut self, of: i64, phase_rad: f64) -> i64 {
        if of < 0 || !phase_rad.is_finite() {
            return -1;
        }
        self.system.add_on_orbit(of as usize, phase_rad).map_or(-1, |i| i as i64)
    }

    /// Caps how far a body pulls; zero or less lifts the cap.
    #[func]
    fn set_reach(&mut self, index: i64, radius_m: f64) -> bool {
        let radius = if radius_m > 0.0 { Some(radius_m) } else { None };
        index >= 0 && self.system.set_influence_radius(index as usize, radius)
    }

    #[func]
    fn body_count(&self) -> i64 {
        self.system.len() as i64
    }

    /// Period of the orbit a body or place rides, seconds; 0 for the root.
    #[func]
    fn period_s(&self, index: i64) -> f64 {
        let Some(body) = self.indexed(index) else { return 0.0 };
        if self.system.body(body).parent.is_none() {
            return 0.0;
        }
        self.system.body(body).elements.period_s()
    }

    /// Position then velocity (six numbers, m and m/s) against the root.
    #[func]
    fn state(&self, index: i64, time_s: f64) -> PackedFloat64Array {
        let Some(body) = self.indexed(index) else { return PackedFloat64Array::new() };
        PackedFloat64Array::from(flatten(self.system.state(body, time_s)))
    }

    /// Position then velocity as seen from `reference`'s centre, with no 1e11 m subtraction.
    #[func]
    fn relative_state(&self, index: i64, reference: i64, time_s: f64) -> PackedFloat64Array {
        let (Some(body), Some(reference)) = (self.indexed(index), self.indexed(reference)) else {
            return PackedFloat64Array::new();
        };
        PackedFloat64Array::from(flatten(self.system.relative_state(body, reference, time_s)))
    }

    /// How far a body's pull reaches with this floor, in metres.
    #[func]
    fn zone_radius(&self, index: i64, a_min: f64) -> f64 {
        let Some(body) = self.indexed(index) else { return 0.0 };
        let reach = self.system.body(body).influence_radius;
        gravity::zone_radius(self.system.pull_gm(body), a_min).min(reach)
    }

    /// Index of the body that dominates at `point` (three numbers against `reference`'s centre), or -1 for none.
    #[func]
    fn dominant(&self, point: PackedFloat64Array, reference: i64, time_s: f64, a_min: f64) -> i64 {
        let (Some(reference), [x, y, z]) = (self.indexed(reference), point.as_slice()) else { return -1 };
        dominant_at(&self.system, [*x, *y, *z], reference, time_s, a_min).map_or(-1, |i| i as i64)
    }

    fn indexed(&self, index: i64) -> Option<usize> {
        (index >= 0 && (index as usize) < self.system.len()).then_some(index as usize)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const GM_STAR: f64 = 1.088e20;
    const GM_PLANET: f64 = 1.68e14;

    fn system() -> System {
        let mut s = System::new();
        s.add_root(Kind::Star, GM_STAR);
        let planet = s.add_body(Kind::Planet, GM_PLANET, 0, Elements::circular(8.976e10, GM_STAR)).unwrap();
        s.add_body(Kind::Minor, 0.0, planet, Elements::circular(2.75e7, GM_PLANET)).unwrap();
        s
    }

    #[test]
    fn a_wrong_count_of_orbit_numbers_is_refused() {
        assert!(elements_from(&[1.0; 6], 1.0).is_none());
        assert!(elements_from(&[1.0; 7], 1.0).is_some());
    }

    #[test]
    fn kind_codes_map_and_unknown_codes_are_refused() {
        assert_eq!(kind_from(1), Some(Kind::Planet));
        assert_eq!(kind_from(4), None);
    }

    #[test]
    fn the_planet_dominates_inside_its_zone_and_the_star_far_in() {
        let s = system();
        // The planet's zone ends where its pull falls to 0.5 m/s^2: 18 300 km.
        assert_eq!(dominant_at(&s, [1.0e7, 0.0, 0.0], 1, 0.0, 0.5), Some(1));
        // At the station's 27 500 km the planet's pull is 0.22 m/s^2, under the floor, and nothing else reaches.
        assert_eq!(dominant_at(&s, [2.75e7, 0.0, 0.0], 1, 0.0, 0.5), None);
        // Towards the star the star's own zone (14.7 million km) takes over.
        assert_eq!(dominant_at(&s, [-8.0e10, 0.0, 0.0], 1, 0.0, 0.5), Some(0));
    }
}
