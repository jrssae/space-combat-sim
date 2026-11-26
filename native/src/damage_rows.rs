// The damage store's shell for GDScript (M10-T75, Q94): `HullHealth`, `CapitalDamage`, `StationSections`, `GridMountHealth`
// and `StationDamage` register their ledgers here and land every hit through it; each call that changes points returns its
// result first and then its write log (`damage_store::LOG_WIDTH` numbers an entry), which GDScript replays onto its read-only
// copies. The rules are `damage_store`, engine-free.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::damage_store::capital::{self as cap, Capital, Part, Rules, Section};
use crate::damage_store::station::{self as st, GridMounts, Station, StationSections};
use crate::damage_store::{DamageStore, Hull, Log};

/// Numbers a section packs into for `capital_add`: kind, max_hp, hp, state, box position (3), box size (3).
const SECTION_LEN: usize = 10;
/// Numbers a part packs into: section, position (3), reach, max_hp, hp, alive.
const PART_LEN: usize = 8;
/// Numbers the rules pack into: subsystem share, power stage at, power stage level, reactor shut-down at, hulk below.
const RULES_LEN: usize = 5;

/// Every ledger of damage in play, one store for the process (`DamageStore.native()` in GDScript).
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsDamageStore {
    base: Base<RefCounted>,
    pub store: DamageStore,
    log: Log,
}

fn vec3(s: &[f64], at: usize) -> Vector3 {
    Vector3::new(s[at] as f32, s[at + 1] as f32, s[at + 2] as f32)
}

fn parts(raw: &PackedFloat64Array) -> Option<Vec<Part>> {
    let s = raw.as_slice();
    if !s.len().is_multiple_of(PART_LEN) {
        return None;
    }
    Some(
        s.chunks(PART_LEN)
            .map(|p| Part {
                section: p[0] as i32,
                pos: vec3(p, 1),
                reach: p[4],
                max_hp: p[5],
                hp: p[6],
                alive: p[7] != 0.0,
            })
            .collect(),
    )
}

impl ScsDamageStore {
    // The result and the log the call left, as one packed array.
    fn answer(&mut self, result: f64) -> PackedFloat64Array {
        let mut out = Vec::with_capacity(1 + self.log.entries.len());
        out.push(result);
        out.extend_from_slice(&self.log.entries);
        self.log.clear();
        PackedFloat64Array::from(out.as_slice())
    }
}

#[godot_api]
impl ScsDamageStore {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Live ledgers by kind: hulls, capitals, station sections, grid mounts, stations (a leak shows here).
    #[func]
    fn live(&self) -> PackedInt64Array {
        let s = &self.store;
        PackedInt64Array::from(
            [s.hulls.live(), s.capitals.live(), s.sections.live(), s.mounts.live(), s.stations.live()]
                .map(|n| n as i64)
                .as_slice(),
        )
    }

    // --- Hulls (`HullHealth`) ---

    /// A hull of `max_hp` points (raised to the least capacity); its handle.
    #[func]
    fn hull_add(&mut self, max_hp: f64) -> i64 {
        self.store.hulls.add(Hull::new(max_hp)) as i64
    }

    #[func]
    fn hull_free(&mut self, id: i64) {
        self.store.hulls.remove(id);
    }

    /// Takes up to `amount` off hull `id`: `[applied, hp, destroyed, destroyed_now]`.
    #[func]
    fn hull_apply(&mut self, id: i64, amount: f64) -> PackedFloat64Array {
        let Some(h) = self.store.hulls.get_mut(id) else {
            godot_error!("ScsDamageStore.hull_apply: no hull {id}");
            return PackedFloat64Array::new();
        };
        let applied = h.apply(amount);
        PackedFloat64Array::from([applied, h.hp, f64::from(u8::from(h.destroyed)), f64::from(u8::from(h.destroyed_now))].as_slice())
    }

    #[func]
    fn hull_restore(&mut self, id: i64) {
        if let Some(h) = self.store.hulls.get_mut(id) {
            h.restore();
        }
    }

    /// A direct write: the capacity and the points (the flags kept).
    #[func]
    fn hull_set(&mut self, id: i64, max_hp: f64, hp: f64) {
        if let Some(h) = self.store.hulls.get_mut(id) {
            h.max_hp = max_hp;
            h.hp = hp;
        }
    }

    /// `[max_hp, hp, destroyed, destroyed_now]`; empty for no such hull.
    #[func]
    fn hull_state(&self, id: i64) -> PackedFloat64Array {
        self.store.hulls.get(id).map_or_else(PackedFloat64Array::new, |h| {
            PackedFloat64Array::from(
                [h.max_hp, h.hp, f64::from(u8::from(h.destroyed)), f64::from(u8::from(h.destroyed_now))].as_slice(),
            )
        })
    }

    // --- Capitals (`CapitalDamage`) ---

    /// A capital's ledger: its rules, sections, mounts, engines and bays (packed, see the lengths above) and its hull's total.
    /// Its handle, or -1 when refused.
    #[func]
    fn capital_add(
        &mut self,
        rules: PackedFloat64Array,
        sections: PackedFloat64Array,
        mounts: PackedFloat64Array,
        engines: PackedFloat64Array,
        bays: PackedFloat64Array,
        hull_max: f64,
    ) -> i64 {
        let r = rules.as_slice();
        let sec = sections.as_slice();
        if r.len() != RULES_LEN || !sec.len().is_multiple_of(SECTION_LEN) {
            godot_error!("ScsDamageStore.capital_add: {} rules (want {RULES_LEN}), {} section numbers", r.len(), sec.len());
            return -1;
        }
        let (Some(m), Some(e), Some(b)) = (parts(&mounts), parts(&engines), parts(&bays)) else {
            godot_error!("ScsDamageStore.capital_add: parts not in {PART_LEN}s");
            return -1;
        };
        let rules = Rules {
            subsystem_hull_share: r[0],
            power_stage_at: r[1],
            power_stage_level: r[2],
            reactor_shutdown_at: r[3],
            hulk_below: r[4],
        };
        let built: Vec<Section> = sec
            .chunks(SECTION_LEN)
            .map(|s| {
                let lo = vec3(s, 4);
                let size = vec3(s, 7);
                Section {
                    kind: s[0] as u8,
                    max_hp: s[1],
                    hp: s[2],
                    state: s[3] as u8,
                    lo,
                    end: Vector3::new(lo.x + size.x, lo.y + size.y, lo.z + size.z),
                    mounts: Vec::new(),
                    engines: Vec::new(),
                    bays: Vec::new(),
                }
            })
            .collect();
        self.store.capitals.add(Capital::new(rules, built, m, e, b, hull_max)) as i64
    }

    #[func]
    fn capital_free(&mut self, id: i64) {
        self.store.capitals.remove(id);
    }

    /// A hit on section `section` (-1: the nearest to `point`) at `point`, body frame at rest: `[hull points removed, log...]`.
    #[func]
    fn capital_hit(&mut self, id: i64, section: i64, point: Vector3, damage: f64) -> PackedFloat64Array {
        let removed = match self.store.capitals.get_mut(id) {
            Some(c) => c.hit(section, point, damage, &mut self.log),
            None => 0.0,
        };
        self.answer(removed)
    }

    /// A hit on part `index` of list `kind` (mount 0, engine 1, bay 2) or on section `index` (kind 3) itself.
    #[func]
    fn capital_hit_part(&mut self, id: i64, kind: i64, index: i64, damage: f64) -> PackedFloat64Array {
        let removed = match self.store.capitals.get_mut(id) {
            Some(c) => c.hit_part(kind as u8, index, damage, &mut self.log),
            None => 0.0,
        };
        self.answer(removed)
    }

    /// The crew scuttles it: `[1 when it did, log...]`.
    #[func]
    fn capital_scuttle(&mut self, id: i64) -> PackedFloat64Array {
        let done = match self.store.capitals.get_mut(id) {
            Some(c) => c.scuttle(&mut self.log),
            None => false,
        };
        self.answer(f64::from(u8::from(done)))
    }

    #[func]
    fn capital_restore(&mut self, id: i64) {
        if let Some(c) = self.store.capitals.get_mut(id) {
            c.restore();
        }
    }

    /// A direct write of field `code` (the log's codes; `kind` the part list for a part's field).
    #[func]
    fn capital_set(&mut self, id: i64, code: i64, kind: i64, index: i64, value: f64) {
        if let Some(c) = self.store.capitals.get_mut(id) {
            c.set(code as u8, kind as u8, index, value);
        }
    }

    /// Section `index`'s `[hp, state]`, a part's `[hp, alive]` (kind 0 to 2), or the hull's `[hull_hp, disabled, destroyed,
    /// blown]` for kind -1: for the tests.
    #[func]
    fn capital_state(&self, id: i64, kind: i64, index: i64) -> PackedFloat64Array {
        let Some(c) = self.store.capitals.get(id) else {
            return PackedFloat64Array::new();
        };
        let i = usize::try_from(index).unwrap_or(usize::MAX);
        let out: Vec<f64> = match kind {
            -1 => vec![c.hull_hp, f64::from(u8::from(c.disabled)), f64::from(u8::from(c.destroyed)), f64::from(c.blown)],
            3 => c.sections.get(i).map_or(vec![], |s| vec![s.hp, f64::from(s.state)]),
            k => c.list(k as u8).get(i).map_or(vec![], |p| vec![p.hp, f64::from(u8::from(p.alive))]),
        };
        PackedFloat64Array::from(out.as_slice())
    }

    // --- The station (`StationSections`, `GridMountHealth`, `StationDamage`) ---

    /// Damage sections: each one's body code, box position and size (`bodies` one a section, `boxes` six), health and full health.
    #[func]
    fn sections_add(&mut self, bodies: PackedInt32Array, boxes: PackedFloat64Array, health: PackedFloat64Array, max_health: PackedFloat64Array) -> i64 {
        let n = bodies.len();
        let b = boxes.as_slice();
        if b.len() != n * 6 || health.len() != n || max_health.len() != n {
            godot_error!("ScsDamageStore.sections_add: {n} bodies, {} box numbers, {} health, {} full", b.len(), health.len(), max_health.len());
            return -1;
        }
        let lo: Vec<Vector3> = b.chunks(6).map(|c| vec3(c, 0)).collect();
        let end: Vec<Vector3> = b
            .chunks(6)
            .map(|c| {
                let p = vec3(c, 0);
                let s = vec3(c, 3);
                Vector3::new(p.x + s.x, p.y + s.y, p.z + s.z)
            })
            .collect();
        self.store.sections.add(StationSections {
            body: bodies.as_slice().to_vec(),
            lo,
            end,
            health: health.as_slice().to_vec(),
            max_health: max_health.as_slice().to_vec(),
        }) as i64
    }

    #[func]
    fn sections_free(&mut self, id: i64) {
        self.store.sections.remove(id);
    }

    /// Takes `amount` off section `index`: `[1 when lost, log...]`.
    #[func]
    fn sections_damage(&mut self, id: i64, index: i64, amount: f64) -> PackedFloat64Array {
        let lost = match self.store.sections.get_mut(id) {
            Some(s) => s.damage(index, amount, &mut self.log),
            None => false,
        };
        self.answer(f64::from(u8::from(lost)))
    }

    /// Adds `amount` to section `index`: `[1 when it came back, its health]`.
    #[func]
    fn sections_repair(&mut self, id: i64, index: i64, amount: f64) -> PackedFloat64Array {
        let Some(s) = self.store.sections.get_mut(id) else {
            return PackedFloat64Array::new();
        };
        let back = s.repair(index, amount);
        let h = usize::try_from(index).ok().and_then(|i| s.health.get(i)).copied().unwrap_or(0.0);
        PackedFloat64Array::from([f64::from(u8::from(back)), h].as_slice())
    }

    #[func]
    fn sections_restore(&mut self, id: i64) {
        if let Some(s) = self.store.sections.get_mut(id) {
            s.restore();
        }
    }

    /// A direct write of every section's health and full health.
    #[func]
    fn sections_set(&mut self, id: i64, health: PackedFloat64Array, max_health: PackedFloat64Array) {
        if let Some(s) = self.store.sections.get_mut(id).filter(|s| health.len() == s.health.len() && max_health.len() == s.health.len()) {
            s.health = health.as_slice().to_vec();
            s.max_health = max_health.as_slice().to_vec();
        }
    }

    #[func]
    fn sections_health(&self, id: i64) -> PackedFloat64Array {
        self.store
            .sections
            .get(id)
            .map_or_else(PackedFloat64Array::new, |s| PackedFloat64Array::from(s.health.as_slice()))
    }

    /// Grid mounts: each one's body code, position (three numbers), radius, health and full health.
    #[func]
    fn mounts_add(
        &mut self,
        bodies: PackedInt32Array,
        positions: PackedFloat64Array,
        radius: PackedFloat64Array,
        health: PackedFloat64Array,
        max_health: PackedFloat64Array,
    ) -> i64 {
        let n = bodies.len();
        let p = positions.as_slice();
        if p.len() != n * 3 || radius.len() != n || health.len() != n || max_health.len() != n {
            godot_error!("ScsDamageStore.mounts_add: {n} bodies and lists that do not match");
            return -1;
        }
        self.store.mounts.add(GridMounts {
            body: bodies.as_slice().to_vec(),
            pos: p.chunks(3).map(|c| vec3(c, 0)).collect(),
            radius: radius.as_slice().to_vec(),
            health: health.as_slice().to_vec(),
            max_health: max_health.as_slice().to_vec(),
        }) as i64
    }

    #[func]
    fn mounts_free(&mut self, id: i64) {
        self.store.mounts.remove(id);
    }

    /// Takes `amount` off mount `index`: `[1 when knocked out, its health]`.
    #[func]
    fn mounts_wear(&mut self, id: i64, index: i64, amount: f64) -> PackedFloat64Array {
        let Some(m) = self.store.mounts.get_mut(id) else {
            return PackedFloat64Array::new();
        };
        let out = m.wear(index, amount, &mut self.log);
        self.log.clear();
        let h = usize::try_from(index).ok().and_then(|i| m.health.get(i)).copied().unwrap_or(0.0);
        PackedFloat64Array::from([f64::from(u8::from(out)), h].as_slice())
    }

    /// Adds `amount` to mount `index`: `[1 when it came back, its health]`.
    #[func]
    fn mounts_heal(&mut self, id: i64, index: i64, amount: f64) -> PackedFloat64Array {
        let Some(m) = self.store.mounts.get_mut(id) else {
            return PackedFloat64Array::new();
        };
        let back = m.heal(index, amount);
        let h = usize::try_from(index).ok().and_then(|i| m.health.get(i)).copied().unwrap_or(0.0);
        PackedFloat64Array::from([f64::from(u8::from(back)), h].as_slice())
    }

    /// Mount `index` whole: `[1 when it was knocked out, its health]`.
    #[func]
    fn mounts_repair(&mut self, id: i64, index: i64) -> PackedFloat64Array {
        let Some(m) = self.store.mounts.get_mut(id) else {
            return PackedFloat64Array::new();
        };
        let was = m.repair(index);
        let h = usize::try_from(index).ok().and_then(|i| m.health.get(i)).copied().unwrap_or(0.0);
        PackedFloat64Array::from([f64::from(u8::from(was)), h].as_slice())
    }

    /// The live mount on `body` whose radius holds `point`, the nearest; -1 for none.
    #[func]
    fn mounts_nearest(&self, id: i64, body: i64, point: Vector3) -> i64 {
        self.store.mounts.get(id).map_or(-1, |m| m.nearest(body as i32, point))
    }

    #[func]
    fn mounts_set(&mut self, id: i64, health: PackedFloat64Array, max_health: PackedFloat64Array) {
        if let Some(m) = self.store.mounts.get_mut(id).filter(|m| health.len() == m.health.len() && max_health.len() == m.health.len()) {
            m.health = health.as_slice().to_vec();
            m.max_health = max_health.as_slice().to_vec();
        }
    }

    #[func]
    fn mounts_health(&self, id: i64) -> PackedFloat64Array {
        self.store
            .mounts
            .get(id)
            .map_or_else(PackedFloat64Array::new, |m| PackedFloat64Array::from(m.health.as_slice()))
    }

    /// A station's rules over sections `sections` and grid mounts `mounts` (-1: none): each section's kind (plain 0, bridge 1,
    /// reactor 2), the rules (subsystem share, hulk below, reactor shut-down at) and the hull's total.
    #[func]
    fn station_add(&mut self, sections: i64, mounts: i64, kinds: PackedInt32Array, rules: PackedFloat64Array, hull_max: f64) -> i64 {
        let r = rules.as_slice();
        if r.len() != 3 || self.store.sections.get(sections).is_none() {
            godot_error!("ScsDamageStore.station_add: {} rules (want 3) or no sections {sections}", r.len());
            return -1;
        }
        self.store.stations.add(Station {
            sections,
            mounts: (mounts >= 0).then_some(mounts),
            kinds: kinds.as_slice().iter().map(|&k| k as u8).collect(),
            subsystem_hull_share: r[0],
            hulk_below: r[1],
            reactor_shutdown_at: r[2],
            hull_max,
            hull_hp: hull_max,
            disabled: false,
            destroyed: false,
            blown: -1,
        }) as i64
    }

    #[func]
    fn station_free(&mut self, id: i64) {
        self.store.stations.remove(id);
    }

    /// A hit at `local` on body `body`: `[hull points removed, log...]`.
    #[func]
    fn station_hit(&mut self, id: i64, body: i64, local: Vector3, damage: f64) -> PackedFloat64Array {
        let removed = self.store.station_hit(id, body as i32, local, damage, &mut self.log);
        self.answer(removed)
    }

    /// A hit on section `index` itself: `[hull points removed, log...]`.
    #[func]
    fn station_hit_section(&mut self, id: i64, index: i64, damage: f64) -> PackedFloat64Array {
        let removed = self.store.station_hit_section(id, index, damage, &mut self.log);
        self.answer(removed)
    }

    #[func]
    fn station_restore(&mut self, id: i64) {
        self.store.station_restore(id);
    }

    /// A direct write of the hull's points and the flags (the console's, the tests').
    #[func]
    fn station_set(&mut self, id: i64, hull_hp: f64, disabled: bool, destroyed: bool, blown: i64) {
        if let Some(s) = self.store.stations.get_mut(id) {
            s.hull_hp = hull_hp;
            s.disabled = disabled;
            s.destroyed = destroyed;
            s.blown = blown;
        }
    }

    /// The log codes GDScript replays, by name, so the two sides cannot drift.
    #[func]
    fn codes() -> VarDictionary {
        let mut d = VarDictionary::new();
        for (name, code) in [
            ("SEC_HP", cap::SEC_HP),
            ("SEC_STATE", cap::SEC_STATE),
            ("SECTION_CHANGED", cap::SECTION_CHANGED),
            ("PART_HP", cap::PART_HP),
            ("PART_LOST", cap::PART_LOST),
            ("DRIVE_CHANGED", cap::DRIVE_CHANGED),
            ("HULL_HP", cap::HULL_HP),
            ("BECAME_DISABLED", cap::BECAME_DISABLED),
            ("BLEW", cap::BLEW),
            ("PART_ALIVE", cap::PART_ALIVE),
            ("FLAG_DISABLED", cap::FLAG_DISABLED),
            ("FLAG_DESTROYED", cap::FLAG_DESTROYED),
            ("BLOWN", cap::BLOWN),
            ("ST_SEC_HEALTH", st::SEC_HEALTH),
            ("ST_SEC_LOST", st::SEC_LOST),
            ("ST_MOUNT_HEALTH", st::MOUNT_HEALTH),
            ("ST_MOUNT_OUT", st::MOUNT_OUT),
            ("ST_HULL_HP", st::HULL_HP),
            ("ST_DISABLED", st::BECAME_DISABLED),
            ("ST_DESTROYED", st::BECAME_DESTROYED),
        ] {
            d.set(name, i64::from(code));
        }
        d
    }
}
