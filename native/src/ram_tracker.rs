// The ram tracker (M5-T33, docs/architecture.md 18.23): the bookkeeping behind ram detection, moved from GDScript's
// `RamTracker` (now the reference in tests/fixtures/). Engine-free: plain data in, plain data out; the shell
// (`ram_contacts.rs`) reads Jolt and the core's rows and hands the columns over.
//
// Once per physics tick, in this order:
//
// 1. `feed`: every rigid body as read this tick and the contacts Jolt reported. Opens a window for each new contact and
//    measures the open ones; returns which bodies hold a measured window. `land` then takes those bodies' ram limits
//    and returns the contact rams that land now.
// 2. For each pair the resolver sweeps: `swept_meeting` when the sweep found their volumes meeting (true = ram now).
//    For each rigid pair it does not sweep (below tunnelling speed): `keep_touching`.
// 3. `end_tick`.
//
// Contact windows. When a body reports a contact with a body it did not touch on the last tick, a window opens for that
// pair (hull, other). For `CONTACT_WINDOW_TICKS` ticks, counting the first, it tracks the largest change of the hull's
// velocity from before the contact that the hull's own forces do not explain. Jolt may report a speculative contact a
// tick before the bounce and spread the bounce over two steps, hence the window. The ram lands once, when the window
// closes, or at once when the change is already lethal. A body that leaves play loses its windows; a body seen without
// the tick before (spawned, respawned) opens none.
//
// Swept rams. A pair the sweep finds meeting is rammed when it did not meet on the last tick. The ram cancels the
// pair's open contact windows, and for `SWEPT_GRACE_TICKS` ticks after it the pair opens no contact window and takes no
// other swept ram: the sweep predicts the hit for the coming step, and Jolt reports the same collision as a contact
// afterwards. While Jolt holds a pair that met in contact and the resolver does not sweep it, `keep_touching` keeps it
// met, so it is not rammed again when the two separate.
use std::collections::{HashMap, HashSet};

use godot::builtin::Vector3;

use crate::v3::{add, length, scale, sub};

/// Ticks over which a new contact's velocity change is measured, counting the tick it is first reported.
pub const CONTACT_WINDOW_TICKS: i32 = 3;
/// Ticks after a swept ram during which its pair opens no contact window and takes no other swept ram.
pub const SWEPT_GRACE_TICKS: i64 = CONTACT_WINDOW_TICKS as i64 + 1;

/// A contact ram: the hull, the body it met, the hull's velocity change and the share of its hull that takes, where
/// they touch (a World-local point and the hull's surface normal there) and how fast the other closed on the tick
/// before the contact.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Ram {
    pub hull_id: i64,
    pub other_id: i64,
    pub dv: f64,
    pub severity: f64,
    pub point: Vector3,
    pub normal: Vector3,
    pub relative_speed: f64,
}

// One open contact window.
struct Window {
    ram: Ram,
    v_before: Vector3,
    own_dv: Vector3,
    ticks_left: i32,
}

/// This tick's bodies and contacts, column by column: every rigid body read (`ids`, `velocities`, `accels`: what its
/// own forces add to its velocity per second), and for the bodies Jolt reports touching something (`touched`, indices
/// into `ids`) their contacts: body `touched[t]` holds `others[starts[t]..starts[t + 1]]` with the matching `points`
/// and `normals`.
pub struct Feed<'a> {
    pub ids: &'a [i64],
    pub velocities: &'a [Vector3],
    pub accels: &'a [Vector3],
    pub touched: &'a [u32],
    pub starts: &'a [u32],
    pub others: &'a [i64],
    pub points: &'a [Vector3],
    pub normals: &'a [Vector3],
}

type Pair = (i64, i64);

/// The state between ticks. Pairs are keyed by their two body ids as integers.
#[derive(Default)]
pub struct Tracker {
    tick: i64,
    // The open windows in the order they opened, and their (hull, other) keys.
    windows: Vec<Window>,
    window_keys: HashSet<Pair>,
    in_contact: HashSet<Pair>,
    touching: HashSet<Pair>,
    touching_now: HashSet<Pair>,
    // Pair -> the tick of its last swept ram.
    swept_at: HashMap<Pair, i64>,
    // The last tick: the bodies, their index by id (filled only when something asks), and who touched whom.
    prev_ids: Vec<i64>,
    prev_velocities: Vec<Vector3>,
    prev_accels: Vec<Vector3>,
    prev_index: HashMap<i64, u32>,
    prev_indexed: bool,
    prev_touches: HashSet<Pair>,
    // Scratch for this tick's side of the same.
    now_index: HashMap<i64, u32>,
    now_touches: HashSet<Pair>,
}

fn pair(a: i64, b: i64) -> Pair {
    (a.min(b), a.max(b))
}

/// 0..1, the share of the hull a velocity change of `dv` takes (`RamMath.severity`): nothing up to `safe`, all of it
/// from `lethal`, quadratic in between.
pub fn severity(dv: f64, safe: f64, lethal: f64) -> f64 {
    if dv <= safe {
        return 0.0;
    }
    if lethal <= safe {
        return 1.0;
    }
    let x = ((dv - safe) / (lethal - safe)).clamp(0.0, 1.0);
    x * x
}

impl Tracker {
    /// Phase 1: opens windows for the new contacts and measures the open ones. Returns, per window still held, its
    /// hull's index in `feed.ids`, in the windows' order: `land` wants those hulls' limits.
    pub fn feed(&mut self, feed: &Feed, delta: f64) -> Vec<u32> {
        self.tick += 1;
        self.in_contact.clear();
        self.touching_now.clear();
        self.now_touches.clear();
        for (t, &at) in feed.touched.iter().enumerate() {
            let id = feed.ids[at as usize];
            let prev = self.prev_at(id);
            for c in feed.starts[t] as usize..feed.starts[t + 1] as usize {
                let other = feed.others[c];
                if !self.now_touches.insert((id, other)) {
                    continue; // only a pair's first report counts
                }
                self.in_contact.insert(pair(id, other));
                let Some(p) = prev else { continue };
                if self.prev_touches.contains(&(id, other))
                    || self.window_keys.contains(&(id, other))
                    || self.swept_recently(pair(id, other))
                {
                    continue;
                }
                let v_before = self.prev_velocities[p];
                let other_v = match self.prev_at(other) {
                    Some(o) => self.prev_velocities[o],
                    None => Vector3::ZERO,
                };
                self.window_keys.insert((id, other));
                self.windows.push(Window {
                    ram: Ram {
                        hull_id: id,
                        other_id: other,
                        dv: 0.0,
                        severity: 0.0,
                        point: feed.points[c],
                        normal: feed.normals[c],
                        relative_speed: f64::from(length(sub(v_before, other_v))),
                    },
                    v_before,
                    own_dv: Vector3::ZERO,
                    ticks_left: CONTACT_WINDOW_TICKS,
                });
            }
        }
        let mut asked: Vec<u32> = Vec::new();
        let indexed = !self.windows.is_empty();
        if indexed {
            self.now_index.clear();
            for (k, &id) in feed.ids.iter().enumerate() {
                self.now_index.insert(id, k as u32);
            }
            let mut windows = std::mem::take(&mut self.windows);
            let dt = delta as f32;
            windows.retain_mut(|w| {
                let hull = w.ram.hull_id;
                let now = find(&self.now_index, hull);
                let (Some(c), Some(p)) = (now, self.prev_at(hull)) else {
                    // the body left play (or was away a tick): its windows go
                    self.window_keys.remove(&(w.ram.hull_id, w.ram.other_id));
                    return false;
                };
                w.own_dv = add(w.own_dv, scale(self.prev_accels[p], dt));
                let change = sub(sub(feed.velocities[c], w.v_before), w.own_dv);
                let dv = f64::from(length(change));
                if dv > w.ram.dv {
                    w.ram.dv = dv;
                }
                w.ticks_left -= 1;
                asked.push(c as u32);
                true
            });
            self.windows = windows;
        }
        self.prev_ids.clear();
        self.prev_ids.extend_from_slice(feed.ids);
        self.prev_velocities.clear();
        self.prev_velocities.extend_from_slice(feed.velocities);
        self.prev_accels.clear();
        self.prev_accels.extend_from_slice(feed.accels);
        std::mem::swap(&mut self.prev_index, &mut self.now_index);
        self.prev_indexed = indexed;
        std::mem::swap(&mut self.prev_touches, &mut self.now_touches);
        asked
    }

    /// Sets what body `at` (an index into the last `feed`'s ids) adds to its own velocity per second, for a body whose
    /// acceleration the caller learns only after the feed.
    pub fn set_accel(&mut self, at: usize, accel: Vector3) {
        if let Some(slot) = self.prev_accels.get_mut(at) {
            *slot = accel;
        }
    }

    /// Phase 1, after `feed`: `limits` holds `[safe_dv, lethal_dv]` for each window `feed` returned, in its order. The
    /// rams whose windows close (or turn lethal) this tick.
    pub fn land(&mut self, limits: &[f64]) -> Vec<Ram> {
        let mut landed: Vec<Ram> = Vec::new();
        let mut k = 0;
        let mut windows = std::mem::take(&mut self.windows);
        windows.retain_mut(|w| {
            let (safe, lethal) = match limits.get(k * 2..k * 2 + 2) {
                Some(l) => (l[0], l[1]),
                None => (f64::INFINITY, f64::INFINITY),
            };
            k += 1;
            w.ram.severity = severity(w.ram.dv, safe, lethal);
            if w.ticks_left > 0 && w.ram.severity < 1.0 {
                return true;
            }
            if w.ram.severity > 0.0 {
                landed.push(w.ram);
            }
            self.window_keys.remove(&(w.ram.hull_id, w.ram.other_id));
            false
        });
        self.windows = windows;
        landed
    }

    /// True when Jolt reported `a` and `b` touching this tick (valid after `feed`).
    pub fn in_contact(&self, a: i64, b: i64) -> bool {
        self.in_contact.contains(&pair(a, b))
    }

    /// How many contact windows are open.
    pub fn open_windows(&self) -> usize {
        self.windows.len()
    }

    /// Phase 2: the sweep found the volumes of `a` and `b` meeting this tick. True when that is a new ram: they did
    /// not meet on the last tick and took no swept ram in the last `SWEPT_GRACE_TICKS` ticks. A ram cancels the pair's
    /// open contact windows.
    pub fn swept_meeting(&mut self, a: i64, b: i64) -> bool {
        let key = pair(a, b);
        self.touching_now.insert(key);
        if self.touching.contains(&key) || self.swept_recently(key) {
            return false;
        }
        self.swept_at.insert(key, self.tick);
        let had_ab = self.window_keys.remove(&(a, b));
        let had_ba = self.window_keys.remove(&(b, a));
        if had_ab || had_ba {
            self.windows.retain(|w| {
                !((w.ram.hull_id == a && w.ram.other_id == b)
                    || (w.ram.hull_id == b && w.ram.other_id == a))
            });
        }
        true
    }

    /// Phase 2, for a rigid pair the resolver does not sweep this tick: a pair that met stays met while Jolt holds it
    /// in contact.
    pub fn keep_touching(&mut self, a: i64, b: i64) {
        if self.touching.is_empty() {
            return;
        }
        let key = pair(a, b);
        if self.in_contact.contains(&key) && self.touching.contains(&key) {
            self.touching_now.insert(key);
        }
    }

    /// Phase 3: the tick is over.
    pub fn end_tick(&mut self) {
        std::mem::swap(&mut self.touching, &mut self.touching_now);
        self.touching_now.clear();
        if !self.swept_at.is_empty() {
            let tick = self.tick;
            self.swept_at.retain(|_, at| tick - *at < SWEPT_GRACE_TICKS);
        }
    }

    /// The World was rebased by `offset`: the open windows' World-local points move by `-offset`, as the hulls did.
    pub fn shift(&mut self, offset: Vector3) {
        for w in self.windows.iter_mut() {
            w.ram.point = sub(w.ram.point, offset);
        }
    }

    /// Forgets everything (ram damage switched off): no velocity, contact, window or grace carries over.
    pub fn reset(&mut self) {
        self.tick = 0;
        self.windows.clear();
        self.window_keys.clear();
        self.in_contact.clear();
        self.touching.clear();
        self.touching_now.clear();
        self.swept_at.clear();
        self.prev_ids.clear();
        self.prev_velocities.clear();
        self.prev_accels.clear();
        self.prev_index.clear();
        self.prev_indexed = false;
        self.prev_touches.clear();
    }

    fn swept_recently(&self, key: Pair) -> bool {
        let key = &key;
        match self.swept_at.get(key) {
            Some(&at) => self.tick - at <= SWEPT_GRACE_TICKS,
            None => false,
        }
    }

    // Where body `id` sat in the last tick's columns. The index is built on the first ask after a quiet tick, so a tick
    // with no contact and no window pays nothing for it.
    fn prev_at(&mut self, id: i64) -> Option<usize> {
        if !self.prev_indexed {
            self.prev_index.clear();
            for (k, &body) in self.prev_ids.iter().enumerate() {
                self.prev_index.insert(body, k as u32);
            }
            self.prev_indexed = true;
        }
        find(&self.prev_index, id)
    }
}

// Where body `id` sits in the columns `index` was built from.
fn find(index: &HashMap<i64, u32>, id: i64) -> Option<usize> {
    let key = &id;
    index.get(key).map(|&k| k as usize)
}

#[cfg(test)]
mod tests;
