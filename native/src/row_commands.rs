// The native pilots' commands as core rows (M4-T33, docs/architecture.md 17.13): the brains' batch writes each native
// pilot's last flight command and trigger here, by body, and the flight step flies it the same tick. A command stays until
// the next think replaces it, so a held or declined think flies the one the row has. GDScript releases a ship's command
// when anything else commands it.
use std::collections::{HashMap, HashSet};
use std::hash::{BuildHasherDefault, Hasher};

use godot::prelude::*;

use crate::brain_step::Snapshot;
use crate::kernels::flight::Cmd;
use crate::sim_core::ScsSimCore;

/// The events a written command raises for the drivers: the ship starts flying from its row (its driver hands the ship
/// and the cannon their commands once), or its trigger changed (the driver tells the cannon).
pub const EVENT_ENTER: u8 = 1;
pub const EVENT_FIRE: u8 = 2;
/// Raised by the batch, not here: the brain wants another target than the ship has selected; and its pilot is read at
/// once (a rammer or a route follower in control, or the ram's commitment changed: what the game reads every tick).
pub const EVENT_SELECT: u8 = 4;
pub const EVENT_SETTLE: u8 = 8;
/// The flight numbers of a think's output a command keeps: the four levels (main left, main right, retro left, retro
/// right), strafe x and y, rot x, y and z, and the brake.
pub const CMD_LEN: usize = 10;

/// The commands by body id (fix round 2): a plain integer hash, since the tier reads the map for every row every tick and
/// the default hasher made that a fifth of a tier row's cost. Nothing iterates it in an order that matters.
pub type CommandMap = HashMap<i64, RowCommand, BuildHasherDefault<IdHasher>>;

/// Any table or set keyed by an instance id or a row handle (M5-T35): the same plain hash. Nothing may depend on the
/// order one is walked in.
pub type IdMap<V> = HashMap<i64, V, BuildHasherDefault<IdHasher>>;
pub type IdSet = HashSet<i64, BuildHasherDefault<IdHasher>>;

/// Hashes a body id (Godot's instance ids differ in their low bits) with one multiply and a fold.
#[derive(Default)]
pub struct IdHasher(u64);

impl Hasher for IdHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0.rotate_left(8) ^ u64::from(b)).wrapping_mul(0x9e37_79b9_7f4a_7c15);
        }
    }

    fn write_i64(&mut self, v: i64) {
        let x = (v as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15);
        self.0 = x ^ (x >> 29);
    }
}

/// One ship's last native command, and what the tier's to-hit roll reads with it (M4-T22): the target its pilot wants
/// (a marker id; 0 or less for none), the pilot's aim error in radians and its fire gate (the miss distance, m, and the
/// widest angle, rad).
#[derive(Clone, Copy, Default)]
pub struct RowCommand {
    pub cmd: [f64; CMD_LEN],
    pub fire: bool,
    pub ram: bool,
    pub target: i64,
    pub aim_error_rad: f64,
    pub miss_m: f64,
    /// The widest angle off the lead its fire gate allows, rad (the gate also holds the nose within `miss_m` of it).
    pub cone_rad: f64,
    /// Grows with every think written, so the tier flies a new command at once rather than at its next beat.
    pub seq: u32,
}

impl RowCommand {
    /// Writes the command into the flight kernel's input, as `FlightBatch.pack_command` packs a `FlightCommand`.
    pub fn apply_to(&self, cmd: &mut Cmd) {
        let c = &self.cmd;
        cmd.levels = [c[1], c[0], c[3], c[2]];
        cmd.strafe = Vector3::new(c[4] as f32, c[5] as f32, 0.0);
        cmd.rot = Vector3::new(c[6] as f32, c[7] as f32, c[8] as f32);
        cmd.brake = c[9] != 0.0;
    }
}

impl ScsSimCore {
    /// The command `body_id` flies from its row, if it flies one.
    pub fn live_command(&self, body_id: i64) -> Option<&RowCommand> {
        self.row_commands.get(&body_id)
    }

    /// Fills a job's snapshot from the tables as they stand (M4-T24): the rows, the bolts, the rows by body, the bodies
    /// touched since the sync, the commands and the version. With `own_releases` the releases counted from now on are
    /// this job's to filter at its handover (a scheduled job); a single think launched while a scheduled job is out
    /// leaves that job's list alone (fix round 2).
    pub(crate) fn snapshot_into(&mut self, snapshot: &mut Snapshot, own_releases: bool) {
        snapshot.rows.clone_from(&self.rows);
        snapshot.bolts.clone_from(&self.bolts);
        snapshot.body_rows.clone_from(self.body_rows());
        snapshot.touched.clone_from(self.touched_set());
        snapshot.commands.clone_from(&self.row_commands);
        snapshot.rows_version = self.rows_version_now();
        self.turret_snapshot_into(&mut snapshot.turrets);
        if own_releases {
            self.released.clear();
        }
    }

    /// Takes a joined job's commands as the rows' (M4-T24): the map swapped in whole and, when the releases are this
    /// job's (`filter`), less the bodies something else commanded since its launch (`release_command`), which fly their
    /// own command until their next think.
    pub(crate) fn take_commands(&mut self, commands: &mut CommandMap, filter: bool) {
        std::mem::swap(&mut self.row_commands, commands);
        if filter {
            for body in self.released.drain(..) {
                self.row_commands.remove(&body);
            }
        }
    }
}

#[godot_api(secondary)]
impl ScsSimCore {
    /// Stops `body_id` flying the command in its row: something else commands the ship now.
    #[func]
    fn release_command(&mut self, body_id: i64) {
        self.row_commands.remove(&body_id);
        self.released.push(body_id);
    }

    /// The command `body_id` flies from its row: 1, the flight numbers (`CMD_LEN`) and the trigger; empty when none.
    #[func]
    fn row_command(&self, body_id: i64) -> PackedFloat64Array {
        let mut out = PackedFloat64Array::new();
        if let Some(rc) = self.row_commands.get(&body_id) {
            out.push(1.0);
            for v in rc.cmd {
                out.push(v);
            }
            out.push(f64::from(u8::from(rc.fire)));
        }
        out
    }

    /// How many ships fly a command from their rows.
    #[func]
    fn live_commands(&self) -> i64 {
        self.row_commands.len() as i64
    }

    /// A hash of every row's command in row order (none, or the numbers and the trigger), for comparing runs.
    #[func]
    fn commands_digest(&self) -> i64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut word = |w: u64| {
            for b in w.to_le_bytes() {
                h ^= u64::from(b);
                h = h.wrapping_mul(0x0000_0100_0000_01b3);
            }
        };
        for i in 0..self.rows.node_count {
            match self.row_commands.get(&self.rows.body_ids[i]) {
                Some(rc) => {
                    word(1);
                    for v in rc.cmd {
                        word(v.to_bits());
                    }
                    word(u64::from(rc.fire));
                }
                None => word(0),
            }
        }
        h as i64
    }
}
