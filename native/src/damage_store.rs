// The damage store (M10-T75, Q94): one owner for every hull's, section's and part's points. Fighters' hulls, capital ships'
// sections, mounts, engines and bays (Q72's rules) and the station's sections and grid mounts live here; every source of
// damage lands through it (bolts, rams and the console one call a hit, beams one batch a tick) and GDScript keeps read-only
// copies, refreshed from the write log each call returns. Engine-free (test_sim_core reads this file): numbers in, numbers
// and a log out, no statics.
// A hit's damage is tested as GDScript tests it, `not (damage > 0.0)`, so NaN is no damage.
#![allow(clippy::neg_cmp_op_on_partial_ord)]
pub mod capital;
pub mod landing;
pub mod station;

use godot::builtin::Vector3;

use capital::Capital;
use station::{GridMounts, Station, StationSections};

/// A log entry is four numbers: what happened, then up to three values (an index, a state, points).
#[cfg_attr(not(test), allow(dead_code))] // GDScript reads entries four at a time; the tests here do too
pub const LOG_WIDTH: usize = 4;

/// Hull points of one ship: `HullHealth`'s rules.
#[derive(Clone, Debug, PartialEq)]
pub struct Hull {
    pub max_hp: f64,
    pub hp: f64,
    pub destroyed: bool,
    pub destroyed_now: bool,
}

/// A capacity below this (zero, negative or NaN) is raised to it, so a fraction never divides by zero.
pub const MIN_MAX_HP: f64 = 1e-3;

impl Hull {
    pub fn new(max_hp: f64) -> Self {
        let max_hp = if max_hp >= MIN_MAX_HP { max_hp } else { MIN_MAX_HP };
        Hull {
            max_hp,
            hp: max_hp,
            destroyed: false,
            destroyed_now: false,
        }
    }

    /// Takes up to `amount` off and returns what it took: nothing for a negative, zero or NaN amount or a dead hull.
    pub fn apply(&mut self, amount: f64) -> f64 {
        self.destroyed_now = false;
        if self.destroyed || !(amount > 0.0) {
            return 0.0;
        }
        let applied = if amount < self.hp { amount } else { self.hp };
        self.hp -= applied;
        if self.hp <= 0.0 {
            self.hp = 0.0;
            self.destroyed = true;
            self.destroyed_now = true;
        }
        applied
    }

    pub fn restore(&mut self) {
        self.hp = self.max_hp;
        self.destroyed = false;
        self.destroyed_now = false;
    }
}

/// What a call changed, in order: each entry `[code, a, b, c]`. GDScript replays it onto its copies and raises the signals at
/// the entries that are events, so a listener sees the state as it stood at that point of the rules.
#[derive(Default, Debug)]
pub struct Log {
    pub entries: Vec<f64>,
}

impl Log {
    pub fn push(&mut self, code: u8, a: f64, b: f64, c: f64) {
        self.entries.extend_from_slice(&[f64::from(code), a, b, c]);
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }
}

/// Slots reused once freed, so a handle stays an index.
#[derive(Debug)]
pub struct Slots<T> {
    items: Vec<Option<T>>,
    free: Vec<usize>,
}

impl<T> Default for Slots<T> {
    fn default() -> Self {
        Slots {
            items: Vec::new(),
            free: Vec::new(),
        }
    }
}

impl<T> Slots<T> {
    pub fn add(&mut self, item: T) -> usize {
        if let Some(i) = self.free.pop() {
            self.items[i] = Some(item);
            i
        } else {
            self.items.push(Some(item));
            self.items.len() - 1
        }
    }

    pub fn remove(&mut self, id: i64) -> bool {
        match usize::try_from(id).ok().and_then(|i| self.items.get_mut(i)) {
            Some(slot) if slot.is_some() => {
                *slot = None;
                self.free.push(id as usize);
                true
            }
            _ => false,
        }
    }

    pub fn get(&self, id: i64) -> Option<&T> {
        usize::try_from(id)
            .ok()
            .and_then(|i| self.items.get(i))
            .and_then(Option::as_ref)
    }

    pub fn get_mut(&mut self, id: i64) -> Option<&mut T> {
        usize::try_from(id)
            .ok()
            .and_then(|i| self.items.get_mut(i))
            .and_then(Option::as_mut)
    }

    /// How many are live.
    pub fn live(&self) -> usize {
        self.items.len() - self.free.len()
    }
}

/// Every ledger, by kind.
#[derive(Default, Debug)]
pub struct DamageStore {
    pub hulls: Slots<Hull>,
    pub capitals: Slots<Capital>,
    pub sections: Slots<StationSections>,
    pub mounts: Slots<GridMounts>,
    pub stations: Slots<Station>,
}

impl DamageStore {
    /// A hit on station `id` at `local` on body `body`: its sections and grid mounts are the station's own ledgers.
    pub fn station_hit(&mut self, id: i64, body: i32, local: Vector3, damage: f64, log: &mut Log) -> f64 {
        let Some(st) = self.stations.get_mut(id) else {
            return 0.0;
        };
        let Some(secs) = self.sections.get_mut(st.sections) else {
            return 0.0;
        };
        let mounts = st.mounts.and_then(|m| self.mounts.get_mut(m));
        st.hit(secs, mounts, body, local, damage, log)
    }

    /// A hit on station `id`'s section `index` itself, no mount struck.
    pub fn station_hit_section(&mut self, id: i64, index: i64, damage: f64, log: &mut Log) -> f64 {
        let Some(st) = self.stations.get_mut(id) else {
            return 0.0;
        };
        let Some(secs) = self.sections.get_mut(st.sections) else {
            return 0.0;
        };
        st.hit_section(secs, index, damage, log)
    }

    /// Station `id` whole again: its sections, hull and power (its grid mounts are the grid's to heal).
    pub fn station_restore(&mut self, id: i64) {
        let Some(st) = self.stations.get_mut(id) else {
            return;
        };
        if let Some(secs) = self.sections.get_mut(st.sections) {
            secs.restore();
        }
        st.restore();
    }
}

#[cfg(test)]
mod tests;
