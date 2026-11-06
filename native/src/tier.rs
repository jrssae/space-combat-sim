// The low-attention tier's rows and integrator (M4-T21, docs/architecture.md 17.14): far fighters and capitals with no
// body and no node, integrated from their held command at the tier's rate. Engine-free by construction (test_sim_core
// reads this file): plain columns in, plain columns out; the core's shell (tier_rows.rs) adds and takes rows and appends
// them to the scan's rows at each sync.
use std::collections::HashMap;

use godot::builtin::{Basis, Vector3};

use crate::kernels::flight::{self, Body, Cmd};
use crate::row_commands::RowCommand;
use crate::rows::{FLAG_HULK, FLAG_HULL, FLAG_TIER, Rows};
use crate::v3::{
    add, cross, length, length_squared, limit_length, normalized, scale, sub, xform, xform_inv,
};

/// A tier row's kind: a fighter flown by the flight kernel, or a capital holding its cruise.
pub const KIND_FIGHTER: u8 = 0;
pub const KIND_CAPITAL: u8 = 1;
// `CapitalStandin`'s engine law: how fast it comes back to its cruise, and the most it can push.
const CRUISE_RESPONSE_S: f64 = 5.0;
const MAX_ACCEL_MPS2: f64 = 2.0;

/// A fighter type as the tier flies it: the flight kernel's body and the centre of mass its nozzles turn it about.
pub struct Type {
    pub body: Body,
    pub center_of_mass: Vector3,
}

/// The environment's pull: point sources (the bench's moon), each `gm / r^2` toward it, as `GravityStandin.accel`.
#[derive(Default)]
pub struct Gravity {
    pub positions: Vec<Vector3>,
    pub gm: Vec<f64>,
}

impl Gravity {
    /// The pull at `at`, m/s^2.
    pub fn accel(&self, at: Vector3) -> Vector3 {
        let mut total = Vector3::ZERO;
        for (k, &source) in self.positions.iter().enumerate() {
            let to_source = sub(source, at);
            let r_sq = f64::from(length_squared(to_source));
            if r_sq < 1.0 {
                continue;
            }
            total = add(
                total,
                scale(to_source, (self.gm[k] / (r_sq * r_sq.sqrt())) as f32),
            );
        }
        total
    }

    /// Moves every source by a rebase.
    pub fn shift(&mut self, offset: Vector3) {
        for p in self.positions.iter_mut() {
            *p = add(*p, offset);
        }
    }
}

/// The tier's rows, column by column, in no particular order (a removed row's place is taken by the last).
#[derive(Default)]
pub struct TierRows {
    pub body_ids: Vec<i64>,
    /// The marker's id (what a selection names), the body's when it has none.
    pub marker_ids: Vec<i64>,
    pub hull_ids: Vec<i64>,
    pub handles: Vec<i64>,
    pub kinds: Vec<u8>,
    pub type_ix: Vec<u32>,
    pub faction_ix: Vec<u32>,
    pub radii: Vec<f64>,
    pub reach: Vec<f64>,
    pub hull_fraction: Vec<f64>,
    pub name_keys: Vec<String>,
    pub positions: Vec<Vector3>,
    pub velocities: Vec<Vector3>,
    pub bases: Vec<Basis>,
    pub angular: Vec<Vector3>,
    /// A capital's cruise velocity (its engines hold it); unused for a fighter.
    pub cruise: Vec<Vector3>,
    /// The command a fighter flies when the brains hold none for it: the one it flew when demoted.
    pub commands: Vec<RowCommand>,
    /// The assist's smoothed pod-yaw command (`FlightAssist.pod_yaw_smoothed`), carried across the handover.
    pub pod_yaw: Vec<f64>,
    pub assist_on: Vec<bool>,
    /// A hulk drifts: no force, no brain, never removed for being idle.
    pub hulk: Vec<bool>,
    /// The row's place in the beat's stagger.
    pub ordinal: Vec<i64>,
    // What the last beat left to apply every tick: the acceleration, the angular acceleration and the speed ceiling.
    pub accel: Vec<Vector3>,
    pub alpha: Vec<Vector3>,
    pub speed_limit: Vec<f64>,
    pub by_body: HashMap<i64, usize>,
}

impl TierRows {
    pub fn len(&self) -> usize {
        self.body_ids.len()
    }

    pub fn is_empty(&self) -> bool {
        self.body_ids.is_empty()
    }

    /// The row of body `body_id`, if it is in the tier.
    pub fn index_of(&self, body_id: i64) -> Option<usize> {
        HashMap::get(&self.by_body, &body_id).copied()
    }

    /// Adds a row from a body's pose and motion; its attributes and control come after (`set_attrs`, `set_control`).
    /// Returns its index, or none when the body is in the tier already.
    #[allow(clippy::too_many_arguments)]
    pub fn add(
        &mut self,
        kind: u8,
        body_id: i64,
        hull_id: i64,
        handle: i64,
        type_ix: u32,
        position: Vector3,
        velocity: Vector3,
        basis: Basis,
        angular: Vector3,
        ordinal: i64,
    ) -> Option<usize> {
        if self.by_body.contains_key(&body_id) {
            return None;
        }
        let at = self.len();
        self.body_ids.push(body_id);
        self.marker_ids.push(body_id);
        self.hull_ids.push(hull_id);
        self.handles.push(handle);
        self.kinds.push(kind);
        self.type_ix.push(type_ix);
        self.faction_ix.push(0);
        self.radii.push(0.0);
        self.reach.push(0.0);
        self.hull_fraction.push(-1.0);
        self.name_keys.push(String::new());
        self.positions.push(position);
        self.velocities.push(velocity);
        self.bases.push(basis);
        self.angular.push(angular);
        self.cruise.push(Vector3::ZERO);
        self.commands.push(RowCommand::default());
        self.pod_yaw.push(0.0);
        self.assist_on.push(true);
        self.hulk.push(false);
        self.ordinal.push(ordinal);
        self.accel.push(Vector3::ZERO);
        self.alpha.push(Vector3::ZERO);
        self.speed_limit.push(0.0);
        self.by_body.insert(body_id, at);
        Some(at)
    }

    /// Removes body `body_id`'s row; the last row takes its place. Returns the removed index and, when another row
    /// moved into it, that row's old index (the shell keeps its own columns in step).
    pub fn remove(&mut self, body_id: i64) -> Option<(usize, Option<usize>)> {
        let at = self.by_body.remove(&body_id)?;
        let last = self.len() - 1;
        self.body_ids.swap_remove(at);
        self.marker_ids.swap_remove(at);
        self.hull_ids.swap_remove(at);
        self.handles.swap_remove(at);
        self.kinds.swap_remove(at);
        self.type_ix.swap_remove(at);
        self.faction_ix.swap_remove(at);
        self.radii.swap_remove(at);
        self.reach.swap_remove(at);
        self.hull_fraction.swap_remove(at);
        self.name_keys.swap_remove(at);
        self.positions.swap_remove(at);
        self.velocities.swap_remove(at);
        self.bases.swap_remove(at);
        self.angular.swap_remove(at);
        self.cruise.swap_remove(at);
        self.commands.swap_remove(at);
        self.pod_yaw.swap_remove(at);
        self.assist_on.swap_remove(at);
        self.hulk.swap_remove(at);
        self.ordinal.swap_remove(at);
        self.accel.swap_remove(at);
        self.alpha.swap_remove(at);
        self.speed_limit.swap_remove(at);
        if at != last {
            self.by_body.insert(self.body_ids[at], at);
            return Some((at, Some(last)));
        }
        Some((at, None))
    }

    /// Moves every row by a rebase.
    pub fn shift(&mut self, offset: Vector3) {
        for p in self.positions.iter_mut() {
            *p = add(*p, offset);
        }
    }

    /// Appends every tier row to the scan's rows: a tier row is a ship to the contacts (not a hulk), has a hull but no
    /// active one (nothing sweeps or rams it here), and no Jolt body; its id is its marker's, so a selection that names it
    /// still finds its row. The shell appends the names and RIDs beside them.
    pub fn append_to(&self, rows: &mut Rows) {
        for i in 0..self.len() {
            let hulk = self.hulk[i];
            rows.body_ids.push(self.body_ids[i]);
            rows.ids.push(self.marker_ids[i]);
            rows.faction_ix.push(self.faction_ix[i]);
            rows.positions.push(self.positions[i]);
            rows.velocities.push(self.velocities[i]);
            rows.bases.push(self.bases[i]);
            rows.angular.push(self.angular[i]);
            rows.radii.push(self.radii[i]);
            rows.kinds.push(self.kinds[i]);
            rows.flags
                .push(FLAG_TIER | FLAG_HULL | if hulk { FLAG_HULK } else { 0 });
            rows.hull_ids.push(self.hull_ids[i]);
            rows.handles.push(self.handles[i]);
            rows.rigid.push(!hulk);
            rows.is_static.push(false);
            rows.is_mine.push(false);
            rows.hull_fraction.push(self.hull_fraction[i]);
            rows.target_ids.push(-1);
            rows.reach.push(self.reach[i]);
            rows.name_keys.push(self.name_keys[i].clone());
        }
        rows.tier_rows = self.len();
    }
}

/// One tick of the tier: every row's pose advances from its velocity and spin; the rows on their beat (every `period`
/// ticks, staggered by ordinal) recompute what pushes them (a fighter's command through the flight kernel, a capital's
/// cruise law, nothing for a hulk) and hold it until the next beat. Returns how many rows had their beat.
#[allow(clippy::too_many_arguments)]
pub fn step(
    t: &mut TierRows,
    types: &[Type],
    gravity: &Gravity,
    commands: &HashMap<i64, RowCommand>,
    tick: i64,
    dt: f64,
    period: i64,
    scratch: &mut Vec<(Vector3, Vector3)>,
) -> usize {
    let period = period.max(1);
    let dt32 = dt as f32;
    let mut beats = 0;
    for i in 0..t.len() {
        if (tick + t.ordinal[i]).rem_euclid(period) == 0 {
            beats += 1;
            beat(t, i, types, gravity, commands, dt * period as f64, scratch);
        }
        // Semi-implicit, as Jolt steps a body: the velocity first, then the pose from the new velocity.
        let mut v = add(t.velocities[i], scale(t.accel[i], dt32));
        let limit = t.speed_limit[i];
        if limit > 0.0 && f64::from(length(v)) > limit {
            v = scale(normalized(v), limit as f32);
        }
        t.velocities[i] = v;
        t.positions[i] = add(t.positions[i], scale(v, dt32));
        let w = add(t.angular[i], scale(t.alpha[i], dt32));
        t.angular[i] = w;
        t.bases[i] = rotate_basis(&t.bases[i], w, dt);
    }
    beats
}

// A row's beat: what pushes it until the next one.
fn beat(
    t: &mut TierRows,
    i: usize,
    types: &[Type],
    gravity: &Gravity,
    commands: &HashMap<i64, RowCommand>,
    dt_beat: f64,
    scratch: &mut Vec<(Vector3, Vector3)>,
) {
    if t.hulk[i] {
        t.accel[i] = Vector3::ZERO;
        t.alpha[i] = Vector3::ZERO;
        t.speed_limit[i] = 0.0;
        return;
    }
    let env = gravity.accel(t.positions[i]);
    if t.kinds[i] == KIND_CAPITAL {
        // `CapitalStandin.cruise_force` divided by the mass: back toward the cruise, holding off the pull, 2 m/s^2 at most.
        let response = if dt_beat > CRUISE_RESPONSE_S {
            dt_beat
        } else {
            CRUISE_RESPONSE_S
        };
        let wanted = scale(sub(t.cruise[i], t.velocities[i]), (1.0 / response) as f32);
        t.accel[i] = limit_length(sub(wanted, env), MAX_ACCEL_MPS2 as f32);
        t.alpha[i] = Vector3::ZERO;
        t.speed_limit[i] = 0.0;
        return;
    }
    let Some(ty) = types.get(t.type_ix[i] as usize) else {
        t.accel[i] = env;
        t.alpha[i] = Vector3::ZERO;
        return;
    };
    let body: &Body = &ty.body;
    let mut cmd = Cmd {
        levels: [0.0; flight::GROUPS],
        strafe: Vector3::ZERO,
        rot: Vector3::ZERO,
        track_dir_b: Vector3::ZERO,
        track_rate_b: Vector3::ZERO,
        face_dir_b: Vector3::ZERO,
        brake: false,
        autotrack: false,
    };
    HashMap::get(commands, &t.body_ids[i])
        .unwrap_or(&t.commands[i])
        .apply_to(&mut cmd);
    let basis = t.bases[i];
    let mut pod_yaw = t.pod_yaw[i];
    let applied = flight::tick(
        body,
        &mut pod_yaw,
        &cmd,
        &basis,
        t.velocities[i],
        t.angular[i],
        env,
        t.assist_on[i],
        dt_beat,
        true,
        scratch,
    );
    t.pod_yaw[i] = pod_yaw;
    // `Ship.applied_force() / mass`, as the ram tracker reads a ship's acceleration.
    let mass = body.spec.mass as f32;
    let force = applied.out_vectors[0];
    t.accel[i] = Vector3::new(force.x / mass, force.y / mass, force.z / mass);
    // The torques Jolt would add: the RCS torque and each nozzle force about the centre of mass.
    let com_w = xform(&basis, ty.center_of_mass);
    let mut torque = applied.torque_w;
    for &(force_w, at_w) in scratch.iter() {
        torque = add(torque, cross(sub(at_w, com_w), force_w));
    }
    let tau_b = xform_inv(&basis, torque);
    let inertia = body.spec.inertia;
    let alpha_b = Vector3::new(
        axis_accel(tau_b.x, inertia.x),
        axis_accel(tau_b.y, inertia.y),
        axis_accel(tau_b.z, inertia.z),
    );
    t.alpha[i] = xform(&basis, alpha_b);
    t.speed_limit[i] = body.spec.speed_limit_mps;
}

fn axis_accel(torque: f32, inertia: f32) -> f32 {
    if inertia > 0.0 {
        (f64::from(torque) / f64::from(inertia)) as f32
    } else {
        0.0
    }
}

/// The basis turned by the spin `w` (world frame, rad/s) over `dt`, then made orthonormal again (as Jolt integrates a
/// body's quaternion and normalises it).
pub fn rotate_basis(basis: &Basis, w: Vector3, dt: f64) -> Basis {
    let (wx, wy, wz) = (f64::from(w.x), f64::from(w.y), f64::from(w.z));
    let rate = (wx * wx + wy * wy + wz * wz).sqrt();
    let angle = rate * dt;
    if angle <= 0.0 {
        return *basis;
    }
    let (x, y, z) = (wx / rate, wy / rate, wz / rate);
    let (c, s) = (angle.cos(), angle.sin());
    let t = 1.0 - c;
    // The rotation about the axis, in the same row form as `Basis(axis, angle)`.
    let r = [
        [x * x * t + c, x * y * t - z * s, x * z * t + y * s],
        [x * y * t + z * s, y * y * t + c, y * z * t - x * s],
        [x * z * t - y * s, y * z * t + x * s, z * z * t + c],
    ];
    let b: [[f64; 3]; 3] = [
        [
            f64::from(basis.rows[0].x),
            f64::from(basis.rows[0].y),
            f64::from(basis.rows[0].z),
        ],
        [
            f64::from(basis.rows[1].x),
            f64::from(basis.rows[1].y),
            f64::from(basis.rows[1].z),
        ],
        [
            f64::from(basis.rows[2].x),
            f64::from(basis.rows[2].y),
            f64::from(basis.rows[2].z),
        ],
    ];
    let mut m = [[0.0f64; 3]; 3];
    for (i, row) in m.iter_mut().enumerate() {
        for (j, cell) in row.iter_mut().enumerate() {
            *cell = r[i][0] * b[0][j] + r[i][1] * b[1][j] + r[i][2] * b[2][j];
        }
    }
    orthonormal(&m)
}

// Gram-Schmidt over the columns (`Basis.orthonormalized()`), the result in 32 bits.
fn orthonormal(m: &[[f64; 3]; 3]) -> Basis {
    let col = |j: usize| [m[0][j], m[1][j], m[2][j]];
    let x = unit(col(0));
    let c1 = col(1);
    let d1 = dot3(x, c1);
    let y = unit([c1[0] - x[0] * d1, c1[1] - x[1] * d1, c1[2] - x[2] * d1]);
    let c2 = col(2);
    let d2x = dot3(x, c2);
    let d2y = dot3(y, c2);
    let z = unit([
        c2[0] - x[0] * d2x - y[0] * d2y,
        c2[1] - x[1] * d2x - y[1] * d2y,
        c2[2] - x[2] * d2x - y[2] * d2y,
    ]);
    Basis {
        rows: [
            Vector3::new(x[0] as f32, y[0] as f32, z[0] as f32),
            Vector3::new(x[1] as f32, y[1] as f32, z[1] as f32),
            Vector3::new(x[2] as f32, y[2] as f32, z[2] as f32),
        ],
    }
}

fn dot3(a: [f64; 3], b: [f64; 3]) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn unit(a: [f64; 3]) -> [f64; 3] {
    let len = dot3(a, a).sqrt();
    if len == 0.0 {
        return a;
    }
    [a[0] / len, a[1] / len, a[2] / len]
}

/// The node rows (the body rows before the statics) that are fighters or capitals in Jolt beyond `radius` of
/// `player_at`, by body id, at most `max` of them: what the director demotes. The player's own body is left out.
pub fn far_bodies(
    rows: &Rows,
    player_at: Vector3,
    exclude: i64,
    radius: f64,
    max: usize,
    out: &mut Vec<i64>,
) {
    out.clear();
    for i in 0..rows.node_count {
        if out.len() >= max {
            return;
        }
        let kind = rows.kinds[i];
        if (kind != KIND_FIGHTER && kind != KIND_CAPITAL)
            || !rows.rigid[i]
            || rows.flags[i] & FLAG_TIER != 0
            || rows.body_ids[i] == exclude
        {
            continue;
        }
        if range(rows.positions[i], player_at) > radius {
            out.push(rows.body_ids[i]);
        }
    }
}

/// The tier rows within `radius` of `player_at`, by body id, at most `max`: what the director promotes.
pub fn near_rows(t: &TierRows, player_at: Vector3, radius: f64, max: usize, out: &mut Vec<i64>) {
    out.clear();
    for i in 0..t.len() {
        if out.len() >= max {
            return;
        }
        if range(t.positions[i], player_at) <= radius {
            out.push(t.body_ids[i]);
        }
    }
}

// The range between two places in 64 bits, as `TargetingSystem.range_between` takes it.
fn range(a: Vector3, b: Vector3) -> f64 {
    let dx = f64::from(a.x) - f64::from(b.x);
    let dy = f64::from(a.y) - f64::from(b.y);
    let dz = f64::from(a.z) - f64::from(b.z);
    (dx * dx + dy * dy + dz * dz).sqrt()
}
