// The station's damage (M7-T06, Q5; M10-T65, Q72; Q78), as `StationSections`, `GridMountHealth` and `StationDamage` laid it
// down: the capitals' rules on Babylon 5's own ledgers. A grid mount within reach takes a hit in full and the hull half; the
// command (bridge) and reactor sections are subsystems too; any other hit is hull damage off its section and the total; a lost
// section's hits go to the total. The reactor or the hull at 0 destroys it; the command at 0, the reactor at a tenth or the
// hull below a tenth leave a hulk.
use godot::builtin::Vector3;

use super::Log;
use crate::v3::{clamp_cw, dist_sq, length, maxf, minf, sub};

/// A point this far outside every section box of its body still lands in the nearest one (`StationSections.SNAP_M`).
pub const SNAP_M: f64 = 50.0;

/// Section kinds the rules tell apart.
pub const KIND_PLAIN: u8 = 0;
pub const KIND_BRIDGE: u8 = 1;
pub const KIND_REACTOR: u8 = 2;

/// Log codes. Writes: a section's or a mount's health, the hull's points. Events: a section lost, a mount knocked out, a
/// hulk, destroyed (the section that blew, or -1 for the hull).
pub const SEC_HEALTH: u8 = 21;
pub const SEC_LOST: u8 = 22;
pub const MOUNT_HEALTH: u8 = 23;
pub const MOUNT_OUT: u8 = 24;
pub const HULL_HP: u8 = 25;
pub const BECAME_DISABLED: u8 = 26;
pub const BECAME_DESTROYED: u8 = 27;

/// The damage sections: each one's body, box (in that body's frame) and health.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct StationSections {
    pub body: Vec<i32>,
    pub lo: Vec<Vector3>,
    pub end: Vec<Vector3>,
    pub health: Vec<f64>,
    pub max_health: Vec<f64>,
}

impl StationSections {
    pub fn count(&self) -> usize {
        self.health.len()
    }

    /// The section a hit at `local` on `body` lands in: the box that holds it, else the nearest within `SNAP_M`; -1 for none.
    pub fn section_at(&self, body: i32, local: Vector3) -> i64 {
        let mut best = -1;
        let mut best_d = SNAP_M;
        for i in 0..self.body.len() {
            if self.body[i] != body {
                continue;
            }
            let d = length(sub(clamp_cw(local, self.lo[i], self.end[i]), local));
            if f64::from(d) < best_d || (d == 0.0 && best_d > 0.0) {
                best = i as i64;
                best_d = f64::from(d);
            }
            if d == 0.0 {
                break;
            }
        }
        best
    }

    /// Takes `amount` off section `index` (never below zero); true when this lost it.
    pub fn damage(&mut self, index: i64, amount: f64, log: &mut Log) -> bool {
        let Some(i) = usize::try_from(index).ok().filter(|&i| i < self.health.len()) else {
            return false;
        };
        if amount <= 0.0 || self.health[i] <= 0.0 {
            return false;
        }
        self.health[i] = maxf(self.health[i] - amount, 0.0);
        log.push(SEC_HEALTH, i as f64, self.health[i], 0.0);
        if self.health[i] > 0.0 {
            return false;
        }
        log.push(SEC_LOST, i as f64, 0.0, 0.0);
        true
    }

    /// Adds `amount` to section `index` (never above full); true when this brought a lost section back.
    pub fn repair(&mut self, index: i64, amount: f64) -> bool {
        let Some(i) = usize::try_from(index).ok().filter(|&i| i < self.health.len()) else {
            return false;
        };
        if amount <= 0.0 {
            return false;
        }
        let was_lost = self.health[i] <= 0.0;
        self.health[i] = minf(self.health[i] + amount, self.max_health[i]);
        was_lost && self.health[i] > 0.0
    }

    pub fn is_lost(&self, index: i64) -> bool {
        usize::try_from(index)
            .ok()
            .and_then(|i| self.health.get(i))
            .is_some_and(|&h| h <= 0.0)
    }

    pub fn fraction(&self, i: usize) -> f64 {
        self.health[i] / maxf(self.max_health[i], 1e-6)
    }

    pub fn restore(&mut self) {
        self.health.clone_from(&self.max_health);
    }
}

/// The grid mounts' own health: each one's body, place, the radius a hit counts within and its health.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct GridMounts {
    pub body: Vec<i32>,
    pub pos: Vec<Vector3>,
    pub radius: Vec<f64>,
    pub health: Vec<f64>,
    pub max_health: Vec<f64>,
}

impl GridMounts {
    /// The live mount on `body` whose radius holds `point`, the nearest of them; -1 for none.
    pub fn nearest(&self, body: i32, point: Vector3) -> i64 {
        let mut best = -1;
        let mut best_d = f64::INFINITY;
        for i in 0..self.body.len() {
            if self.body[i] != body || self.health[i] <= 0.0 {
                continue;
            }
            let r = self.radius[i];
            let d = f64::from(dist_sq(self.pos[i], point));
            if d <= r * r && d < best_d {
                best_d = d;
                best = i as i64;
            }
        }
        best
    }

    /// Takes `amount` off mount `index` alone; true when that knocked it out.
    pub fn wear(&mut self, index: i64, amount: f64, log: &mut Log) -> bool {
        let Some(i) = usize::try_from(index).ok().filter(|&i| i < self.health.len()) else {
            return false;
        };
        if amount <= 0.0 || self.health[i] <= 0.0 {
            return false;
        }
        self.health[i] = maxf(self.health[i] - amount, 0.0);
        log.push(MOUNT_HEALTH, i as f64, self.health[i], 0.0);
        self.health[i] <= 0.0
    }

    /// Adds `amount` to mount `index` (never above full); true when this brought a knocked-out mount back.
    pub fn heal(&mut self, index: i64, amount: f64) -> bool {
        let Some(i) = usize::try_from(index).ok().filter(|&i| i < self.health.len()) else {
            return false;
        };
        if amount <= 0.0 {
            return false;
        }
        let was_out = self.health[i] <= 0.0;
        self.health[i] = minf(self.health[i] + amount, self.max_health[i]);
        was_out && self.health[i] > 0.0
    }

    /// Whole again; true when it was knocked out.
    pub fn repair(&mut self, index: i64) -> bool {
        let Some(i) = usize::try_from(index).ok().filter(|&i| i < self.health.len()) else {
            return false;
        };
        let was_out = self.health[i] <= 0.0;
        self.health[i] = self.max_health[i];
        was_out
    }
}

/// The station's rules over its sections and grid mounts, and its hull's total.
#[derive(Clone, Debug, PartialEq)]
pub struct Station {
    pub sections: i64,
    pub mounts: Option<i64>,
    pub kinds: Vec<u8>,
    pub subsystem_hull_share: f64,
    pub hulk_below: f64,
    pub reactor_shutdown_at: f64,
    pub hull_max: f64,
    pub hull_hp: f64,
    pub disabled: bool,
    pub destroyed: bool,
    pub blown: i64,
}

impl Station {
    pub fn hit(&mut self, secs: &mut StationSections, mounts: Option<&mut GridMounts>, body: i32, local: Vector3, damage: f64, log: &mut Log) -> f64 {
        if self.destroyed || !(damage > 0.0) {
            return 0.0;
        }
        let index = secs.section_at(body, local);
        let mount = match &mounts {
            Some(m) if index >= 0 && !secs.is_lost(index) => m.nearest(body, local),
            _ => -1,
        };
        self.land(secs, mounts, index, mount, damage, log)
    }

    pub fn hit_section(&mut self, secs: &mut StationSections, index: i64, damage: f64, log: &mut Log) -> f64 {
        if self.destroyed || !(damage > 0.0) || index < 0 || index as usize >= secs.count() {
            return 0.0;
        }
        self.land(secs, None, index, -1, damage, log)
    }

    pub fn restore(&mut self) {
        self.hull_hp = self.hull_max;
        self.disabled = false;
        self.destroyed = false;
        self.blown = -1;
    }

    fn is_subsystem(&self, index: i64) -> bool {
        usize::try_from(index)
            .ok()
            .and_then(|i| self.kinds.get(i))
            .is_some_and(|&k| k == KIND_BRIDGE || k == KIND_REACTOR)
    }

    fn land(&mut self, secs: &mut StationSections, mounts: Option<&mut GridMounts>, index: i64, mount: i64, damage: f64, log: &mut Log) -> f64 {
        let mut to_hull = damage;
        if index >= 0 && !secs.is_lost(index) {
            if mount >= 0 {
                if mounts.is_some_and(|m| m.wear(mount, damage, log)) {
                    log.push(MOUNT_OUT, mount as f64, 0.0, 0.0);
                }
                to_hull = damage * self.subsystem_hull_share;
            } else if self.is_subsystem(index) {
                self.wear_section(secs, index, damage, log);
                to_hull = damage * self.subsystem_hull_share;
            } else {
                self.wear_section(secs, index, damage, log);
            }
        }
        if self.destroyed {
            return to_hull;
        }
        self.hull_hp = maxf(self.hull_hp - to_hull, 0.0);
        log.push(HULL_HP, self.hull_hp, 0.0, 0.0);
        if self.hull_hp <= 0.0 {
            self.destroy(-1, log);
        } else if !self.disabled && self.hull_hp < self.hulk_below * self.hull_max {
            self.disable(log);
        }
        to_hull
    }

    fn wear_section(&mut self, secs: &mut StationSections, index: i64, amount: f64, log: &mut Log) {
        let lost = secs.damage(index, amount, log);
        let kind = self.kinds.get(index as usize).copied().unwrap_or(KIND_PLAIN);
        if kind == KIND_REACTOR {
            if lost {
                self.destroy(index, log);
            } else if secs.fraction(index as usize) <= self.reactor_shutdown_at {
                self.disable(log);
            }
        } else if kind == KIND_BRIDGE && lost {
            self.disable(log);
        }
    }

    fn disable(&mut self, log: &mut Log) {
        if self.disabled || self.destroyed {
            return;
        }
        self.disabled = true;
        log.push(BECAME_DISABLED, 0.0, 0.0, 0.0);
    }

    fn destroy(&mut self, section: i64, log: &mut Log) {
        if self.destroyed {
            return;
        }
        self.destroyed = true;
        self.blown = section;
        self.hull_hp = 0.0;
        log.push(BECAME_DESTROYED, section as f64, 0.0, 0.0);
    }
}
