// The ephemeris (M6-T02, D65): where every star, planet and moon is at any sim time. Each body rides a Kepler orbit
// around its parent, evaluated directly from the time, so the answer never depends on what was asked before (M9's
// warp can jump). 64-bit throughout, and answers are given relative to a body so no caller subtracts two numbers of
// 1e11 m. Axes: the reference plane is xy, z its north; the binding maps them to the game's. Engine-free by
// construction (test_sim_core reads this file): plain numbers in, plain numbers out, no statics.
#![allow(dead_code)] // partly wired in by M6-T04 (the frame); the rest by M6-T07

use std::f64::consts::{PI, TAU};

pub type V3 = [f64; 3];

/// Newton steps taken for every solve, converged or not, so a time always gives the same bits.
pub const KEPLER_STEPS: usize = 24;
/// The most eccentric orbit accepted; the solve is tested up to here.
pub const MAX_ECCENTRICITY: f64 = 0.99;

/// One elliptic orbit around a parent. Angles in radians, lengths in metres, times in sim seconds.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Elements {
    pub semi_major_axis: f64,
    pub eccentricity: f64,
    pub inclination: f64,
    /// Longitude of the ascending crossing of the reference plane.
    pub ascending_longitude: f64,
    pub periapsis_argument: f64,
    pub mean_anomaly_at_epoch: f64,
    pub epoch_s: f64,
    /// The parent's GM, m^3/s^2.
    pub parent_gm: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct State {
    pub position: V3,
    pub velocity: V3,
}

/// What a body is. Only stars, planets and moons pull (nothing smaller ever does).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Star,
    Planet,
    Moon,
    Minor,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Body {
    pub kind: Kind,
    pub gm: f64,
    pub parent: Option<usize>,
    /// Unused for the root, which sits at the system's origin.
    pub elements: Elements,
    /// How far the body pulls, metres from its centre; unbounded unless set.
    pub influence_radius: f64,
    depth: u32,
}

/// The body tree. Parents are added before their children; the first body is the root.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct System {
    bodies: Vec<Body>,
}

fn add(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

fn sub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

impl Elements {
    /// A circular orbit in the reference plane, starting on the x axis at time zero.
    pub fn circular(radius: f64, parent_gm: f64) -> Elements {
        Elements {
            semi_major_axis: radius,
            eccentricity: 0.0,
            inclination: 0.0,
            ascending_longitude: 0.0,
            periapsis_argument: 0.0,
            mean_anomaly_at_epoch: 0.0,
            epoch_s: 0.0,
            parent_gm,
        }
    }

    /// The same orbit, a fixed angle ahead (or behind, if negative) in mean anomaly: where a station's jumpgate
    /// rides, or a point that leads or trails a body on its orbit.
    pub fn at_phase(&self, phase_rad: f64) -> Elements {
        Elements { mean_anomaly_at_epoch: self.mean_anomaly_at_epoch + phase_rad, ..*self }
    }

    pub fn is_valid(&self) -> bool {
        self.semi_major_axis > 0.0
            && self.parent_gm > 0.0
            && (0.0..=MAX_ECCENTRICITY).contains(&self.eccentricity)
            && self.inclination.is_finite()
            && self.ascending_longitude.is_finite()
            && self.periapsis_argument.is_finite()
            && self.mean_anomaly_at_epoch.is_finite()
            && self.epoch_s.is_finite()
    }

    /// Radians per second.
    pub fn mean_motion(&self) -> f64 {
        (self.parent_gm / (self.semi_major_axis * self.semi_major_axis * self.semi_major_axis)).sqrt()
    }

    pub fn period_s(&self) -> f64 {
        TAU / self.mean_motion()
    }

    /// Where the body is around its parent at a time, and how fast.
    pub fn state_at(&self, time_s: f64) -> State {
        let a = self.semi_major_axis;
        let e = self.eccentricity;
        let mean = self.mean_anomaly_at_epoch + self.mean_motion() * (time_s - self.epoch_s);
        let (sin_e, cos_e) = solve_kepler(mean, e).sin_cos();
        // In the orbit's own plane, x towards periapsis.
        let minor = (1.0 - e * e).sqrt();
        let rate = (self.parent_gm * a).sqrt() / (a * (1.0 - e * cos_e));
        let (px, py) = (a * (cos_e - e), a * minor * sin_e);
        let (vx, vy) = (-rate * sin_e, rate * minor * cos_e);
        // Turn the plane into the reference axes: periapsis, tilt, then the crossing's longitude.
        let (sw, cw) = self.periapsis_argument.sin_cos();
        let (si, ci) = self.inclination.sin_cos();
        let (so, co) = self.ascending_longitude.sin_cos();
        let p = [co * cw - so * sw * ci, so * cw + co * sw * ci, sw * si];
        let q = [-co * sw - so * cw * ci, -so * sw + co * cw * ci, cw * si];
        State {
            position: [px * p[0] + py * q[0], px * p[1] + py * q[1], px * p[2] + py * q[2]],
            velocity: [vx * p[0] + vy * q[0], vx * p[1] + vy * q[1], vx * p[2] + vy * q[2]],
        }
    }
}

/// The eccentric anomaly for a mean anomaly (Kepler's equation, E - e sin E = M), in [-pi, pi].
/// The start is at or above the root on the half turn where the equation curves upward, so every Newton step
/// moves down towards it and none overshoots, however eccentric the orbit.
pub fn solve_kepler(mean_anomaly: f64, eccentricity: f64) -> f64 {
    let wrapped = (mean_anomaly + PI).rem_euclid(TAU) - PI;
    let m = wrapped.abs();
    let mut x = (m + eccentricity).min(PI);
    for _ in 0..KEPLER_STEPS {
        x -= (x - eccentricity * x.sin() - m) / (1.0 - eccentricity * x.cos());
    }
    if wrapped < 0.0 {
        -x
    } else {
        x
    }
}

impl System {
    pub fn new() -> System {
        System::default()
    }

    pub fn len(&self) -> usize {
        self.bodies.len()
    }

    pub fn is_empty(&self) -> bool {
        self.bodies.is_empty()
    }

    pub fn body(&self, index: usize) -> &Body {
        &self.bodies[index]
    }

    /// The body every other one hangs from, at the origin. Returns its index, or None if there is one already.
    pub fn add_root(&mut self, kind: Kind, gm: f64) -> Option<usize> {
        if !self.bodies.is_empty() {
            return None;
        }
        let unused = Elements::circular(1.0, 1.0);
        self.bodies.push(Body { kind, gm, parent: None, elements: unused, influence_radius: f64::INFINITY, depth: 0 });
        Some(0)
    }

    /// A body in orbit around one already added. Returns its index, or None for a bad parent or orbit.
    pub fn add_body(&mut self, kind: Kind, gm: f64, parent: usize, elements: Elements) -> Option<usize> {
        if parent >= self.bodies.len() || !elements.is_valid() {
            return None;
        }
        let depth = self.bodies[parent].depth + 1;
        self.bodies.push(Body { kind, gm, parent: Some(parent), elements, influence_radius: f64::INFINITY, depth });
        Some(self.bodies.len() - 1)
    }

    /// A point with no pull that shares a body's orbit at a phase offset. Returns its index, or None for the root
    /// (it has no orbit) or a bad index or angle.
    pub fn add_on_orbit(&mut self, of: usize, phase_rad: f64) -> Option<usize> {
        let leader = *self.bodies.get(of)?;
        self.add_body(Kind::Minor, 0.0, leader.parent?, leader.elements.at_phase(phase_rad))
    }

    /// Limits how far a body pulls; None lifts the limit again. False for a radius that is not a distance.
    pub fn set_influence_radius(&mut self, index: usize, radius: Option<f64>) -> bool {
        let radius = radius.unwrap_or(f64::INFINITY);
        if index >= self.bodies.len() || radius.is_nan() || radius <= 0.0 {
            return false;
        }
        self.bodies[index].influence_radius = radius;
        true
    }

    /// The GM a body pulls with: zero for anything smaller than a moon.
    pub fn pull_gm(&self, index: usize) -> f64 {
        let body = &self.bodies[index];
        match body.kind {
            Kind::Minor => 0.0,
            _ => body.gm.max(0.0),
        }
    }

    /// A body's state against the root (barycentric). Only for display and far maths: it loses the small digits.
    pub fn state(&self, index: usize, time_s: f64) -> State {
        self.relative_state(index, 0, time_s)
    }

    /// A body's state as seen from another body's centre. Only the orbits between the two are summed, so a moon
    /// seen from its planet keeps its full precision however far the star is.
    pub fn relative_state(&self, index: usize, reference: usize, time_s: f64) -> State {
        let (mut a, mut b) = (index, reference);
        let (mut up, mut down) = (State::default(), State::default());
        while a != b {
            if self.bodies[a].depth >= self.bodies[b].depth {
                a = self.climb(a, time_s, &mut up);
            } else {
                b = self.climb(b, time_s, &mut down);
            }
        }
        State { position: sub(up.position, down.position), velocity: sub(up.velocity, down.velocity) }
    }

    // Adds a body's orbit to a running sum and returns its parent.
    fn climb(&self, index: usize, time_s: f64, sum: &mut State) -> usize {
        let body = &self.bodies[index];
        let step = body.elements.state_at(time_s);
        sum.position = add(sum.position, step.position);
        sum.velocity = add(sum.velocity, step.velocity);
        body.parent.unwrap_or(0)
    }

    /// The tick's gravity sample: every body's place against a point (a body's centre plus an offset), the GM it
    /// pulls with and its influence radius, in body order. The lists are what the gravity kernel reads, frozen for
    /// the tick; it turns the radii into zones.
    pub fn sample(
        &self,
        time_s: f64,
        reference: usize,
        offset: V3,
        positions: &mut Vec<V3>,
        gms: &mut Vec<f64>,
        reaches: &mut Vec<f64>,
    ) {
        positions.clear();
        gms.clear();
        reaches.clear();
        for index in 0..self.bodies.len() {
            positions.push(sub(self.relative_state(index, reference, time_s).position, offset));
            gms.push(self.pull_gm(index));
            reaches.push(self.bodies[index].influence_radius);
        }
    }
}

#[cfg(test)]
mod tests;
