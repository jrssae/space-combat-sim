// The capitals' interceptor batteries (M10-T13, Q81) on the battery model the station grid uses (`intercept_kernels`): every
// `interceptor` mount of every capital is a row of the capital guns (`ROLE_PD`), here given its targets and shots. A battery
// guards its own hull and the big hulls its ship perceives as friendly (capitals and stations, never fighters), takes hostile
// missiles and torpedoes first, then the shot that hits soonest, its own hull before its friends', and leaves friendly fire
// and a still-disguised shooter's shots alone (Q55: hostility is what the ship perceives of the shooter). Pulses are real:
// led, spread by a seeded hash, able to miss; a tough shot needs several. Run on the main thread in mount order with no
// randomness but the hash, so 1 and 6 threads fire the same pulses. Engine-free (test_sim_core reads this file).
use std::collections::{HashMap, HashSet};

use godot::builtin::Vector3;

use crate::capital_gun_kernels::{GunWorld, Missile, Mount, Owner, ROLE_PD, WARHEAD_TORPEDO, live_hull, own_hull_blocks};
use crate::intercept_kernels::{self as ik, Incoming, KIND_MISSILE, PulseBook, PulseHit, PulseScratch};
use crate::rows::{Bolts, Rows};
use crate::sweep_cells::CellGrid;
use crate::turret_kernels as tk;
use crate::v3::{dist_sq, length};

/// What a shot down was, for the counters: a plain bolt, a heavy bolt (toughness 2 or more), a missile, a torpedo.
pub const SHOT_BOLT: u8 = 0;
pub const SHOT_HEAVY: u8 = 1;
pub const SHOT_MISSILE: u8 = 2;
pub const SHOT_TORPEDO: u8 = 3;
/// How often the records of shots seen and struck are pruned of shots gone, ticks.
const PRUNE_EVERY: i64 = 60;

/// A pulse a battery fired this tick, for the shell to add as a bolt row: the mount (index and id), where it leaves and how
/// fast, its barrel, the shot it was fired at and when its lead says they meet.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PulseShot {
    pub mount: u32,
    pub mount_id: i64,
    pub start: Vector3,
    pub velocity: Vector3,
    pub barrel: u8,
    pub target: i64,
    pub meet_at: f64,
}

/// A pulse that met a shot this tick: the mount that fired it (-1 when gone), the shot's id, where they met, the shot's colour,
/// whether it went down, and what it was (`SHOT_*`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Met {
    pub mount: i32,
    pub shot: i64,
    pub at: Vector3,
    pub color: [f32; 4],
    pub downed: bool,
    pub kind: u8,
}

/// The batteries' counts since the rows were made: pulses fired, pulses that met a shot, shots down by kind (`SHOT_*`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GuardTally {
    pub pulses: i64,
    pub met: i64,
    pub down: [i64; 4],
}

/// One ship's share: hostile shots its batteries saw headed for its own hull, and how many of those went down.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ShipTally {
    pub body: i64,
    pub incoming: i64,
    pub downed: i64,
}

/// What the guarded sides read beside the gun world: who is friendly to whom (the core's faction indices, `factions` square,
/// as `GunWorld::hostile`) and, per bolt row, its shooter's row (-1: not in the rows) for the perceived faction.
pub struct GuardView<'a> {
    pub friendly: &'a [bool],
    pub shooter_rows: &'a [i32],
}

// One side's guarded set this tick: the big hulls friendly to faction `faction` (its own among them), a flag per row, and each
// bolt's first guarded hull and when (`NOT_SWEPT` until asked), so a bolt is swept once a tick per side.
#[derive(Default)]
struct Side {
    faction: u32,
    guarded: Vec<usize>,
    bounds: Vec<f64>,
    is_guarded: Vec<bool>,
    times: Vec<(f64, u32)>,
}

/// The capitals' interceptor state between ticks: the pulses in flight, the counters and the step's reused buffers.
#[derive(Default)]
pub struct Guards {
    pub book: PulseBook,
    pub tally: GuardTally,
    pub ships: Vec<ShipTally>,
    sides: Vec<Side>,
    sides_used: usize,
    cells: CellGrid,
    shot_rows: Vec<u32>,
    points: Vec<Vector3>,
    zero: Vec<f64>,
    look: Vec<u32>,
    candidates: Vec<usize>,
    incoming: Vec<Incoming>,
    taken: Vec<u8>,
    guided: Vec<i64>,
    scratch: PulseScratch,
    hits: Vec<PulseHit>,
    // Shots a battery saw headed for its own hull, by id: the ship they were headed for (its share's count).
    seen: HashMap<i64, i64>,
    // Pulses that met each shot still flying (a heavy bolt took two or more).
    struck: HashMap<i64, u8>,
    live_ids: HashSet<i64>,
}

/// Whether bolt `q` is hostile to a ship of faction `observer` as it perceives the shooter (Q55): the shooter's broadcast
/// faction while it is disguised, its own otherwise, and the bolt's faction when the shooter is not in the rows.
pub fn hostile_to(rows: &Rows, bolts: &Bolts, shooter_rows: &[i32], hostile: &[bool], n: usize, observer: u32, q: usize) -> bool {
    let seen = shooter_rows
        .get(q)
        .and_then(|&r| usize::try_from(r).ok())
        .filter(|&r| r < rows.flags.len())
        .map_or(bolts.faction_ix[q], |r| rows.seen_ix(r, observer));
    let (a, s) = (observer as usize, seen as usize);
    a < n && s < n && hostile[a * n + s]
}

impl Guards {
    /// Ship `body` left: its share goes.
    pub fn forget(&mut self, body: i64) {
        self.ships.retain(|t| t.body != body);
    }

    /// The share of ship `body`: `(incoming seen, downed)`.
    pub fn share_of(&self, body: i64) -> (i64, i64) {
        self.ships.iter().find(|t| t.body == body).map_or((0, 0), |t| (t.incoming, t.downed))
    }

    /// A pulse the shell added as bolt `id`, fired by mount `mount_id` at shot `target`, expected to meet it at `meet_at`.
    pub fn note_pulse(&mut self, id: i64, mount_id: i64, target: i64, meet_at: f64) {
        self.book.pulses.insert(id, ik::Pulse { battery: mount_id, target, meet_at });
    }

    /// The batteries' pulses that met a shot along the bolts' last move (first in a tick): each pulse spent, the shot one hit
    /// fewer and spent at none left (Q81), reported in pulse row order. `missiles` tells a torpedo from a missile.
    #[allow(clippy::too_many_arguments)]
    pub fn meet(
        &mut self,
        mounts: &[Mount],
        bolts: &mut Bolts,
        rows: &Rows,
        shooter_rows: &[i32],
        hostile: &[bool],
        factions: usize,
        missiles: &[Missile],
        out: &mut Vec<Met>,
    ) {
        out.clear();
        if self.book.pulses.is_empty() {
            return;
        }
        let book = &self.book;
        {
            let b: &Bolts = bolts;
            ik::pulse_hits_by(
                b,
                |p| book.owns(b.ids[p]),
                |p, q| hostile_to(rows, b, shooter_rows, hostile, factions, b.faction_ix[p], q),
                &mut self.scratch,
                &mut self.hits,
            );
        }
        for h in &self.hits {
            let (p, q) = (h.pulse as usize, h.target as usize);
            let shot = bolts.ids[q];
            let struck = self.struck.entry(shot).or_insert(0);
            *struck = struck.saturating_add(1);
            self.tally.met += 1;
            let kind = if bolts.kinds[q] == KIND_MISSILE {
                if missiles.iter().any(|m| m.bolt == shot && m.warhead == WARHEAD_TORPEDO) { SHOT_TORPEDO } else { SHOT_MISSILE }
            } else if *struck >= 2 {
                SHOT_HEAVY
            } else {
                SHOT_BOLT
            };
            if h.downed {
                self.tally.down[usize::from(kind)] += 1;
                self.struck.remove(&shot);
                if let Some(body) = self.seen.remove(&shot)
                    && let Some(t) = self.ships.iter_mut().find(|t| t.body == body)
                {
                    t.downed += 1;
                }
            }
            let pulse = &bolts.ids[p];
            let mount = self
                .book
                .pulses
                .get(pulse)
                .and_then(|pl| mounts.iter().position(|m| m.id == pl.battery))
                .map_or(-1, |k| k as i32);
            out.push(Met {
                mount,
                shot,
                at: ik::meeting_point(bolts, h),
                color: bolts.colors[q],
                downed: h.downed,
                kind,
            });
        }
        ik::apply_hits(bolts, &self.hits);
    }

    /// One tick of every battery, in mount order (after `meet`): the pulses in flight give their cover, then each working
    /// battery whose next barrel is ready fires at the best shot it can take (`intercept_kernels::fire_battery`), its own hull
    /// never in the way. Appends the pulses fired.
    #[allow(clippy::too_many_arguments)]
    pub fn step<F: Fn(i64) -> Option<usize>>(
        &mut self,
        mounts: &mut [Mount],
        owners: &[Owner],
        owner_of: &[u32],
        world: &GunWorld<'_, F>,
        view: &GuardView<'_>,
        bolts: &Bolts,
        missiles: &[Missile],
        now_s: f64,
        delta: f64,
        tick: i64,
        out: &mut Vec<PulseShot>,
    ) {
        out.clear();
        let any_battery = mounts.iter().any(|m| m.spec.role == ROLE_PD);
        if !any_battery && self.book.pulses.is_empty() {
            return;
        }
        self.book.refresh(bolts, now_s);
        if tick % PRUNE_EVERY == 0 {
            self.prune(bolts);
        }
        if !any_battery || !self.place_shots(bolts) {
            return;
        }
        self.guide(bolts, missiles);
        self.sides_used = 0;
        self.taken.clear();
        self.taken.resize(bolts.ids.len(), 0);
        let rows = world.rows;
        for (i, m) in mounts.iter_mut().enumerate() {
            if m.spec.role != ROLE_PD || !m.works || m.rate <= 0.0 {
                continue;
            }
            let o = owner_of[i] as usize;
            let Some(owner) = owners.get(o) else {
                continue;
            };
            let Some(r) = usize::try_from(world.owner_rows[o]).ok() else {
                continue;
            };
            let frame = tk::frame(&rows.bases[r], rows.positions[r], m.local_at, m.axis, m.zero);
            let side = self.side_for(rows.faction_ix[r], world, view, bolts);
            self.cells.look(frame.pivot, m.spec.range_m, &mut self.look);
            self.candidates.clear();
            self.candidates.extend(self.look.iter().map(|&k| self.shot_rows[k as usize] as usize));
            self.candidates.sort_unstable();
            let observer = rows.faction_ix[r];
            let (sides, guided) = (&mut self.sides, &self.guided);
            let s = &mut sides[side];
            ik::gather(
                bolts,
                self.candidates.iter().copied(),
                frame.pivot,
                m.spec.range_m,
                |p| hostile_to(rows, bolts, view.shooter_rows, world.hostile, world.factions, observer, p),
                |p| side_time(s, rows, bolts, guided, &world.row_of, p, now_s).0,
                &mut self.incoming,
            );
            let own = |c: &Incoming| {
                let k = s.times[c.bolt as usize].1 as usize;
                k < rows.body_ids.len() && owner.bodies.contains(&rows.body_ids[k])
            };
            for c in &self.incoming {
                if own(c)
                    && let std::collections::hash_map::Entry::Vacant(e) = self.seen.entry(bolts.ids[c.bolt as usize])
                {
                    e.insert(owner.body);
                    match self.ships.iter_mut().find(|t| t.body == owner.body) {
                        Some(t) => t.incoming += 1,
                        None => self.ships.push(ShipTally { body: owner.body, incoming: 1, downed: 0 }),
                    }
                }
            }
            if now_s + 1e-6 < m.ready_at || !m.battery.barrel_ready(now_s) || self.incoming.is_empty() {
                continue;
            }
            let gun = m.spec.gun();
            let mut at = ik::BatteryAt {
                frame,
                min_elevation: m.min_elevation,
                azimuth: m.azimuth,
                elevation: m.elevation,
                battery: &mut m.battery,
                gun: &gun,
                velocity: rows.velocities[r],
                lane: m.id.wrapping_mul(1 << 20).wrapping_add(m.shots),
            };
            let fired = ik::fire_battery(
                &mut at,
                bolts,
                &self.incoming,
                &mut self.book.cover,
                &mut self.taken,
                |c| u8::from(!own(c)),
                |from, to| !own_hull_blocks(world, owner, from, to),
                now_s,
                delta,
                tick,
            );
            let Some(f) = fired else {
                continue;
            };
            m.ready_at = now_s + m.spec.cycle_s / m.rate;
            m.shots += 1;
            m.azimuth = f.azimuth;
            m.elevation = f.elevation;
            self.tally.pulses += 1;
            out.push(PulseShot {
                mount: i as u32,
                mount_id: m.id,
                start: f.muzzle,
                velocity: f.velocity,
                barrel: f.barrel as u8,
                target: f.target,
                meet_at: f.meet_at,
            });
        }
    }

    // The shots a battery could take this tick placed in the broad phase's cells as points; false when there are none.
    fn place_shots(&mut self, bolts: &Bolts) -> bool {
        self.shot_rows.clear();
        self.points.clear();
        self.zero.clear();
        for p in 0..bolts.ids.len() {
            if ik::is_shot(bolts, p) {
                self.shot_rows.push(p as u32);
                self.points.push(bolts.positions[p]);
                self.zero.push(0.0);
            }
        }
        if self.shot_rows.is_empty() {
            return false;
        }
        self.cells.place(&self.points, &self.zero);
        self.cells.mark_cells();
        true
    }

    // Each bolt row's guided target (a capital's missile or torpedo in flight), 0 for none.
    fn guide(&mut self, bolts: &Bolts, missiles: &[Missile]) {
        self.guided.clear();
        self.guided.resize(bolts.ids.len(), 0);
        let owned = &bolts.ids[..bolts.owned.min(bolts.ids.len())];
        for missile in missiles {
            // Owned bolts are in launch order with falling ids, so a binary search finds one.
            if let Ok(i) = owned.binary_search_by(|id| missile.bolt.cmp(id)) {
                self.guided[i] = missile.target;
            }
        }
    }

    // The guarded set of faction `faction` this tick (made on its first battery's turn): every live big hull it perceives as
    // its own side's or a friend's.
    fn side_for<F: Fn(i64) -> Option<usize>>(&mut self, faction: u32, world: &GunWorld<'_, F>, view: &GuardView<'_>, bolts: &Bolts) -> usize {
        if let Some(k) = self.sides[..self.sides_used].iter().position(|s| s.faction == faction) {
            return k;
        }
        if self.sides.len() <= self.sides_used {
            self.sides.push(Side::default());
        }
        let k = self.sides_used;
        self.sides_used += 1;
        let rows = world.rows;
        let n = world.factions;
        let s = &mut self.sides[k];
        s.faction = faction;
        s.guarded.clear();
        s.bounds.clear();
        s.is_guarded.clear();
        s.is_guarded.resize(rows.body_ids.len(), false);
        for &h in world.hull_rows {
            let j = h as usize;
            if j >= rows.body_ids.len() || rows.surface(j).is_none() || !live_hull(rows, j) {
                continue;
            }
            let seen = rows.seen_ix(j, faction) as usize;
            let a = faction as usize;
            if seen == a || (a < n && seen < n && view.friendly.get(a * n + seen).copied().unwrap_or(false)) {
                s.guarded.push(j);
                s.bounds.push(rows.surface(j).map_or(f64::INFINITY, ik::hull_bound));
                s.is_guarded[j] = true;
            }
        }
        s.times.clear();
        s.times.resize(bolts.ids.len(), (ik::NOT_SWEPT, u32::MAX));
        k
    }

    // Drops the records of shots no longer flying.
    fn prune(&mut self, bolts: &Bolts) {
        if self.seen.is_empty() && self.struck.is_empty() {
            return;
        }
        self.live_ids.clear();
        self.live_ids.extend(bolts.ids.iter().zip(&bolts.spent).filter(|(_, s)| !**s).map(|(id, _)| *id));
        let live = &self.live_ids;
        self.seen.retain(|id, _| live.contains(id));
        self.struck.retain(|id, _| live.contains(id));
    }
}

// How soon bolt `p` meets one of side `s`'s guarded hulls, and which (infinite and `u32::MAX` for none), kept for the tick. A
// guided missile meets its own target, guarded or not: its straight path says nothing of where it turns.
fn side_time<F: Fn(i64) -> Option<usize>>(
    s: &mut Side,
    rows: &Rows,
    bolts: &Bolts,
    guided: &[i64],
    row_of: &F,
    p: usize,
    now_s: f64,
) -> (f64, u32) {
    if !s.times[p].0.is_nan() {
        return s.times[p];
    }
    let target = guided.get(p).copied().unwrap_or(0);
    let found = if bolts.kinds[p] == KIND_MISSILE && target != 0 {
        row_of(target)
            .filter(|&j| s.is_guarded.get(j).copied().unwrap_or(false))
            .and_then(|j| {
                let speed = f64::from(length(bolts.velocities[p])).max(1.0);
                let gap = (f64::from(dist_sq(bolts.positions[p], rows.positions[j])).sqrt() - rows.radii[j]).max(0.0);
                let when = gap / speed;
                let life = bolts.expires_at[p] - now_s;
                (when <= ik::INTERCEPT_HORIZON_S && (!life.is_finite() || when <= life)).then_some((when, j))
            })
    } else {
        ik::first_hull_hit_within(rows, &s.guarded, &s.bounds, bolts, p, now_s)
    };
    s.times[p] = found.map_or((f64::INFINITY, u32::MAX), |(t, j)| (t, j as u32));
    s.times[p]
}

#[cfg(test)]
mod tests;
