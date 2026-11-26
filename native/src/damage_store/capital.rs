// A capital ship's damage by what a shot hits (M10-T08, D12.5; M10-T65, Q72; Q78), as `CapitalDamage` laid it down: only the
// part a shot strikes takes it (a mount, an engine or a bay within reach, or the bridge or reactor section itself, in full
// with half off the hull), any other hit is hull damage off its section and the total, a lost section's hits go to the total.
// Explosive sections blow at 0; the bridge at 0, a reactor at a tenth or the hull below a tenth leave a hulk. Every write and
// every event goes into the log in the order the rules make them.
use godot::builtin::Vector3;

use super::Log;
use crate::v3::{clamp_cw, clampf, length, maxf, sub};

/// Section kinds the rules tell apart (any other kind, 0, is plain hull).
pub const KIND_BRIDGE: u8 = 1;
pub const KIND_REACTOR: u8 = 2;
pub const KIND_MAGAZINE: u8 = 3;
pub const KIND_FUEL: u8 = 4;

/// `CapitalSection.State`.
pub const INTACT: u8 = 0;
pub const DAMAGED: u8 = 1;
pub const DISABLED: u8 = 2;
pub const DESTROYED: u8 = 3;

/// Which list a part is in.
pub const PART_MOUNT: u8 = 0;
pub const PART_ENGINE: u8 = 1;
pub const PART_BAY: u8 = 2;
/// `hit_part` on a section itself.
pub const PART_SECTION: u8 = 3;

/// Log codes. Writes: a section's points and state, a part's points, the hull's points. Events (a write and a signal):
/// a section changed state, a part was lost, the thrust changed, a hulk, a blown section.
pub const SEC_HP: u8 = 1;
pub const SEC_STATE: u8 = 2;
pub const SECTION_CHANGED: u8 = 3;
pub const PART_HP: u8 = 4;
pub const PART_LOST: u8 = 5;
pub const DRIVE_CHANGED: u8 = 6;
pub const HULL_HP: u8 = 7;
pub const BECAME_DISABLED: u8 = 8;
pub const BLEW: u8 = 9;
/// Direct writes only (GDScript's setters): a part alive or not, the flags, the blown section.
pub const PART_ALIVE: u8 = 10;
pub const FLAG_DISABLED: u8 = 11;
pub const FLAG_DESTROYED: u8 = 12;
pub const BLOWN: u8 = 13;

/// The rules' numbers (`section_damage`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rules {
    pub subsystem_hull_share: f64,
    pub power_stage_at: f64,
    pub power_stage_level: f64,
    pub reactor_shutdown_at: f64,
    pub hulk_below: f64,
}

/// One damage section: its points, state and box (body frame, rotating pieces at rest), and the parts it holds.
#[derive(Clone, Debug, PartialEq)]
pub struct Section {
    pub kind: u8,
    pub max_hp: f64,
    pub hp: f64,
    pub state: u8,
    pub lo: Vector3,
    pub end: Vector3,
    pub mounts: Vec<usize>,
    pub engines: Vec<usize>,
    pub bays: Vec<usize>,
}

impl Section {
    pub fn lost(&self) -> bool {
        self.state == DISABLED || self.state == DESTROYED
    }

    fn explosive(&self) -> bool {
        matches!(self.kind, KIND_REACTOR | KIND_MAGAZINE | KIND_FUEL)
    }

    fn is_subsystem(&self) -> bool {
        matches!(self.kind, KIND_BRIDGE | KIND_REACTOR)
    }

    pub fn fraction(&self) -> f64 {
        if self.max_hp > 0.0 {
            clampf(self.hp / self.max_hp, 0.0, 1.0)
        } else {
            0.0
        }
    }

    /// How far `p` is from its box, 0 inside.
    fn distance_to(&self, p: Vector3) -> f32 {
        length(sub(clamp_cw(p, self.lo, self.end), p))
    }
}

/// A weapon mount, an engine or a bay: its own points, where it sits and how close a hit must land (below 0: never by point).
#[derive(Clone, Debug, PartialEq)]
pub struct Part {
    pub section: i32,
    pub pos: Vector3,
    pub reach: f64,
    pub max_hp: f64,
    pub hp: f64,
    pub alive: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Capital {
    pub rules: Rules,
    pub sections: Vec<Section>,
    pub mounts: Vec<Part>,
    pub engines: Vec<Part>,
    pub bays: Vec<Part>,
    pub hull_max: f64,
    pub hull_hp: f64,
    pub disabled: bool,
    pub destroyed: bool,
    pub blown: i32,
}

impl Capital {
    /// The ledger from its sections and parts; each section lists the parts whose `section` names it, in their order.
    pub fn new(rules: Rules, mut sections: Vec<Section>, mounts: Vec<Part>, engines: Vec<Part>, bays: Vec<Part>, hull_max: f64) -> Self {
        for s in &mut sections {
            s.mounts.clear();
            s.engines.clear();
            s.bays.clear();
        }
        let n = sections.len();
        let owner = |p: &Part| usize::try_from(p.section).ok().filter(|&i| i < n);
        for (i, p) in mounts.iter().enumerate() {
            if let Some(s) = owner(p) {
                sections[s].mounts.push(i);
            }
        }
        for (i, p) in engines.iter().enumerate() {
            if let Some(s) = owner(p) {
                sections[s].engines.push(i);
            }
        }
        for (i, p) in bays.iter().enumerate() {
            if let Some(s) = owner(p) {
                sections[s].bays.push(i);
            }
        }
        Capital {
            rules,
            sections,
            mounts,
            engines,
            bays,
            hull_max,
            hull_hp: hull_max,
            disabled: false,
            destroyed: false,
            blown: -1,
        }
    }

    /// A hit of `damage` on section `section` (out of range: the nearest one by `point`) at `point`: on the part it strikes,
    /// else on the hull there. The hull points it removed.
    pub fn hit(&mut self, section: i64, point: Vector3, damage: f64, log: &mut Log) -> f64 {
        if self.destroyed || !(damage > 0.0) {
            return 0.0;
        }
        let s = usize::try_from(section)
            .ok()
            .filter(|&i| i < self.sections.len())
            .or_else(|| self.nearest(point));
        let part = s
            .filter(|&i| !self.sections[i].lost())
            .and_then(|i| self.part_at(i, point));
        self.land(s, part, damage, log)
    }

    /// A hit of `damage` on part `index` of list `kind` itself, or on a section (`PART_SECTION`). 0 for one it does not hold.
    pub fn hit_part(&mut self, kind: u8, index: i64, damage: f64, log: &mut Log) -> f64 {
        if self.destroyed || !(damage > 0.0) {
            return 0.0;
        }
        let Ok(i) = usize::try_from(index) else {
            return 0.0;
        };
        if kind == PART_SECTION {
            return if i < self.sections.len() { self.land(Some(i), None, damage, log) } else { 0.0 };
        }
        let Some(p) = self.list(kind).get(i) else {
            return 0.0;
        };
        let s = usize::try_from(p.section).ok().filter(|&k| k < self.sections.len());
        let part = if s.is_some_and(|k| self.sections[k].lost()) { None } else { Some((kind, i)) };
        self.land(s, part, damage, log)
    }

    /// The crew scuttles it: disabled at once. False when already disabled or destroyed.
    pub fn scuttle(&mut self, log: &mut Log) -> bool {
        if self.disabled || self.destroyed {
            return false;
        }
        self.disable(log);
        true
    }

    pub fn restore(&mut self) {
        for s in &mut self.sections {
            s.hp = s.max_hp;
            s.state = INTACT;
        }
        for p in self.mounts.iter_mut().chain(self.engines.iter_mut()).chain(self.bays.iter_mut()) {
            p.hp = p.max_hp;
            p.alive = true;
        }
        self.hull_hp = self.hull_max;
        self.disabled = false;
        self.destroyed = false;
        self.blown = -1;
    }

    /// A direct write (a setter in GDScript): `code` names the field as the log does.
    pub fn set(&mut self, code: u8, kind: u8, index: i64, value: f64) {
        let i = usize::try_from(index).unwrap_or(usize::MAX);
        match code {
            SEC_HP => {
                if let Some(s) = self.sections.get_mut(i) {
                    s.hp = value;
                }
            }
            SEC_STATE => {
                if let Some(s) = self.sections.get_mut(i) {
                    s.state = value as u8;
                }
            }
            PART_HP => {
                if let Some(p) = self.list_mut(kind).get_mut(i) {
                    p.hp = value;
                }
            }
            PART_ALIVE => {
                if let Some(p) = self.list_mut(kind).get_mut(i) {
                    p.alive = value != 0.0;
                }
            }
            HULL_HP => self.hull_hp = value,
            FLAG_DISABLED => self.disabled = value != 0.0,
            FLAG_DESTROYED => self.destroyed = value != 0.0,
            BLOWN => self.blown = value as i32,
            _ => {}
        }
    }

    /// The share of full power: 1, or the stage's level while a reactor is below its stage; 0 for a hulk or a wreck.
    pub fn power(&self) -> f64 {
        if self.disabled || self.destroyed {
            return 0.0;
        }
        let mut total = 0.0;
        let mut count = 0;
        for s in self.sections.iter().filter(|s| s.kind == KIND_REACTOR) {
            count += 1;
            if s.lost() {
                continue;
            }
            total += if s.fraction() <= self.rules.power_stage_at { self.rules.power_stage_level } else { 1.0 };
        }
        if count > 0 { total / f64::from(count) } else { 1.0 }
    }

    pub fn list(&self, kind: u8) -> &[Part] {
        match kind {
            PART_ENGINE => &self.engines,
            PART_BAY => &self.bays,
            _ => &self.mounts,
        }
    }

    fn list_mut(&mut self, kind: u8) -> &mut Vec<Part> {
        match kind {
            PART_ENGINE => &mut self.engines,
            PART_BAY => &mut self.bays,
            _ => &mut self.mounts,
        }
    }

    fn has_bridge(&self) -> bool {
        let mut any = false;
        for s in self.sections.iter().filter(|s| s.kind == KIND_BRIDGE) {
            any = true;
            if !s.lost() {
                return true;
            }
        }
        !any
    }

    fn reactor_shut_down(&self) -> bool {
        let at = self.rules.reactor_shutdown_at;
        self.sections
            .iter()
            .any(|s| s.kind == KIND_REACTOR && !s.lost() && s.fraction() <= at)
    }

    /// The section nearest `point`, whatever its state; ties go to the earlier.
    fn nearest(&self, point: Vector3) -> Option<usize> {
        let mut best = None;
        let mut best_d = f64::INFINITY;
        for (i, s) in self.sections.iter().enumerate() {
            let d = f64::from(s.distance_to(point));
            if d < best_d {
                best_d = d;
                best = Some(i);
            }
        }
        best
    }

    /// The live part of section `s` nearest `point` within its reach: its mounts, then engines, then bays (ties to the first).
    fn part_at(&self, s: usize, point: Vector3) -> Option<(u8, usize)> {
        let sec = &self.sections[s];
        let mut best = None;
        let mut best_d = f64::INFINITY;
        for (kind, list) in [(PART_MOUNT, &sec.mounts), (PART_ENGINE, &sec.engines), (PART_BAY, &sec.bays)] {
            for &i in list {
                let p = &self.list(kind)[i];
                let d = f64::from(length(sub(point, p.pos)));
                if p.alive && d <= p.reach && d < best_d {
                    best_d = d;
                    best = Some((kind, i));
                }
            }
        }
        best
    }

    fn land(&mut self, s: Option<usize>, part: Option<(u8, usize)>, damage: f64, log: &mut Log) -> f64 {
        let mut to_hull = damage;
        let share = self.rules.subsystem_hull_share;
        if let Some(si) = s.filter(|&i| !self.sections[i].lost()) {
            if let Some((kind, i)) = part {
                self.wear_part(kind, i, damage, log);
                to_hull = damage * share;
            } else if self.sections[si].is_subsystem() {
                self.wear_section(si, damage, log);
                to_hull = damage * share;
            } else {
                self.wear_section(si, damage, log);
            }
        }
        if self.destroyed {
            return to_hull;
        }
        self.hull_hp = maxf(self.hull_hp - to_hull, 0.0);
        log.push(HULL_HP, self.hull_hp, 0.0, 0.0);
        self.check_disabled(log);
        to_hull
    }

    fn wear_part(&mut self, kind: u8, i: usize, damage: f64, log: &mut Log) {
        let p = &mut self.list_mut(kind)[i];
        p.hp = maxf(p.hp - damage, 0.0);
        let hp = p.hp;
        log.push(PART_HP, f64::from(kind), i as f64, hp);
        if hp <= 0.0 {
            self.lose_part(kind, i, log);
        }
    }

    fn wear_section(&mut self, si: usize, amount: f64, log: &mut Log) {
        let power_before = self.power();
        let s = &mut self.sections[si];
        s.hp = maxf(s.hp - amount, 0.0);
        log.push(SEC_HP, si as f64, s.hp, 0.0);
        if s.hp <= 0.0 {
            self.lose_section(si, log);
            return;
        }
        if s.state == INTACT {
            s.state = DAMAGED;
            log.push(SECTION_CHANGED, si as f64, f64::from(DAMAGED), 0.0);
        }
        if self.power() != power_before {
            log.push(DRIVE_CHANGED, 0.0, 0.0, 0.0);
        }
    }

    fn lose_part(&mut self, kind: u8, i: usize, log: &mut Log) {
        let p = &mut self.list_mut(kind)[i];
        if !p.alive {
            return;
        }
        p.alive = false;
        log.push(PART_LOST, f64::from(kind), i as f64, 0.0);
        if kind == PART_ENGINE {
            log.push(DRIVE_CHANGED, 0.0, 0.0, 0.0);
        }
    }

    // A section at 0 loses what it holds (mounts, then bays, then engines); an explosive one blows, else a lost bridge leaves a hulk.
    fn lose_section(&mut self, si: usize, log: &mut Log) {
        self.sections[si].state = DISABLED;
        log.push(SEC_STATE, si as f64, f64::from(DISABLED), 0.0);
        for k in 0..self.sections[si].mounts.len() {
            let i = self.sections[si].mounts[k];
            self.lose_part(PART_MOUNT, i, log);
        }
        for k in 0..self.sections[si].bays.len() {
            let i = self.sections[si].bays[k];
            self.lose_part(PART_BAY, i, log);
        }
        for k in 0..self.sections[si].engines.len() {
            let i = self.sections[si].engines[k];
            self.lose_part(PART_ENGINE, i, log);
        }
        log.push(SECTION_CHANGED, si as f64, f64::from(DISABLED), 0.0);
        if self.sections[si].explosive() {
            self.blow(si, log);
            return;
        }
        self.check_disabled(log);
    }

    fn blow(&mut self, si: usize, log: &mut Log) {
        self.sections[si].state = DESTROYED;
        log.push(SECTION_CHANGED, si as f64, f64::from(DESTROYED), 0.0);
        if self.destroyed {
            return;
        }
        self.destroyed = true;
        self.blown = si as i32;
        log.push(BLEW, si as f64, 0.0, 0.0);
    }

    fn check_disabled(&mut self, log: &mut Log) {
        if self.disabled || self.destroyed || self.hull_hp <= 0.0 {
            return;
        }
        if !self.has_bridge() || self.reactor_shut_down() || self.hull_hp < self.rules.hulk_below * self.hull_max {
            self.disable(log);
        }
    }

    fn disable(&mut self, log: &mut Log) {
        self.disabled = true;
        log.push(BECAME_DISABLED, 0.0, 0.0, 0.0);
        log.push(DRIVE_CHANGED, 0.0, 0.0, 0.0);
    }
}
