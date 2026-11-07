// The bolts' read at the core's two sync points, cheaper (M4-T34, docs/architecture.md 17.13): the same rows as
// `ScsSimCore`'s own bolt read, which stays the reference behind `perf_native_bolt_sync`.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::collections::HashMap;
use std::collections::hash_map::Entry;
use std::hash::{BuildHasherDefault, Hasher};

use godot::classes::{Node, Node3D};
use godot::prelude::*;

use crate::rows::LOOK_NONE;
use crate::sim_core::{KIND_BOLT, ScsSimCore, color_of, kind_of};

// Instance ids hash by one multiply: the default hasher costs more than the read it guards.
#[derive(Default)]
struct IdHasher(u64);

impl Hasher for IdHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0.rotate_left(8) ^ u64::from(b)).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        }
    }

    fn write_i64(&mut self, id: i64) {
        let h = (id as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        self.0 = h ^ (h >> 29);
    }
}

type IdMap<V> = HashMap<i64, V, BuildHasherDefault<IdHasher>>;

// The script properties read, made once.
struct Names {
    velocity: StringName,
    last_step: StringName,
    faction: StringName,
    shooter_id: StringName,
    kind: StringName,
    hit_radius_m: StringName,
    damage: StringName,
    color: StringName,
}

impl Names {
    fn new() -> Self {
        Self {
            velocity: StringName::from("velocity"),
            last_step: StringName::from("last_step"),
            faction: StringName::from("faction"),
            shooter_id: StringName::from("shooter_id"),
            kind: StringName::from("kind"),
            hit_radius_m: StringName::from("hit_radius_m"),
            damage: StringName::from("damage"),
            color: StringName::from("color"),
        }
    }
}

// A bolt in flight, as the core keeps one: what is read once, when it is first seen, and the read that last saw it.
struct Bolt {
    node: Gd<Node3D>,
    faction_ix: u32,
    shooter: i64,
    kind: u8,
    radius: f64,
    velocity: Vector3,
    plain: bool,
    first_tick: i64,
    seen: u64,
    damage: f64,
    color: [f32; 4],
}

/// Reads the live bolts into the core's bolt table exactly as `ScsSimCore` does at its sync points (the position always,
/// the velocity for the first sync, the last step for the hit resolver's), for less: a bolt already known is found by the
/// instance id in its array slot instead of being made into an object handle, the group's nodes are not asked whether they
/// are in the tree (a group holds only nodes that are), and the known bolts sit in a cheaper map. `SimCore` calls the core's
/// own sync with no bolts and then this. Engine calls are counted per tick as the core counts them.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsBoltSync {
    base: Base<RefCounted>,
    names: Option<Names>,
    known: IdMap<Bolt>,
    reads_done: u64,
    reads: i64,
    last_reads: i64,
}

#[godot_api]
impl ScsBoltSync {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Fills `core`'s bolt table from `projectiles` (the group as it is now, in its order): ids, positions, the velocity
    /// column when `velocity` (else zeros), the last step when `last_step` (else zeros), factions, shooters, kinds and radii.
    /// `tick` is the core's tick (its last `sync_in`). Returns the bolt count.
    #[func]
    fn read(
        &mut self,
        mut core: Gd<ScsSimCore>,
        projectiles: Array<Gd<Node>>,
        tick: i64,
        delta: f64,
        velocity: bool,
        last_step: bool,
    ) -> i64 {
        let names = self.names.get_or_insert_with(Names::new);
        self.reads_done += 1;
        let pass = self.reads_done;
        let mut core = core.bind_mut();
        let mut bolts = std::mem::take(&mut core.bolts);
        bolts.truncate_to_owned();
        let slots = projectiles.upcast_any_array();
        for i in 0..slots.len() {
            let Some(slot) = slots.get(i) else {
                continue;
            };
            let Some(id) = slot.object_id_unchecked().map(|id| id.to_i64()) else {
                continue;
            };
            self.reads += 1;
            let bolt = match self.known.entry(id) {
                Entry::Occupied(found) => {
                    let bolt = found.into_mut();
                    if bolt.node.is_queued_for_deletion() {
                        continue;
                    }
                    bolt
                }
                Entry::Vacant(slot_entry) => {
                    let Ok(node) = slot.try_to::<Gd<Node>>() else {
                        continue;
                    };
                    if node.is_queued_for_deletion() {
                        continue;
                    }
                    let Ok(node3d) = node.clone().try_cast::<Node3D>() else {
                        continue;
                    };
                    self.reads += 6;
                    let faction = node
                        .get(&names.faction)
                        .try_to::<StringName>()
                        .unwrap_or_default();
                    let shooter = node.get(&names.shooter_id).try_to::<i64>().unwrap_or(0);
                    let kind = kind_of(&node.get(&names.kind));
                    let radius = node.get(&names.hit_radius_m).try_to::<f64>().unwrap_or(0.0);
                    let launch_velocity = node
                        .get(&names.velocity)
                        .try_to::<Vector3>()
                        .unwrap_or(Vector3::ZERO);
                    let damage = node.get(&names.damage).try_to::<f64>().unwrap_or(0.0);
                    let color = color_of(&node.get(&names.color));
                    let bolt = Bolt {
                        node: node3d,
                        faction_ix: core.faction_index(faction),
                        shooter,
                        kind,
                        radius,
                        velocity: launch_velocity,
                        plain: kind == KIND_BOLT,
                        first_tick: tick,
                        seen: pass,
                        damage,
                        color,
                    };
                    slot_entry.insert(bolt)
                }
            };
            bolt.seen = pass;
            self.reads += 1;
            bolts.ids.push(id);
            bolts.positions.push(bolt.node.get_global_position());
            let v = if bolt.plain {
                bolt.velocity
            } else if velocity || last_step {
                self.reads += 1;
                bolt.node
                    .get(&names.velocity)
                    .try_to::<Vector3>()
                    .unwrap_or(Vector3::ZERO)
            } else {
                Vector3::ZERO
            };
            bolts
                .velocities
                .push(if velocity { v } else { Vector3::ZERO });
            bolts.last_steps.push(if !last_step {
                Vector3::ZERO
            } else if bolt.plain && bolt.first_tick < tick {
                // `Projectile._physics_process`: `last_step = velocity * delta`, the float rounded to 32 bits first.
                let dt = delta as f32;
                Vector3::new(v.x * dt, v.y * dt, v.z * dt)
            } else {
                self.reads += 1;
                bolt.node
                    .get(&names.last_step)
                    .try_to::<Vector3>()
                    .unwrap_or(Vector3::ZERO)
            });
            bolts.faction_ix.push(bolt.faction_ix);
            bolts.shooters.push(bolt.shooter);
            bolts.kinds.push(bolt.kind);
            bolts.radii.push(bolt.radius);
            bolts.damage.push(bolt.damage);
            bolts.colors.push(bolt.color);
            bolts.looks.push(LOOK_NONE);
            bolts.expires_at.push(f64::INFINITY);
            bolts.launched.push(bolt.first_tick);
            bolts.spent.push(false);
            bolts.draw_slots.push(-1);
        }
        self.known.retain(|_, bolt| bolt.seen == pass);
        let count = bolts.ids.len() as i64;
        core.bolts = bolts;
        count
    }

    /// Bolts known now (seen by the last read).
    #[func]
    fn known_count(&self) -> i64 {
        self.known.len() as i64
    }

    /// Engine calls so far in the open tick.
    #[func]
    fn reads_open(&self) -> i64 {
        self.reads
    }

    /// Closes the tick's engine-call count (with the core's `sync_out`).
    #[func]
    fn close_tick(&mut self) {
        self.last_reads = self.reads;
        self.reads = 0;
    }

    /// Engine calls of the last closed tick.
    #[func]
    fn last_reads(&self) -> i64 {
        self.last_reads
    }
}
