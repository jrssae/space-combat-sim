// The low-attention tier's rows and integrator (M4-T21, docs/architecture.md 17.14): far fighters and capitals with no
// body and no node, integrated from their held command at the tier's rate. Engine-free by construction (test_sim_core
// reads this file): plain columns in, plain columns out; the core's shell (tier_rows.rs) adds and takes rows and appends
// them to the scan's rows at each sync.
use std::collections::HashMap;

use godot::builtin::{Basis, Vector3};

use crate::kernels::flight::{self, Body, Cmd};
use crate::row_commands::{CommandMap, IdMap, RowCommand};
use crate::rows::{FLAG_HULK, FLAG_HULL, FLAG_TIER, ROLE_CIVILIAN, ROLE_COMBAT, Rows};
use crate::v3::{
    add, cross, length, limit_length, normalized, scale, sub, xform, xform_inv,
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
    /// The lowered name as an id of the core's name table (0 for none).
    pub name_ids: Vec<u32>,
    /// The row's role (M5-T16): a civilian keeps it in the tier.
    pub roles: Vec<u8>,
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
    /// The row command's `seq` the last beat flew (fix round 1): a newer one gets a beat at once.
    pub seen_seq: Vec<u32>,
    // What the last beat left to apply every tick: the acceleration, the angular acceleration and the speed ceiling.
    pub accel: Vec<Vector3>,
    pub alpha: Vec<Vector3>,
    pub speed_limit: Vec<f64>,
    /// What the row draws as (M4-T23): -1 a far dot, else the far hull class of its capital's mesh.
    pub proxy: Vec<i32>,
    /// A far dot's paint, linear rgb.
    pub paint: Vec<[f32; 3]>,
    /// A capital's hull box (half extents in its own frame, fix round 1); zero for a fighter, held as a sphere.
    pub half_extents: Vec<Vector3>,
    pub by_body: IdMap<usize>,
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
        self.name_ids.push(0);
        self.roles.push(ROLE_COMBAT);
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
        self.seen_seq.push(0);
        self.accel.push(Vector3::ZERO);
        self.alpha.push(Vector3::ZERO);
        self.speed_limit.push(0.0);
        self.proxy.push(-1);
        self.paint.push([0.5, 0.5, 0.5]);
        self.half_extents.push(Vector3::ZERO);
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
        self.name_ids.swap_remove(at);
        self.roles.swap_remove(at);
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
        self.seen_seq.swap_remove(at);
        self.accel.swap_remove(at);
        self.alpha.swap_remove(at);
        self.speed_limit.swap_remove(at);
        self.proxy.swap_remove(at);
        self.paint.swap_remove(at);
        self.half_extents.swap_remove(at);
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

    /// A velocity rebase: every row loses `dv`, and so does the cruise a capital holds, which is a velocity in the same
    /// frame. A fighter's cruise slot is unused and stays zero.
    pub fn boost(&mut self, dv: Vector3) {
        for v in self.velocities.iter_mut() {
            *v -= dv;
        }
        for (c, &kind) in self.cruise.iter_mut().zip(&self.kinds) {
            if kind == KIND_CAPITAL {
                *c -= dv;
            }
        }
    }

    /// Appends every tier row to the scan's rows: a tier row is a ship to the contacts (not a hulk), has a hull but no
    /// active one (nothing sweeps or rams it here), and no Jolt body; its id is its marker's, so a selection that names it
    /// still finds its row. The shell appends the names and RIDs beside them.
    pub fn append_to(&self, rows: &mut Rows) {
        // Column by column (M5-T35): the same rows `push_row` gives, as block copies.
        let n = self.len();
        let total = rows.body_ids.len() + n;
        rows.body_ids.extend_from_slice(&self.body_ids);
        rows.ids.extend_from_slice(&self.marker_ids);
        rows.faction_ix.extend_from_slice(&self.faction_ix);
        rows.positions.extend_from_slice(&self.positions);
        rows.velocities.extend_from_slice(&self.velocities);
        rows.bases.extend_from_slice(&self.bases);
        rows.angular.extend_from_slice(&self.angular);
        rows.radii.extend_from_slice(&self.radii);
        rows.kinds.extend_from_slice(&self.kinds);
        rows.flags.extend(
            self.hulk
                .iter()
                .map(|&hulk| FLAG_TIER | FLAG_HULL | if hulk { FLAG_HULK } else { 0 }),
        );
        rows.hull_ids.extend_from_slice(&self.hull_ids);
        rows.handles.extend_from_slice(&self.handles);
        rows.rigid.extend(self.hulk.iter().map(|&hulk| !hulk));
        rows.is_static.resize(total, false);
        rows.is_mine.resize(total, false);
        rows.hull_fraction.extend_from_slice(&self.hull_fraction);
        rows.target_ids.resize(total, -1);
        rows.reach.extend_from_slice(&self.reach);
        rows.name_ids.extend_from_slice(&self.name_ids);
        rows.roles.extend_from_slice(&self.roles);
        rows.tier_rows = n;
    }

    /// Pushes row `i` onto `rows` as `append_to` does.
    pub fn push_row(&self, i: usize, rows: &mut Rows) {
        {
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
            rows.name_ids.push(self.name_ids[i]);
            rows.roles.push(self.roles[i]);
        }
    }
}

/// One tick of the tier: every row's pose advances from its velocity and spin; the rows on their beat (every `period`
/// ticks, staggered by ordinal) recompute what their engines push (a fighter's command through the flight kernel, a
/// capital's cruise law, nothing for a hulk) and hold it until the next beat. `pull` is what each row feels from gravity
/// this tick (the frame's residual, one per row), applied every tick on top of the engines; empty where nothing pulls.
/// Returns how many rows had their beat.
#[allow(clippy::too_many_arguments)]
pub fn step(
    t: &mut TierRows,
    types: &[Type],
    pull: &[Vector3],
    commands: &CommandMap,
    tick: i64,
    dt: f64,
    period: i64,
    scratch: &mut Vec<(Vector3, Vector3)>,
) -> usize {
    let period = period.max(1);
    let dt32 = dt as f32;
    let mut beats = 0;
    for i in 0..t.len() {
        // A command a think wrote since the last beat is flown at once (fix round 1): waiting for the beat added up to two
        // ticks of steering lag on top of the step's one-tick handover, enough to swing a 4 Hz pilot's nose off its gate.
        let fresh =
            HashMap::get(commands, &t.body_ids[i]).is_some_and(|rc| rc.seq != t.seen_seq[i]);
        if fresh || (tick + t.ordinal[i]).rem_euclid(period) == 0 {
            beats += 1;
            if let Some(rc) = HashMap::get(commands, &t.body_ids[i]) {
                t.seen_seq[i] = rc.seq;
            }
            let env = pull.get(i).copied().unwrap_or(Vector3::ZERO);
            beat(t, i, types, env, commands, dt * period as f64, scratch);
        }
        // Semi-implicit, as Jolt steps a body: the velocity first, then the pose from the new velocity.
        let mut v = add(t.velocities[i], scale(t.accel[i], dt32));
        if let Some(&g) = pull.get(i) {
            v = add(v, scale(g, dt32));
        }
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

// A row's beat: what its engines push until the next one, against `env`, the pull it feels now (feed-forward only: the
// step applies the pull itself every tick).
fn beat(
    t: &mut TierRows,
    i: usize,
    types: &[Type],
    env: Vector3,
    commands: &CommandMap,
    dt_beat: f64,
    scratch: &mut Vec<(Vector3, Vector3)>,
) {
    if t.hulk[i] {
        t.accel[i] = Vector3::ZERO;
        t.alpha[i] = Vector3::ZERO;
        t.speed_limit[i] = 0.0;
        return;
    }
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
        t.accel[i] = Vector3::ZERO;
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
    // `Ship.applied_force() / mass` less the pull, which the step adds every tick.
    let mass = body.spec.mass as f32;
    let force = if env == Vector3::ZERO {
        applied.out_vectors[0]
    } else {
        sub(applied.out_vectors[0], applied.env_force)
    };
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
/// `player_at`, by body id, at most `max` of them: what the director demotes. The player's own body is left out. A civilian
/// hull (M5-T16) is measured from its surface, so a 260 m freighter leaves and comes back when its near end crosses the line.
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
        let r = range(rows.positions[i], player_at);
        let gap = if rows.role(i) == ROLE_CIVILIAN {
            r - rows.radii[i]
        } else {
            r
        };
        if gap > radius {
            out.push(rows.body_ids[i]);
        }
    }
}

/// The tier rows within `radius` of `player_at`, by body id, at most `max`: what the director promotes (a civilian hull by
/// its surface, as `far_bodies` measures it).
pub fn near_rows(t: &TierRows, player_at: Vector3, radius: f64, max: usize, out: &mut Vec<i64>) {
    out.clear();
    for i in 0..t.len() {
        if out.len() >= max {
            return;
        }
        let r = range(t.positions[i], player_at);
        let gap = if t.roles[i] == ROLE_CIVILIAN {
            r - t.radii[i]
        } else {
            r
        };
        if gap <= radius {
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

// --- far proxies and the promotion's clearance (M4-T23) -------------------------------------------------------------

/// Floats per far dot (`FarDots`' layout): a 3x4 transform, then the paint (rgb) and the hull radius.
pub const DOT_STRIDE: usize = 16;
/// How far past a static's surface a promoted row is put, m.
pub const CLEARANCE_M: f64 = 5.0;
// Passes over the statics, for rocks that touch each other.
const CLEAR_PASSES: usize = 8;
// A hair past the exit, so 32-bit rounding never leaves the row just inside.
const EXIT_SLACK_M: f64 = 0.01;

/// Rows drawn as far dots.
pub fn dot_count(t: &TierRows) -> usize {
    t.proxy.iter().filter(|&&p| p < 0).count()
}

/// Writes every row drawn as a dot into `out` from instance `start` on: its position plus `offset` (the dots' node
/// frame), no rotation, its paint and radius. `out` must hold them. Returns how many it wrote.
pub fn fill_dots(t: &TierRows, offset: Vector3, out: &mut [f32], start: usize) -> usize {
    let mut n = 0;
    for i in 0..t.len() {
        if t.proxy[i] >= 0 {
            continue;
        }
        let b = (start + n) * DOT_STRIDE;
        let p = add(t.positions[i], offset);
        let paint = t.paint[i];
        out[b..b + DOT_STRIDE].copy_from_slice(&[
            1.0,
            0.0,
            0.0,
            p.x,
            0.0,
            1.0,
            0.0,
            p.y,
            0.0,
            0.0,
            1.0,
            p.z,
            paint[0],
            paint[1],
            paint[2],
            t.radii[i] as f32,
        ]);
        n += 1;
    }
    n
}

/// Appends every row of far hull class `class` to `out` at its pose plus `offset`, a 3x4 transform each (MultiMesh's layout). Returns how many it appended.
pub fn fill_hulls(t: &TierRows, class: i32, offset: Vector3, out: &mut Vec<f32>) -> usize {
    let mut n = 0;
    for i in 0..t.len() {
        if t.proxy[i] != class {
            continue;
        }
        let r = &t.bases[i].rows;
        let p = add(t.positions[i], offset);
        out.extend_from_slice(&[
            r[0].x, r[0].y, r[0].z, p.x, r[1].x, r[1].y, r[1].z, p.y, r[2].x, r[2].y, r[2].z, p.z,
        ]);
        n += 1;
    }
    n
}

/// Where a row must go to clear every static sphere (`centers`, `radii`) by `CLEARANCE_M`, by the shortest way out of each
/// (fix round 1: the least jump at the handover): a fighter as a sphere of `radius`, a capital as its hull box (`half`, in
/// the frame of `basis`; zero for none), so a rock near a carrier's bounding sphere but clear of its hull moves nothing. A
/// few passes for rocks that touch; a row still overlapping after them stays where the last pass put it. None when it
/// overlaps nothing.
pub fn clear_of_statics(
    position: Vector3,
    basis: &Basis,
    half: Vector3,
    radius: f64,
    centers: &[Vector3],
    radii: &[f64],
) -> Option<Vector3> {
    let boxed = half != Vector3::ZERO;
    let mut at = position;
    let mut moved = false;
    for _ in 0..CLEAR_PASSES {
        let mut clear = true;
        for (k, &c) in centers.iter().enumerate() {
            let push = if boxed {
                box_push(sub(c, at), basis, half, radii[k] + CLEARANCE_M)
            } else {
                sphere_push(sub(at, c), radii[k] + radius + CLEARANCE_M)
            };
            if let Some(p) = push {
                at = add(at, p);
                clear = false;
                moved = true;
            }
        }
        if clear {
            break;
        }
    }
    moved.then_some(at)
}

// How far a sphere whose centre is `rel` from a rock's must move to stand `need` from it, or none.
fn sphere_push(rel: Vector3, need: f64) -> Option<Vector3> {
    let d = f64::from(length(rel));
    if d >= need {
        return None;
    }
    let out_dir = if d > 1e-6 {
        normalized(rel)
    } else {
        Vector3::UP
    };
    Some(scale(out_dir, (need - d + EXIT_SLACK_M) as f32))
}

// How far a box (half extents `half` in the frame of `basis`) must move to stand `need` from a rock whose centre is `to_rock`
// from the box's, or none: straight away from the hull's nearest point, or out along its thinnest side when the rock's
// centre is inside the hull.
fn box_push(to_rock: Vector3, basis: &Basis, half: Vector3, need: f64) -> Option<Vector3> {
    let local = xform_inv(basis, to_rock);
    let l = [f64::from(local.x), f64::from(local.y), f64::from(local.z)];
    let h = [f64::from(half.x), f64::from(half.y), f64::from(half.z)];
    let q = [
        l[0].clamp(-h[0], h[0]),
        l[1].clamp(-h[1], h[1]),
        l[2].clamp(-h[2], h[2]),
    ];
    let diff = [l[0] - q[0], l[1] - q[1], l[2] - q[2]];
    let dist = (diff[0] * diff[0] + diff[1] * diff[1] + diff[2] * diff[2]).sqrt();
    if dist >= need {
        return None;
    }
    let mut p = [0.0; 3];
    if dist > 1e-6 {
        let s = -(need - dist + EXIT_SLACK_M) / dist;
        p = [diff[0] * s, diff[1] * s, diff[2] * s];
    } else {
        let mut axis = 0;
        for i in 1..3 {
            if h[i] - l[i].abs() < h[axis] - l[axis].abs() {
                axis = i;
            }
        }
        let depth = h[axis] - l[axis].abs() + need + EXIT_SLACK_M;
        p[axis] = if l[axis] >= 0.0 { -depth } else { depth };
    }
    Some(xform(
        basis,
        Vector3::new(p[0] as f32, p[1] as f32, p[2] as f32),
    ))
}

#[cfg(test)]
mod tests;
