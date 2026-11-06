// The AI step as a job (M4-T24, docs/architecture.md 17.13): one tick of the brains' batch over a snapshot of the core's
// rows, run on the main thread or on the step's worker thread. Engine-free by construction (test_sim_core reads this
// file): the job owns everything it touches (the brains, the hosted drivers' state, the rows' copy, the commands' copy)
// and hands it all back when it is done, so nothing here can reach the engine or race the main thread.
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::thread::ThreadId;
use std::time::Instant;

use godot::builtin::Vector3;

use crate::brain_behaviours::{self, Brain, Field, Inputs, Scratch};
use crate::kernels::contact::{self, Grid, Query, Work as QueryWork};
use crate::row_commands::RowCommand;
use crate::row_commands::{CMD_LEN, EVENT_ENTER, EVENT_FIRE, EVENT_SELECT, EVENT_SETTLE};
use crate::rows::{Bolts, FLAG_HULK, FLAG_TIER, Rows};
use crate::threads::{Pass, Runner};
use crate::v3::dist_sq;

/// Where a think's output holds the wanted target (two halves), the behaviour in control and the contacts it saw.
pub const OUT_TARGET: usize = 11;
pub const OUT_CURRENT: usize = 20;
pub const OUT_CONTACTS: usize = 23;
pub const OUT_RAW: usize = 24;
pub const OUT_WEIGHTED: usize = OUT_RAW + brain_behaviours::KINDS;
pub const OUT_MIRROR: usize = OUT_WEIGHTED + brain_behaviours::KINDS;
pub const OUT_RAM: usize = OUT_MIRROR + brain_behaviours::MIRROR;
pub const OUT_LEN: usize = OUT_RAM + 1;
/// A batch think's output per ship (M4-T18): 1 when the host thought it (0: declined, the rest zeros), then `OUT_LEN`.
pub const BATCH_OUT: usize = OUT_LEN + 1;
/// `events`' head: thinks near the player, thinks far, thinks declined, the most contacts a think saw, the hosted
/// drivers that held this tick (M4-T35), the hosted drivers left alone as low-attention tier rows (M4-T21); then a pair
/// (the ship's place in the batch, its events) for every ship whose driver has something to do.
pub const EVENTS_HEAD: usize = 6;
/// `set_fault`'s injected bug for the determinism test: a think adds to its main thrust what the worker's previous think
/// left behind, so it reads another row's output.
pub const FAULT_CARRY: i64 = 1;
/// `set_fault`'s injected panic: every think of a batch panics (without the panic hook's report).
pub const FAULT_PANIC: i64 = 2;
/// `set_fault`'s injected slowness (M4-T24): the job sleeps this long before it thinks, so a deadline is missed.
pub const FAULT_SLOW: i64 = 3;
pub const FAULT_SLOW_MS: u64 = 40;
/// `set_fault`'s injected panic after the pass (fix round 2): the job's commands and events are written, then it panics,
/// so the handover must come with no events for an empty output.
pub const FAULT_PANIC_JOB: i64 = 4;

// What one worker thread fills for the thinks it runs: the query scratch, the picked lists, the keeps, and what the
// injected fault carries from one think to the next.
#[derive(Default)]
pub struct Worker {
    pub query: Query,
    pub scratch: Scratch,
    pub keep: Vec<i64>,
    pub carry: f64,
}

// One ship of a batch think: its brain (taken from the slot for the pass), its inputs and its packed output.
#[derive(Default)]
pub struct Item {
    pub slot: usize,
    pub brain: Option<Brain>,
    pub own_row: i64,
    pub relations: (usize, usize),
    pub selected_id: i64,
    pub last_attacker_id: i64,
    pub dt: f64,
    pub hull_fraction: f64,
    pub last_hit_s: f64,
    pub last_bolt_hit_s: f64,
    pub out: Vec<f64>,
    pub ok: bool,
    pub near: bool,
    /// A low-attention tier row's think (M4-T22): its command goes to the tier, its driver has nothing to do.
    pub tier: bool,
}

/// A driver the host steps (M4-T35): the think rate's state the driver kept, its latest hits, and its last think.
pub struct Hosted {
    pub slot: usize,
    pub body_id: i64,
    pub ordinal: i64,
    pub steps: i64,
    pub since_think_s: f64,
    pub woken: bool,
    pub attacker_id: i64,
    pub hit_s: f64,
    pub bolt_hit_s: f64,
    pub live: bool,
    /// Its ship flies as a low-attention tier row (M4-T22): the node is parked, the host thinks at the tier's brain rate.
    pub tiered: bool,
    pub near: bool,
    pub thinks: i64,
    pub dt: f64,
    pub out: Vec<f64>,
    // The target of the last think that attacked (the context's `attack_target_id`, which every think's mirror kept).
    pub attack_target: i64,
}

/// What the drivers' step reads once a tick (M4-T35): the tick, the player and the think rate's settings.
#[derive(Default)]
pub struct DriverFrame {
    pub delta: f64,
    pub player_live: bool,
    pub player_at: Vector3,
    pub rate_on: bool,
    pub near_sq: f64,
    pub period: i64,
    /// Ticks between a tier row's thinks (`tier_brain_hz`, M4-T22).
    pub tier_period: i64,
}

// What every think of a batch shares, read-only.
struct Shared<'a> {
    rows: &'a Rows,
    bolts: &'a Bolts,
    grid: &'a Grid,
    field: &'a Field,
    relations: &'a [u8],
    now_s: f64,
    friendly_fire: bool,
    origin: [f64; 3],
    nearest_k: i64,
    static_k: i64,
    fault: i64,
}

/// The brains' state and the batch's scratch: everything a job needs, moved to the step's thread with the job and back
/// with its result, so the main thread never shares it with the worker.
#[derive(Default)]
pub struct Work {
    pub slots: Vec<Option<Brain>>,
    pub grid: Grid,
    pub grid_version: i64,
    pub field: Field,
    pub nearest_k: i64,
    pub static_k: i64,
    pub fault: i64,
    // The batch's per-thread scratch, its ships and its output (M4-T18), kept between ticks.
    pub workers: Vec<Mutex<Worker>>,
    pub items: Vec<Item>,
    pub batch_out: Vec<f64>,
    // The last batch's counts and events (M4-T33).
    pub events: Vec<i64>,
    // The drivers the host steps (M4-T35), the tick's frame, the relation matrix over the core's factions (a row per
    // faction, `stride` wide), the batch's relations with the matrix behind them, and the last job's hosted items' slots.
    pub hosted: Vec<Hosted>,
    pub frame: DriverFrame,
    pub matrix: Vec<u8>,
    pub stride: usize,
    pub rel_scratch: Vec<u8>,
    pub hosted_slots: Vec<i64>,
    // The last job's pass panicked: its thinks were declined and their brains kept (the main thread counts and warns).
    pub failed: bool,
}

/// The core's tables as a job's launch found them: the double buffer's back half, filled by `clone_from` into kept
/// allocations, read by the job while the main thread goes on writing the front.
#[derive(Default)]
pub struct Snapshot {
    pub rows: Rows,
    pub bolts: Bolts,
    pub body_rows: HashMap<i64, u32>,
    pub touched: HashSet<i64>,
    pub commands: HashMap<i64, RowCommand>,
    pub rows_version: i64,
}

impl Snapshot {
    /// The row a kernel may read for body `body_id`, or -1: none for a body touched since the sync (its row is stale).
    pub fn row_for_kernel(&self, body_id: i64) -> i64 {
        if self.touched.contains(&body_id) {
            return -1;
        }
        HashMap::get(&self.body_rows, &body_id).map_or(-1, |&r| i64::from(r))
    }
}

/// What a batch shares beyond its rows: the batch's size and relations, the clock and the frame, and which path it is.
pub struct Params {
    pub n: usize,
    pub rel: Vec<u8>,
    pub now_s: f64,
    pub friendly_fire: bool,
    pub origin: [f64; 3],
    pub rows_version: i64,
    pub from_rows: bool,
}

/// One tick's job: the brains' state, the rows it thinks over, the batch and the pool it may use.
pub struct Job {
    pub work: Box<Work>,
    pub snapshot: Snapshot,
    pub params: Params,
    pub runner: Runner,
}

/// What a job gives back: the state and the snapshot (its commands written), the batch's output, how long it ran and
/// on which thread.
pub struct Done {
    pub work: Box<Work>,
    pub snapshot: Snapshot,
    pub out: Vec<f64>,
    pub run_us: i64,
    pub thread: ThreadId,
    pub from_rows: bool,
}

/// Runs one job to its end: the pass across the runner's threads, then (on the rows path) the commands into the
/// snapshot's copy and the hosted drivers' clocks. The same function on every path, so `inline`, `delayed` and
/// `threaded` give the same bits from the same snapshot.
pub fn run(job: Job) -> Done {
    let started = Instant::now();
    let Job {
        mut work,
        mut snapshot,
        params,
        runner,
    } = job;
    let from_rows = params.from_rows;
    // A panic anywhere in the job (not only in the pass, which `run_batch` catches itself) must not lose the brains: the
    // state comes back flagged, every brain taken into an item goes back to its slot, and the tick is held.
    let out = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        run_body(&mut work, &mut snapshot, &params, &runner)
    })) {
        Ok(out) => out,
        Err(_) => {
            for item in work.items.iter_mut() {
                if let Some(brain) = item.brain.take()
                    && item.slot < work.slots.len()
                {
                    work.slots[item.slot] = Some(brain);
                }
            }
            // No output, so no events to index against it; the hosted items' slots go with them.
            work.events.truncate(EVENTS_HEAD);
            work.events.iter_mut().for_each(|e| *e = 0);
            work.hosted_slots.clear();
            work.failed = true;
            Vec::new()
        }
    };
    Done {
        work,
        snapshot,
        out,
        run_us: started.elapsed().as_micros() as i64,
        thread: std::thread::current().id(),
        from_rows,
    }
}

// The job itself: the pass, then (on the rows path) the commands and the hosted drivers' clocks; the batch's output.
fn run_body(
    work: &mut Work,
    snapshot: &mut Snapshot,
    params: &Params,
    runner: &Runner,
) -> Vec<f64> {
    if work.fault == FAULT_SLOW {
        std::thread::sleep(std::time::Duration::from_millis(FAULT_SLOW_MS));
    }
    // The relations every item indexes: the batch's rows, then (on the rows path) the matrix the hosted items use.
    let mut rel = std::mem::take(&mut work.rel_scratch);
    rel.clear();
    rel.extend_from_slice(&params.rel);
    let total = if params.from_rows {
        let total = queue_hosted(work, snapshot, params.n, params.rel.len());
        rel.extend_from_slice(&work.matrix);
        total
    } else {
        params.n
    };
    run_batch(work, snapshot, runner, total, &rel, params);
    work.rel_scratch = rel;
    if params.from_rows {
        write_commands(work, snapshot, total);
        settle_hosted(work, params.n, total);
    }
    if work.fault == FAULT_PANIC_JOB {
        std::panic::resume_unwind(Box::new("the injected panic after the pass"));
    }
    std::mem::take(&mut work.batch_out)
}

// Thinks the batch's first `n` items (inputs filled, brains taken from their slots) across the runner's threads and
// packs their outputs in order; with `from_rows` each ship's hull and selection are read from its own row first.
fn run_batch(work: &mut Work, snap: &Snapshot, runner: &Runner, n: usize, rel: &[u8], p: &Params) {
    refresh_grid(work, snap);
    for item in &mut work.items[..n] {
        item.own_row = match &item.brain {
            None => -1,
            Some(b) => snap.row_for_kernel(b.ship.own_body_id),
        };
        if let (true, Ok(r)) = (p.from_rows, usize::try_from(item.own_row)) {
            // What the driver read from the ship's hull and targeting, as the sync stamped them (-1: none).
            let hull = snap.rows.hull_fraction[r];
            item.hull_fraction = if hull < 0.0 { 1.0 } else { hull };
            item.selected_id = snap.rows.target_ids[r].max(0);
        }
    }
    while work.workers.len() < runner.count().max(1) {
        work.workers.push(Mutex::new(Worker::default()));
    }
    let shared = Shared {
        rows: &snap.rows,
        bolts: &snap.bolts,
        grid: &work.grid,
        field: &work.field,
        relations: rel,
        now_s: p.now_s,
        friendly_fire: p.friendly_fire,
        origin: p.origin,
        nearest_k: work.nearest_k,
        static_k: work.static_k,
        fault: work.fault,
    };
    // The rows moved between the drivers' scan and the launch (a resync or a rebase): every think is declined and each
    // ship holds its last command, as T17's per-ship check did.
    let moved = snap.rows_version != p.rows_version;
    let items = &mut work.items[..n];
    let workers = &work.workers;
    let passed = moved
        || std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            runner.run(Pass::Brains, items, workers, |item, worker| {
                think_item(&shared, item, worker);
            });
        }))
        .is_ok();
    if moved || !passed {
        for item in &mut work.items[..n] {
            item.ok = false;
        }
    }
    work.failed = !passed;
    work.batch_out.clear();
    work.batch_out.resize(n * BATCH_OUT, 0.0);
    for k in 0..n {
        let item = &mut work.items[k];
        if let Some(brain) = item.brain.take() {
            work.slots[item.slot] = Some(brain);
        }
        if item.ok {
            let at = k * BATCH_OUT;
            work.batch_out[at] = 1.0;
            work.batch_out[at + 1..at + BATCH_OUT].copy_from_slice(&item.out);
        }
    }
}

// One ship's think in a batch: its brain over the shared rows with the worker's scratch, its output packed into its item.
fn think_item(shared: &Shared, item: &mut Item, worker: &mut Worker) {
    item.ok = false;
    let Some(brain) = item.brain.as_mut() else {
        return;
    };
    let Ok(own_row) = usize::try_from(item.own_row) else {
        return;
    };
    if shared.fault == FAULT_PANIC {
        std::panic::resume_unwind(Box::new("the injected panic"));
    }
    let inputs = Inputs {
        relations: &shared.relations[item.relations.0..item.relations.1],
        own_body_id: brain.ship.own_body_id,
        now_s: shared.now_s,
        dt: item.dt,
        hull_fraction: item.hull_fraction,
        self_id: brain.ship.self_id,
        selected_id: item.selected_id,
        last_hit_s: item.last_hit_s,
        last_bolt_hit_s: item.last_bolt_hit_s,
        last_attacker_id: item.last_attacker_id,
        friendly_fire: shared.friendly_fire,
        origin: shared.origin,
        nearest_k: shared.nearest_k,
        static_k: shared.static_k,
    };
    let Worker {
        query,
        scratch,
        keep,
        carry,
    } = worker;
    let mut result = brain.think(
        shared.rows,
        shared.bolts,
        &mut QueryWork {
            grid: shared.grid,
            query,
        },
        shared.field,
        own_row,
        scratch,
        keep,
        &inputs,
    );
    if shared.fault == FAULT_CARRY {
        result.flight.main_left = (result.flight.main_left * 0.5 + *carry).min(1.0);
        *carry = result.flight.main_left * 0.5;
    }
    pack_output(brain, &result, &mut item.out);
    item.ok = true;
}

/// The output of a think, `OUT_LEN` numbers.
pub fn pack_output(brain: &Brain, result: &brain_behaviours::Output, out: &mut Vec<f64>) {
    out.clear();
    out.resize(OUT_LEN, 0.0);
    let f = &result.flight;
    out[0] = f.main_left;
    out[1] = f.main_right;
    out[2] = f.retro_left;
    out[3] = f.retro_right;
    out[4] = f64::from(f.strafe_x);
    out[5] = f64::from(f.strafe_y);
    out[6] = f64::from(f.rot.x);
    out[7] = f64::from(f.rot.y);
    out[8] = f64::from(f.rot.z);
    out[9] = f64::from(u8::from(f.brake));
    out[10] = f64::from(u8::from(result.fire));
    let (hi, lo) = brain_behaviours::split_id(brain.wanted_target_id);
    out[11] = hi;
    out[12] = lo;
    out[13] = f64::from(u8::from(brain.avoiding));
    out[14] = f64::from(u8::from(brain.avoiding_urgent));
    out[15] = f64::from(u8::from(brain.has_desired_velocity));
    out[16] = f64::from(u8::from(brain.desired_all_axes));
    out[17] = f64::from(brain.desired_velocity.x);
    out[18] = f64::from(brain.desired_velocity.y);
    out[19] = f64::from(brain.desired_velocity.z);
    out[OUT_CURRENT] = f64::from(brain.current_kind());
    out[21] = brain.dwell_s;
    out[22] = brain.switches as f64;
    out[OUT_CONTACTS] = brain.contacts_seen as f64;
    for (i, kind) in brain.behaviours.iter().enumerate() {
        out[OUT_RAW + usize::from(*kind)] = brain.raw[i];
        out[OUT_WEIGHTED + usize::from(*kind)] = brain.weighted[i];
    }
    let mut mirror = [0.0; brain_behaviours::MIRROR];
    brain.mirror(&mut mirror);
    out[OUT_MIRROR..OUT_RAM].copy_from_slice(&mirror);
    out[OUT_RAM] = f64::from(u8::from(brain.ram_committed()));
}

// After a rows batch: every think's command into the snapshot's commands, the counts, and the events of the ships whose
// drivers have something to do (`ScsBrains.think_batch_rows`).
fn write_commands(work: &mut Work, snap: &mut Snapshot, n: usize) {
    for k in 0..n {
        let item = &work.items[k];
        if !item.ok {
            work.events[2] += 1;
            continue;
        }
        work.events[if item.near { 0 } else { 1 }] += 1;
        work.events[3] = work.events[3].max(item.out[OUT_CONTACTS] as i64);
        let Some(brain) = work.slots.get(item.slot).and_then(Option::as_ref) else {
            continue;
        };
        let body = brain.ship.own_body_id;
        let mut events = write_command(&mut snap.commands, body, &item.out[..=CMD_LEN]);
        let wanted = brain.wanted_target_id;
        note_aim(&mut snap.commands, body, brain);
        if item.tier {
            continue; // a tier row's driver is parked: the command is all the tier needs
        }
        let selected = usize::try_from(item.own_row).map_or(-1, |r| snap.rows.target_ids[r]);
        // The driver follows the brain's target: it clears a selection for none, selects anything else it wants, and
        // for the nearest hostile (0) runs its retarget every think, as T18's path does.
        if wanted == 0 || (wanted < 0 && selected > 0) || (wanted > 0 && wanted != selected) {
            events |= EVENT_SELECT;
        }
        // Ram (0) and follow path (7) in control are mirrored at once, as the facade does, and so is a new commitment.
        let kind = item.out[OUT_CURRENT] as i64;
        if note_ram(&mut snap.commands, body, item.out[OUT_RAM] != 0.0) || kind == 0 || kind == 7 {
            events |= EVENT_SETTLE;
        }
        if events != 0 {
            work.events.push(k as i64);
            work.events.push(i64::from(events));
        }
    }
}

/// Keeps a native think's command for `body_id` in `commands` (`out` is the think's output, flight numbers then the
/// trigger) and returns the events it raises: the ship starts flying from its row, or its trigger changed.
pub fn write_command(commands: &mut HashMap<i64, RowCommand>, body_id: i64, out: &[f64]) -> u8 {
    let fire = out[CMD_LEN] != 0.0;
    let mut events = 0;
    match commands.get_mut(&body_id) {
        Some(known) => {
            if known.fire != fire {
                events |= EVENT_FIRE;
            }
            known.fire = fire;
            known.cmd.copy_from_slice(&out[..CMD_LEN]);
        }
        None => {
            events |= EVENT_ENTER;
            let mut made = RowCommand {
                fire,
                ..RowCommand::default()
            };
            made.cmd.copy_from_slice(&out[..CMD_LEN]);
            commands.insert(body_id, made);
        }
    }
    events
}

/// Notes what the tier's to-hit roll reads with `body_id`'s command (M4-T22): the target its pilot wants, the pilot's aim
/// error (its skill) and the miss distance its fire gate allows.
pub fn note_aim(commands: &mut HashMap<i64, RowCommand>, body_id: i64, brain: &Brain) {
    if let Some(rc) = commands.get_mut(&body_id) {
        rc.target = brain.wanted_target_id;
        rc.aim_error_rad = brain.profile.aim_error_deg.to_radians();
        rc.miss_m = brain.profile.tactics.fire_miss_m;
        rc.cone_rad = brain.profile.tactics.fire_cone_deg.to_radians();
    }
}

/// Notes whether `body_id`'s pilot is committed to a ram (after `write_command`); true when that changed.
pub fn note_ram(commands: &mut HashMap<i64, RowCommand>, body_id: i64, committed: bool) -> bool {
    commands
        .get_mut(&body_id)
        .is_some_and(|rc| std::mem::replace(&mut rc.ram, committed) != committed)
}

// The hosted drivers' step (M4-T35), as `AiPilotDriver.step` decided it: a step and the time since the last think
// added, near the player or not, and the think rate's rule (`AiThinkRate.thinks`); a ship with no row this tick holds
// (as a declined think did). The thinking ones become items after the `n` queued; returns the item count.
fn queue_hosted(work: &mut Work, snap: &Snapshot, n: usize, rel_len: usize) -> usize {
    work.hosted_slots.clear();
    let mut total = n;
    let frame = &work.frame;
    for at in 0..work.hosted.len() {
        let h = &mut work.hosted[at];
        if !h.live && !h.tiered {
            continue;
        }
        let row = snap.row_for_kernel(h.body_id);
        h.steps += 1;
        h.since_think_s += frame.delta;
        let Ok(r) = usize::try_from(row) else {
            work.events[2] += 1; // no row this tick: held, as a declined think is
            continue;
        };
        let tier = snap.rows.flags[r] & FLAG_TIER != 0;
        if tier {
            // A low-attention tier row (M4-T22) thinks on its own beat; a hulk or a driver not handed to the tier never.
            let on_beat = (h.steps + h.ordinal).rem_euclid(frame.tier_period.max(1)) == 0;
            if !h.tiered || snap.rows.flags[r] & FLAG_HULK != 0 || !(on_beat || h.woken) {
                work.events[5] += 1;
                continue;
            }
            h.near = false;
        } else {
            h.near = frame.player_live
                && f64::from(dist_sq(snap.rows.positions[r], frame.player_at)) <= frame.near_sq;
            let on_beat = (h.steps + h.ordinal).rem_euclid(frame.period) == 0;
            if frame.rate_on && !h.woken && !h.near && !on_beat {
                work.events[4] += 1; // held: the ship flies its last command on
                continue;
            }
        }
        let Some(brain) = work.slots.get_mut(h.slot).and_then(Option::take) else {
            work.events[2] += 1;
            continue;
        };
        if work.items.len() <= total {
            work.items.resize_with(total + 1, Item::default);
        }
        let fix = snap.rows.faction_ix[r] as usize;
        let item = &mut work.items[total];
        item.slot = h.slot;
        item.brain = Some(brain);
        item.relations = (
            rel_len + fix * work.stride,
            rel_len + (fix + 1) * work.stride,
        );
        item.selected_id = 0;
        item.last_attacker_id = h.attacker_id;
        item.near = h.near;
        item.tier = tier;
        item.dt = h.since_think_s;
        item.hull_fraction = 1.0;
        item.last_hit_s = h.hit_s;
        item.last_bolt_hit_s = h.bolt_hit_s;
        item.ok = false;
        work.hosted_slots.push(h.slot as i64);
        total += 1;
    }
    total
}

// After the pass: a hosted driver whose think landed starts its clock again; a declined one keeps it, as the driver's
// settle put it back.
fn settle_hosted(work: &mut Work, n: usize, total: usize) {
    for k in n..total {
        let item = &work.items[k];
        let Some(at) = work.hosted.iter().position(|h| h.slot == item.slot) else {
            continue;
        };
        let h = &mut work.hosted[at];
        if item.ok {
            h.dt = h.since_think_s;
            h.since_think_s = 0.0;
            h.woken = false;
            h.thinks += 1;
            h.out.clear();
            h.out.extend_from_slice(&item.out);
            // Attack (3) in control: its target, as `AiPilot._apply_state` and `_retire_pending` keep it in the context.
            if item.out[OUT_CURRENT] as i64 == 3 {
                let hi = item.out[OUT_TARGET];
                if hi >= 0.0 {
                    h.attack_target = ((hi as i64) << 32) | (item.out[OUT_TARGET + 1] as i64);
                }
            }
        }
    }
}

/// Rebuilds the contact grid and the tick's field when the rows changed under them.
pub fn refresh_grid(work: &mut Work, snap: &Snapshot) {
    if snap.rows_version == work.grid_version {
        return;
    }
    work.grid_version = snap.rows_version;
    work.grid.cells = contact::sorted_cells(&snap.rows.positions, work.grid.cell_m);
    work.grid.max_static_radius = (0..snap.rows.positions.len())
        .filter(|&i| snap.rows.is_static[i])
        .map(|i| snap.rows.radii[i].abs())
        .fold(0.0, f64::max);
    work.field.build(&snap.rows, &snap.bolts, work.grid.cell_m);
    work.field
        .index_names(&snap.rows, wanted_names(&work.slots));
}

/// The names the slots' brains look for (objectives and guarded ships), for the tick's name index.
pub fn wanted_names(slots: &[Option<Brain>]) -> impl Iterator<Item = &str> {
    slots
        .iter()
        .flatten()
        .flat_map(|b| [b.ctx.objective_key.as_str(), b.ctx.guard_key.as_str()])
}
