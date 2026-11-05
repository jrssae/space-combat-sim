// The bolt kernels (M4-T35, docs/architecture.md 17.13): the core's own bolts stepped as `Projectile._physics_process`
// stepped a node, the pulse cannon's gate and capacitor as `PulseCannonGate` and `WeaponCapacitor` decide them, a shot's
// start and velocity as `PulseCannon.step` computes them, and the multimesh transforms the renderer draws. Engine-free:
// plain data in and out, under test_sim_core's guard.
use godot::builtin::{Basis, Vector3};

use crate::rows::Bolts;
use crate::v3::{add, col_a, col_b, col_c, cross, dot, maxf, minf, neg, normalized, scale, sub};

/// `PulseCannonGate.TIME_EPSILON_S`: a clock summed from ticks reaches an interval a few ulps short.
pub const TIME_EPSILON_S: f64 = 1e-6;
/// `WeaponCapacitor.CHARGE_EPSILON`.
pub const CHARGE_EPSILON: f64 = 1e-9;
/// Floats per multimesh instance: three rows of a basis with the origin in the fourth column.
pub const INSTANCE_FLOATS: usize = 12;

/// Expires the owned bolts whose time is up and moves the rest, as `Projectile._physics_process` does for a node: the
/// expiry test first (the bolt is gone before it moves), then `last_step = velocity * delta` with the delta rounded to 32
/// bits and `position += last_step`. A bolt launched this tick does not move yet (§15.3: its launch tick sweeps only its
/// muzzle). Returns how many expired.
pub fn step(bolts: &mut Bolts, delta: f64, now_s: f64, tick: i64) -> usize {
    let owned = bolts.owned;
    let mut keep: Vec<bool> = Vec::with_capacity(owned);
    let mut expired = 0;
    for i in 0..owned {
        let alive = now_s < bolts.expires_at[i];
        keep.push(alive);
        if !alive {
            expired += 1;
        }
    }
    if expired > 0 {
        bolts.retain_owned(&keep);
    }
    let dt = delta as f32;
    for i in 0..bolts.owned {
        if bolts.launched[i] >= tick {
            continue;
        }
        let step = scale(bolts.velocities[i], dt);
        bolts.last_steps[i] = step;
        bolts.positions[i] = add(bolts.positions[i], step);
    }
    expired
}

/// Drops the owned bolts a hit spent (a spent node is freed at the end of its frame, gone by the next tick's sync).
/// Returns how many went.
pub fn drop_spent(bolts: &mut Bolts) -> usize {
    let owned = bolts.owned;
    let keep: Vec<bool> = (0..owned).map(|i| !bolts.spent[i]).collect();
    let gone = keep.iter().filter(|&&k| !k).count();
    if gone > 0 {
        bolts.retain_owned(&keep);
    }
    gone
}

/// `WeaponCapacitor`: the energy store the shots are paid from.
#[derive(Clone, Copy, Debug)]
pub struct Capacitor {
    pub capacity: f64,
    pub cost_per_shot: f64,
    pub recharge_per_s: f64,
    charge: f64,
    // Sim time at which `charge` was exact; NaN until the first advance or spend.
    stamp_s: f64,
}

impl Capacitor {
    pub fn new(capacity: f64, cost_per_shot: f64, recharge_per_s: f64) -> Self {
        let capacity = maxf(0.0, capacity);
        Self {
            capacity,
            cost_per_shot: maxf(0.0, cost_per_shot),
            recharge_per_s: maxf(0.0, recharge_per_s),
            charge: capacity,
            stamp_s: f64::NAN,
        }
    }

    /// Energy units in the store at `now_s`.
    pub fn charge_at(&self, now_s: f64) -> f64 {
        let elapsed = if self.stamp_s.is_nan() {
            0.0
        } else {
            maxf(0.0, now_s - self.stamp_s)
        };
        minf(self.capacity, self.charge + self.recharge_per_s * elapsed)
    }

    /// 0..1 at `now_s`; 0 for a capacitor without capacity.
    pub fn fraction_at(&self, now_s: f64) -> f64 {
        if self.capacity > 0.0 {
            (self.charge_at(now_s) / self.capacity).clamp(0.0, 1.0)
        } else {
            0.0
        }
    }

    /// Folds the time up to `now_s` into the charge.
    pub fn advance(&mut self, now_s: f64) {
        self.charge = self.charge_at(now_s);
        self.stamp_s = now_s;
    }

    /// Pays for `shots` projectiles at `now_s`; false and nothing taken when the store cannot cover them.
    pub fn spend(&mut self, shots: i64, now_s: f64) -> bool {
        self.advance(now_s);
        let need = shots as f64 * self.cost_per_shot;
        if self.charge + CHARGE_EPSILON < need {
            return false;
        }
        self.charge = maxf(0.0, self.charge - need);
        true
    }

    pub fn refill(&mut self) {
        self.charge = self.capacity;
    }

    /// Sets the charge to `fraction` of the capacity as of `now_s`; a NaN changes nothing.
    pub fn set_fraction(&mut self, fraction: f64, now_s: f64) {
        if fraction.is_nan() {
            return;
        }
        self.advance(now_s);
        self.charge = fraction.clamp(0.0, 1.0) * self.capacity;
    }
}

/// `PulseCannonGate`: which muzzles fire on a tick. `linked` is the mode (false: alternating).
#[derive(Clone, Copy, Debug)]
pub struct Gate {
    pub linked: bool,
    pub muzzle_count: usize,
    pub interval_s: f64,
    pub capacitor: Option<Capacitor>,
    ready_at_s: f64,
    next_alternating: usize,
}

impl Gate {
    pub fn new(muzzle_count: usize, interval_s: f64, capacitor: Option<Capacitor>) -> Self {
        let mut gate = Self {
            linked: false,
            muzzle_count: 1,
            interval_s: 0.25,
            capacitor,
            ready_at_s: f64::NEG_INFINITY,
            next_alternating: 0,
        };
        gate.configure(muzzle_count, interval_s);
        gate
    }

    /// Sets the muzzle count (at least 1) and the interval (above zero), keeping the cooldown and mode.
    pub fn configure(&mut self, muzzle_count: usize, interval_s: f64) {
        self.muzzle_count = muzzle_count.max(1);
        self.interval_s = if interval_s > 0.0 { interval_s } else { 0.25 };
        self.next_alternating %= self.muzzle_count;
    }

    pub fn linked_interval_s(&self) -> f64 {
        self.interval_s * self.muzzle_count as f64
    }

    pub fn cycle_mode(&mut self) {
        self.linked = !self.linked;
    }

    /// The muzzles that fire this tick, into `fired` (cleared first).
    pub fn update(&mut self, now_s: f64, trigger_held: bool, fired: &mut Vec<usize>) {
        fired.clear();
        self.ready_at_s = self.clamped_ready_at(now_s);
        if let Some(cap) = self.capacitor.as_mut() {
            cap.advance(now_s);
        }
        if !trigger_held || now_s + TIME_EPSILON_S < self.ready_at_s {
            return;
        }
        let projectiles = if self.linked { self.muzzle_count } else { 1 };
        if let Some(cap) = self.capacitor.as_mut() {
            if !cap.spend(projectiles as i64, now_s) {
                return;
            }
        }
        if self.linked {
            fired.extend(0..self.muzzle_count);
            self.ready_at_s = now_s + self.linked_interval_s();
        } else {
            fired.push(self.next_alternating);
            self.next_alternating = (self.next_alternating + 1) % self.muzzle_count;
            self.ready_at_s = now_s + self.interval_s;
        }
    }

    /// Seconds until the next shot is allowed, 0 when ready.
    pub fn cooldown_remaining(&self, now_s: f64) -> f64 {
        maxf(0.0, self.clamped_ready_at(now_s) - now_s)
    }

    /// Forgets the cooldown and the muzzle turn, and refills the capacitor.
    pub fn reset(&mut self) {
        self.ready_at_s = f64::NEG_INFINITY;
        self.next_alternating = 0;
        if let Some(cap) = self.capacitor.as_mut() {
            cap.refill();
        }
    }

    /// The gate's ready time, for carrying it over to or from the GDScript gate.
    pub fn ready_at(&self) -> f64 {
        self.ready_at_s
    }

    pub fn set_ready_at(&mut self, ready_at_s: f64, next_alternating: usize) {
        self.ready_at_s = ready_at_s;
        self.next_alternating = next_alternating % self.muzzle_count;
    }

    pub fn next_alternating(&self) -> usize {
        self.next_alternating
    }

    // The cooldown never exceeds the longest interval (a clock reset must not stick the cannon).
    fn clamped_ready_at(&self, now_s: f64) -> f64 {
        minf(self.ready_at_s, now_s + self.linked_interval_s())
    }
}

/// A muzzle's World position as the engine composes a child's transform: `basis.rows[i].dot(local) + origin`.
pub fn muzzle_world(basis: &Basis, origin: Vector3, local: Vector3) -> Vector3 {
    Vector3::new(
        dot(basis.rows[0], local) + origin.x,
        dot(basis.rows[1], local) + origin.y,
        dot(basis.rows[2], local) + origin.z,
    )
}

/// A shot's velocity as `PulseCannon.step` computes it: along the body's nose, or toward the convergence point ahead of
/// the body when the weapon has one, at `muzzle_speed` on top of the body's velocity.
pub fn shot_velocity(
    basis: &Basis,
    position: Vector3,
    body_velocity: Vector3,
    muzzle: Vector3,
    convergence_m: f64,
    muzzle_speed: f64,
) -> Vector3 {
    let forward = neg(col_c(basis));
    let mut direction = forward;
    if convergence_m > 0.0 {
        let converge_at = add(position, scale(forward, convergence_m as f32));
        direction = normalized(sub(converge_at, muzzle));
    }
    add(body_velocity, scale(direction, muzzle_speed as f32))
}

/// The multimesh transforms of the owned bolts drawn with `look`, drawn `fraction` of the way from their last tick's
/// place to this one (so a frame between ticks shows them where the interpolated node would be), the capsule pointed
/// along the velocity as `Projectile._face` points it, `child` the mesh's own basis under the node, `visual_scale` the
/// chase camera's enlargement. Spent bolts are left out. Returns the instances written.
pub fn instance_transforms(
    bolts: &Bolts,
    look: u8,
    fraction: f32,
    visual_scale: f32,
    child: &Basis,
    out: &mut Vec<f32>,
) -> usize {
    out.clear();
    let mut count = 0;
    let behind = 1.0 - fraction;
    for i in 0..bolts.owned {
        if bolts.looks[i] != look || bolts.spent[i] {
            continue;
        }
        let origin = sub(bolts.positions[i], scale(bolts.last_steps[i], behind));
        let facing = looking_along(bolts.velocities[i]);
        let basis = mul(&facing, child);
        for row in 0..3 {
            let r = basis.rows[row];
            out.push(r.x * visual_scale);
            out.push(r.y * visual_scale);
            out.push(r.z * visual_scale);
            out.push(match row {
                0 => origin.x,
                1 => origin.y,
                _ => origin.z,
            });
        }
        count += 1;
    }
    count
}

// `Basis.looking_at(direction, up)` with `Projectile._face`'s up (UP, or RIGHT when the direction is near vertical); the
// identity for a near-zero direction, as the node leaves its orientation alone.
fn looking_along(direction: Vector3) -> Basis {
    let unit = normalized(direction);
    if dot(unit, unit) <= 1e-6 {
        return Basis::IDENTITY;
    }
    let up = if unit.y.abs() < 0.99 {
        Vector3::new(0.0, 1.0, 0.0)
    } else {
        Vector3::new(1.0, 0.0, 0.0)
    };
    let v_z = neg(unit);
    let v_x = normalized(cross(up, v_z));
    let v_y = cross(v_z, v_x);
    Basis {
        rows: [
            Vector3::new(v_x.x, v_y.x, v_z.x),
            Vector3::new(v_x.y, v_y.y, v_z.y),
            Vector3::new(v_x.z, v_y.z, v_z.z),
        ],
    }
}

// `Basis * Basis`, row by column.
fn mul(a: &Basis, b: &Basis) -> Basis {
    let (c0, c1, c2) = (col_a(b), col_b(b), col_c(b));
    Basis {
        rows: [
            Vector3::new(dot(a.rows[0], c0), dot(a.rows[0], c1), dot(a.rows[0], c2)),
            Vector3::new(dot(a.rows[1], c0), dot(a.rows[1], c1), dot(a.rows[1], c2)),
            Vector3::new(dot(a.rows[2], c0), dot(a.rows[2], c1), dot(a.rows[2], c2)),
        ],
    }
}
