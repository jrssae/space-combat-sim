// The native pilots' commands as core rows (M4-T33, docs/architecture.md 17.13): the brains' batch writes each native
// pilot's last flight command and trigger here, by body, and the flight step flies it the same tick. A command stays until
// the next think replaces it, so a held or declined think flies the one the row has. GDScript releases a ship's command
// when anything else commands it.
use godot::prelude::*;

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

/// One ship's last native command.
#[derive(Clone, Copy, Default)]
pub struct RowCommand {
    pub cmd: [f64; CMD_LEN],
    pub fire: bool,
    pub ram: bool,
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
    /// Keeps a native think's command for `body_id` (`out` is the think's output, flight numbers then the trigger) and
    /// returns the events it raises.
    pub fn write_command(&mut self, body_id: i64, out: &[f64]) -> u8 {
        let fire = out[CMD_LEN] != 0.0;
        let mut events = 0;
        match self.row_commands.get_mut(&body_id) {
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
                self.row_commands.insert(body_id, made);
            }
        }
        events
    }

    /// Notes whether `body_id`'s pilot is committed to a ram (after `write_command`); true when that changed.
    pub fn note_ram(&mut self, body_id: i64, committed: bool) -> bool {
        self.row_commands
            .get_mut(&body_id)
            .is_some_and(|rc| std::mem::replace(&mut rc.ram, committed) != committed)
    }

    /// The command `body_id` flies from its row, if it flies one.
    pub fn live_command(&self, body_id: i64) -> Option<&RowCommand> {
        self.row_commands.get(&body_id)
    }
}

#[godot_api(secondary)]
impl ScsSimCore {
    /// Stops `body_id` flying the command in its row: something else commands the ship now.
    #[func]
    fn release_command(&mut self, body_id: i64) {
        self.row_commands.remove(&body_id);
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
