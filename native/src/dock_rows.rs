// A carrier's docking rows for GDScript (M12-T19): the fighters one carrier is launching, calling back or drawing in, each
// keyed by its body. The maths is `dock_kernels`; GDScript (`CarrierDock`) owns the ships and applies what a step returns.
// gdext's class derive writes `base: base` in the code it generates for this module.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::dock_kernels::{self as dk, Carrier, Row};

/// The docking rows of one carrier.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsDockRows {
    base: Base<RefCounted>,
    keys: Vec<i64>,
    rows: Vec<Row>,
}

#[godot_api]
impl ScsDockRows {
    /// Puts the fighter `key` under the dock's control in `phase` (0 launch, 1 return) on a cradle given in the carrier's
    /// frame; `rest` is the point of the fighter that meets the pad. A key already there is replaced.
    #[func]
    fn add(&mut self, key: i64, phase: i32, cradle_position: Vector3, cradle_basis: Basis, approach_m: f32, rest: Vector3) {
        self.remove(key);
        self.keys.push(key);
        self.rows.push(Row::new(phase, cradle_position, cradle_basis, approach_m, rest));
    }

    /// Lets the fighter `key` go; false when it was not there.
    #[func]
    fn remove(&mut self, key: i64) -> bool {
        match self.keys.iter().position(|&k| k == key) {
            Some(i) => {
                self.keys.remove(i);
                self.rows.remove(i);
                true
            }
            None => false,
        }
    }

    /// The cradle takes a returning fighter from where it is (the carrier's frame).
    #[func]
    fn begin_capture(&mut self, key: i64, position: Vector3, basis: Basis) {
        if let Some(i) = self.keys.iter().position(|&k| k == key) {
            self.rows[i].begin_capture(position, basis);
        }
    }

    #[func]
    fn clear(&mut self) {
        self.keys.clear();
        self.rows.clear();
    }

    #[func]
    fn count(&self) -> i64 {
        self.rows.len() as i64
    }

    /// The fighters in row order: the order `step` answers in.
    #[func]
    fn keys(&self) -> PackedInt64Array {
        PackedInt64Array::from(self.keys.as_slice())
    }

    /// The phase of `key` (0 launch, 1 return, 2 capture), -1 when it is not there.
    #[func]
    fn phase_of(&self, key: i64) -> i32 {
        self.keys.iter().position(|&k| k == key).map_or(-1, |i| self.rows[i].phase)
    }

    /// One tick of every row. The carrier's pose, velocity and spin and each fighter's `positions`, `velocities` and
    /// braking (`brakes`, m/s2) are World-frame, in row order. Returns `[events, positions, velocities, x, y, z]`: per
    /// row its event (0 none, 1 released, 2 at its approach point, 3 docked), the pose to set (launch, capture) or the
    /// point flown to (return), the velocity to set or to hold, and the attitude's three axes. Released and docked rows
    /// are gone after the step.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn step(
        &mut self,
        delta: f64,
        carrier_position: Vector3,
        carrier_basis: Basis,
        carrier_velocity: Vector3,
        carrier_spin: Vector3,
        shell_m: f32,
        positions: PackedVector3Array,
        velocities: PackedVector3Array,
        brakes: PackedFloat32Array,
    ) -> VarArray {
        let n = self.rows.len();
        let mut out = VarArray::new();
        if positions.len() != n || velocities.len() != n || brakes.len() != n {
            godot_error!("ScsDockRows.step: {} rows but {} positions, {} velocities, {} brakes; nothing stepped", n, positions.len(),
                velocities.len(), brakes.len());
            return out;
        }
        let carrier = Carrier { position: carrier_position, basis: carrier_basis, velocity: carrier_velocity, spin: carrier_spin };
        let (p, v, b) = (positions.as_slice(), velocities.as_slice(), brakes.as_slice());
        let mut events = Vec::with_capacity(n);
        let mut at = Vec::with_capacity(n);
        let mut vel = Vec::with_capacity(n);
        let (mut xs, mut ys, mut zs) = (Vec::with_capacity(n), Vec::with_capacity(n), Vec::with_capacity(n));
        for i in 0..n {
            let o = dk::step_row(&mut self.rows[i], &carrier, p[i], v[i], b[i], shell_m, delta);
            events.push(o.event);
            at.push(o.position);
            vel.push(o.velocity);
            xs.push(o.basis.col_a());
            ys.push(o.basis.col_b());
            zs.push(o.basis.col_c());
        }
        for i in (0..n).rev() {
            if events[i] == dk::EVENT_RELEASED || events[i] == dk::EVENT_DOCKED {
                self.keys.remove(i);
                self.rows.remove(i);
            }
        }
        out.push(&PackedInt32Array::from(events.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(at.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(vel.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(xs.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(ys.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(zs.as_slice()).to_variant());
        out
    }

    /// The kernel's numbers, for the tests and the console: launch and capture times (s), release height, capture
    /// radius (m) and capture speed (m/s).
    #[func]
    fn constants(&self) -> PackedFloat64Array {
        PackedFloat64Array::from([dk::LAUNCH_S, dk::CAPTURE_S, dk::RELEASE_M, dk::CAPTURE_RADIUS_M, dk::CAPTURE_MPS].as_slice())
    }
}
