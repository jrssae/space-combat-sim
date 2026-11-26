// A carrier's docking rows for GDScript (M12-T19): the fighters one carrier is launching, calling back or drawing in, each
// keyed by its body. The maths is `dock_kernels`; GDScript (`CarrierDock`) owns the ships and applies what a step returns.
// M10-T17: a capital's hangar steps its rows with `step_bodies` instead, on the main thread: the rows read their bodies and
// the carrier from the physics server and place the bodies they hold themselves, so GDScript only hears events and steers
// the craft flying home.
// gdext's class derive writes `base: base` in the code it generates for this module.
#![allow(clippy::redundant_field_names)]
use godot::classes::PhysicsServer3D;
use godot::classes::physics_server_3d::BodyState;
use godot::prelude::*;

use crate::dock_kernels::{self as dk, Carrier, Row};
use crate::v3::{col_c, neg};

/// The docking rows of one carrier.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsDockRows {
    base: Base<RefCounted>,
    keys: Vec<i64>,
    rows: Vec<Row>,
    // Per row, the body `step_bodies` reads and places (invalid: none given) and what it brakes with, m/s2.
    bodies: Vec<(Rid, f32)>,
}

impl ScsDockRows {
    // Released and docked rows leave the table.
    fn drop_finished(&mut self, events: &[i32]) {
        for i in (0..events.len()).rev() {
            if events[i] == dk::EVENT_RELEASED || events[i] == dk::EVENT_DOCKED {
                self.keys.remove(i);
                self.rows.remove(i);
                self.bodies.remove(i);
            }
        }
    }
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
        self.bodies.push((Rid::Invalid, 0.0));
    }

    /// Puts the fighter `key` under a bay's control (M10-T17): it rests at `position` (the bay's floor point, the carrier's
    /// frame) with attitude `basis`, launches along `out_axis` for `launch_m` and returns to `approach_m` out along it; with
    /// `lift_m` over 0 a lift brings it up from that far below the floor first, and takes it down after a capture.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn add_bay(&mut self, key: i64, phase: i32, position: Vector3, basis: Basis, out_axis: Vector3, approach_m: f32, launch_m: f64,
            lift_m: f32, rest: Vector3) {
        self.remove(key);
        self.keys.push(key);
        self.rows.push(Row::bay(phase, position, basis, out_axis, approach_m, launch_m, lift_m, rest));
        self.bodies.push((Rid::Invalid, 0.0));
    }

    /// The body (a physics server RID) of the craft `key`, which `step_bodies` reads and places, and what it brakes with
    /// on its way home, m/s2.
    #[func]
    fn set_body(&mut self, key: i64, body: Rid, brake_mps2: f32) {
        if let Some(i) = self.keys.iter().position(|&k| k == key) {
            self.bodies[i] = (body, brake_mps2);
        }
    }

    /// Lets the fighter `key` go; false when it was not there.
    #[func]
    fn remove(&mut self, key: i64) -> bool {
        match self.keys.iter().position(|&k| k == key) {
            Some(i) => {
                self.keys.remove(i);
                self.rows.remove(i);
                self.bodies.remove(i);
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

    /// The lift takes the fighter `key`, waiting on a bay's floor, down to the hangar deck (M10-T17).
    #[func]
    fn begin_lower(&mut self, key: i64) {
        if let Some(i) = self.keys.iter().position(|&k| k == key) {
            self.rows[i].begin_lower();
        }
    }

    #[func]
    fn clear(&mut self) {
        self.keys.clear();
        self.rows.clear();
        self.bodies.clear();
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

    /// The phase of `key` (0 launch, 1 return, 2 capture, 3 lift, 4 lower, 5 waiting on a bay's floor), -1 when it is not there.
    #[func]
    fn phase_of(&self, key: i64) -> i32 {
        self.keys.iter().position(|&k| k == key).map_or(-1, |i| self.rows[i].phase)
    }

    /// One tick of every row. The carrier's pose, velocity and spin and each fighter's `positions`, `velocities` and
    /// braking (`brakes`, m/s2) are World-frame, in row order. Returns `[events, positions, velocities, x, y, z]`: per
    /// row its event (0 none, 1 released, 2 at its approach point, 3 docked, 4 lifted to the bay's floor, 5 in a bay waiting for its lift), the pose to set (launch, capture) or the
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
        self.drop_finished(&events);
        out.push(&PackedInt32Array::from(events.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(at.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(vel.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(xs.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(ys.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(zs.as_slice()).to_variant());
        out
    }

    /// One tick of every row whose body was given (`set_body`), the bodies read from and written to the physics server: the
    /// carrier's pose, velocity and spin from `carrier`, a returning craft's place and velocity from its own body; a craft the
    /// rows place (launching, lifted, drawn in, waiting, lowered) is set there with the carrier's spin. Returns `[events, fly_keys, fly_velocities, fly_noses]`: `events` the non-zero
    /// events as key, event pairs in row order (as `step`'s); for every craft still flying home its key, the velocity to hold
    /// and the way to face near it (World). Released and docked rows are gone after the step. A row without a body, or with
    /// no carrier, is not stepped.
    #[func]
    fn step_bodies(&mut self, delta: f64, carrier: Rid, shell_m: f32) -> VarArray {
        let mut out = VarArray::new();
        let mut server = PhysicsServer3D::singleton();
        let Some(c) = carrier.is_valid().then(|| server.body_get_direct_state(carrier)).flatten() else {
            return out;
        };
        let t = c.get_transform();
        let carrier = Carrier {
            position: t.origin,
            basis: t.basis.orthonormalized(),
            velocity: c.get_linear_velocity(),
            spin: c.get_angular_velocity(),
        };
        let n = self.rows.len();
        let mut events = vec![dk::EVENT_NONE; n];
        let mut pairs = PackedInt64Array::new();
        let mut fly_keys = PackedInt64Array::new();
        let mut fly_v = PackedVector3Array::new();
        let mut fly_nose = PackedVector3Array::new();
        for (i, event) in events.iter_mut().enumerate() {
            let (rid, brake_mps2) = self.bodies[i];
            if !rid.is_valid() {
                continue;
            }
            // Only a craft flying home is read: the rows place every other one wherever its body was.
            let flying = self.rows[i].phase == dk::PHASE_RETURN;
            let (at, v) = if flying {
                match server.body_get_direct_state(rid) {
                    Some(body) => (body.get_transform().origin, body.get_linear_velocity()),
                    None => continue,
                }
            } else {
                (Vector3::ZERO, Vector3::ZERO)
            };
            let o = dk::step_row(&mut self.rows[i], &carrier, at, v, brake_mps2, shell_m, delta);
            *event = o.event;
            if flying {
                fly_keys.push(self.keys[i]);
                fly_v.push(o.velocity);
                fly_nose.push(neg(col_c(&o.basis)));
            } else {
                server.body_set_state(rid, BodyState::TRANSFORM, &Transform3D::new(o.basis, o.position).to_variant());
                server.body_set_state(rid, BodyState::LINEAR_VELOCITY, &o.velocity.to_variant());
                server.body_set_state(rid, BodyState::ANGULAR_VELOCITY, &carrier.spin.to_variant());
            }
            if o.event != dk::EVENT_NONE {
                pairs.push(self.keys[i]);
                pairs.push(i64::from(o.event));
            }
        }
        self.drop_finished(&events);
        out.push(&pairs.to_variant());
        out.push(&fly_keys.to_variant());
        out.push(&fly_v.to_variant());
        out.push(&fly_nose.to_variant());
        out
    }

    /// The kernel's numbers, for the tests and the console: launch and capture times (s), release height, capture
    /// radius (m), capture speed (m/s), a lift's time (s) and a bay's entry speed (m/s).
    #[func]
    fn constants(&self) -> PackedFloat64Array {
        PackedFloat64Array::from(
            [dk::LAUNCH_S, dk::CAPTURE_S, dk::RELEASE_M, dk::CAPTURE_RADIUS_M, dk::CAPTURE_MPS, dk::LIFT_S, dk::BAY_ENTRY_MPS].as_slice(),
        )
    }
}
