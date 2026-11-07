// The stand-ins' weapons on the core's rows (M4-T20, docs/architecture.md 17.13): the capitals' guns, interceptors and beam
// emitters, their strike targets and missile launches, the mines' triggers and blasts, and a missile's guidance, one call
// per tick (or per missile). The maths is `weapon_kernels`; this class binds the core, keeps the turrets' and mines' state
// between ticks and hands the decisions over. The GDScript stand-ins stay the reference and do every engine write (bolts
// spawned, projectiles spent, hits applied) from what this returns.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::rows::{FLAG_HULK, FLAG_RIGID, FLAG_TIER};
use crate::sim_core::ScsSimCore;
use crate::tier_fire;
use crate::weapon_kernels::{
    self as wk, Candidate, Capitals, Mines, ROLE_BEAM, ROLE_GUN, ROLE_INTERCEPTOR, Turrets,
};

/// The capitals' turrets and the mine belts as rows with no node, stepped once per tick over the core's rows by the
/// weapon kernels. Never calls the engine or `Factions`: the caller passes the hostility table (by the core's faction
/// indices) and does what the step decides.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsWeaponRows {
    base: Base<RefCounted>,
    core: Option<Gd<ScsSimCore>>,
    turrets: Turrets,
    capitals: Capitals,
    mines: Mines,
    // The hostility table, row-major by the core's faction indices, and its size.
    hostile: Vec<bool>,
    factions: usize,
    // Per-call scratch, owned by this shell.
    fighters: Vec<u32>,
    cap_rows: Vec<i64>,
    candidates: Vec<Candidate>,
    spent: Vec<bool>,
    hits: Vec<u32>,
    fired: Vec<bool>,
    // The far capitals' fire (M4-T22): missiles resolved at launch and still flying to their targets, and the rolls run.
    tier_missiles: Vec<TierMissile>,
    tier_rolls: i64,
    tier_us: f64,
    // The far missiles' ids so far, and each capital's interceptor shots spent on far missiles in its current second
    // (`(second, shots)`), so its interceptors take at most two a second each (fix round 1).
    next_tier_missile: i64,
    intercept_used: Vec<(i64, i64)>,
}

// A far capital's missile, its outcome rolled at launch, landing (or missing) when it would have arrived.
struct TierMissile {
    id: i64,
    shooter: i64,
    faction_ix: u32,
    target: i64,
    arrive_tick: i64,
    hit: bool,
}

// What a far capital's rolls land this tick, for GDScript to hand to each target's `Damageable`.
#[derive(Default)]
struct TierLanded {
    targets: Vec<i64>,
    shooters: Vec<i64>,
    damage: Vec<f64>,
    points: Vec<Vector3>,
    // Each hit's far missile (0 for a gun or beam), the far missiles launched (ids, targets), those that left the air this
    // tick (landed, missed or shot down), and how many of those were shot down.
    missile_ids: Vec<i64>,
    launched_ids: Vec<i64>,
    launched_targets: Vec<i64>,
    ended_ids: Vec<i64>,
    intercepted: i64,
    launches: i64,
}

impl TierLanded {
    fn push(&mut self, target: i64, shooter: i64, damage: f64, at: Vector3) {
        self.targets.push(target);
        self.shooters.push(shooter);
        self.damage.push(damage);
        self.points.push(at);
        self.missile_ids.push(0);
    }
}

#[godot_api]
impl ScsWeaponRows {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Reads the core's rows from now on.
    #[func]
    fn attach_core(&mut self, core: Gd<ScsSimCore>) -> bool {
        self.core = Some(core);
        true
    }

    /// The capitals in the director's order (0 for one that is gone), each with no strike target looked up yet.
    #[func]
    fn set_capitals(&mut self, body_ids: PackedInt64Array) {
        let n = body_ids.len();
        self.capitals = Capitals {
            body_ids: body_ids.as_slice().to_vec(),
            strike_target: vec![0; n],
            strike_tick: vec![0; n],
            strike_known: vec![false; n],
            turn: 0,
        };
    }

    /// The turrets, capital by capital in the director's order: each one's capital (its place in `set_capitals`), offset
    /// from it and role (0 gun, 1 interceptor, 2 beam). Their state starts empty (`set_turret_state` gives it).
    #[func]
    fn set_turrets(
        &mut self,
        capitals: PackedInt32Array,
        locals: PackedVector3Array,
        roles: PackedByteArray,
    ) -> bool {
        let n = capitals.len();
        if locals.len() != n || roles.len() != n {
            godot_error!(
                "ScsWeaponRows.set_turrets: array lengths differ (capitals {n}, locals {}, roles {})",
                locals.len(),
                roles.len()
            );
            return false;
        }
        let bound = self.capitals.body_ids.len();
        if let Some(bad) = capitals
            .as_slice()
            .iter()
            .find(|&&c| c < 0 || c as usize >= bound)
        {
            godot_error!(
                "ScsWeaponRows.set_turrets: a turret of capital {bad}, but {bound} capitals are bound (set_capitals first)"
            );
            return false;
        }
        self.turrets = Turrets {
            capital: capitals
                .as_slice()
                .iter()
                .map(|&c| c.max(0) as u32)
                .collect(),
            local: locals.as_slice().to_vec(),
            role: roles.as_slice().to_vec(),
            axis: vec![Vector3::ZERO; n],
            target: vec![0; n],
            aim_error: vec![std::f64::consts::PI; n],
            ready_at: vec![f64::NEG_INFINITY; n],
            shots: vec![0; n],
            missile_shots: vec![0; n],
        };
        true
    }

    /// Every turret's state as the GDScript keeps it: axes, targets (body ids), aim errors, the gates' ready times, shots
    /// and missiles shot down.
    #[func]
    fn set_turret_state(
        &mut self,
        axes: PackedVector3Array,
        targets: PackedInt64Array,
        aim_errors: PackedFloat64Array,
        ready_ats: PackedFloat64Array,
        shots: PackedInt64Array,
        missile_shots: PackedInt64Array,
    ) -> bool {
        let n = self.turrets.role.len();
        let lined_up = [
            axes.len(),
            targets.len(),
            aim_errors.len(),
            ready_ats.len(),
            shots.len(),
            missile_shots.len(),
        ]
        .iter()
        .all(|&l| l == n);
        if !lined_up {
            godot_error!("ScsWeaponRows.set_turret_state: every array must hold {n} turrets");
            return false;
        }
        let t = &mut self.turrets;
        t.axis = axes.as_slice().to_vec();
        t.target = targets.as_slice().to_vec();
        t.aim_error = aim_errors.as_slice().to_vec();
        t.ready_at = ready_ats.as_slice().to_vec();
        t.shots = shots.as_slice().to_vec();
        t.missile_shots = missile_shots.as_slice().to_vec();
        true
    }

    /// `[axes, targets, aim errors, ready times, shots, missiles shot down]`, turret by turret.
    #[func]
    fn turret_state(&self) -> VarArray {
        let t = &self.turrets;
        let mut out = VarArray::new();
        out.push(&PackedVector3Array::from(t.axis.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(t.target.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(t.aim_error.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(t.ready_at.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(t.shots.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(t.missile_shots.as_slice()).to_variant());
        out
    }

    /// The capitals' strike state: held targets, the ticks they were looked up, whether one was (1) or not yet (0), and
    /// whose turn it is to launch.
    #[func]
    fn set_strike_state(
        &mut self,
        targets: PackedInt64Array,
        ticks: PackedInt64Array,
        known: PackedByteArray,
        turn: i64,
    ) -> bool {
        let n = self.capitals.body_ids.len();
        if targets.len() != n || ticks.len() != n || known.len() != n {
            godot_error!("ScsWeaponRows.set_strike_state: every array must hold {n} capitals");
            return false;
        }
        let c = &mut self.capitals;
        c.strike_target = targets.as_slice().to_vec();
        c.strike_tick = ticks.as_slice().to_vec();
        c.strike_known = known.as_slice().iter().map(|&k| k == 1).collect();
        c.turn = turn;
        true
    }

    /// `[targets, ticks, known (bytes), turn]`, as `set_strike_state` takes them.
    #[func]
    fn strike_state(&self) -> VarArray {
        let c = &self.capitals;
        let known: Vec<u8> = c.strike_known.iter().map(|&k| u8::from(k)).collect();
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(c.strike_target.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(c.strike_tick.as_slice()).to_variant());
        out.push(&PackedByteArray::from(known.as_slice()).to_variant());
        out.push(&c.turn.to_variant());
        out
    }

    /// The hostility table: `matrix[a * count + b]` is 1 when the core's factions `a` and `b` are hostile.
    #[func]
    fn set_hostility(&mut self, count: i64, matrix: PackedByteArray) -> bool {
        let n = usize::try_from(count).unwrap_or(0);
        if matrix.len() != n * n {
            godot_error!(
                "ScsWeaponRows.set_hostility: {} entries for {n} factions",
                matrix.len()
            );
            return false;
        }
        self.factions = n;
        self.hostile = matrix.as_slice().iter().map(|&b| b == 1).collect();
        true
    }

    /// How many factions the core knows now (the hostility table must cover them all).
    #[func]
    fn faction_count(&self) -> i64 {
        self.core
            .as_ref()
            .map_or(0, |c| c.bind().factions.len() as i64)
    }

    /// One tick of the guns, interceptors, beams and missile launches at tick `tick` and sim time `now_s`, over the core's
    /// rows. Returns what the GDScript must do, in its order: `[guns that fired (turret rows), their bolts' starts, their
    /// velocities, projectiles shot down (ids), whether each was a missile (bytes), beams that fired (turret rows), their
    /// targets' places, launches (capital places), their targets (body ids), missiles in flight after the launches]`, then
    /// the far capitals' fire (M4-T22): `[hits' targets (body ids), their shooters, their damage, their places, missiles
    /// launched from the tier, group rolls run, each hit's far missile (0: a gun or beam), the far missiles launched (ids),
    /// their targets (body ids), the far missiles that left the air, how many far missiles were shot down]`. A second is
    /// `ticks_per_second` ticks.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn step(
        &mut self,
        tick: i64,
        now_s: f64,
        delta: f64,
        intercept_ticks: i64,
        beam_ticks: i64,
        missile_target: i64,
        max_launches: i64,
        ticks_per_second: i64,
    ) -> VarArray {
        let mut gun_rows: Vec<i32> = Vec::new();
        let mut bolt_at: Vec<Vector3> = Vec::new();
        let mut bolt_velocity: Vec<Vector3> = Vec::new();
        let mut spent_ids: Vec<i64> = Vec::new();
        let mut spent_missile: Vec<u8> = Vec::new();
        let mut beam_rows: Vec<i32> = Vec::new();
        let mut beam_targets: Vec<Vector3> = Vec::new();
        let mut launch_caps: Vec<i32> = Vec::new();
        let mut launch_targets: Vec<i64> = Vec::new();
        let mut flying: i64 = 0;
        let mut landed = TierLanded::default();
        if let Some(core) = self.core.clone() {
            let guard = core.bind();
            let Self {
                turrets,
                capitals,
                hostile,
                factions,
                fighters,
                cap_rows,
                candidates,
                spent,
                tier_missiles,
                tier_rolls,
                tier_us,
                next_tier_missile,
                intercept_used,
                ..
            } = self;
            let n = *factions;
            let row_of = |f: u32| table_row(hostile, n, f);
            let rows = &guard.rows;
            cap_rows.clear();
            // A capital in the low-attention tier (M4-T21) has no row here: its weapons wait for T22's aggregated fire.
            cap_rows.extend(capitals.body_ids.iter().map(|&id| {
                if id == 0 {
                    return -1;
                }
                let r = guard.row_of_id(id);
                match usize::try_from(r) {
                    Ok(i) if rows.flags[i] & FLAG_TIER != 0 => -1,
                    _ => r,
                }
            }));
            // Guns: a pick every few ticks (staggered), then the aim step and the gate every tick.
            wk::fighter_rows(rows, fighters);
            let mut gun_index: i64 = 0;
            for t in 0..turrets.role.len() {
                if turrets.role[t] != ROLE_GUN {
                    continue;
                }
                let c = turrets.capital[t] as usize;
                let Some(r) = usize::try_from(cap_rows[c]).ok() else {
                    continue;
                };
                let at = wk::turret_at(&rows.bases[r], rows.positions[r], turrets.local[t]);
                let cap_velocity = rows.velocities[r];
                if (tick + gun_index) % wk::RETARGET_TICKS == 0 {
                    turrets.target[t] = wk::retarget(
                        rows,
                        fighters,
                        row_of(rows.faction_ix[r]),
                        capitals.body_ids[c],
                        at,
                    );
                }
                gun_index += 1;
                let target_row = if turrets.target[t] == 0 {
                    -1
                } else {
                    guard.row_of_id(turrets.target[t])
                };
                let Some(j) = usize::try_from(target_row)
                    .ok()
                    .filter(|&j| wk::in_reach(at, rows.positions[j]))
                else {
                    turrets.target[t] = 0;
                    turrets.aim_error[t] = std::f64::consts::PI;
                    continue;
                };
                let target_velocity = if rows.rigid[j] {
                    rows.velocities[j]
                } else {
                    Vector3::ZERO
                };
                let Some(aim) = wk::aim_gun(
                    at,
                    cap_velocity,
                    rows.positions[j],
                    target_velocity,
                    turrets.axis[t],
                    delta,
                ) else {
                    continue;
                };
                turrets.axis[t] = aim.axis;
                turrets.aim_error[t] = aim.aim_error;
                let (fire, ready) = wk::gate(
                    turrets.ready_at[t],
                    now_s,
                    wk::on_target(aim.aim_error),
                    wk::SHOT_INTERVAL_S,
                );
                turrets.ready_at[t] = ready;
                if fire {
                    let (start, velocity) = wk::muzzle(at, cap_velocity, aim.axis);
                    gun_rows.push(t as i32);
                    bolt_at.push(start);
                    bolt_velocity.push(velocity);
                    turrets.shots[t] += 1;
                }
            }
            // Interceptors: those due this tick, each taking the best projectile in reach not yet shot down this tick.
            let bolts = &guard.bolts;
            let shots_in_flight = wk::shots_in_flight(bolts);
            let mut index: i64 = 0;
            spent.clear();
            spent.resize(bolts.ids.len(), false);
            let due_ticks = intercept_ticks.max(1);
            for t in 0..turrets.role.len() {
                if turrets.role[t] != ROLE_INTERCEPTOR {
                    continue;
                }
                let c = turrets.capital[t] as usize;
                let Some(r) = usize::try_from(cap_rows[c]).ok() else {
                    continue;
                };
                index += 1;
                if (tick + index) % due_ticks != 0 || shots_in_flight == 0 {
                    continue;
                }
                let at = wk::turret_at(&rows.bases[r], rows.positions[r], turrets.local[t]);
                wk::intercept_candidates(bolts, row_of(rows.faction_ix[r]), at, candidates);
                if let Some(best) = wk::intercept_pick(candidates, spent) {
                    spent[best.bolt as usize] = true;
                    spent_ids.push(bolts.ids[best.bolt as usize]);
                    spent_missile.push(u8::from(best.missile));
                    turrets.shots[t] += 1;
                    turrets.missile_shots[t] += i64::from(best.missile);
                }
            }
            // Beams: those due this tick fire at their capital's strike target within a beam's reach.
            let mut index: i64 = 0;
            let beam_due = beam_ticks.max(1);
            for t in 0..turrets.role.len() {
                if turrets.role[t] != ROLE_BEAM {
                    continue;
                }
                let c = turrets.capital[t] as usize;
                let Some(r) = usize::try_from(cap_rows[c]).ok() else {
                    continue;
                };
                index += 1;
                if (tick + index) % beam_due != 0 {
                    continue;
                }
                let Some(target_at) =
                    strike(&guard, capitals, c, r, tick, row_of(rows.faction_ix[r]))
                else {
                    continue;
                };
                let at = wk::turret_at(&rows.bases[r], rows.positions[r], turrets.local[t]);
                if !wk::in_beam_reach(target_at, at) {
                    continue;
                }
                beam_rows.push(t as i32);
                beam_targets.push(target_at);
            }
            // The far capitals (M4-T22): once a second each, the guns and beams as rolls, the interceptors as removals.
            let tier_started = std::time::Instant::now();
            let second_ticks = ticks_per_second.max(1);
            let seed = guard.tier_seed;
            for (c, &body) in capitals.body_ids.iter().enumerate() {
                let Some(r) = tier_row_of(&guard, body) else {
                    continue;
                };
                if (tick + c as i64 * 7).rem_euclid(second_ticks) != 0 {
                    continue;
                }
                *tier_rolls += 1;
                let hostile = row_of(rows.faction_ix[r]);
                let at = rows.positions[r];
                let (mut guns, mut beams, mut interceptors) = (0i64, 0i64, 0i64);
                for t in 0..turrets.role.len() {
                    if turrets.capital[t] as usize != c {
                        continue;
                    }
                    match turrets.role[t] {
                        ROLE_GUN => guns += 1,
                        ROLE_BEAM => beams += 1,
                        _ => interceptors += 1,
                    }
                }
                let second = tick.div_euclid(second_ticks);
                let key = c as i64 * 8;
                if let Some(j) = tier_fire::nearest_hostile_fighter(
                    rows,
                    hostile,
                    at,
                    tier_fire::GUN_RANGE_M,
                    body,
                ) {
                    let range = f64::from(wk_distance(at, rows.positions[j]));
                    let chance = tier_fire::turret_chance(range, rows.radii[j]);
                    let hits = tier_fire::hits_of(seed, tick, key, guns, chance);
                    for _ in 0..hits {
                        landed.push(
                            rows.body_ids[j],
                            body,
                            tier_fire::GUN_DAMAGE,
                            rows.positions[j],
                        );
                    }
                }
                // Each beam fires every `BEAM_INTERVAL_S` (two seconds), the emitters on alternate seconds.
                let due = (0..beams)
                    .filter(|k| (second + k).rem_euclid(2) == 0)
                    .count() as i64;
                if due > 0
                    && let Some(j) = tier_fire::nearest_hostile_fighter(
                        rows,
                        hostile,
                        at,
                        tier_fire::STRIKE_RANGE_M,
                        body,
                    )
                {
                    let range = f64::from(wk_distance(at, rows.positions[j]));
                    let hits =
                        tier_fire::hits_of(seed, tick, key + 1, due, tier_fire::beam_chance(range));
                    for _ in 0..hits {
                        landed.push(
                            rows.body_ids[j],
                            body,
                            tier_fire::BEAM_DAMAGE,
                            rows.positions[j],
                        );
                    }
                }
                // The interceptors: two shots each a second at the nearest hostile missiles in reach, as the near ones pick.
                if interceptors > 0 && shots_in_flight > 0 {
                    wk::intercept_candidates(bolts, hostile, at, candidates);
                    candidates.retain(|cand| cand.missile);
                    for _ in 0..interceptors * 2 {
                        let Some(best) = wk::intercept_pick(candidates, spent) else {
                            break;
                        };
                        spent[best.bolt as usize] = true;
                        spent_ids.push(bolts.ids[best.bolt as usize]);
                        spent_missile.push(1);
                    }
                }
            }
            // The far capitals' missiles that arrive this tick: shot down when an interceptor hostile to them (near or tier)
            // came within its reach of the missile's path (its capital to the target) with a shot to spare this second, as the near interceptors take a missile
            // in reach at two shots a second each; else they land if their launch rolled a hit and the target still flies
            // (not a hulk). GDScript drops a landing on a target that was released and taken out again since its launch.
            intercept_used.resize(capitals.body_ids.len(), (-1, 0));
            let second = tick.div_euclid(second_ticks);
            let mut interceptors_of = vec![0i64; capitals.body_ids.len()];
            for t in 0..turrets.role.len() {
                if turrets.role[t] == ROLE_INTERCEPTOR {
                    interceptors_of[turrets.capital[t] as usize] += 1;
                }
            }
            tier_missiles.retain(|m| {
                if m.arrive_tick > tick {
                    return true;
                }
                landed.ended_ids.push(m.id);
                let Some(j) = usize::try_from(guard.row_of_id(m.target))
                    .ok()
                    .filter(|&j| rows.flags[j] & FLAG_HULK == 0)
                else {
                    return false;
                };
                let target_at = rows.positions[j];
                // The path: from its capital (where it is now; a cruising capital moves little in a missile's flight, and a
                // rebase moves it with the rows) to the target.
                let from = usize::try_from(guard.row_of_id(m.shooter))
                    .map_or(target_at, |s| rows.positions[s]);
                for (c, &body) in capitals.body_ids.iter().enumerate() {
                    let r = match usize::try_from(cap_rows[c]) {
                        Ok(r) => Some(r),
                        Err(_) => tier_row_of(&guard, body),
                    };
                    let Some(r) = r else {
                        continue;
                    };
                    let interceptors = interceptors_of[c];
                    let reach = tier_fire::INTERCEPT_RANGE_M + rows.radii[r];
                    if interceptors == 0
                        || !table_row(hostile, n, rows.faction_ix[r])
                            .get(m.faction_ix as usize)
                            .copied()
                            .unwrap_or(false)
                        || tier_fire::segment_dist_sq(from, target_at, rows.positions[r])
                            > reach * reach
                    {
                        continue;
                    }
                    let used = &mut intercept_used[c];
                    if used.0 != second {
                        *used = (second, 0);
                    }
                    if used.1 < interceptors * 2 {
                        used.1 += 1;
                        landed.intercepted += 1;
                        return false;
                    }
                }
                if m.hit {
                    landed.push(m.target, m.shooter, tier_fire::MISSILE_DAMAGE, target_at);
                    if let Some(last) = landed.missile_ids.last_mut() {
                        *last = m.id;
                    }
                }
                false
            });
            let mut tier_ns = tier_started.elapsed().as_nanos() as f64;
            // Missiles: top the count in flight up from the capitals in turn that have a strike target.
            flying = (wk::missiles_in_flight(bolts) + tier_missiles.len()) as i64;
            let count = capitals.body_ids.len();
            if missile_target > 0 && count > 0 {
                let mut launched: i64 = 0;
                let mut tried = 0;
                while flying < missile_target && launched < max_launches && tried < count {
                    let c = capitals.turn.rem_euclid(count as i64) as usize;
                    capitals.turn += 1;
                    tried += 1;
                    let Some(r) = usize::try_from(cap_rows[c]).ok() else {
                        // A far capital's launch is resolved now (M4-T22): the hit rolled, the landing when it arrives.
                        let launch_started = std::time::Instant::now();
                        let body = capitals.body_ids[c];
                        let Some(t) = tier_row_of(&guard, body) else {
                            continue;
                        };
                        let hostile = row_of(rows.faction_ix[t]);
                        let at = rows.positions[t];
                        let Some(j) = tier_fire::nearest_hostile_fighter(
                            rows,
                            hostile,
                            at,
                            tier_fire::STRIKE_RANGE_M,
                            body,
                        ) else {
                            continue;
                        };
                        let range = f64::from(wk_distance(at, rows.positions[j]));
                        let flight_ticks = (range / tier_fire::MISSILE_SPEED_MPS
                            * second_ticks as f64)
                            .ceil() as i64;
                        let draw = tier_fire::roll(seed, tick, c as i64 * 8 + 2, landed.launches);
                        *next_tier_missile += 1;
                        tier_missiles.push(TierMissile {
                            id: *next_tier_missile,
                            shooter: body,
                            faction_ix: rows.faction_ix[t],
                            target: rows.body_ids[j],
                            arrive_tick: tick + flight_ticks.max(1),
                            hit: draw < tier_fire::missile_chance(range),
                        });
                        landed.launched_ids.push(*next_tier_missile);
                        landed.launched_targets.push(rows.body_ids[j]);
                        landed.launches += 1;
                        tier_ns += launch_started.elapsed().as_nanos() as f64;
                        flying += 1;
                        launched += 1;
                        continue;
                    };
                    if strike(&guard, capitals, c, r, tick, row_of(rows.faction_ix[r])).is_none() {
                        continue;
                    }
                    launch_caps.push(c as i32);
                    launch_targets.push(capitals.strike_target[c]);
                    flying += 1;
                    launched += 1;
                }
            }
            *tier_us = tier_ns / 1000.0;
        }
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(gun_rows.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(bolt_at.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(bolt_velocity.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(spent_ids.as_slice()).to_variant());
        out.push(&PackedByteArray::from(spent_missile.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(beam_rows.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(beam_targets.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(launch_caps.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(launch_targets.as_slice()).to_variant());
        out.push(&flying.to_variant());
        out.push(&PackedInt64Array::from(landed.targets.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(landed.shooters.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(landed.damage.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(landed.points.as_slice()).to_variant());
        out.push(&landed.launches.to_variant());
        out.push(&self.tier_rolls.to_variant());
        out.push(&PackedInt64Array::from(landed.missile_ids.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(landed.launched_ids.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(landed.launched_targets.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(landed.ended_ids.as_slice()).to_variant());
        out.push(&landed.intercepted.to_variant());
        out
    }

    /// The last step's far-capital rolls, microseconds (wall clock; a readout, M4-T22).
    #[func]
    fn tier_us(&self) -> f64 {
        self.tier_us
    }

    /// The far capitals' missiles resolved at launch and not yet arrived (M4-T22).
    #[func]
    fn tier_missiles(&self) -> i64 {
        self.tier_missiles.len() as i64
    }

    /// The mines: offsets from the belt's node, layers (faction names) and which are in play.
    #[func]
    fn set_mines(
        &mut self,
        locals: PackedVector3Array,
        factions: Array<StringName>,
        alive: PackedByteArray,
    ) -> bool {
        let n = locals.len();
        if factions.len() != n || alive.len() != n {
            godot_error!("ScsWeaponRows.set_mines: every array must hold {n} mines");
            return false;
        }
        let Some(core) = self.core.as_mut() else {
            return false;
        };
        let faction_ix: Vec<u32> = {
            let mut guard = core.bind_mut();
            factions
                .iter_shared()
                .map(|f| guard.faction_index(f))
                .collect()
        };
        let local = locals.as_slice().to_vec();
        self.mines = Mines {
            cells: wk::mine_cells(&local),
            local,
            faction_ix,
            alive: alive.as_slice().iter().map(|&a| a == 1).collect(),
        };
        true
    }

    /// Mine `index` is in play again, or went off.
    #[func]
    fn set_mine_alive(&mut self, index: i64, alive: bool) {
        if let Some(a) = usize::try_from(index)
            .ok()
            .and_then(|i| self.mines.alive.get_mut(i))
        {
            *a = alive;
        }
    }

    /// One tick of the mines' triggers at tick `tick` with the belt's node at `origin`: `[mines that checked, mines set
    /// off (ascending)]`.
    #[func]
    fn mine_step(&mut self, tick: i64, origin: Vector3) -> VarArray {
        let phase = tick.rem_euclid(wk::TRIGGER_TICKS) as usize;
        let mines = &self.mines;
        let checked = (0..mines.local.len())
            .filter(|&i| i % wk::TRIGGER_TICKS as usize == phase && mines.alive[i])
            .count() as i64;
        let mut set_off: Vec<i32> = Vec::new();
        if let Some(core) = self.core.as_ref() {
            let guard = core.bind();
            let rows = &guard.rows;
            let n = self.factions;
            self.fired.clear();
            self.fired.resize(mines.local.len(), false);
            // Each hull's column of the table, by mine faction (hostility is symmetric); tier rows set mines off too.
            for &h in &guard.sweep_rows {
                let j = h as usize;
                if rows.flags[j] & FLAG_RIGID == 0 && rows.flags[j] & FLAG_TIER == 0 {
                    continue;
                }
                let column = table_row(&self.hostile, n, rows.faction_ix[j]);
                self.hits.clear();
                wk::mine_hits(
                    mines,
                    phase,
                    origin,
                    rows.positions[j],
                    rows.radii[j],
                    column,
                    &mut self.hits,
                );
                for &m in &self.hits {
                    self.fired[m as usize] = true;
                }
            }
            set_off = (0..self.fired.len())
                .filter(|&i| self.fired[i])
                .map(|i| i as i32)
                .collect();
        }
        let mut out = VarArray::new();
        out.push(&checked.to_variant());
        out.push(&PackedInt32Array::from(set_off.as_slice()).to_variant());
        out
    }

    /// The hulls in the blast of a mine at `at`, near and tier rows in the core's order (M4-T23): `[hull ids, their bodies' places]`.
    #[func]
    fn blast(&mut self, at: Vector3) -> VarArray {
        let mut ids: Vec<i64> = Vec::new();
        let mut places: Vec<Vector3> = Vec::new();
        if let Some(core) = self.core.as_ref() {
            let guard = core.bind();
            self.hits.clear();
            wk::blast(&guard.rows, &guard.sweep_rows, at, &mut self.hits);
            for &r in &self.hits {
                ids.push(guard.rows.hull_ids[r as usize]);
                places.push(guard.rows.positions[r as usize]);
            }
        }
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(places.as_slice()).to_variant());
        out
    }

    /// One missile's guidance toward body `target_id` from its row: the velocity in x, y and z and in w 1 when steered,
    /// 0 when the target is gone (it flies straight on), -1 when the rows cannot answer (no core, or the target was
    /// touched since its row was read) and the GDScript must.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn steer_missile(
        &self,
        target_id: i64,
        position: Vector3,
        velocity: Vector3,
        nav_gain: f64,
        max_turn_rate: f64,
        delta: f64,
    ) -> Vector4 {
        let answer = |v: Vector3, w: f32| Vector4::new(v.x, v.y, v.z, w);
        let Some(core) = self.core.as_ref() else {
            return answer(velocity, -1.0);
        };
        let guard = core.bind();
        if guard.is_touched(target_id) {
            return answer(velocity, -1.0);
        }
        let Some(j) = usize::try_from(guard.row_of_id(target_id)).ok() else {
            return answer(velocity, 0.0);
        };
        let rows = &guard.rows;
        let target_velocity = if rows.rigid[j] {
            rows.velocities[j]
        } else {
            Vector3::ZERO
        };
        let v = wk::steer(
            position,
            velocity,
            rows.positions[j],
            target_velocity,
            nav_gain,
            max_turn_rate,
            delta,
        );
        answer(v, 1.0)
    }

    // --- the kernels' maths alone, for the differential tests ---------------------------------------------------------

    /// `InterceptMath.solve`'s aim direction in x, y and z and 1 in w when a meeting exists (0 otherwise).
    #[func]
    fn solve_aim(
        shooter_pos: Vector3,
        shooter_vel: Vector3,
        target_pos: Vector3,
        target_vel: Vector3,
        bolt_speed: f64,
        max_time: f64,
    ) -> Vector4 {
        let (aim, ok) = wk::solve(
            shooter_pos,
            shooter_vel,
            target_pos,
            target_vel,
            bolt_speed,
            max_time,
        );
        Vector4::new(aim.x, aim.y, aim.z, if ok { 1.0 } else { 0.0 })
    }

    /// `TurretStandin.turned_toward`.
    #[func]
    fn turned_toward(from: Vector3, wanted: Vector3, max_angle: f64) -> Vector3 {
        wk::turned_toward(from, wanted, max_angle)
    }

    /// `Vector3.angle_to`, as the kernels compute it.
    #[func]
    fn angle_to(a: Vector3, b: Vector3) -> f64 {
        f64::from(wk::angle_to(a, b))
    }

    /// `MissileStandin.steer`.
    #[func]
    fn steer(
        position: Vector3,
        velocity: Vector3,
        target_position: Vector3,
        target_velocity: Vector3,
        nav_gain: f64,
        max_turn_rate: f64,
        delta: f64,
    ) -> Vector3 {
        wk::steer(
            position,
            velocity,
            target_position,
            target_velocity,
            nav_gain,
            max_turn_rate,
            delta,
        )
    }
}

// A capital's strike target as `StandinDirector._strike_target` holds it: looked up again when stale, then its place when
// it is still a row within a missile's reach of the capital (row `r`), else none.
fn strike(
    core: &ScsSimCore,
    capitals: &mut Capitals,
    c: usize,
    r: usize,
    tick: i64,
    hostile: &[bool],
) -> Option<Vector3> {
    let rows = &core.rows;
    let stale = !capitals.strike_known[c]
        || tick.saturating_sub(capitals.strike_tick[c]) >= wk::STRIKE_RETARGET_TICKS;
    if stale {
        capitals.strike_target[c] =
            wk::strike_target(rows, &core.hull_rows, hostile, rows.positions[r]);
        capitals.strike_tick[c] = tick;
        capitals.strike_known[c] = true;
    }
    let id = capitals.strike_target[c];
    if id == 0 {
        return None;
    }
    let j = usize::try_from(core.row_of_id(id)).ok()?;
    let target_at = rows.positions[j];
    wk::in_strike_reach(target_at, rows.positions[r]).then_some(target_at)
}

// A far capital's tier row (M4-T22), or none for a capital in Jolt (or gone).
fn tier_row_of(core: &ScsSimCore, body: i64) -> Option<usize> {
    if body == 0 {
        return None;
    }
    usize::try_from(core.row_of_id(body))
        .ok()
        .filter(|&i| core.rows.flags[i] & FLAG_TIER != 0)
}

// The distance between two places, as the stand-ins measure it.
fn wk_distance(a: Vector3, b: Vector3) -> f32 {
    crate::v3::distance(a, b)
}

// Faction `f`'s row of the hostility table (`n` factions), or none for a faction the table does not cover yet.
fn table_row(hostile: &[bool], n: usize, f: u32) -> &[bool] {
    let f = f as usize;
    if f < n {
        &hostile[f * n..(f + 1) * n]
    } else {
        &[]
    }
}
