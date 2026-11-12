// The free-falling frame's shell on the core (M6-T04, D64): GDScript sets the star system and the anchor, the World takes the
// tick's sample first in the tick and steps the anchor last, and the flight step reads the residual per ship. Converts
// between the game's axes (y up) and the kernel's (z north): kernel (x, y, z) = game (x, -z, y), both right-handed.
use godot::prelude::*;

use crate::ephemeris::V3;
use crate::ephemeris_binding::ScsEphemeris;
use crate::frame::Anchor;
use crate::sim_core::ScsSimCore;

fn to_kernel(x: f64, y: f64, z: f64) -> V3 {
    [x, -z, y]
}

fn to_game(v: V3) -> [f64; 3] {
    [v[0] + 0.0, v[2] + 0.0, 0.0 - v[1]] // never a negative zero: a frame at rest reads as plain zeros
}

fn game_vector(v: V3) -> Vector3 {
    let g = to_game(v);
    Vector3::new(g[0] as f32, g[1] as f32, g[2] as f32)
}

impl ScsSimCore {
    /// What a mover at `local` (World coordinates) feels from the frame this tick, or None while the frame is quiet, so a
    /// caller adds nothing and keeps today's bits.
    pub(crate) fn frame_residual_at(&self, local: Vector3) -> Option<Vector3> {
        if !self.frame.active() {
            return None;
        }
        let at = to_kernel(f64::from(local.x), f64::from(local.y), f64::from(local.z));
        Some(game_vector(self.frame.residual(at)))
    }

    /// The local frame's velocity against its anchor, in 32 bits for the drawing; zero while it rides.
    pub(crate) fn frame_velocity(&self) -> Vector3 {
        game_vector(self.frame.origin_velocity())
    }
}

#[godot_api(secondary)]
impl ScsSimCore {
    /// The star system the frame falls in, copied from `ephemeris`, with its pull floor (m/s^2). The anchor is dropped.
    #[func]
    fn frame_set_system(&mut self, ephemeris: Gd<ScsEphemeris>, a_min: f64) {
        let system = ephemeris.bind().system().clone();
        self.frame.set_system(system, a_min);
    }

    /// No star system: nothing pulls.
    #[func]
    fn frame_clear(&mut self) {
        self.frame.clear();
    }

    /// Anchors the frame on a place or body's rail (an ephemeris index). False for an unknown index.
    #[func]
    fn frame_anchor_on_rail(&mut self, place: i64) -> bool {
        usize::try_from(place).is_ok_and(|p| self.frame.anchor_on_rail(p))
    }

    /// Anchors the frame on a free-falling particle: `state` is position then velocity (six numbers, m and m/s, game axes)
    /// against body `home`'s centre at `time_s`; `dt` is the physics tick it will be stepped with.
    #[func]
    fn frame_anchor_in_orbit(&mut self, home: i64, state: PackedFloat64Array, time_s: f64, dt: f64) -> bool {
        let (Ok(home), [px, py, pz, vx, vy, vz]) = (usize::try_from(home), state.as_slice()) else {
            return false;
        };
        let (position, velocity) = (to_kernel(*px, *py, *pz), to_kernel(*vx, *vy, *vz));
        self.frame.anchor_in_orbit(home, position, velocity, time_s, dt)
    }

    /// Where the World's local origin is against the anchor, metres (the World's `origin`, game axes).
    #[func]
    fn frame_set_origin(&mut self, x: f64, y: f64, z: f64) {
        self.frame.set_origin(to_kernel(x, y, z));
    }

    /// The tick's gravity sample at sim time `time_s`; true when anything near the local space pulls.
    #[func]
    fn frame_sample(&mut self, time_s: f64) -> bool {
        self.frame.sample(time_s)
    }

    /// The frame's step, last in the tick: the anchor, and the local origin while it is off the anchor.
    #[func]
    fn frame_step(&mut self, dt: f64) {
        self.frame.step(dt);
    }

    /// A velocity rebase (D64): the frame gains `dv` (m/s, game axes) against its anchor, and every velocity the core
    /// holds loses it. The caller takes the same `dv` off every body and node.
    #[func]
    fn boost(&mut self, dv: Vector3) {
        self.frame.boost(to_kernel(f64::from(dv.x), f64::from(dv.y), f64::from(dv.z)));
        self.boost_rows(dv);
    }

    /// The velocity rebase back onto the anchor: returns the `dv` it took off every velocity the core holds, for the
    /// caller to take off every body and node. `dt` is the tick the frame is stepped with.
    #[func]
    fn boost_to_anchor(&mut self, dt: f64) -> Vector3 {
        let dv = game_vector(self.frame.boost_to_anchor(dt));
        self.boost_rows(dv);
        dv
    }

    /// Where the local origin is against the anchor, metres (three numbers, game axes, 64-bit).
    #[func]
    fn frame_origin(&self) -> PackedFloat64Array {
        PackedFloat64Array::from(&to_game(self.frame.origin())[..])
    }

    /// The local origin's velocity against the anchor, m/s (three numbers, game axes, 64-bit); zero while riding.
    #[func]
    fn frame_origin_velocity(&self) -> PackedFloat64Array {
        PackedFloat64Array::from(&to_game(self.frame.origin_velocity())[..])
    }

    /// Whether the frame rides its anchor.
    #[func]
    fn frame_riding(&self) -> bool {
        self.frame.riding()
    }

    /// Whether the last sample found anything pulling near the local space.
    #[func]
    fn frame_active(&self) -> bool {
        self.frame.active()
    }

    /// The residual at `local` (World coordinates, m/s^2); zero while the frame is quiet.
    #[func]
    fn frame_residual(&self, local: Vector3) -> Vector3 {
        self.frame_residual_at(local).unwrap_or(Vector3::ZERO)
    }

    /// What the frame falls with: `none`, `rail` (a place's orbit) or `orbit` (a free-falling particle).
    #[func]
    fn frame_anchor_kind(&self) -> GString {
        GString::from(match self.frame.anchor() {
            Anchor::None => "none",
            Anchor::Rail { .. } => "rail",
            Anchor::Particle { .. } => "orbit",
        })
    }

    /// The ephemeris index of the anchor's place, or of the body its particle circles; -1 for none.
    #[func]
    fn frame_anchor_index(&self) -> i64 {
        match self.frame.anchor() {
            Anchor::None => -1,
            Anchor::Rail { place } => place as i64,
            Anchor::Particle { home, .. } => home as i64,
        }
    }

    /// The anchor's own pull at the last sample, m/s^2 (game axes).
    #[func]
    fn frame_pull(&self) -> Vector3 {
        game_vector(self.frame.pull())
    }

    /// The anchor against the centre of the body it orbits: that body's ephemeris index, then position and velocity (seven
    /// numbers, m and m/s, game axes, 64-bit); empty with no anchor. `dt` is the tick the frame is stepped with.
    #[func]
    fn frame_anchor_state(&self, dt: f64) -> PackedFloat64Array {
        let Some((home, state)) = self.frame.anchor_state(dt) else {
            return PackedFloat64Array::new();
        };
        let (p, v) = (to_game(state.position), to_game(state.velocity));
        PackedFloat64Array::from(&[home as f64, p[0], p[1], p[2], v[0], v[1], v[2]][..])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_axes_map_both_ways_and_keep_up_as_north() {
        assert_eq!(to_kernel(0.0, 1.0, 0.0), [0.0, 0.0, 1.0], "the game's up is the kernel's north");
        assert_eq!(to_kernel(0.0, 0.0, -1.0), [0.0, 1.0, 0.0], "the game's forward is the kernel's y");
        let g = [3.0, -4.0, 5.0];
        let back = to_game(to_kernel(g[0], g[1], g[2]));
        assert_eq!(back, g);
    }
}
