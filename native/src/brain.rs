// The native brain host (M4-T17, docs/architecture.md 17.13): the AI pilots' brains on the core's rows. The maths lives in
// `brain_maths.rs` and the behaviours in `brain_behaviours.rs` (both engine-free); this class binds the core, keeps one
// slot per pilot and hands answers over. T17a: the maths behind `test_brain_parity`; T17b adds the brains.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::brain_maths::{
    self, Capability, FlightCmd, Manoeuvre, Pcg, Pose, Temperament, deg_to_rad_lerp,
};
use crate::kernels::contact::{self, Work};
use crate::sim_core::ScsSimCore;

// `test_brain_parity`'s per-step layouts for a manoeuvre run.
const STEP_IN: usize = 23;
const STEP_OUT: usize = 16;

/// The AI pilots' native brains over the core's rows.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsBrains {
    base: Base<RefCounted>,
    core: Option<Gd<ScsSimCore>>,
    grid: Work,
    grid_version: i64,
}

#[godot_api]
impl ScsBrains {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Reads the core's rows from now on.
    #[func]
    fn attach_core(&mut self, core: Gd<ScsSimCore>, cell_m: f64) -> bool {
        self.grid = Work::default();
        self.grid.cell_m = cell_m;
        self.grid_version = -1;
        self.core = Some(core);
        self.refresh_grid();
        true
    }

    /// Whether the host reads a core.
    #[func]
    fn on_core(&self) -> bool {
        self.core.is_some()
    }

    // --- the maths, for the differential tests ---------------------------------------------------------------------

    /// `hash([seed, label])`.
    #[func]
    fn hash_seed(seed: i64, label: GString) -> i64 {
        brain_maths::hash_seed(seed, &label.to_string())
    }

    /// The first `count` `randi()` draws of a generator seeded with `seed`.
    #[func]
    fn randi_sequence(seed: i64, count: i64) -> PackedInt64Array {
        let mut rng = Pcg::seeded(seed);
        (0..count.max(0))
            .map(|_| i64::from(rng.randi()))
            .collect::<Vec<i64>>()
            .as_slice()
            .into()
    }

    /// The first `count` `randf()` draws of a generator seeded with `seed`.
    #[func]
    fn randf_sequence(seed: i64, count: i64) -> PackedFloat64Array {
        let mut rng = Pcg::seeded(seed);
        (0..count.max(0))
            .map(|_| f64::from(rng.randf()))
            .collect::<Vec<f64>>()
            .as_slice()
            .into()
    }

    /// The first `count` `randf_range` draws over the test's six bounds in turn.
    #[func]
    fn randf_range_sequence(seed: i64, count: i64) -> PackedFloat64Array {
        const BOUNDS: [(f32, f32); 6] = [
            (0.05, 0.15),
            (0.15, 0.35),
            (0.0, std::f32::consts::TAU),
            (-45.0, 45.0),
            (2.0, 4.0),
            (-62.0, 62.0),
        ];
        let mut rng = Pcg::seeded(seed);
        (0..count.max(0) as usize)
            .map(|i| {
                let (a, b) = BOUNDS[i % BOUNDS.len()];
                f64::from(rng.randf_range(a, b))
            })
            .collect::<Vec<f64>>()
            .as_slice()
            .into()
    }

    /// `[deg_to_rad(x), rad_to_deg(x), lerpf(x, b, t)]`.
    #[func]
    fn angle_helpers(x: f64, b: f64, t: f64) -> PackedFloat64Array {
        PackedFloat64Array::from(&deg_to_rad_lerp(x, b, t)[..])
    }

    /// `[angle_to, face, face_tracking, align_roll]` of `PilotSteering`.
    #[func]
    fn steering_face(
        basis: Basis,
        direction: Vector3,
        omega: Vector3,
        rate_max: Vector3,
        gain: f64,
    ) -> VarArray {
        let mut out = VarArray::new();
        out.push(&brain_maths::angle_to(&basis, direction).to_variant());
        out.push(&brain_maths::face(&basis, direction, rate_max, gain).to_variant());
        out.push(
            &brain_maths::face_tracking(&basis, direction, omega, rate_max, gain).to_variant(),
        );
        out.push(&brain_maths::align_roll(&basis, direction, rate_max, gain).to_variant());
        out
    }

    /// `PilotSteering.seek` as `[main, retro, strafe]`; `cap` as `capability_of` reads it.
    #[func]
    fn steering_seek(
        velocity: Vector3,
        v_des: Vector3,
        basis: Basis,
        cap: PackedFloat64Array,
        horizon_s: f64,
        all_axes: bool,
    ) -> VarArray {
        let s = brain_maths::seek(
            velocity,
            v_des,
            &basis,
            &capability_of(&cap),
            horizon_s,
            all_axes,
        );
        let mut out = VarArray::new();
        out.push(&s.main.to_variant());
        out.push(&s.retro.to_variant());
        out.push(&Vector2::new(s.strafe_x, s.strafe_y).to_variant());
        out
    }

    /// `PilotSteering.lean_toward`.
    #[func]
    fn steering_lean(base: Vector3, accel: Vector3, a_side: f64, max_lean_rad: f64) -> Vector3 {
        brain_maths::lean_toward(base, accel, a_side, max_lean_rad)
    }

    /// `InterceptMath.solve` as `[ok, t, aim_dir, lead_point]`.
    #[func]
    fn intercept(
        shooter_pos: Vector3,
        shooter_vel: Vector3,
        target_pos: Vector3,
        target_vel: Vector3,
        bolt_speed: f64,
        max_time: f64,
    ) -> VarArray {
        let lead = brain_maths::solve(
            shooter_pos,
            shooter_vel,
            target_pos,
            target_vel,
            bolt_speed,
            max_time,
        );
        let mut out = VarArray::new();
        out.push(&lead.ok.to_variant());
        out.push(&lead.t.to_variant());
        out.push(&lead.aim_dir.to_variant());
        out.push(&lead.lead_point.to_variant());
        out
    }

    /// `AiTemperament`'s fifteen factors, in `test_brain_parity`'s order.
    #[func]
    fn temperament_factors(skill: f64, aggression: f64) -> PackedFloat64Array {
        let t = Temperament::new(skill, aggression);
        PackedFloat64Array::from(
            &[
                t.aim_factor(),
                t.reaction_s(),
                t.miss_factor(),
                t.jink_factor(),
                t.reversal_spread_deg(),
                t.attack_weight_factor(),
                t.evade_weight_factor(),
                t.retreat_weight_factor(),
                t.retreat_threshold_factor(),
                t.press_factor(),
                t.slash_chance(),
                t.close_pass_chance(),
                t.awareness(),
                f64::from(u8::from(t.never_starts())),
                f64::from(u8::from(t.may_ram())),
            ][..],
        )
    }

    /// `AiTemperament.apply` on `[attack weight, evade weight, retreat weight, retreat_below, aim_error_deg, fire_miss_m,
    /// near_range_m, break_range_m]`.
    #[func]
    fn temperament_apply(
        skill: f64,
        aggression: f64,
        base: PackedFloat64Array,
    ) -> PackedFloat64Array {
        let t = Temperament::new(skill, aggression);
        let b = base.as_slice();
        if b.len() != 8 {
            return PackedFloat64Array::new();
        }
        PackedFloat64Array::from(
            &[
                t.weight(b[0], t.attack_weight_factor()),
                t.weight(b[1], t.evade_weight_factor()),
                t.weight(b[2], t.retreat_weight_factor()),
                brain_maths::clamp01(b[3] * t.retreat_threshold_factor()),
                b[4] * t.aim_factor(),
                b[5] * t.miss_factor(),
                b[6] * t.press_factor(),
                b[7] * t.press_factor(),
            ][..],
        )
    }

    /// Flies manoeuvre `kind` through `steps` (`STEP_IN` numbers a step) with `cap`, and gives `[the commands, STEP_OUT
    /// numbers a step; the result as a Dictionary]`.
    #[func]
    fn manoeuvre_run(kind: i64, cap: PackedFloat64Array, steps: PackedFloat64Array) -> VarArray {
        let mut out = VarArray::new();
        let Some(mut m) = u8::try_from(kind).ok().and_then(Manoeuvre::create) else {
            return out;
        };
        let cap = capability_of(&cap);
        let s = steps.as_slice();
        let mut commands: Vec<f64> = Vec::with_capacity(s.len() / STEP_IN * STEP_OUT);
        for step in s.as_chunks::<STEP_IN>().0 {
            let v =
                |at: usize| Vector3::new(step[at] as f32, step[at + 1] as f32, step[at + 2] as f32);
            // The test packs the basis as GDScript reads it: `basis.x`, `basis.y`, `basis.z`, its columns.
            let (cx, cy, cz) = (v(4), v(7), v(10));
            let pose = Pose {
                now_s: step[0],
                position: v(1),
                basis: Basis {
                    rows: [
                        Vector3::new(cx.x, cy.x, cz.x),
                        Vector3::new(cx.y, cy.y, cz.y),
                        Vector3::new(cx.z, cy.z, cz.z),
                    ],
                },
                velocity: v(13),
                angular: v(16),
                origin: [step[19], step[20], step[21]],
            };
            let cmd: FlightCmd = m.step(&pose, &cap, step[22]);
            commands.extend([
                cmd.main_left,
                cmd.main_right,
                cmd.retro_left,
                cmd.retro_right,
                f64::from(cmd.strafe_x),
                f64::from(cmd.strafe_y),
                f64::from(cmd.rot.x),
                f64::from(cmd.rot.y),
                f64::from(cmd.rot.z),
                f64::from(u8::from(cmd.brake)),
                f64::from(u8::from(m.done)),
                f64::from(u8::from(m.timed_out)),
                f64::from(u8::from(m.has_desired_velocity)),
                f64::from(m.desired_velocity.x),
                f64::from(m.desired_velocity.y),
                f64::from(m.desired_velocity.z),
            ]);
        }
        out.push(&PackedFloat64Array::from(commands.as_slice()).to_variant());
        let result = m.result();
        let mut dict = VarDictionary::new();
        for (key, value) in result.keys.iter().zip(result.values.iter()) {
            dict.set(*key, *value);
        }
        for (key, flag) in &result.flags {
            dict.set(*key, *flag);
        }
        for (key, count) in &result.ints {
            dict.set(*key, *count);
        }
        if let Some(legs) = &result.legs_m {
            let mut list = VarArray::new();
            for leg in legs {
                list.push(&leg.to_variant());
            }
            dict.set("legs_m", &list);
        }
        out.push(&dict.to_variant());
        out
    }
}

impl ScsBrains {
    // Rebuilds the contact grid when the core's rows changed under it.
    fn refresh_grid(&mut self) {
        let Some(core) = &self.core else {
            return;
        };
        let c = core.bind();
        if c.rows_version_now() == self.grid_version {
            return;
        }
        self.grid_version = c.rows_version_now();
        self.grid.cells = contact::sorted_cells(&c.rows.positions, self.grid.cell_m);
        self.grid.max_static_radius = (0..c.rows.positions.len())
            .filter(|&i| c.rows.is_static[i])
            .map(|i| c.rows.radii[i].abs())
            .fold(0.0, f64::max);
    }
}

// `ShipCapability` as the tests pack it: a_main, a_retro, a_rcs x and y, the rate maxima, the angular acceleration maxima.
fn capability_of(cap: &PackedFloat64Array) -> Capability {
    let c = cap.as_slice();
    if c.len() < 10 {
        return Capability::default();
    }
    Capability {
        a_main: c[0],
        a_retro: c[1],
        a_rcs_x: c[2],
        a_rcs_y: c[3],
        rate_max: Vector3::new(c[4] as f32, c[5] as f32, c[6] as f32),
        alpha_max: Vector3::new(c[7] as f32, c[8] as f32, c[9] as f32),
    }
}
