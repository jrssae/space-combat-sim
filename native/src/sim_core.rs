// The native simulation core (M4-T15, docs/architecture.md 17.13): one store of rows for every simulated entity, filled
// from the engine at the tick's sync points and read by every native kernel.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::collections::{HashMap, HashSet};

use godot::classes::{Node, Node3D, Object, PhysicsServer3D, RigidBody3D};
use godot::prelude::*;

use crate::threads::{self, Pass, Threads};

pub use crate::rows::{Bolts, FLAG_HULL, FLAG_HULL_ACTIVE, FLAG_LATE, FLAG_RIGID, Rows};

// The snapshot the scan takes of the rows, built here (it crosses the boundary).
trait RowsSnapshot {
    fn to_array(
        &self,
        names: &[GString],
        count: usize,
        node_count: usize,
        factions: &[StringName],
    ) -> VarArray;
}

// `BodyKind` (src/ai/body_kind.gd) in value order, then the projectile kinds the core adds (`SimCore.KIND_*`).
const KIND_NAMES: [&str; 9] = [
    "ship", "capital", "turret", "missile", "mine", "static", "prop", "bolt", "beam",
];
pub const KIND_SHIP: u8 = 0;
pub const KIND_MINE: u8 = 4;
pub const KIND_STATIC: u8 = 5;
pub const KIND_BOLT: u8 = 7;
pub const KIND_BEAM: u8 = 8;

// The script properties the core reads, as StringNames made once: a name built per read costs as much as the read.
struct Names {
    velocity: StringName,
    last_step: StringName,
    faction: StringName,
    shooter_id: StringName,
    kind: StringName,
    hit_radius_m: StringName,
    damage: StringName,
    color: StringName,
    bounding_radius: StringName,
    display_name: StringName,
    hull: StringName,
    destroyed: StringName,
    hp: StringName,
    max_hp: StringName,
    targeting: StringName,
    system: StringName,
    selected_id: StringName,
    broadcast_range_m: StringName,
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
            bounding_radius: StringName::from("bounding_radius"),
            display_name: StringName::from("display_name"),
            hull: StringName::from("hull"),
            destroyed: StringName::from("destroyed"),
            hp: StringName::from("hp"),
            max_hp: StringName::from("max_hp"),
            targeting: StringName::from("targeting"),
            system: StringName::from("system"),
            selected_id: StringName::from("_selected_id"),
            broadcast_range_m: StringName::from("broadcast_range_m"),
        }
    }
}

// What a body's components say about it, read when it turns active (or is touched), not every tick.
#[derive(Clone)]
struct Attrs {
    faction_ix: u32,
    name: GString,
    name_key: String,
    kind: u8,
    radius: f64,
    destroyed: bool,
    reach: f64,
    // The hull's health object and the ship's targeting system, read every tick for the brains' contacts (M4-T17); none
    // for a body without them.
    health: Option<Gd<Object>>,
    targeting: Option<Gd<Object>>,
    // The hull 0..1 and the selection as the events last gave them (M4-T35: `note_hull`, `note_selection`), read live when
    // the attributes are.
    hull_fraction: f64,
    target_id: i64,
}

// One `Targetable` (or, for a body without one, one `Damageable`) of the tree, with the body it marks.
struct Member {
    key: i64,
    body: Gd<Node3D>,
    body_id: i64,
    marker: Option<Gd<Node3D>>,
    hull: Option<Gd<Node>>,
    rigid: Option<Gd<RigidBody3D>>,
    attrs: Option<Attrs>,
    // The sync this member was last a row of, and how often it has turned active (its handle's generation).
    active_at: u64,
    generation: u32,
    // The hull's place in the `damageable` group: the order the resolvers walk hulls in.
    hull_rank: i64,
    // The member's place in `slot_of`, which outlives `set_members`.
    slot: u32,
    // The body's RID (invalid for a body with no rigid body) and whether it was active at the last check (M4-T35: with the
    // event columns on, checked again only when touched).
    rid: Rid,
    active: bool,
    active_known: bool,
}

// A bolt in flight: its node and what is read once, when it is first seen. A plain bolt's velocity never changes after
// its launch and its step each tick is `velocity * delta`, so only its position is read again; a missile steers and a
// beam lays its segment, so their motion is read every sync.
struct Bolt {
    node: Gd<Node3D>,
    faction_ix: u32,
    shooter: i64,
    kind: u8,
    radius: f64,
    velocity: Vector3,
    plain: bool,
    // The tick the core first saw it: on that tick its step is whatever the node holds (zero until its first
    // `_physics_process`, §15.3); from the next tick on a plain bolt's step is `velocity * delta`.
    first_tick: i64,
    // What a hit lands with (M4-T35): read once with the rest.
    damage: f64,
    color: [f32; 4],
}

// What one read of a body gives: its pose, motion and flags.
struct Read {
    position: Vector3,
    basis: Basis,
    velocity: Vector3,
    angular: Vector3,
    flags: u32,
    hull_fraction: f64,
    target_id: i64,
}

// A row with no node (T20's turrets, missiles and mines to come): what `add_row` keeps and `row` gives back.
struct DataRow {
    handle: i64,
    kind: u8,
    id: i64,
    faction: StringName,
    radius: f64,
    flags: i64,
    position: Vector3,
    velocity: Vector3,
    basis: Basis,
    angular: Vector3,
    command: Vec<f64>,
    state: Vec<f64>,
}

/// One store of rows for every simulated entity, filled once per tick from the engine (`sync_in`, then `sync_bolts` for
/// the bolts after they moved) and read by every native kernel, so no kernel loads a copy of its own or calls the
/// engine. The bodies are the registry's (M4-T09): known once (`set_members`), read through the nodes' own getters so
/// every value is the one GDScript reads, their faction, name, kind and radius read when they turn active or are touched.
/// A row has a handle that changes each time its body turns active, so a ship back from the pool is a new row to anyone
/// holding the old handle. `shift` moves the node and bolt rows by a rebase; the static rows come again from
/// `StaticRows` at the next sync. Engine calls are counted: the sync's grow with the rows, the kernels make none.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsSimCore {
    base: Base<RefCounted>,
    names: Option<Names>,
    markers: Vec<Member>,
    hulls: Vec<Member>,
    marker_at: HashMap<i64, usize>,
    // A member's slot by its key, kept across `set_members` with its generation.
    slot_of: HashMap<i64, (u32, u32)>,
    next_slot: u32,
    touched: HashSet<i64>,
    seen: HashSet<i64>,
    syncs: u64,
    attribute_reads: i64,
    static_ids: Vec<i64>,
    static_positions: Vec<Vector3>,
    static_radii: Vec<f64>,
    static_factions: Vec<u32>,
    static_kinds: Vec<u8>,
    bolt_known: HashMap<i64, Bolt>,
    /// Every faction the core has seen, in first-sight order; rows carry an index into it.
    pub factions: Vec<StringName>,
    /// The scan's rows and the bolts, as of the last sync point.
    pub rows: Rows,
    pub bolts: Bolts,
    /// Each row's display name, beside the rows (an engine string the worker threads must not share, M4-T18).
    pub row_names: Vec<GString>,
    /// The rows with an active hull, in the `damageable` group's order: what the sweep and the ram phase walk.
    pub hull_rows: Vec<u32>,
    row_of_id: HashMap<i64, u32>,
    row_of_handle: HashMap<i64, u32>,
    data: Vec<DataRow>,
    next_data_handle: i64,
    pub(crate) sync_reads: i64,
    fallback_reads: i64,
    last_calls: [i64; 2],
    pub(crate) tick: i64,
    bolt_tick: i64,
    open: bool,
    // Grows whenever the rows change under a scan taken from them: each sync, resync and shift (M4-T16).
    rows_version: i64,
    // Reads of the brains' columns that found no value where a body had the object (a renamed property): counted and
    // warned about once (M4-T17).
    column_read_failures: i64,
    // The worker threads the kernels' per-ship passes run on (M4-T18).
    threads: Threads,
    // The native pilots' last commands by body, written by the brains' batch and flown by the flight step (M4-T33).
    pub row_commands: HashMap<i64, crate::row_commands::RowCommand>,
    // The core owns its bolts (M4-T35): the owned rows stay across the sync points and the kernels step them; the ids it
    // hands out count down from -1, so no instance id is ever one.
    pub(crate) bolt_rows: bool,
    pub(crate) next_bolt_id: i64,
    // The core's state from events (M4-T35b): activity, hull and selection kept in the attributes and written to the rows
    // at the sync points; `body_direct` reads the rigid bodies from the physics server's direct state by RID.
    event_columns: bool,
    body_direct: bool,
    activity_dirty: bool,
    /// Each row's body RID (invalid for a body with none), beside the rows (M4-T35: the ram stage's contact read).
    pub row_rids: Vec<Rid>,
    /// The ships' accelerations from their own forces this tick, by body, as the flight step wrote them (M4-T35: the ram
    /// tracker's accel column; `force / mass` in 32 bits, as `Ship.applied_force() / ship.mass`).
    pub accels: HashMap<i64, Vector3>,
    // The AI targeting controllers whose selection check runs here (M4-T35): body id and sensor range; and every body's
    // selection as the events last gave it (or as its attributes read it).
    selection_watch: Vec<(i64, f64)>,
    latest_target: HashMap<i64, i64>,
}

#[godot_api]
impl ScsSimCore {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Takes the tree's markers and hulls, each list in group (tree) order. What was known of a body stays known.
    #[func]
    pub fn set_members(&mut self, targetables: Array<Gd<Node>>, damageables: Array<Gd<Node>>) {
        let mut known: HashMap<i64, (Option<Attrs>, u64)> = HashMap::new();
        for m in self.markers.drain(..).chain(self.hulls.drain(..)) {
            known.insert(m.key, (m.attrs, m.active_at));
        }
        self.marker_at.clear();
        // A body's hull is the first `Damageable` under it in group order, which is child order: what both the tree
        // gather's group lookup and `Damageable.of(body)` (the broadcast scan's) take.
        let mut first_hull: HashMap<i64, (Gd<Node>, i64)> = HashMap::new();
        for (rank, hull) in damageables.iter_shared().enumerate() {
            if let Some(parent) = hull.get_parent() {
                first_hull
                    .entry(parent.instance_id().to_i64())
                    .or_insert((hull, rank as i64));
            }
        }
        for node in targetables.iter_shared() {
            let Ok(marker) = node.try_cast::<Node3D>() else {
                continue;
            };
            let Some(body) = marker
                .get_parent()
                .and_then(|p| p.try_cast::<Node3D>().ok())
            else {
                continue;
            };
            let body_id = body.instance_id().to_i64();
            let key = marker.instance_id().to_i64();
            let (attrs, active_at) = known.remove(&key).unwrap_or((None, 0));
            let (slot, generation) = self.slot_for(key);
            let (hull, hull_rank) = first_hull
                .get(&body_id)
                .map_or((None, -1), |(h, r)| (Some(h.clone()), *r));
            self.marker_at.insert(key, self.markers.len());
            let rigid = body.clone().try_cast::<RigidBody3D>().ok();
            let rid = rigid.as_ref().map_or(Rid::Invalid, |r| r.get_rid());
            self.markers.push(Member {
                key,
                rigid,
                hull,
                body,
                body_id,
                marker: Some(marker),
                attrs,
                active_at,
                generation,
                hull_rank,
                slot,
                rid,
                active: false,
                active_known: false,
            });
        }
        for (rank, hull) in damageables.iter_shared().enumerate() {
            let Some(body) = hull.get_parent().and_then(|p| p.try_cast::<Node3D>().ok()) else {
                continue;
            };
            let key = hull.instance_id().to_i64();
            let (attrs, active_at) = known.remove(&key).unwrap_or((None, 0));
            let (slot, generation) = self.slot_for(key);
            let rigid = body.clone().try_cast::<RigidBody3D>().ok();
            let rid = rigid.as_ref().map_or(Rid::Invalid, |r| r.get_rid());
            self.hulls.push(Member {
                key,
                rigid,
                body_id: body.instance_id().to_i64(),
                body,
                marker: None,
                hull: Some(hull),
                attrs,
                active_at,
                generation,
                hull_rank: rank as i64,
                slot,
                rid,
                active: false,
                active_known: false,
            });
        }
    }

    /// Takes the node-less static rows (rocks by RID, mines): ids, positions, radii, factions and kinds, in order. Returns
    /// false, after logging why, when the arrays do not line up; the core then holds none.
    #[func]
    pub fn set_statics(
        &mut self,
        ids: PackedInt64Array,
        positions: PackedVector3Array,
        radii: PackedFloat64Array,
        factions: Array<StringName>,
        kinds: PackedByteArray,
    ) -> bool {
        let n = ids.len();
        if positions.len() != n || radii.len() != n || factions.len() != n || kinds.len() != n {
            godot_error!(
                "ScsSimCore.set_statics: array lengths differ (ids {n}, positions {}, radii {}, factions {}, kinds {}); \
                 the statics are dropped",
                positions.len(),
                radii.len(),
                factions.len(),
                kinds.len()
            );
            self.static_ids.clear();
            self.static_positions.clear();
            self.static_radii.clear();
            self.static_factions.clear();
            self.static_kinds.clear();
            return false;
        }
        self.static_ids = ids.as_slice().to_vec();
        self.static_positions = positions.as_slice().to_vec();
        self.static_radii = radii.as_slice().to_vec();
        self.static_factions = factions
            .iter_shared()
            .map(|f| self.faction_index(f))
            .collect();
        self.static_kinds = kinds.as_slice().to_vec();
        true
    }

    /// Marks a body whose faction, name, kind, radius, place or activity may have changed: it is read again at the next
    /// sync point, and a touched body that turned active after the tick's first sync gets its row at the next one.
    #[func]
    pub fn touch(&mut self, body_id: i64) {
        self.touched.insert(body_id);
    }

    /// Forgets every body's faction, name, kind and radius, so the next sync reads them all again.
    #[func]
    pub fn forget_attributes(&mut self) {
        for m in self.markers.iter_mut().chain(self.hulls.iter_mut()) {
            m.attrs = None;
        }
        self.activity_dirty = true;
    }

    /// How many times a body's attributes were read (the work count: once per activation, not per tick).
    #[func]
    pub fn attribute_reads(&self) -> i64 {
        self.attribute_reads
    }

    /// How many `sync_in` calls ran.
    #[func]
    pub fn syncs(&self) -> i64 {
        self.syncs as i64
    }

    /// The tick's first sync point: builds this tick's rows from the bodies and the bolts (`projectiles`, the group as it is
    /// now), the statics after the bodies. `tick` stamps the rows. Returns the body row count.
    #[func]
    pub fn sync_in(&mut self, projectiles: Array<Gd<Node>>, tick: i64, delta: f64) -> i64 {
        if self.open {
            self.close_tick();
        }
        // The owned bolts a hit spent last tick go now, as a spent node is gone by its next tick (M4-T35).
        crate::bolt_kernels::drop_spent(&mut self.bolts);
        self.open = true;
        self.tick = tick;
        self.syncs += 1;
        self.rows_version += 1;
        let now = self.syncs;
        let mut rows = std::mem::take(&mut self.rows);
        rows.clear();
        self.row_names.clear();
        self.row_rids.clear();
        self.seen.clear();
        let cached = self.event_columns && !self.activity_dirty;
        let mut markers = std::mem::take(&mut self.markers);
        for m in markers.iter_mut() {
            // With the event columns, a body's activity is checked again only when it was touched (hidden, shown,
            // destroyed) or first seen; the facade's events cover every change the pool and the resolvers make.
            if !cached || !m.active_known || self.touched.contains(&m.body_id) {
                m.active = marker_active(m, &mut self.sync_reads);
                m.active_known = true;
            }
            if !m.active {
                m.active_at = 0; // out of play: when it comes back it is a new row
                continue;
            }
            if !self.seen.insert(m.body_id) {
                continue;
            }
            self.fresh_attrs(m, now);
            self.push_member(&mut rows, m);
        }
        self.markers = markers;
        self.activity_dirty = false;
        let mut hulls = std::mem::take(&mut self.hulls);
        for m in hulls.iter_mut() {
            if self.seen.contains(&m.body_id) {
                continue;
            }
            let names = self.names.get_or_insert_with(Names::new);
            if !hull_only_active(m, names, &mut self.sync_reads) {
                m.active_at = 0;
                continue;
            }
            self.seen.insert(m.body_id);
            self.fresh_attrs(m, now);
            self.push_member(&mut rows, m);
        }
        self.hulls = hulls;
        rows.node_count = rows.body_ids.len();
        for s in 0..self.static_ids.len() {
            rows.body_ids.push(self.static_ids[s]);
            rows.ids.push(self.static_ids[s]);
            rows.faction_ix.push(self.static_factions[s]);
            rows.positions.push(self.static_positions[s]);
            rows.velocities.push(Vector3::ZERO);
            rows.bases.push(Basis::IDENTITY);
            rows.angular.push(Vector3::ZERO);
            rows.radii.push(self.static_radii[s]);
            rows.kinds.push(self.static_kinds[s]);
            rows.flags.push(0);
            self.row_names.push(GString::new());
            self.row_rids.push(Rid::Invalid);
            rows.hull_ids.push(0);
            rows.handles.push(0);
            rows.rigid.push(false);
            rows.is_static.push(is_static_kind(self.static_kinds[s]));
            rows.is_mine.push(self.static_kinds[s] == KIND_MINE);
            rows.hull_fraction.push(-1.0);
            rows.target_ids.push(-1);
            rows.reach.push(0.0);
            rows.name_keys.push(String::new());
        }
        self.rows = rows;
        self.touched.clear();
        self.index_rows();
        self.read_bolts(projectiles, delta, true, false);
        self.rows.node_count as i64
    }

    /// The tick's later sync point (the hit resolver's, after the bolts moved): reads the bolts again (their positions
    /// and last steps; the velocity column is left zero, the scan read it at the first sync), and the bodies that were touched since the
    /// first sync (a ship back from the pool gets its row now, a parked one loses its hull).
    #[func]
    pub fn sync_bolts(&mut self, projectiles: Array<Gd<Node>>, delta: f64) -> i64 {
        self.bolt_tick = self.tick;
        if !self.touched.is_empty() {
            self.resync_touched();
        }
        self.read_bolts(projectiles, delta, false, true)
    }

    // Reads the live bolts into the bolt table: the position always, the velocity for the scan's first sync and the last
    // step for the resolver's; a bolt seen for the first time gives its faction, shooter, kind and radius once. A spent
    // bolt is queued for deletion (`Projectile.spend`), so that one check covers it.
    fn read_bolts(
        &mut self,
        projectiles: Array<Gd<Node>>,
        delta: f64,
        velocity: bool,
        last_step: bool,
    ) -> i64 {
        if self.names.is_none() {
            self.names = Some(Names::new());
        }
        let mut bolts = std::mem::take(&mut self.bolts);
        bolts.truncate_to_owned();
        let mut live: HashSet<i64> = HashSet::new();
        for node in projectiles.iter_shared() {
            let id = node.instance_id().to_i64();
            self.sync_reads += 1;
            if !node.is_inside_tree() || node.is_queued_for_deletion() {
                continue;
            }
            live.insert(id);
            if !self.bolt_known.contains_key(&id) {
                let Ok(node3d) = node.clone().try_cast::<Node3D>() else {
                    continue;
                };
                self.sync_reads += 6;
                let names = self.names.as_ref().expect("made above");
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
                    faction_ix: self.faction_index(faction),
                    shooter,
                    kind,
                    radius,
                    velocity: launch_velocity,
                    plain: kind == KIND_BOLT,
                    first_tick: self.tick,
                    damage,
                    color,
                };
                self.bolt_known.insert(id, bolt);
            }
            let names = self.names.as_ref().expect("made above");
            let bolt = &self.bolt_known[&id];
            self.sync_reads += 1;
            bolts.ids.push(id);
            bolts.positions.push(bolt.node.get_global_position());
            let v = if bolt.plain {
                bolt.velocity
            } else if velocity || last_step {
                self.sync_reads += 1;
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
            } else if bolt.plain && bolt.first_tick < self.tick {
                // `Projectile._physics_process`: `last_step = velocity * delta`, the float rounded to 32 bits first. A
                // bolt first seen this tick may not have stepped yet, so its node says.
                let dt = delta as f32;
                Vector3::new(v.x * dt, v.y * dt, v.z * dt)
            } else {
                self.sync_reads += 1;
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
            bolts.looks.push(crate::rows::LOOK_NONE);
            bolts.expires_at.push(f64::INFINITY);
            bolts.launched.push(bolt.first_tick);
            bolts.spent.push(false);
        }
        self.bolt_known.retain(|id, _| live.contains(id));
        self.bolts = bolts;
        self.bolts.ids.len() as i64
    }

    /// Reads the bodies touched since the last sync point again (a hull destroyed by the hit resolver leaves the ram
    /// resolver's rows), without reading the bolts. Returns how many were touched.
    #[func]
    pub fn resync_touched_now(&mut self) -> i64 {
        let touched = self.touched.len() as i64;
        if touched > 0 {
            self.resync_touched();
        }
        touched
    }

    /// Bodies touched since the last sync point and not read again yet.
    #[func]
    fn touched_count(&self) -> i64 {
        self.touched.len() as i64
    }

    /// The tick's last point: closes the tick's engine-call count. The seam where later tasks write rows back.
    #[func]
    pub fn sync_out(&mut self) {
        self.close_tick();
    }

    /// Moves every node and bolt row by `offset`, as the World's rebase moved their nodes; the static rows are taken again
    /// from `StaticRows` at the next sync.
    #[func]
    pub fn shift(&mut self, offset: Vector3) {
        self.rows_version += 1;
        for i in 0..self.rows.positions.len() {
            if self.rows.handles[i] != 0 {
                self.rows.positions[i] = add(self.rows.positions[i], offset);
            }
        }
        for p in self.bolts.positions.iter_mut() {
            *p = add(*p, offset);
        }
    }

    /// Engine calls of the last closed tick: `[sync, fallbacks]`: the sync points' reads, which grow with the bodies and
    /// bolts, and the flight step's reads of the physics server for ships without a row. The kernels make none: they live
    /// in `kernels.rs`, which holds no engine type (`test_sim_core` reads the file).
    #[func]
    pub fn engine_calls(&self) -> PackedInt64Array {
        PackedInt64Array::from(&self.last_calls[..])
    }

    /// Engine calls so far in the open tick: `[sync, fallbacks]`.
    #[func]
    fn engine_calls_open(&self) -> PackedInt64Array {
        PackedInt64Array::from(&[self.sync_reads, self.fallback_reads][..])
    }

    /// Counts the flight step's fallback reads of the physics server (a ship without a row this tick).
    #[func]
    pub fn note_fallback_read(&mut self, calls: i64) {
        self.fallback_reads += calls;
    }

    /// A count that grows whenever the rows change (a sync, a resync of touched bodies, a rebase's shift), so a scan taken
    /// from them knows when its indices no longer name the same values (the pilot kernels, M4-T16).
    #[func]
    fn rows_version(&self) -> i64 {
        self.rows_version
    }

    /// Reads of the brains' columns (a hull's `hp` and `max_hp`, a targeting system's `_selected_id`) that found no value
    /// where the body had the object (M4-T17); 0 unless a property was renamed. The first one is also warned about.
    #[func]
    fn column_read_failures(&self) -> i64 {
        self.column_read_failures
    }

    /// Runs the per-ship passes on `count` threads from the next pass on (`perf_threads`, M4-T18): 0 or less means the
    /// machine's performance cores, 1 the calling thread alone. Returns the count in use.
    #[func]
    fn set_threads(&mut self, count: i64) -> i64 {
        let wanted = if count <= 0 {
            threads::performance_cores()
        } else {
            count as usize
        };
        self.threads.set_count(wanted) as i64
    }

    /// The threads the per-ship passes use.
    #[func]
    fn threads(&self) -> i64 {
        self.threads.count() as i64
    }

    /// The machine's performance cores, what `set_threads(0)` uses.
    #[func]
    fn performance_cores(&self) -> i64 {
        threads::performance_cores() as i64
    }

    /// Passes that ran in parallel since the core was made (a readout; a single-threaded core never adds to it).
    #[func]
    fn parallel_passes(&self) -> i64 {
        self.threads.parallel_passes()
    }

    /// Parallel passes of one kind: 0 the brains, 1 the flight step.
    #[func]
    fn parallel_passes_of(&self, pass: i64) -> i64 {
        self.threads.parallel_passes_of(if pass == 1 {
            Pass::Flight
        } else {
            Pass::Brains
        })
    }

    /// Worker threads running now: 0 with one thread, once the last pool's workers have been joined.
    #[func]
    fn live_workers(&self) -> i64 {
        self.threads.live_workers()
    }

    /// The fewest thinks the brains' pass runs in parallel with, and setting it (the benches that chose the default).
    #[func]
    fn parallel_min(&self) -> i64 {
        self.threads.min_items(Pass::Brains) as i64
    }

    #[func]
    fn set_parallel_min(&mut self, items: i64) {
        self.threads
            .set_min_items(Pass::Brains, items.max(0) as usize);
    }

    /// The same for the flight step's pass.
    #[func]
    fn flight_parallel_min(&self) -> i64 {
        self.threads.min_items(Pass::Flight) as i64
    }

    #[func]
    fn set_flight_parallel_min(&mut self, items: i64) {
        self.threads
            .set_min_items(Pass::Flight, items.max(0) as usize);
    }

    /// A 64-bit digest of every row's state and every bolt (positions, velocities, bases, spins, flags, hulls, the
    /// selections as rows), with no instance id in it, so two runs of one seeded fight compare tick by tick (M4-T18).
    #[func]
    fn rows_digest(&self) -> i64 {
        let mut d = Digest::default();
        let r = &self.rows;
        for i in 0..r.body_ids.len() {
            for v in [r.positions[i], r.velocities[i], r.angular[i]] {
                d.vector(v);
            }
            for row in r.bases[i].rows {
                d.vector(row);
            }
            d.word(u64::from(r.flags[i]));
            d.word(r.hull_fraction[i].to_bits());
            let target = r.target_ids.get(i).copied().unwrap_or(-1);
            d.word(i64::from(if target > 0 { r.row_of_id(target) } else { -1 }) as u64);
        }
        for i in 0..self.bolts.positions.len() {
            d.vector(self.bolts.positions[i]);
            d.vector(self.bolts.velocities[i]);
        }
        d.0 as i64
    }

    /// The physics frame of the last `sync_in`, and of the last bolt sync.
    #[func]
    fn tick(&self) -> i64 {
        self.tick
    }

    #[func]
    fn bolt_tick(&self) -> i64 {
        self.bolt_tick
    }

    /// Rows now: the bodies, the statics and the late rows together.
    #[func]
    pub fn row_count(&self) -> i64 {
        self.rows.body_ids.len() as i64
    }

    /// The body rows (before the statics).
    #[func]
    fn node_count(&self) -> i64 {
        self.rows.node_count as i64
    }

    #[func]
    fn static_count(&self) -> i64 {
        self.static_ids.len() as i64
    }

    #[func]
    fn bolt_count(&self) -> i64 {
        self.bolts.ids.len() as i64
    }

    /// Every faction the core has seen, in the order rows and hostility rows index it.
    #[func]
    fn factions(&self) -> Array<StringName> {
        self.factions.iter().cloned().collect()
    }

    /// The handle of the row body `body_id` has now, or 0.
    #[func]
    fn handle_of(&self, body_id: i64) -> i64 {
        self.row_of_id
            .get(&body_id)
            .map_or(0, |&r| self.rows.handles[r as usize])
    }

    /// The row a handle points at now, or -1 (its body left, or came back as a new row).
    #[func]
    fn row_of(&self, handle: i64) -> i64 {
        self.row_of_handle
            .get(&handle)
            .map_or(-1, |&r| i64::from(r))
    }

    /// The row of body `body_id` now, or -1.
    #[func]
    pub fn row_of_id(&self, body_id: i64) -> i64 {
        self.row_of_id.get(&body_id).map_or(-1, |&r| i64::from(r))
    }

    /// `rows_version` for the crate's own readers (the brain host's grid, M4-T17).
    pub fn rows_version_now(&self) -> i64 {
        self.rows_version
    }

    /// The worker threads for the crate's per-ship passes (M4-T18).
    pub fn worker_threads(&self) -> &Threads {
        &self.threads
    }

    /// The row a kernel may read for body `body_id` between sync points, or -1: none when the body was touched since the
    /// last sync (hidden, shown, teleported by the pool), since its row is then stale and the engine must be asked.
    pub fn row_for_kernel(&self, body_id: i64) -> i64 {
        if self.touched.contains(&body_id) {
            return -1;
        }
        self.row_of_id(body_id)
    }

    #[func]
    fn row_name(&self, row: i64) -> GString {
        self.row_index(row)
            .map_or_else(GString::new, |r| self.row_names[r].clone())
    }

    #[func]
    fn row_position(&self, row: i64) -> Vector3 {
        self.row_index(row).map_or(
            Vector3::new(f32::INFINITY, f32::INFINITY, f32::INFINITY),
            |r| self.rows.positions[r],
        )
    }

    #[func]
    fn row_flags(&self, row: i64) -> i64 {
        self.row_index(row)
            .map_or(0, |r| i64::from(self.rows.flags[r]))
    }

    /// Every row's position (bodies, statics, late rows), and the bolts'.
    #[func]
    fn positions(&self) -> PackedVector3Array {
        PackedVector3Array::from(self.rows.positions.as_slice())
    }

    #[func]
    fn bolt_positions(&self) -> PackedVector3Array {
        PackedVector3Array::from(self.bolts.positions.as_slice())
    }

    #[func]
    fn static_positions(&self) -> PackedVector3Array {
        PackedVector3Array::from(self.static_positions.as_slice())
    }

    /// The node rows' body ids and positions (the static rows left out), in row order.
    #[func]
    fn body_ids(&self) -> PackedInt64Array {
        let ids: Vec<i64> = (0..self.rows.body_ids.len())
            .filter(|&i| self.rows.handles[i] != 0)
            .map(|i| self.rows.body_ids[i])
            .collect();
        PackedInt64Array::from(ids.as_slice())
    }

    #[func]
    fn body_positions(&self) -> PackedVector3Array {
        let positions: Vec<Vector3> = (0..self.rows.body_ids.len())
            .filter(|&i| self.rows.handles[i] != 0)
            .map(|i| self.rows.positions[i])
            .collect();
        PackedVector3Array::from(positions.as_slice())
    }

    /// The scan's node rows as `[body_ids, ids, factions, positions, velocities, forwards, ups, radii, is_ship, kinds,
    /// names, hull_ids, node_count, statics]`: the arrays `ContactScan` keeps, without the static rows (the scan appends
    /// those from `StaticRows` itself) and without rows added after the first sync.
    #[func]
    fn snapshot(&self) -> VarArray {
        self.rows.to_array(
            &self.row_names,
            self.rows.node_count,
            self.rows.node_count,
            &self.factions,
        )
    }

    /// `snapshot` with the static rows too (the registry's face, M4-T09), late rows left out.
    #[func]
    pub fn snapshot_all(&self) -> VarArray {
        let count = self.rows.node_count + self.static_ids.len();
        self.rows
            .to_array(&self.row_names, count, self.rows.node_count, &self.factions)
    }

    /// The broadcast scan, `ContactScan.from_broadcasters` for the markers `ids` (the broadcasters, in their order): a row
    /// for each one that is active, read now, as `snapshot` gives rows, plus a last entry: the positions in `ids` that gave
    /// a row. A body's second marker gets its own row here, as it does there.
    #[func]
    pub fn select(&mut self, ids: PackedInt64Array) -> VarArray {
        let mut rows = Rows::default();
        let mut found: Vec<i32> = Vec::new();
        // The selection's names go to a list of its own; the core's rows keep theirs.
        let core_names = std::mem::take(&mut self.row_names);
        let mut markers = std::mem::take(&mut self.markers);
        for (j, id) in ids.as_slice().iter().enumerate() {
            let Some(&at) = self.marker_at.get(id) else {
                continue;
            };
            let m = &mut markers[at];
            if !marker_active(m, &mut self.sync_reads) {
                continue;
            }
            if m.attrs.is_none() || self.touched.contains(&m.body_id) {
                m.attrs = Some(self.read_attrs(m));
                self.attribute_reads += 1;
            }
            self.push_member(&mut rows, m);
            found.push(j as i32);
        }
        self.markers = markers;
        let names = std::mem::replace(&mut self.row_names, core_names);
        rows.node_count = rows.body_ids.len();
        let mut out = rows.to_array(&names, rows.node_count, rows.node_count, &self.factions);
        out.push(&PackedInt32Array::from(found.as_slice()).to_variant());
        out
    }

    /// The hull rows (an active hull each, in the `damageable` group's order) as `[body_ids, hull_ids, rigid, positions,
    /// velocities, radii, bases, rigid_rows]`: the bases as three columns (x, y and z axes) a hull, and the indices of
    /// the rigid hulls among them. What the resolvers need beside the pairs.
    #[func]
    fn hull_columns(&self) -> VarArray {
        let r = &self.rows;
        let n = self.hull_rows.len();
        let mut body_ids = Vec::with_capacity(n);
        let mut hull_ids = Vec::with_capacity(n);
        let mut rigid = Vec::with_capacity(n);
        let mut positions = Vec::with_capacity(n);
        let mut velocities = Vec::with_capacity(n);
        let mut radii = Vec::with_capacity(n);
        let mut bases = Vec::with_capacity(n * 3);
        let mut rigid_rows: Vec<i32> = Vec::new();
        for (k, &j) in self.hull_rows.iter().enumerate() {
            let j = j as usize;
            body_ids.push(r.body_ids[j]);
            hull_ids.push(r.hull_ids[j]);
            rigid.push(u8::from(r.rigid[j]));
            if r.rigid[j] {
                rigid_rows.push(k as i32);
            }
            positions.push(r.positions[j]);
            velocities.push(r.velocities[j]);
            radii.push(r.radii[j]);
            let b = &r.bases[j];
            bases.push(Vector3::new(b.rows[0].x, b.rows[1].x, b.rows[2].x));
            bases.push(col_b(b));
            bases.push(col_c(b));
        }
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(body_ids.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(hull_ids.as_slice()).to_variant());
        out.push(&PackedByteArray::from(rigid.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(positions.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(velocities.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(radii.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(bases.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(rigid_rows.as_slice()).to_variant());
        out
    }

    /// The bolts as `[ids, starts, ends, radii, kinds, beams, shooters, factions, damage, colors, spent, owned, velocities,
    /// last_steps]`: a bolt's segment this tick (`end - last_step` to `end`), its hit radius, its kind (`SimCore.KIND_*`),
    /// which bolts are beams, and (M4-T35) what a hit lands with, which rows a hit already spent, how many rows at the
    /// front the core owns, the velocities and the steps themselves.
    #[func]
    fn bolt_columns(&self) -> VarArray {
        let b = &self.bolts;
        let starts: Vec<Vector3> = (0..b.ids.len())
            .map(|i| sub(b.positions[i], b.last_steps[i]))
            .collect();
        let beams: Vec<i32> = (0..b.ids.len())
            .filter(|&i| b.kinds[i] == KIND_BEAM)
            .map(|i| i as i32)
            .collect();
        let factions: Array<StringName> = b
            .faction_ix
            .iter()
            .map(|&f| self.factions[f as usize].clone())
            .collect();
        let colors: Vec<Color> = b
            .colors
            .iter()
            .map(|c| Color::from_rgba(c[0], c[1], c[2], c[3]))
            .collect();
        let spent: Vec<u8> = b.spent.iter().map(|&s| u8::from(s)).collect();
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(b.ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(starts.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(b.positions.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(b.radii.as_slice()).to_variant());
        out.push(&PackedByteArray::from(b.kinds.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(beams.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(b.shooters.as_slice()).to_variant());
        out.push(&factions.to_variant());
        out.push(&PackedFloat64Array::from(b.damage.as_slice()).to_variant());
        out.push(&PackedColorArray::from(colors.as_slice()).to_variant());
        out.push(&PackedByteArray::from(spent.as_slice()).to_variant());
        out.push(&(b.owned as i64).to_variant());
        out.push(&PackedVector3Array::from(b.velocities.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(b.last_steps.as_slice()).to_variant());
        out
    }

    /// The bolts as the scan's `incoming_fire` arrays: `[positions, velocities, factions, shooters]`.
    #[func]
    fn bolt_scan(&self) -> VarArray {
        let b = &self.bolts;
        let factions: Array<StringName> = b
            .faction_ix
            .iter()
            .map(|&f| self.factions[f as usize].clone())
            .collect();
        let mut out = VarArray::new();
        out.push(&PackedVector3Array::from(b.positions.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(b.velocities.as_slice()).to_variant());
        out.push(&factions.to_variant());
        out.push(&PackedInt64Array::from(b.shooters.as_slice()).to_variant());
        out
    }

    // --- rows with no node (the seam T20 builds on) ---------------------------------------------------------------

    /// Adds a row with no node from `row` (`kind`, `id`, `faction`, `radius`, `flags`, `position`, `velocity`, `basis`,
    /// `angular`, `command`, `state`; missing keys take zeros) and returns its handle.
    #[func]
    fn add_row(&mut self, row: VarDictionary) -> i64 {
        if self.next_data_handle == 0 {
            self.next_data_handle = 1;
        }
        let handle = self.next_data_handle;
        self.next_data_handle += 1;
        // A missing or wrongly typed key takes its zero; a kind out of range is a ship; a float field takes an int too.
        fn take<T: FromGodot>(row: &VarDictionary, key: &str, zero: T) -> T {
            row.get(key)
                .and_then(|v| v.try_to::<T>().ok())
                .unwrap_or(zero)
        }
        fn take_f64(row: &VarDictionary, key: &str) -> f64 {
            row.get(key)
                .and_then(|v| {
                    v.try_to::<f64>()
                        .ok()
                        .or_else(|| v.try_to::<i64>().ok().map(|i| i as f64))
                })
                .unwrap_or(0.0)
        }
        let kind = take::<i64>(&row, "kind", 0);
        self.data.push(DataRow {
            handle,
            kind: if (0..KIND_NAMES.len() as i64).contains(&kind) {
                kind as u8
            } else {
                KIND_SHIP
            },
            id: take(&row, "id", 0),
            faction: take(&row, "faction", StringName::default()),
            radius: take_f64(&row, "radius"),
            flags: take(&row, "flags", 0),
            position: take(&row, "position", Vector3::ZERO),
            velocity: take(&row, "velocity", Vector3::ZERO),
            basis: take(&row, "basis", Basis::IDENTITY),
            angular: take(&row, "angular", Vector3::ZERO),
            command: take(&row, "command", PackedFloat64Array::new())
                .as_slice()
                .to_vec(),
            state: take(&row, "state", PackedFloat64Array::new())
                .as_slice()
                .to_vec(),
        });
        handle
    }

    /// The data row `handle` as a Dictionary with `add_row`'s keys, or an empty one.
    #[func]
    fn row(&self, handle: i64) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(r) = self.data.iter().find(|r| r.handle == handle) else {
            return out;
        };
        out.set("kind", i64::from(r.kind));
        out.set("id", r.id);
        out.set("faction", &r.faction);
        out.set("radius", r.radius);
        out.set("flags", r.flags);
        out.set("position", r.position);
        out.set("velocity", r.velocity);
        out.set("basis", r.basis);
        out.set("angular", r.angular);
        out.set("command", &PackedFloat64Array::from(r.command.as_slice()));
        out.set("state", &PackedFloat64Array::from(r.state.as_slice()));
        out
    }

    #[func]
    fn set_row_motion(
        &mut self,
        handle: i64,
        position: Vector3,
        velocity: Vector3,
        basis: Basis,
        angular: Vector3,
    ) {
        if let Some(r) = self.data.iter_mut().find(|r| r.handle == handle) {
            r.position = position;
            r.velocity = velocity;
            r.basis = basis;
            r.angular = angular;
        }
    }

    #[func]
    fn set_row_command(&mut self, handle: i64, command: PackedFloat64Array) {
        if let Some(r) = self.data.iter_mut().find(|r| r.handle == handle) {
            r.command = command.as_slice().to_vec();
        }
    }

    #[func]
    fn set_row_state(&mut self, handle: i64, state: PackedFloat64Array) {
        if let Some(r) = self.data.iter_mut().find(|r| r.handle == handle) {
            r.state = state.as_slice().to_vec();
        }
    }

    #[func]
    fn remove_row(&mut self, handle: i64) {
        self.data.retain(|r| r.handle != handle);
    }

    #[func]
    fn data_rows(&self) -> i64 {
        self.data.len() as i64
    }
}

impl ScsSimCore {
    // The index of `faction` in the core's table, added on first sight.
    pub fn faction_index(&mut self, faction: StringName) -> u32 {
        if let Some(at) = self.factions.iter().position(|f| *f == faction) {
            return at as u32;
        }
        self.factions.push(faction);
        (self.factions.len() - 1) as u32
    }

    // The slot and generation of member `key`, made on first sight.
    fn slot_for(&mut self, key: i64) -> (u32, u32) {
        if let Some(&known) = self.slot_of.get(&key) {
            return known;
        }
        let slot = self.next_slot;
        self.next_slot += 1;
        self.slot_of.insert(key, (slot, 0));
        (slot, 0)
    }

    // Reads member `m`'s attributes again when it has just turned active or was touched, marks it active now, and gives it
    // a new generation when it turned active.
    fn fresh_attrs(&mut self, m: &mut Member, now: u64) {
        let turned_active = m.active_at + 1 != now;
        if m.attrs.is_none() || turned_active || self.touched.contains(&m.body_id) {
            m.attrs = Some(self.read_attrs(m));
            self.attribute_reads += 1;
        }
        if turned_active {
            m.generation += 1;
            self.slot_of.insert(m.key, (m.slot, m.generation));
        }
        m.active_at = now;
    }

    // A member's row handle: its slot and generation, never 0.
    fn handle(m: &Member) -> i64 {
        (i64::from(m.slot) + 1) << 32 | i64::from(m.generation)
    }

    // Reads member `m`'s body as the tree gather's `_add` reads it (its attributes already read): one transform read, the
    // velocities, and the flags.
    fn read_member(&mut self, m: &Member) -> Read {
        let attrs = m
            .attrs
            .as_ref()
            .expect("attributes are read before a row is made");
        // The pose and motion: from the physics server's direct state by RID (M4-T35, `perf_core_body_direct`: one state
        // handle and three reads), else through the node's own getters as the tree gather reads them.
        let direct = if self.body_direct && m.rigid.is_some() && m.rid.is_valid() {
            self.sync_reads += 1;
            PhysicsServer3D::singleton().body_get_direct_state(m.rid)
        } else {
            None
        };
        let (xf, velocity, angular) = match direct {
            Some(state) => {
                self.sync_reads += 3;
                (
                    state.get_transform(),
                    state.get_linear_velocity(),
                    state.get_angular_velocity(),
                )
            }
            None => {
                self.sync_reads += 1;
                let xf = m.body.get_global_transform();
                let (velocity, angular) = match (&m.rigid, &m.marker) {
                    (Some(rigid), _) => {
                        self.sync_reads += 2;
                        (rigid.get_linear_velocity(), rigid.get_angular_velocity())
                    }
                    (None, Some(marker)) => {
                        self.sync_reads += 1;
                        (
                            marker
                                .get(&self.names.get_or_insert_with(Names::new).velocity)
                                .try_to::<Vector3>()
                                .unwrap_or(Vector3::ZERO),
                            Vector3::ZERO,
                        )
                    }
                    (None, None) => (Vector3::ZERO, Vector3::ZERO),
                };
                (xf, velocity, angular)
            }
        };
        let has_hull = m.hull.is_some();
        let mut flags = 0;
        if m.rigid.is_some() {
            flags |= FLAG_RIGID;
        }
        if has_hull {
            flags |= FLAG_HULL;
        }
        if has_hull && !attrs.destroyed {
            flags |= FLAG_HULL_ACTIVE;
        }
        // The brains' two live reads of a contact (M4-T17): `Damageable.hull.fraction()` and the ship's selection, as the
        // scan stamped them. Two property reads for the hull, one for the selection; with the event columns (M4-T35) the
        // values the events last gave, read live only with the attributes.
        if self.event_columns {
            return Read {
                position: xf.origin,
                basis: xf.basis,
                velocity,
                angular,
                flags,
                hull_fraction: attrs.hull_fraction,
                target_id: attrs.target_id,
            };
        }
        let names = self.names.get_or_insert_with(Names::new);
        let mut failed = 0;
        let hull_fraction = match &attrs.health {
            Some(health) => {
                self.sync_reads += 2;
                let hp = health.get(&names.hp).try_to::<f64>();
                let max_hp = health.get(&names.max_hp).try_to::<f64>();
                match (hp, max_hp) {
                    (Ok(hp), Ok(max_hp)) => clamp01(hp / max_hp),
                    _ => {
                        failed += 1;
                        -1.0
                    }
                }
            }
            None => -1.0,
        };
        let target_id = match &attrs.targeting {
            Some(system) => {
                self.sync_reads += 1;
                match system.get(&names.selected_id).try_to::<i64>() {
                    Ok(selected) if selected != 0 => selected,
                    Ok(_) => -1,
                    Err(_) => {
                        failed += 1;
                        -1
                    }
                }
            }
            None => -1,
        };
        if failed > 0 {
            if self.column_read_failures == 0 {
                godot_warn!(
                    "ScsSimCore: a hull's hp and max_hp or a targeting system's _selected_id did not read; the brains see no \
                     hull or no selection for that body (a renamed property?)"
                );
            }
            self.column_read_failures += failed;
        }
        Read {
            position: xf.origin,
            basis: xf.basis,
            velocity,
            angular,
            flags,
            hull_fraction,
            target_id,
        }
    }

    // Appends member `m`'s body as a row.
    fn push_member(&mut self, rows: &mut Rows, m: &Member) {
        let read = self.read_member(m);
        let attrs = m.attrs.as_ref().expect("read before the row is made");
        rows.body_ids.push(m.body_id);
        rows.ids
            .push(if m.marker.is_some() { m.key } else { m.body_id });
        rows.faction_ix.push(attrs.faction_ix);
        rows.positions.push(read.position);
        rows.velocities.push(read.velocity);
        rows.bases.push(read.basis);
        rows.angular.push(read.angular);
        rows.radii.push(attrs.radius);
        rows.kinds.push(attrs.kind);
        rows.flags.push(read.flags);
        self.row_names.push(attrs.name.clone());
        self.row_rids.push(m.rid);
        rows.hull_ids
            .push(m.hull.as_ref().map_or(0, |h| h.instance_id().to_i64()));
        rows.handles.push(Self::handle(m));
        rows.rigid.push(m.rigid.is_some());
        rows.is_static.push(is_static_kind(attrs.kind));
        rows.is_mine.push(attrs.kind == KIND_MINE);
        rows.hull_fraction.push(read.hull_fraction);
        rows.target_ids.push(read.target_id);
        rows.reach.push(attrs.reach);
        rows.name_keys.push(attrs.name_key.clone());
    }

    // Reads member `m` again into its row `r` (the row keeps its place, handle and lateness).
    fn refresh_member(&mut self, rows: &mut Rows, r: usize, m: &Member) {
        let read = self.read_member(m);
        let attrs = m.attrs.as_ref().expect("read before the row is made");
        rows.faction_ix[r] = attrs.faction_ix;
        rows.positions[r] = read.position;
        rows.velocities[r] = read.velocity;
        rows.bases[r] = read.basis;
        rows.angular[r] = read.angular;
        rows.radii[r] = attrs.radius;
        rows.kinds[r] = attrs.kind;
        rows.flags[r] = read.flags | (rows.flags[r] & FLAG_LATE);
        self.row_names[r] = attrs.name.clone();
        rows.is_static[r] = is_static_kind(attrs.kind);
        rows.is_mine[r] = attrs.kind == KIND_MINE;
        rows.hull_fraction[r] = read.hull_fraction;
        rows.target_ids[r] = read.target_id;
        rows.reach[r] = attrs.reach;
        rows.name_keys[r] = attrs.name_key.clone();
    }

    // Reads the bodies touched since the first sync again: a row in place, or a new row at the end for a body that turned
    // active since (a ship back from the pool).
    fn resync_touched(&mut self) {
        self.rows_version += 1;
        let now = self.syncs;
        let touched: Vec<i64> = self.touched.iter().copied().collect();
        let mut markers = std::mem::take(&mut self.markers);
        let mut hulls = std::mem::take(&mut self.hulls);
        let mut rows = std::mem::take(&mut self.rows);
        for m in markers.iter_mut().chain(hulls.iter_mut()) {
            if !touched.contains(&m.body_id) {
                continue;
            }
            let names = self.names.get_or_insert_with(Names::new);
            let active = if m.marker.is_some() {
                marker_active(m, &mut self.sync_reads)
            } else {
                hull_only_active(m, names, &mut self.sync_reads)
            };
            m.active = active;
            m.active_known = true;
            match self.row_of_id.get(&m.body_id).copied() {
                Some(r) if rows.handles[r as usize] == Self::handle(m) => {
                    let r = r as usize;
                    if active {
                        m.attrs = Some(self.read_attrs(m));
                        self.attribute_reads += 1;
                        self.refresh_member(&mut rows, r, m);
                    } else {
                        // Parked or destroyed since: the row stays (the scan's indices hold) but no kernel treats it as a hull.
                        rows.flags[r] &= !FLAG_HULL_ACTIVE;
                        m.active_at = 0;
                    }
                }
                Some(_) => {}
                None if active && !self.seen.contains(&m.body_id) => {
                    self.seen.insert(m.body_id);
                    self.fresh_attrs(m, now);
                    self.push_member(&mut rows, m);
                    let last = rows.flags.len() - 1;
                    rows.flags[last] |= FLAG_LATE;
                }
                None => {}
            }
        }
        self.markers = markers;
        self.hulls = hulls;
        self.rows = rows;
        self.touched.clear();
        self.index_rows();
    }

    // Rebuilds the lookups over the rows: by body id, by handle, by marker id (the kernels'), and the hull rows in the
    // resolvers' order.
    fn index_rows(&mut self) {
        self.rows.index_ids();
        self.row_of_id.clear();
        self.row_of_handle.clear();
        let mut hull_rows: Vec<(i64, u32)> = Vec::new();
        // A body's rank is its first `Damageable`'s (the marker members carry it; the hull members come in group order).
        let mut ranks: HashMap<i64, i64> = HashMap::new();
        for m in self.markers.iter().chain(self.hulls.iter()) {
            ranks.entry(m.body_id).or_insert(m.hull_rank);
        }
        for i in 0..self.rows.body_ids.len() {
            if self.rows.handles[i] == 0 {
                continue;
            }
            self.row_of_id.insert(self.rows.body_ids[i], i as u32);
            self.row_of_handle.insert(self.rows.handles[i], i as u32);
            if self.rows.flags[i] & FLAG_HULL_ACTIVE != 0 {
                let rank = ranks
                    .get(&self.rows.body_ids[i])
                    .copied()
                    .unwrap_or(i64::MAX);
                hull_rows.push((rank, i as u32));
            }
        }
        hull_rows.sort_unstable();
        self.hull_rows = hull_rows.into_iter().map(|(_, i)| i).collect();
    }

    fn close_tick(&mut self) {
        self.last_calls = [self.sync_reads, self.fallback_reads];
        self.sync_reads = 0;
        self.fallback_reads = 0;
        self.open = false;
    }

    fn row_index(&self, row: i64) -> Option<usize> {
        usize::try_from(row)
            .ok()
            .filter(|&r| r < self.rows.body_ids.len())
    }

    // Faction, name, kind, radius and the destroyed flag as the tree gather reads them: from the marker, or from the hull
    // when there is none.
    fn read_attrs(&mut self, m: &Member) -> Attrs {
        // With a hull: its validity, then (when valid) the radius and the two reads of the destroyed flag; then the
        // marker's three reads, or the hull's one.
        let names = self.names.get_or_insert_with(Names::new);
        let hull = m.hull.as_ref().filter(|h| {
            self.sync_reads += 1;
            let valid = h.is_instance_valid();
            if valid {
                self.sync_reads += 3;
            }
            valid
        });
        self.sync_reads += if m.marker.is_some() {
            3
        } else {
            i64::from(hull.is_some())
        };
        let radius = hull.map_or(0.0, |h| {
            h.get(&names.bounding_radius).try_to::<f64>().unwrap_or(0.0)
        });
        let destroyed = hull.is_some_and(|h| destroyed(h, names));
        let (faction, name, kind) = match &m.marker {
            Some(marker) => (
                marker
                    .get(&names.faction)
                    .try_to::<StringName>()
                    .unwrap_or_default(),
                marker
                    .get(&names.display_name)
                    .try_to::<GString>()
                    .unwrap_or_default(),
                kind_of(&marker.get(&names.kind)),
            ),
            None => (
                hull.map(|h| {
                    h.get(&names.faction)
                        .try_to::<StringName>()
                        .unwrap_or_default()
                })
                .unwrap_or_default(),
                GString::new(),
                KIND_SHIP,
            ),
        };
        // The brains' handles (M4-T17): the hull's health object, the ship's targeting system and the marker's broadcast
        // range, read once here with the other attributes.
        let health = hull.and_then(|h| {
            self.sync_reads += 1;
            h.get(&names.hull).try_to::<Gd<Object>>().ok()
        });
        let targeting = {
            self.sync_reads += 1;
            m.body
                .get(&names.targeting)
                .try_to::<Gd<Object>>()
                .ok()
                .and_then(|t| {
                    self.sync_reads += 1;
                    t.get(&names.system).try_to::<Gd<Object>>().ok()
                })
        };
        let reach = match &m.marker {
            Some(marker) => {
                self.sync_reads += 1;
                match marker.get(&names.broadcast_range_m).try_to::<f64>() {
                    Ok(reach) => reach,
                    Err(_) => {
                        if self.column_read_failures == 0 {
                            godot_warn!(
                                "ScsSimCore: a marker's broadcast_range_m did not read; the brains hear no broadcast from \
                                 it (a renamed property?)"
                            );
                        }
                        self.column_read_failures += 1;
                        0.0
                    }
                }
            }
            None => 0.0,
        };
        // The event columns' starting values (M4-T35): the hull and the selection as they are now; the events keep them.
        let hull_fraction = match &health {
            Some(h) => {
                self.sync_reads += 2;
                let hp = h.get(&names.hp).try_to::<f64>();
                let max_hp = h.get(&names.max_hp).try_to::<f64>();
                match (hp, max_hp) {
                    (Ok(hp), Ok(max_hp)) => clamp01(hp / max_hp),
                    _ => -1.0,
                }
            }
            None => -1.0,
        };
        let target_id = match &targeting {
            Some(system) => {
                self.sync_reads += 1;
                match system.get(&names.selected_id).try_to::<i64>() {
                    Ok(selected) if selected != 0 => selected,
                    _ => -1,
                }
            }
            None => -1,
        };
        self.latest_target.insert(m.body_id, target_id);
        Attrs {
            faction_ix: self.faction_index(faction),
            name_key: name.to_string().to_lowercase(),
            name,
            kind,
            radius,
            destroyed,
            reach,
            health,
            targeting,
            hull_fraction,
            target_id,
        }
    }
}

// `HullHealth.fraction`'s clamp (`clampf`; a NaN stays NaN either way).
fn clamp01(v: f64) -> f64 {
    v.clamp(0.0, 1.0)
}

impl RowsSnapshot for Rows {
    // The first `count` rows as the `VarArray` `snapshot` documents (forwards and ups from the bases), `node_count` of
    // them nodes.
    fn to_array(
        &self,
        names: &[GString],
        count: usize,
        node_count: usize,
        factions: &[StringName],
    ) -> VarArray {
        let count = count.min(self.body_ids.len());
        let faction_names: Array<StringName> = self.faction_ix[..count]
            .iter()
            .map(|&f| factions[f as usize].clone())
            .collect();
        let forwards: Vec<Vector3> = self.bases[..count]
            .iter()
            .map(|b| neg(normalized(col_c(b))))
            .collect();
        let ups: Vec<Vector3> = self.bases[..count]
            .iter()
            .map(|b| normalized(col_b(b)))
            .collect();
        let is_ship: Vec<u8> = self.rigid[..count].iter().map(|&r| u8::from(r)).collect();
        let statics = self.kinds[..count]
            .iter()
            .filter(|&&k| is_static_kind(k))
            .count() as i64;
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(&self.body_ids[..count]).to_variant());
        out.push(&PackedInt64Array::from(&self.ids[..count]).to_variant());
        out.push(&faction_names.to_variant());
        out.push(&PackedVector3Array::from(&self.positions[..count]).to_variant());
        out.push(&PackedVector3Array::from(&self.velocities[..count]).to_variant());
        out.push(&PackedVector3Array::from(forwards.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(ups.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(&self.radii[..count]).to_variant());
        out.push(&PackedByteArray::from(is_ship.as_slice()).to_variant());
        out.push(&PackedByteArray::from(&self.kinds[..count]).to_variant());
        out.push(&PackedStringArray::from(&names[..count.min(names.len())]).to_variant());
        out.push(&PackedInt64Array::from(&self.hull_ids[..count]).to_variant());
        out.push(&(node_count.min(count) as i64).to_variant());
        out.push(&statics.to_variant());
        out
    }
}

// `Targetable.is_active()` for member `m`'s marker (in the tree, visible, its body processing), and both still exist.
fn marker_active(m: &Member, calls: &mut i64) -> bool {
    let Some(marker) = m.marker.as_ref() else {
        return false;
    };
    // Each test is one engine call; the chain stops at the first false.
    let checks: [&dyn Fn() -> bool; 5] = [
        &|| marker.is_instance_valid(),
        &|| m.body.is_instance_valid(),
        &|| marker.is_inside_tree(),
        &|| marker.is_visible_in_tree(),
        &|| m.body.can_process(),
    ];
    for check in checks {
        *calls += 1;
        if !check() {
            return false;
        }
    }
    true
}

// `Damageable.is_active()` for a member with no active marker: the hull in the tree, the body visible and processing, the
// hull not destroyed (a script read, last).
fn hull_only_active(m: &Member, names: &Names, calls: &mut i64) -> bool {
    *calls += 1;
    if !m.body.is_instance_valid() {
        return false;
    }
    let Some(hull) = m.hull.as_ref() else {
        return false;
    };
    let checks: [&dyn Fn() -> bool; 4] = [
        &|| hull.is_instance_valid(),
        &|| hull.is_inside_tree(),
        &|| m.body.is_visible_in_tree(),
        &|| m.body.can_process(),
    ];
    for check in checks {
        *calls += 1;
        if !check() {
            return false;
        }
    }
    *calls += 2;
    !destroyed(hull, names)
}

// `BodyKind.from_variant` (plus the core's projectile kinds): a value in range, or a name in any case; else a ship.
pub fn kind_of(value: &Variant) -> u8 {
    match value.get_type() {
        VariantType::INT => {
            let v = value.to::<i64>();
            if (0..KIND_NAMES.len() as i64).contains(&v) {
                v as u8
            } else {
                KIND_SHIP
            }
        }
        VariantType::STRING | VariantType::STRING_NAME => {
            let name = value.stringify().to_string().to_lowercase();
            KIND_NAMES
                .iter()
                .position(|k| *k == name)
                .map_or(KIND_SHIP, |p| p as u8)
        }
        _ => KIND_SHIP,
    }
}

// A `Color` property as four floats; opaque white when the property is not a colour.
pub fn color_of(value: &Variant) -> [f32; 4] {
    match value.try_to::<Color>() {
        Ok(c) => [c.r, c.g, c.b, c.a],
        Err(_) => [1.0, 1.0, 1.0, 1.0],
    }
}

// `BodyKind.is_static`: rocks and mines.
pub fn is_static_kind(kind: u8) -> bool {
    kind == KIND_MINE || kind == KIND_STATIC
}

// Whether a `Damageable`'s hull is destroyed (`hull.destroyed`).
fn destroyed(hull: &Gd<Node>, names: &Names) -> bool {
    hull.get(&names.hull)
        .try_to::<Gd<Object>>()
        .is_ok_and(|h| h.get(&names.destroyed).try_to::<bool>().unwrap_or(false))
}

fn col_b(b: &Basis) -> Vector3 {
    Vector3::new(b.rows[0].y, b.rows[1].y, b.rows[2].y)
}

fn col_c(b: &Basis) -> Vector3 {
    Vector3::new(b.rows[0].z, b.rows[1].z, b.rows[2].z)
}

// Godot's `Vector3.normalized()` in 32 bits: divide by the length, zero stays zero.
fn normalized(v: Vector3) -> Vector3 {
    let x2 = v.x * v.x;
    let y2 = v.y * v.y;
    let z2 = v.z * v.z;
    let lsq = x2 + y2 + z2;
    if lsq == 0.0 {
        return Vector3::ZERO;
    }
    let len = lsq.sqrt();
    Vector3::new(v.x / len, v.y / len, v.z / len)
}

fn neg(v: Vector3) -> Vector3 {
    Vector3::new(-v.x, -v.y, -v.z)
}

pub fn add(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x + b.x, a.y + b.y, a.z + b.z)
}

pub fn sub(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x - b.x, a.y - b.y, a.z - b.z)
}

// M4-T20: what the weapon rows ask the core beyond its columns.
impl ScsSimCore {
    /// Whether `body_id` was hidden, shown or lost its hull since its row was last read (its row may be stale).
    pub fn is_touched(&self, body_id: i64) -> bool {
        self.touched.contains(&body_id)
    }
}

// FNV-1a over 64-bit words: `rows_digest`'s hash.
struct Digest(u64);

impl Default for Digest {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Digest {
    fn word(&mut self, w: u64) {
        for b in w.to_le_bytes() {
            self.0 ^= u64::from(b);
            self.0 = self.0.wrapping_mul(0x0100_0000_01b3);
        }
    }

    fn vector(&mut self, v: Vector3) {
        self.word(u64::from(v.x.to_bits()));
        self.word(u64::from(v.y.to_bits()));
        self.word(u64::from(v.z.to_bits()));
    }
}

// M4-T35b: the core's state from events, the selection check and what the ram stage reads.
#[godot_api(secondary)]
impl ScsSimCore {
    /// Keeps activity, hull and selection from the facade's events (`perf_core_event_columns`): a body is checked again
    /// only when touched, and its hull and selection columns carry what `note_hull` and `note_selection` last gave.
    #[func]
    fn set_event_columns(&mut self, on: bool) {
        if on != self.event_columns {
            self.activity_dirty = true;
            self.forget_attributes();
        }
        self.event_columns = on;
    }

    #[func]
    fn event_columns(&self) -> bool {
        self.event_columns
    }

    /// Reads the rigid bodies from the physics server's direct state by RID (`perf_core_body_direct`) instead of the nodes.
    #[func]
    fn set_body_direct(&mut self, on: bool) {
        self.body_direct = on;
    }

    #[func]
    fn body_direct(&self) -> bool {
        self.body_direct
    }

    /// A hull's points changed (`Damageable.damaged`, a heal): its column reads `clamp(hp / max_hp)` from the next sync.
    #[func]
    fn note_hull(&mut self, body_id: i64, hp: f64, max_hp: f64) {
        let fraction = clamp01(hp / max_hp);
        for m in self.markers.iter_mut().chain(self.hulls.iter_mut()) {
            if m.body_id == body_id {
                if let Some(a) = m.attrs.as_mut() {
                    if a.health.is_some() {
                        a.hull_fraction = fraction;
                    }
                }
            }
        }
    }

    /// A ship's selection changed (`TargetingController.target_changed`): its column reads it from the next sync.
    #[func]
    fn note_selection(&mut self, body_id: i64, selected_id: i64) {
        let target = if selected_id != 0 { selected_id } else { -1 };
        self.latest_target.insert(body_id, target);
        for m in self.markers.iter_mut().chain(self.hulls.iter_mut()) {
            if m.body_id == body_id {
                if let Some(a) = m.attrs.as_mut() {
                    if a.targeting.is_some() {
                        a.target_id = target;
                    }
                }
            }
        }
    }

    /// A row's hull column (0..1, -1 without a hull) and selection column (a `Targetable` id, -1 for none).
    #[func]
    fn row_hull_fraction(&self, row: i64) -> f64 {
        self.row_index(row)
            .map_or(-1.0, |r| self.rows.hull_fraction[r])
    }

    #[func]
    fn row_target_id(&self, row: i64) -> i64 {
        self.row_index(row).map_or(-1, |r| self.rows.target_ids[r])
    }

    /// Runs the selection check of body `body_id`'s AI targeting controller here (`perf_native_selection_check`): its
    /// selection must be a row within `sensor_range_m` or the target's own reach, and not its own ship.
    #[func]
    fn watch_selection(&mut self, body_id: i64, sensor_range_m: f64) {
        self.unwatch_selection(body_id);
        self.selection_watch.push((body_id, sensor_range_m));
    }

    #[func]
    fn unwatch_selection(&mut self, body_id: i64) {
        self.selection_watch.retain(|(b, _)| *b != body_id);
    }

    #[func]
    fn watched_selections(&self) -> i64 {
        self.selection_watch.len() as i64
    }

    /// A watched body's check, step by step, for the tests: `[row, latest target, target row, range, reach, sensor]`.
    #[func]
    fn selection_check_of(&self, body_id: i64) -> PackedFloat64Array {
        let sensor = self
            .selection_watch
            .iter()
            .find(|(b, _)| *b == body_id)
            .map_or(-1.0, |(_, s)| *s);
        let r = self.row_of_id.get(&body_id).map_or(-1, |&r| i64::from(r));
        let target = self.latest_target.get(&body_id).copied().unwrap_or(-1);
        let tr = if target > 0 { i64::from(self.rows.row_of_id(target)) } else { -1 };
        let (range, reach) = match (usize::try_from(r), usize::try_from(tr)) {
            (Ok(r), Ok(t)) => {
                let from = self.rows.positions[r];
                let to = self.rows.positions[t];
                let dx = f64::from(to.x) - f64::from(from.x);
                let dy = f64::from(to.y) - f64::from(from.y);
                let dz = f64::from(to.z) - f64::from(from.z);
                ((dx * dx + dy * dy + dz * dz).sqrt(), self.rows.reach[t])
            }
            _ => (-1.0, -1.0),
        };
        PackedFloat64Array::from(&[r as f64, target as f64, tr as f64, range, reach, sensor][..])
    }

    /// The watched bodies whose selection the controllers would clear now (`TargetingController._check_selection`): no
    /// row for the target (parked, gone), the ship's own marker, or out of reach, the range in 64 bits as
    /// `TargetingSystem.range_between` takes it. The selection is the latest the events gave.
    #[func]
    fn selection_clears(&self) -> PackedInt64Array {
        let mut out: Vec<i64> = Vec::new();
        for &(body_id, sensor_range) in &self.selection_watch {
            let Some(&r) = self.row_of_id.get(&body_id) else {
                continue; // no row: a parked ship's controller does not run either
            };
            let target = self.latest_target.get(&body_id).copied().unwrap_or(-1);
            if target <= 0 {
                continue;
            }
            let tr = self.rows.row_of_id(target);
            let Ok(t) = usize::try_from(tr) else {
                out.push(body_id);
                continue;
            };
            if self.rows.body_ids[t] == body_id {
                out.push(body_id);
                continue;
            }
            let from = self.rows.positions[r as usize];
            let to = self.rows.positions[t];
            let dx = f64::from(to.x) - f64::from(from.x);
            let dy = f64::from(to.y) - f64::from(from.y);
            let dz = f64::from(to.z) - f64::from(from.z);
            let range = (dx * dx + dy * dy + dz * dz).sqrt();
            let reach = if sensor_range > self.rows.reach[t] {
                sensor_range
            } else {
                self.rows.reach[t]
            };
            if range > reach {
                out.push(body_id);
            }
        }
        PackedInt64Array::from(out.as_slice())
    }
}
