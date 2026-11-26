// A tick's beam hits landed in one batch on the damage store (M10-T75, Q70, Q94): each hit as `CapitalBeams` landed it one at
// a time through its target's `Damageable` (a hull its side may hurt, god mode and invulnerable hulls taking nothing, a
// capital by the section its surface volume names and the part there, the station by section and grid mount, any other
// hull whole), with the disguise a shooter gives away and the attackers the turrets remember. GDScript gets, per batch, the
// writes coalesced, the events, and one summary per damaged ship. A hit that raises an event (a section, a part, a hulk, a
// blast, a kill, a reveal) ends the batch, so GDScript answers it before the next hit lands, as it did hit by hit. A blast's hits
// (M10-T76) land the same way, friend or foe alike, one `land_more` a hull, so a blast and its chain share one batch's writes and
// summaries.
use std::collections::HashMap;

use godot::builtin::Vector3;

use super::capital::{self as cap};
use super::station as st;
use super::{DamageStore, Log, LOG_WIDTH};

/// How a target takes a hit: whole, by a capital's sections, by the station's sections and mounts.
pub const ROUTE_PLAIN: u8 = 0;
pub const ROUTE_CAPITAL: u8 = 1;
pub const ROUTE_STATION: u8 = 2;

/// The silhouettes' zones (`DamageZones.Layout`): none, the X fighter, the delta.
pub const LAYOUT_X_FIGHTER: u8 = 1;
pub const LAYOUT_DELTA: u8 = 2;
const X_FIGHTER_ARM_X: f32 = 2.0;
const DELTA_WING_X: f32 = 1.8;

/// What a coalesced or event entry is about: a hull, a capital's ledger, a station's.
pub const ON_HULL: u8 = 0;
pub const ON_CAPITAL: u8 = 1;
pub const ON_STATION: u8 = 2;
/// Entries out are six numbers: what it is about, its ledger, then the log's four.
pub const OUT_WIDTH: usize = 6;

/// One `Damageable` as the batch lands on it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Target {
    pub hull: i64,
    /// The `Damageable` its summary goes to (a capital's rotor: the capital's own).
    pub summary: i64,
    pub route: u8,
    /// The capital's or the station's ledger.
    pub ledger: i64,
    /// The station body it is (its sections' body code).
    pub station_body: i32,
    /// A capital piece's sections by surface volume (the store's slots).
    pub volume_sections: Vec<i32>,
    /// Where its piece's frame sits on the capital at rest (a rotor's pivot).
    pub rest_offset: Vector3,
    pub layout: u8,
    pub invulnerable: bool,
    pub respects_god_mode: bool,
    pub hit_by_anyone: bool,
    pub is_player: bool,
}

/// One hit as the beams' step found it, with what the shell read for it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LandHit {
    pub target: i64,
    pub body: i64,
    pub shooter: i64,
    pub shooter_faction: u32,
    /// The target's faction index, None when the core does not know it.
    pub target_faction: Option<u32>,
    /// The faction the shooter's transponder broadcasts while disguised.
    pub disguise: Option<u32>,
    pub damage: f64,
    pub point: Vector3,
    pub volume: i32,
    /// The point in the hit body's frame, by the engine's maths; None when the body is out of the tree.
    pub local: Option<Vector3>,
}

/// The rules of the tick: the settings and the relations (1 hostile, 2 friendly, by faction index).
pub struct Ctx<'a> {
    /// A blast's hits (M10-T76): any side's hull, no attacker to remember and no disguise to give away.
    pub blast: bool,
    pub friendly_fire: bool,
    pub god_mode: bool,
    pub relation: &'a [u8],
    pub factions: usize,
}

/// One damaged ship's tick: every attacker in the order they first hit, the hits, damage carried and points removed, the
/// last point, each hit's section (a capital's slot, -1 for none) and the zones or station sections the points went to.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Summary {
    pub target: i64,
    pub body: i64,
    pub attackers: Vec<i64>,
    pub attacker_factions: Vec<u32>,
    pub last_shooter: i64,
    pub hits: u32,
    pub damage: f64,
    pub applied: f64,
    pub point: Vector3,
    pub sections: Vec<i32>,
    pub zones: Vec<(i32, f64)>,
}

/// One landed hit, for the tests' log: the summary target, the body, the shooter, damage, points removed, the point.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Landed {
    pub target: i64,
    pub body: i64,
    pub shooter: i64,
    pub damage: f64,
    pub applied: f64,
    pub point: Vector3,
}

/// What a batch hands back.
#[derive(Default, Debug)]
pub struct LandOut {
    pub sync: Vec<f64>,
    pub events: Vec<f64>,
    pub summaries: Vec<Summary>,
    /// The hit that destroyed its hull, with the points it removed and its section slot.
    pub kill: Option<(usize, f64, i32)>,
    pub reveals: Vec<i64>,
    /// A hit the batch cannot land (no target registered, no volume to name its section): GDScript lands it.
    pub deferred: Option<usize>,
    /// `(victim body, shooter)` in landing order, for the turrets' memory.
    pub attackers: Vec<(i64, i64)>,
    pub landed: Vec<Landed>,
    pub hits: u32,
    pub damage: f64,
    /// The last `land_more` stopped on a hit GDScript must answer (an event, a kill, a reveal) or land itself.
    pub stopped: bool,
    sync_at: HashMap<(u8, i64, u8, i64, i64), usize>,
    summary_at: HashMap<i64, usize>,
}

impl LandOut {
    pub fn clear(&mut self) {
        self.sync.clear();
        self.events.clear();
        self.summaries.clear();
        self.kill = None;
        self.reveals.clear();
        self.deferred = None;
        self.attackers.clear();
        self.landed.clear();
        self.hits = 0;
        self.damage = 0.0;
        self.stopped = false;
        self.sync_at.clear();
        self.summary_at.clear();
    }

    // Keeps the last value of each field a hit wrote.
    fn merge(&mut self, on: u8, ledger: i64, log: &Log) {
        for e in log.entries.chunks(LOG_WIDTH) {
            let code = e[0] as u8;
            let key = match code {
                cap::PART_HP if on == ON_CAPITAL => (on, ledger, code, e[1] as i64, e[2] as i64),
                cap::HULL_HP | st::HULL_HP => (on, ledger, code, 0, 0),
                _ => (on, ledger, code, e[1] as i64, 0),
            };
            self.put(key, [f64::from(on), ledger as f64, e[0], e[1], e[2], e[3]]);
        }
    }

    fn put(&mut self, key: (u8, i64, u8, i64, i64), entry: [f64; OUT_WIDTH]) {
        if let Some(&at) = HashMap::get(&self.sync_at, &key) {
            self.sync[at * OUT_WIDTH..(at + 1) * OUT_WIDTH].copy_from_slice(&entry);
        } else {
            self.sync_at.insert(key, self.sync.len() / OUT_WIDTH);
            self.sync.extend_from_slice(&entry);
        }
    }

    /// Ends a batch: the coalesced writes grouped by ledger, in the order each was first written (GDScript takes a ledger's in
    /// one call). Nothing more may land into it until `clear`.
    pub fn finish(&mut self) {
        let n = self.sync.len() / OUT_WIDTH;
        let mut first: Vec<(u8, i64)> = Vec::new();
        let mut rank = Vec::with_capacity(n);
        for k in 0..n {
            let e = &self.sync[k * OUT_WIDTH..(k + 1) * OUT_WIDTH];
            let key = (e[0] as u8, e[1] as i64);
            let r = first.iter().position(|&f| f == key).unwrap_or_else(|| {
                first.push(key);
                first.len() - 1
            });
            rank.push((r, k));
        }
        rank.sort_by_key(|&(r, k)| (r, k));
        let old = std::mem::take(&mut self.sync);
        for (_, k) in rank {
            self.sync.extend_from_slice(&old[k * OUT_WIDTH..(k + 1) * OUT_WIDTH]);
        }
    }

    fn summary(&mut self, target: i64) -> &mut Summary {
        let at = *self.summary_at.entry(target).or_insert_with(|| {
            self.summaries.push(Summary {
                target,
                ..Summary::default()
            });
            self.summaries.len() - 1
        });
        &mut self.summaries[at]
    }
}

fn hull_entry(ledger: i64, hp: f64, destroyed: bool, now: bool) -> [f64; OUT_WIDTH] {
    [f64::from(ON_HULL), ledger as f64, 0.0, hp, f64::from(u8::from(destroyed)), f64::from(u8::from(now))]
}

fn is_event(code: u8) -> bool {
    !matches!(code, cap::SEC_HP | cap::SEC_STATE | cap::PART_HP | cap::HULL_HP | st::SEC_HEALTH | st::MOUNT_HEALTH | st::HULL_HP)
}

/// The silhouette zone a body-frame point falls in (`DamageZones.zone_for`), -1 for none.
pub fn zone_for(layout: u8, local: Vector3) -> i32 {
    match layout {
        LAYOUT_X_FIGHTER => {
            if local.x.abs() <= X_FIGHTER_ARM_X {
                0
            } else if local.y >= 0.0 {
                if local.x > 0.0 { 2 } else { 1 }
            } else if local.x > 0.0 {
                4
            } else {
                3
            }
        }
        LAYOUT_DELTA => {
            if local.x.abs() <= DELTA_WING_X {
                0
            } else if local.x > 0.0 {
                2
            } else {
                1
            }
        }
        _ => -1,
    }
}

/// Lands `hits` from `start` in order until the end or a hit that raises an event; returns the next hit to land.
pub fn land(store: &mut DamageStore, targets: &HashMap<i64, Target>, hits: &[LandHit], start: usize, ctx: &Ctx, out: &mut LandOut) -> usize {
    out.clear();
    let next = land_more(store, targets, hits, start, ctx, out);
    out.finish();
    next
}

/// As `land`, into a batch already begun (`out` neither cleared nor finished), so several calls share its writes and
/// summaries; `out.stopped` says whether it stopped on a hit GDScript must answer or land.
pub fn land_more(store: &mut DamageStore, targets: &HashMap<i64, Target>, hits: &[LandHit], start: usize, ctx: &Ctx, out: &mut LandOut) -> usize {
    out.stopped = false;
    let mut log = Log::default();
    let rel = |a: u32, b: u32| {
        let (a, b) = (a as usize, b as usize);
        if a < ctx.factions && b < ctx.factions { ctx.relation[a * ctx.factions + b] } else { 0 }
    };
    let mut revealed: Vec<i64> = Vec::new();
    for (k, h) in hits.iter().enumerate().skip(start) {
        let Some(t) = HashMap::get(targets, &h.target) else {
            out.deferred = Some(k);
            out.stopped = true;
            return k + 1;
        };
        let Some(hull) = store.hulls.get(t.hull) else {
            out.deferred = Some(k);
            out.stopped = true;
            return k + 1;
        };
        if hull.destroyed {
            continue; // a hull already dead takes no more
        }
        let tf = h.target_faction;
        let hurts = ctx.blast
            || ctx.friendly_fire
            || tf.is_some_and(|f| rel(h.shooter_faction, f) == 1)
            || (t.hit_by_anyone && tf != Some(h.shooter_faction));
        if !hurts {
            continue; // the line stops on a hull its side may not hurt
        }
        let section = match t.route {
            ROUTE_CAPITAL => match usize::try_from(h.volume).ok().and_then(|v| t.volume_sections.get(v)) {
                Some(&s) => s,
                None => {
                    out.deferred = Some(k);
                    out.stopped = true;
                    return k + 1;
                }
            },
            _ => -1,
        };
        let local = match (t.route, h.local) {
            (ROUTE_PLAIN, l) => l,
            (_, Some(l)) => Some(l),
            (_, None) => {
                out.deferred = Some(k);
                out.stopped = true;
                return k + 1;
            }
        };
        if !ctx.blast {
            out.attackers.push((h.body, h.shooter));
        }
        let mut stop = false;
        let gives_away = |f: u32| t.is_player || tf.is_some_and(|v| rel(f, v) == 2);
        if !ctx.blast && h.disguise.is_some_and(gives_away) && !revealed.contains(&h.shooter) {
            revealed.push(h.shooter);
            out.reveals.push(h.shooter);
            stop = true;
        }
        log.clear();
        let mut applied = 0.0;
        let mut zone: Option<(i32, f64)> = None;
        let takes = !(t.invulnerable || (t.respects_god_mode && ctx.god_mode));
        if takes {
            match t.route {
                ROUTE_CAPITAL => {
                    let l = local.unwrap_or(h.point);
                    let at = Vector3::new(l.x + t.rest_offset.x, l.y + t.rest_offset.y, l.z + t.rest_offset.z);
                    let (removed, gone) = match store.capitals.get_mut(t.ledger) {
                        Some(c) => (c.hit(i64::from(section), at, h.damage, &mut log), c.destroyed),
                        None => (0.0, false),
                    };
                    let hull = store.hulls.get_mut(t.hull).expect("checked above");
                    let amount = if gone { hull.hp } else { removed };
                    applied = hull.apply(amount);
                }
                ROUTE_STATION => {
                    let l = local.unwrap_or(h.point);
                    let (index, before, secs) = match store.stations.get(t.ledger).and_then(|s| store.sections.get(s.sections).map(|x| (s.sections, x))) {
                        Some((secs, x)) => {
                            let i = x.section_at(t.station_body, l);
                            (i, usize::try_from(i).ok().map_or(0.0, |u| x.health[u]), secs)
                        }
                        None => (-1, 0.0, -1),
                    };
                    let removed = store.station_hit(t.ledger, t.station_body, l, h.damage, &mut log);
                    let gone = store.stations.get(t.ledger).is_some_and(|s| s.destroyed);
                    if let (Ok(u), Some(x)) = (usize::try_from(index), store.sections.get(secs)) {
                        let lost = before - x.health[u];
                        if lost > 0.0 {
                            zone = Some((index as i32, lost));
                        }
                    }
                    let hull = store.hulls.get_mut(t.hull).expect("checked above");
                    let amount = if gone { hull.hp } else { removed };
                    applied = hull.apply(amount);
                }
                _ => {
                    let hull = store.hulls.get_mut(t.hull).expect("checked above");
                    applied = hull.apply(h.damage);
                    if let Some(l) = local.filter(|_| applied > 0.0) {
                        let z = zone_for(t.layout, l);
                        if z >= 0 {
                            zone = Some((z, applied));
                        }
                    }
                }
            }
        }
        let hull = store.hulls.get(t.hull).expect("checked above");
        let killed = takes && hull.destroyed_now;
        let on = match t.route {
            ROUTE_CAPITAL => ON_CAPITAL,
            ROUTE_STATION => ON_STATION,
            _ => ON_HULL,
        };
        let events = log.entries.chunks(LOG_WIDTH).any(|e| is_event(e[0] as u8));
        let entry = hull_entry(t.hull, hull.hp, hull.destroyed, hull.destroyed_now);
        stop = stop || killed || events;
        if stop {
            for e in log.entries.chunks(LOG_WIDTH) {
                out.events.extend_from_slice(&[f64::from(on), t.ledger as f64, e[0], e[1], e[2], e[3]]);
            }
            out.events.extend_from_slice(&entry);
        } else {
            if on != ON_HULL {
                out.merge(on, t.ledger, &log);
            }
            out.put((ON_HULL, t.hull, 0, 0, 0), entry);
        }
        if killed {
            out.kill = Some((k, applied, section));
        }
        out.hits += 1;
        out.damage += h.damage;
        out.landed.push(Landed {
            target: t.summary,
            body: h.body,
            shooter: h.shooter,
            damage: h.damage,
            applied,
            point: h.point,
        });
        let s = out.summary(t.summary);
        s.body = h.body;
        if !s.attackers.contains(&h.shooter) {
            s.attackers.push(h.shooter);
            s.attacker_factions.push(h.shooter_faction);
        }
        // A blast with no shooter (a death, 0) names no one: the last shooter stays the last one that has an id.
        if h.shooter != 0 || s.hits == 0 {
            s.last_shooter = h.shooter;
        }
        s.hits += 1;
        s.damage += h.damage;
        s.applied += applied;
        s.point = h.point;
        if t.route == ROUTE_CAPITAL {
            s.sections.push(section);
        }
        if let Some(z) = zone {
            s.zones.push(z);
        }
        if stop {
            out.stopped = true;
            return k + 1;
        }
    }
    hits.len()
}
