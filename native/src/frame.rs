// The free-falling frame (M6-T04, D64): the World's anchor, the tick's gravity sample taken against it, and the pull the
// local space still feels. A `UniversePos` is relative to the anchor, so the anchor is what the scene falls with: a place on
// a rail (the station), or a 64-bit test particle on an orbit. Every mover of a tick reads the one sample taken at its start,
// and the anchor's own step reads it too, last in the tick. Engine-free: 64-bit numbers in the kernel's axes (reference
// plane xy, z north); the shell converts to the game's.
//
// The velocity rebase (M6-T05, D64). The frame rides its anchor until a boost gives it a velocity of its own against the
// anchor. From then on the local origin is a free-falling point itself: it takes the pull at its own place less the
// anchor's (`origin_pull`, fixed at the sample), and a mover feels the pull at its place less the origin's, so
//   mover against the anchor = origin (kick `origin_pull`, drift) + local (kick `residual(local)`, drift)
// has the acceleration `pull(mover) - pull(anchor)` whichever frame carries it. The tick's `origin_pull` holds for the whole
// tick, through a position rebase and a boost, because the movers' forces were built with it before either.
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
    // The local origin's velocity against the anchor, zero while riding, and the pull the origin itself takes this tick.
    origin_velocity: V3,
    origin_pull: V3,
    riding: bool,
    time_s: f64,
    positions: Vec<V3>,
    gms: Vec<f64>,
    reaches: Vec<f64>,
    zones: Vec<f64>,
    pull: V3,
    active: bool,
    // Per body, how close to its centre a mover is destroyed (its radius and atmosphere's top, M6-T08); 0 for none.
    impact_radii: Vec<f64>,
}

impl Default for Frame {
    fn default() -> Frame {
        Frame {
            system: System::new(),
            a_min: gravity::A_MIN_DEFAULT,
            anchor: Anchor::None,
            origin: [0.0; 3],
            origin_velocity: [0.0; 3],
            origin_pull: [0.0; 3],
            riding: true,
            time_s: 0.0,
            positions: Vec::new(),
            gms: Vec::new(),
            reaches: Vec::new(),
            zones: Vec::new(),
            pull: [0.0; 3],
            active: false,
            impact_radii: Vec::new(),
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
    /// Takes a star system and its pull floor; the anchor is dropped until one is set again. The local origin keeps its
    /// place and its velocity: they are the local space's, whatever it falls with.
    pub fn set_system(&mut self, system: System, a_min: f64) {
        *self = Frame { system, a_min, ..self.unanchored() };
    }

    /// Back to no system and no pull; the local origin keeps its place and its velocity.
    pub fn clear(&mut self) {
        *self = self.unanchored();
    }

    fn unanchored(&self) -> Frame {
        Frame { origin: self.origin, origin_velocity: self.origin_velocity, riding: self.riding, ..Frame::default() }
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
                self.origin_pull = [0.0; 3];
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
        self.origin_pull = if self.active && !self.riding {
            gravity::residual(self.origin, &self.positions, &self.gms, &self.zones)
        } else {
            [0.0; 3]
        };
        self.active
    }

    /// What a mover at `local` (against the local origin) feels: the pull there less the frame's own, from the tick's
    /// sample. The frame's own is the anchor's while it rides, and the pull at its origin once it falls by itself.
    /// Exactly zero while the frame is quiet.
    pub fn residual(&self, local: V3) -> V3 {
        if !self.active {
            return [0.0; 3];
        }
        let offset = [self.origin[0] + local[0], self.origin[1] + local[1], self.origin[2] + local[2]];
        let r = gravity::residual(offset, &self.positions, &self.gms, &self.zones);
        [r[0] - self.origin_pull[0], r[1] - self.origin_pull[1], r[2] - self.origin_pull[2]]
    }

    /// `residual` for many movers at once (the tier's rows, the bolts): `rows` holds their local places and takes what each
    /// feels, the same bits as one `residual` per mover, so a row and a ship at one place feel one pull. Zeros while quiet.
    pub fn residual_rows(&self, rows: &mut [V3]) {
        if !self.active {
            rows.fill([0.0; 3]);
            return;
        }
        let o = self.origin;
        for r in rows.iter_mut() {
            *r = [o[0] + r[0], o[1] + r[1], o[2] + r[2]];
        }
        gravity::residual_rows_in_place(rows, &self.positions, &self.gms, &self.zones);
        let p = self.origin_pull;
        for r in rows.iter_mut() {
            *r = [r[0] - p[0], r[1] - p[1], r[2] - p[2]];
        }
    }

    /// A velocity rebase: the frame gains `dv` against the anchor and falls by itself from now on. Every local velocity
    /// loses `dv` in the same tick (the caller's part), so nothing moves differently.
    pub fn boost(&mut self, dv: V3) {
        for i in 0..3 {
            self.origin_velocity[i] += dv[i];
        }
        self.riding = false;
    }

    /// The boost that puts the frame back on its anchor, and takes it: every local velocity loses the returned `dv`.
    /// The movers' forces of this tick still hold the origin's pull, so the frame keeps the kick it owes them and is at
    /// rest against the anchor once this tick's step has run.
    pub fn boost_to_anchor(&mut self, dt: f64) -> V3 {
        let owed = [self.origin_pull[0] * dt, self.origin_pull[1] * dt, self.origin_pull[2] * dt];
        let dv = [
            -(self.origin_velocity[0] + owed[0]),
            -(self.origin_velocity[1] + owed[1]),
            -(self.origin_velocity[2] + owed[2]),
        ];
        self.origin_velocity = [0.0 - owed[0], 0.0 - owed[1], 0.0 - owed[2]];
        self.riding = true;
        dv
    }

    /// The frame's step, last in the tick, with the sample's pulls: kick, then drift, for the local origin (only off
    /// the anchor) and for the anchor. A rail moves with time alone.
    pub fn step(&mut self, dt: f64) {
        if self.origin_velocity != [0.0; 3] || self.origin_pull != [0.0; 3] {
            gravity::step(&mut self.origin, &mut self.origin_velocity, self.origin_pull, dt);
        }
        if self.riding {
            self.origin_velocity = [0.0; 3]; // the return's owed kick is paid; no rounding is left to drift on
        }
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

    /// Where the local origin is against the anchor.
    pub fn origin(&self) -> V3 {
        self.origin
    }

    /// The local origin's velocity against the anchor, as the integrator holds it; zero while the frame rides.
    pub fn origin_velocity(&self) -> V3 {
        self.origin_velocity
    }

    /// Whether the frame rides its anchor (no velocity of its own).
    pub fn riding(&self) -> bool {
        self.riding
    }

    /// Whether the last sample found anything pulling near the local space.
    pub fn active(&self) -> bool {
        self.active
    }

    /// The anchor's own pull at the last sample.
    pub fn pull(&self) -> V3 {
        self.pull
    }

    /// The pull the local origin takes this tick beyond the anchor's (zero while riding): the anchor falls with minus
    /// this in the local frame.
    pub fn origin_pull(&self) -> V3 {
        self.origin_pull
    }

    /// A body's place and velocity against the local origin and frame at the sample's time (M6-T08: what the HUD's
    /// reference reads); None with no anchor or an unknown body.
    pub fn body_local_state(&self, index: usize, dt: f64) -> Option<State> {
        if index >= self.system.len() {
            return None;
        }
        let (home, anchor) = self.anchor_state(dt)?;
        let body = self.system.relative_state(index, home, self.time_s);
        let mut state = State::default();
        for i in 0..3 {
            state.position[i] = body.position[i] - anchor.position[i] - self.origin[i];
            state.velocity[i] = body.velocity[i] - anchor.velocity[i] - self.origin_velocity[i];
        }
        Some(state)
    }

    /// The body that pulls hardest at `local` and its pull there, under the zone rule (the circular orbit's speed is read
    /// from it); None where nothing pulls or with no anchor.
    pub fn dominant_at(&self, local: V3) -> Option<(usize, V3)> {
        if matches!(self.anchor, Anchor::None) || self.positions.is_empty() {
            return None;
        }
        let at = [self.origin[0] + local[0], self.origin[1] + local[1], self.origin[2] + local[2]];
        let index = gravity::dominant(at, &self.positions, &self.gms, &self.zones)?;
        Some((index, gravity::pull_at(at, &self.positions, &self.gms, &self.zones)))
    }

    /// How close to each body's centre a mover is destroyed, by body index (0 or missing: never).
    pub fn set_impact_radii(&mut self, radii: Vec<f64>) {
        self.impact_radii = radii;
    }

    /// The body a mover at `local` has hit (within its impact radius), from the tick's sample; None while the frame is
    /// quiet, since then every zone, and so every body, is far beyond the local space.
    pub fn inside_body(&self, local: V3) -> Option<usize> {
        if !self.active {
            return None;
        }
        let at = [self.origin[0] + local[0], self.origin[1] + local[1], self.origin[2] + local[2]];
        self.positions
            .iter()
            .zip(&self.impact_radii)
            .position(|(&body, &radius)| radius > 0.0 && distance(body, at) < radius)
    }
}

#[cfg(test)]
mod tests;
