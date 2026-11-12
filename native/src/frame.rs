// The free-falling frame (M6-T04, D64): the World's anchor, the tick's gravity sample taken against it, and the pull the
// local space still feels. A `UniversePos` is relative to the anchor, so the anchor is what the scene falls with: a place on
// a rail (the station), or a 64-bit test particle on an orbit. Every mover of a tick reads the one sample taken at its start,
// and the anchor's own step reads it too, last in the tick. Engine-free: 64-bit numbers in the kernel's axes (reference
// plane xy, z north); the shell converts to the game's.
use crate::ephemeris::{State, System, V3};
use crate::gravity;

/// How far beyond the local origin every zone must stay for the frame to be quiet: nothing in the local space then feels a
/// pull, so the movers skip the residual. 1 000 km is the farthest broadcast (the jumpgate's), the farthest anything is
/// simulated from the player.
pub const QUIET_MARGIN_M: f64 = 1.0e6;

/// What the frame falls with.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Anchor {
    /// No star system: nothing pulls.
    None,
    /// A place on a rail (the station): the ephemeris gives its state at the tick's time.
    Rail { place: usize },
    /// A test particle held against `home`'s centre; its velocity is held half a kick behind, as the integrator keeps it.
    Particle { home: usize, position: V3, velocity: V3 },
}

/// The World's frame: its star system, its anchor, where the local origin is against the anchor, and the tick's sample.
#[derive(Clone, Debug)]
pub struct Frame {
    system: System,
    a_min: f64,
    anchor: Anchor,
    origin: V3,
    time_s: f64,
    positions: Vec<V3>,
    gms: Vec<f64>,
    reaches: Vec<f64>,
    zones: Vec<f64>,
    pull: V3,
    active: bool,
}

impl Default for Frame {
    fn default() -> Frame {
        Frame {
            system: System::new(),
            a_min: gravity::A_MIN_DEFAULT,
            anchor: Anchor::None,
            origin: [0.0; 3],
            time_s: 0.0,
            positions: Vec::new(),
            gms: Vec::new(),
            reaches: Vec::new(),
            zones: Vec::new(),
            pull: [0.0; 3],
            active: false,
        }
    }
}

fn is_finite(v: V3) -> bool {
    v.iter().all(|c| c.is_finite())
}

fn distance(a: V3, b: V3) -> f64 {
    let d = [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt()
}

impl Frame {
    /// Takes a star system and its pull floor; the anchor is dropped until one is set again.
    pub fn set_system(&mut self, system: System, a_min: f64) {
        *self = Frame { system, a_min, ..Frame::default() };
    }

    /// Back to no system and no pull.
    pub fn clear(&mut self) {
        *self = Frame::default();
    }

    /// Anchors on a place or body's rail. False for an unknown index.
    pub fn anchor_on_rail(&mut self, place: usize) -> bool {
        if place >= self.system.len() {
            return false;
        }
        self.anchor = Anchor::Rail { place };
        self.active = false;
        true
    }

    /// Anchors on a test particle at `position` with `velocity` against `home`'s centre at `time_s`. The velocity is moved
    /// half a kick back with the pull there, which is where the step holds it (without that an orbit starts hundreds of
    /// metres off its path). False for an unknown home or a number that is not finite.
    pub fn anchor_in_orbit(&mut self, home: usize, position: V3, velocity: V3, time_s: f64, dt: f64) -> bool {
        if home >= self.system.len() || !is_finite(position) || !is_finite(velocity) || !time_s.is_finite() {
            return false;
        }
        self.anchor = Anchor::Particle { home, position, velocity };
        self.sample(time_s);
        let held = gravity::half_kick_back(velocity, self.pull, dt);
        self.anchor = Anchor::Particle { home, position, velocity: held };
        true
    }

    /// Where the local origin is against the anchor (the World's `origin`).
    pub fn set_origin(&mut self, origin: V3) {
        self.origin = origin;
    }

    /// The tick's gravity sample: the bodies placed against the anchor at `time_s`, their zones, the anchor's own pull, and
    /// whether anything near the local space pulls at all. Returns that last answer.
    pub fn sample(&mut self, time_s: f64) -> bool {
        self.time_s = time_s;
        let (reference, offset) = match self.anchor {
            Anchor::None => {
                self.positions.clear();
                self.pull = [0.0; 3];
                self.active = false;
                return false;
            }
            Anchor::Rail { place } => (place, [0.0; 3]),
            Anchor::Particle { home, position, .. } => (home, position),
        };
        self.system.sample(time_s, reference, offset, &mut self.positions, &mut self.gms, &mut self.reaches);
        gravity::zones(&self.gms, &self.reaches, self.a_min, &mut self.zones);
        self.pull = gravity::pull_at([0.0; 3], &self.positions, &self.gms, &self.zones);
        let near = self
            .positions
            .iter()
            .zip(&self.gms)
            .zip(&self.zones)
            .any(|((&body, &gm), &zone)| gm > 0.0 && zone > 0.0 && distance(body, self.origin) - zone < QUIET_MARGIN_M);
        self.active = near || self.pull != [0.0; 3];
        self.active
    }

    /// What a mover at `local` (against the local origin) feels: the pull there less the anchor's, from the tick's sample.
    /// Exactly zero while the frame is quiet.
    pub fn residual(&self, local: V3) -> V3 {
        if !self.active {
            return [0.0; 3];
        }
        let offset = [self.origin[0] + local[0], self.origin[1] + local[1], self.origin[2] + local[2]];
        gravity::residual(offset, &self.positions, &self.gms, &self.zones)
    }

    /// The anchor's own step, last in the tick, with the sample's pull: kick, then drift. A rail moves with time alone.
    pub fn step(&mut self, dt: f64) {
        if let Anchor::Particle { home, mut position, mut velocity } = self.anchor {
            gravity::step(&mut position, &mut velocity, self.pull, dt);
            self.anchor = Anchor::Particle { home, position, velocity };
        }
    }

    /// The anchor's state against the centre of the body it orbits, and that body's index; None with no anchor. A
    /// particle's velocity is brought to the tick from where the integrator holds it, with the sample's pull.
    pub fn anchor_state(&self, dt: f64) -> Option<(usize, State)> {
        match self.anchor {
            Anchor::None => None,
            Anchor::Rail { place } => {
                let home = self.system.body(place).parent.unwrap_or(place);
                Some((home, self.system.relative_state(place, home, self.time_s)))
            }
            Anchor::Particle { home, position, velocity } => {
                let velocity = gravity::velocity_at_tick(velocity, self.pull, dt);
                Some((home, State { position, velocity }))
            }
        }
    }

    pub fn anchor(&self) -> Anchor {
        self.anchor
    }

    /// Whether the last sample found anything pulling near the local space.
    pub fn active(&self) -> bool {
        self.active
    }

    /// The anchor's own pull at the last sample.
    pub fn pull(&self) -> V3 {
        self.pull
    }
}

#[cfg(test)]
mod tests;
