// The native simulation core (M4-T15, docs/architecture.md 17.13): one store of rows for every simulated entity, filled
// from the engine at the tick's sync points and read by every native kernel.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::collections::HashMap;
use std::sync::Arc;

use godot::classes::{Node, Node3D, Object, RigidBody3D};
use godot::prelude::*;

use crate::row_commands::{IdMap, IdSet};
use crate::rows::NameTable;
use crate::threads::{self, Pass, Threads};
use crate::v3::{add, col_b, col_c, neg, normalized, sub};

pub use crate::rows::{Bolts, FLAG_HULL, FLAG_HULL_ACTIVE, FLAG_LATE, FLAG_RIGID, FLAG_TIER, Rows};

// The snapshot the scan takes of the rows, built here (it crosses the boundary).
trait RowsSnapshot {
    fn to_array(
        &self,
        names: PackedStringArray,
        faction_names: Array<StringName>,
        count: usize,
        node_count: usize,
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
    faction: StringName,
    kind: StringName,
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
            faction: StringName::from("faction"),
            kind: StringName::from("kind"),
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
    // The display name and its lowered form, as ids of the core's two name tables (M5-T35; 0 for no name).
    name_id: u32,
    key_id: u32,
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
    // The role (M5-T16): civilian when `set_civilian` named the body, read with the other attributes.
    role: u8,
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
    // The place of the body's first hull in the `damageable` group: the order the resolvers walk hulls in (-1 with none).
    hull_rank: i64,
    // The member's place in `slot_of`, which outlives `set_members`.
    slot: u32,
    // The body's RID (invalid for a body with no rigid body) and whether it was active at the last check (M4-T35: with the
    // event columns on, checked again only when touched).
    rid: Rid,
    active: bool,
    active_known: bool,
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
    marker_at: IdMap<usize>,
    // A member's slot by its key, kept across `set_members` with its generation; a member that left the groups gives its
    // slot back (M4-T21), and the slot's generation count goes on when another member takes it, so no old handle names
    // the new row.
    slot_of: IdMap<(u32, u32)>,
    slot_generation: Vec<u32>,
    free_slots: Vec<u32>,
    touched: IdSet,
    // Bodies a resync found parked since the tick's first sync: their rows stay until the next sync, but nothing aims at them.
    parked_since_sync: IdSet,
    seen: IdSet,
    syncs: u64,
    attribute_reads: i64,
    static_ids: Vec<i64>,
    static_positions: Vec<Vector3>,
    static_radii: Vec<f64>,
    static_factions: Vec<u32>,
    static_kinds: Vec<u8>,
    // The rocks and mines as ready rows (M5-T35), built when they are set and copied in whole at each sync, with their
    // `(id, place)` pairs sorted for the rows' id lookup.
    static_block: Rows,
    static_sorted: Vec<(i64, u32)>,
    // Whether the rows hold that block as it is now (not between `set_statics` and the next first sync).
    statics_current: bool,
    /// Every faction the core has seen, in first-sight order; rows carry an index into it.
    pub factions: Vec<StringName>,
    /// The scan's rows and the bolts, as of the last sync point.
    pub rows: Rows,
    pub bolts: Bolts,
    /// Each row's display name as an id of `display_names` (0 for none), beside the rows (the names are engine strings
    /// the worker threads must not share, M4-T18).
    pub row_name_ids: Vec<u32>,
    // The display names by id (id 1 first), each with its lowered form's id in `name_table`, and the ids by name.
    display_names: Vec<GString>,
    display_keys: Vec<u32>,
    display_ids: HashMap<String, u32>,
    // The lowered names the rows' `name_ids` stand for; `names_shared` is the copy the rows and the jobs' snapshots hold,
    // made again when a name was added.
    name_table: NameTable,
    names_shared: Arc<NameTable>,
    names_stale: bool,
    // Each row's hull rank (its member's), beside the rows: what orders `hull_rows`.
    row_ranks: Vec<i64>,
    // Every member by its body, sorted by body: `(body id, place)`, a place past the markers being a hull's (M5-T35, L9).
    members_by_body: Vec<(i64, u32)>,
    // Lists the lookups are built in, kept between syncs.
    id_scratch: Vec<(i64, u32)>,
    hull_scratch: Vec<(i64, u32)>,
    // The scan's faction and name columns as last handed out, and the row columns they were made from.
    scan_cache: ScanCache,
    /// The rows with an active hull, in the `damageable` group's order: what the sweep and the ram phase walk.
    pub hull_rows: Vec<u32>,
    // The rows the hit sweep tests (M4-T22): the hull rows, then every low-attention tier row (a sphere with no body), so a
    // near ship's bolt hits a tier ship. The ram phase and the weapon kernels keep to the hull rows.
    pub sweep_rows: Vec<u32>,
    row_of_id: IdMap<u32>,
    row_of_handle: IdMap<u32>,
    pub(crate) sync_reads: i64,
    fallback_reads: i64,
    last_calls: [i64; 2],
    pub(crate) tick: i64,
    open: bool,
    // Grows whenever the rows change under a scan taken from them: each sync, resync and shift (M4-T16).
    rows_version: i64,
    // Reads of the brains' columns that found no value where a body had the object (a renamed property): counted and
    // warned about once (M4-T17).
    column_read_failures: i64,
    // The worker threads the kernels' per-ship passes run on (M4-T18).
    threads: Threads,
    // The native pilots' last commands by body, written by the brains' batch and flown by the flight step (M4-T33).
    pub row_commands: crate::row_commands::CommandMap,
    // The core owns its bolts (M4-T35): the owned rows stay across the sync points and the kernels step them; the ids it
    // hands out count down from -1, so no instance id is ever one.
    pub(crate) next_bolt_id: i64,
    // The core's state from events (M4-T35b): activity, hull and selection kept in the attributes and written to the rows
    // at the sync points.
    activity_dirty: bool,
    /// Each row's body RID (invalid for a body with none), beside the rows (M4-T35: the ram stage's contact read).
    pub row_rids: Vec<Rid>,
    /// The ships' accelerations from their own forces this tick, by body, as the flight step wrote them (M4-T35: the ram
    /// tracker's accel column; `force / mass` in 32 bits, as `Ship.applied_force() / ship.mass`).
    pub accels: IdMap<Vector3>,
    // The AI targeting controllers whose selection check runs here (M4-T35): body id and sensor range; and every body's
    // selection as the events last gave it (or as its attributes read it).
    selection_watch: Vec<(i64, f64)>,
    latest_target: IdMap<i64>,
    // Bodies whose row command GDScript released since the step's last launch (M4-T24): dropped from the job's commands
    // at the join.
    pub(crate) released: Vec<i64>,
    // The low-attention tier (M4-T21): its rows, the fighter types they fly as, the pull they feel, the beat's period in
    // ticks, each row's display name beside the engine-free table, the next handle and ordinal, the beat's scratch and the
    // step's readouts.
    pub(crate) tier: crate::tier::TierRows,
    pub(crate) tier_types: Vec<crate::tier::Type>,
    pub(crate) tier_gravity: crate::tier::Gravity,
    pub(crate) tier_period: i64,
    pub(crate) tier_name_ids: Vec<u32>,
    pub(crate) next_tier_handle: i64,
    pub(crate) next_tier_ordinal: i64,
    pub(crate) tier_scratch: Vec<(Vector3, Vector3)>,
    pub(crate) tier_step_us: i64,
    pub(crate) tier_beats: i64,
    pub(crate) tier_promotions: i64,
    // The tier's fire (M4-T22): the seed every roll draws from, the fighters' hits rolled since GDScript took them, and the
    // shots and hits rolled so far.
    pub(crate) tier_seed: u64,
    pub(crate) tier_hits: crate::tier_fire::Hits,
    pub(crate) tier_shots_total: i64,
    pub(crate) tier_hits_total: i64,
    // The rammer and target pairs in contact at the last check, so a ram lands once, when they first touch (fix round 1).
    pub(crate) tier_ram_pairs: std::collections::HashSet<(i64, i64)>,
    pub(crate) tier_ram_scratch: std::collections::HashSet<(i64, i64)>,
    // The defensive turrets (M5-T21): mounts on the ships' rows and the attacker memory.
    pub(crate) turrets: crate::turret_rows::TurretState,
    // Promotions moved clear of a rock or mine they overlapped (M4-T23).
    pub(crate) tier_cleared: i64,
    // The last first sync's wall-clock parts, microseconds (readouts only, M5-T35): the tier's step, the bodies, the
    // statics, the tier's rows, the lookups.
    sync_parts: [i64; 5],
    // The World's free-falling frame (M6-T04, D64): its star system, its anchor and the tick's gravity sample.
    pub(crate) frame: crate::frame::Frame,
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
            let body_id = body.instance_id().to_i64();
            // The body's rank is its first hull's, whichever of its hulls this member is.
            let rank = first_hull.get(&body_id).map_or(rank as i64, |(_, r)| *r);
            let (attrs, active_at) = known.remove(&key).unwrap_or((None, 0));
            let (slot, generation) = self.slot_for(key);
            let rigid = body.clone().try_cast::<RigidBody3D>().ok();
            let rid = rigid.as_ref().map_or(Rid::Invalid, |r| r.get_rid());
            self.hulls.push(Member {
                key,
                rigid,
                body_id,
                body,
                marker: None,
                hull: Some(hull),
                attrs,
                active_at,
                generation,
                hull_rank: rank,
                slot,
                rid,
                active: false,
                active_known: false,
            });
        }
        // Whoever was known and is in neither list has left the groups.
        self.free_slots_of(known.into_keys());
        self.index_members();
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
            self.build_static_block();
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
        self.build_static_block();
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

    /// Members with a slot now (the live markers and hulls; M4-T21: a member that left gave its slot back).
    #[func]
    fn slot_count(&self) -> i64 {
        self.slot_of.len() as i64
    }

    /// How many `sync_in` calls ran.
    #[func]
    pub fn syncs(&self) -> i64 {
        self.syncs as i64
    }

    /// The tick's first sync point: builds this tick's rows from the bodies, the statics after the bodies, and keeps only
    /// the owned bolts (`ScsBoltSync` reads the node bolts after it). `tick` stamps the rows. Returns the body row count.
    #[func]
    pub fn sync_in(&mut self, tick: i64, delta: f64) -> i64 {
        if self.open {
            self.close_tick();
        }
        // The owned bolts a hit spent last tick go now, as a spent node is gone by its next tick (M4-T35).
        crate::bolt_kernels::drop_spent(&mut self.bolts);
        self.open = true;
        self.tick = tick;
        self.syncs += 1;
        self.rows_version += 1;
        let mut clock = PartClock::new();
        // The tier's integration for the current tick (M4-T21). The body rows read below are a tick older, so a tier row
        // leads them by one tick's motion; a demote and promote pair still steps the ship exactly once a tick.
        self.tier_step(delta);
        self.sync_parts[0] = clock.lap();
        let now = self.syncs;
        let mut rows = std::mem::take(&mut self.rows);
        rows.clear();
        self.row_name_ids.clear();
        self.row_rids.clear();
        self.row_ranks.clear();
        self.compact_names();
        self.seen.clear();
        self.parked_since_sync.clear();
        let cached = !self.activity_dirty;
        let mut markers = std::mem::take(&mut self.markers);
        for m in markers.iter_mut() {
            // A body's activity is checked again only when it was touched (hidden, shown, destroyed) or first seen; the facade's events cover every change the pool and the resolvers make.
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
            // As for the markers (M5-T35): checked again only when touched or first asked. A body whose marker turned
            // inactive was touched for it, so its hull is checked in that same sync.
            if !cached || !m.active_known || self.touched.contains(&m.body_id) {
                let names = self.names.get_or_insert_with(Names::new);
                m.active = hull_only_active(m, names, &mut self.sync_reads);
                m.active_known = true;
            }
            if !m.active {
                m.active_at = 0;
                continue;
            }
            self.seen.insert(m.body_id);
            self.fresh_attrs(m, now);
            self.push_member(&mut rows, m);
        }
        self.hulls = hulls;
        rows.node_count = rows.body_ids.len();
        self.sync_parts[1] = clock.lap();
        rows.extend_from(&self.static_block);
        self.statics_current = true;
        let with_statics = rows.body_ids.len();
        self.row_name_ids.resize(with_statics, 0);
        self.row_rids.resize(with_statics, Rid::Invalid);
        self.row_ranks.resize(with_statics, i64::MAX);
        self.sync_parts[2] = clock.lap();
        // The tier's rows after the statics (M4-T21): contacts to the brains, out of the scan GDScript builds.
        let tier_base = rows.body_ids.len();
        self.tier.append_to(&mut rows);
        // A tier ship's selection is its own (M4-T23): its brain sees what it holds, as a near brain does.
        for (k, body_id) in self.tier.body_ids.iter().enumerate() {
            if let Some(&target) = self.latest_target.get(body_id) {
                rows.target_ids[tier_base + k] = target;
            }
        }
        self.row_name_ids.extend_from_slice(&self.tier_name_ids);
        self.row_rids.resize(rows.body_ids.len(), Rid::Invalid);
        self.row_ranks.resize(rows.body_ids.len(), i64::MAX);
        self.rows = rows;
        self.touched.clear();
        self.sync_parts[3] = clock.lap();
        self.index_rows();
        self.sync_parts[4] = clock.lap();
        self.bolts.truncate_to_owned();
        self.rows.node_count as i64
    }

    /// The last first sync's parts, wall-clock microseconds: `[tier step, bodies, statics, tier rows, lookups]` (readouts
    /// only).
    #[func]
    fn sync_parts_us(&self) -> PackedInt64Array {
        PackedInt64Array::from(&self.sync_parts[..])
    }

    /// The tick's later sync point (the hit resolver's, after the bolts moved): reads the bodies that were touched since
    /// the first sync again (a ship back from the pool gets its row now, a parked one loses its hull) and keeps only the
    /// owned bolts for `ScsBoltSync` to read the node bolts after. Returns the bolt row count.
    #[func]
    pub fn sync_bolts(&mut self) -> i64 {
        if !self.touched.is_empty() {
            self.resync_touched();
        }
        self.bolts.truncate_to_owned();
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
        self.tier.shift(offset);
        self.tier_gravity.shift(offset);
    }

    /// Engine calls of the last closed tick: `[sync, fallbacks]`: the sync points' reads, which grow with the bodies and
    /// bolts, and the flight step's reads of the physics server for ships without a row. The kernels make none: they live
    /// in `kernels.rs`, which holds no engine type (`test_sim_core` reads the file).
    #[func]
    pub fn engine_calls(&self) -> PackedInt64Array {
        PackedInt64Array::from(&self.last_calls[..])
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

    /// The rows by body id, and the bodies touched since the last sync point (a job's snapshot copies both, M4-T24).
    pub(crate) fn body_rows(&self) -> &IdMap<u32> {
        &self.row_of_id
    }

    pub(crate) fn touched_set(&self) -> &IdSet {
        &self.touched
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
            .map_or_else(GString::new, |r| self.display_name(self.row_name_ids[r]))
    }

    /// The body a row reads its contacts from (the ram phase's), for tests.
    #[func]
    fn row_rid(&self, row: i64) -> Rid {
        self.row_index(row)
            .and_then(|r| self.row_rids.get(r).copied())
            .unwrap_or(Rid::Invalid)
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
    fn snapshot(&mut self) -> VarArray {
        let count = self.rows.node_count.min(self.rows.body_ids.len());
        // The two columns of engine strings are made again only when a row's faction or name changed (M5-T35); the scan
        // gets copies of its own, since it appends the statics to them.
        let cache = &mut self.scan_cache;
        if !(cache.valid
            && cache.faction_ix == self.rows.faction_ix[..count]
            && cache.name_ids == self.row_name_ids[..count])
        {
            cache.faction_ix.clear();
            cache.faction_ix.extend_from_slice(&self.rows.faction_ix[..count]);
            cache.name_ids.clear();
            cache.name_ids.extend_from_slice(&self.row_name_ids[..count]);
            cache.factions = Some(faction_names(&cache.faction_ix, &self.factions));
            cache.names = names_of(&cache.name_ids, &self.display_names);
            cache.valid = true;
            cache.builds += 1;
        }
        let factions = cache
            .factions
            .as_ref()
            .map_or_else(Array::new, |a| a.duplicate_shallow());
        self.rows
            .to_array(cache.names.clone(), factions, count, self.rows.node_count)
    }

    /// How often `snapshot` made its faction and name columns again (the work count: not once a call).
    #[func]
    fn snapshot_builds(&self) -> i64 {
        self.scan_cache.builds
    }

    /// Bodies whose selection the core holds (members and tier rows; a freed body's goes with it).
    #[func]
    fn selections_held(&self) -> i64 {
        self.latest_target.len() as i64
    }

    /// Display names and lowered names the core holds ids for (they are dropped once most belong to no body).
    #[func]
    fn name_count(&self) -> PackedInt64Array {
        PackedInt64Array::from(&[self.display_names.len() as i64, self.name_table.len() as i64][..])
    }

    /// `snapshot` with the static rows too (the registry's face, M4-T09), late rows left out.
    #[func]
    pub fn snapshot_all(&self) -> VarArray {
        let count = (self.rows.node_count + self.static_ids.len()).min(self.rows.body_ids.len());
        self.rows.to_array(
            names_of(&self.row_name_ids[..count.min(self.row_name_ids.len())], &self.display_names),
            faction_names(&self.rows.faction_ix[..count], &self.factions),
            count,
            self.rows.node_count,
        )
    }

    /// The broadcast scan, `ContactScan.from_broadcasters` for the markers `ids` (the broadcasters, in their order): a row
    /// for each one that is active, read now, as `snapshot` gives rows, plus a last entry: the positions in `ids` that gave
    /// a row. A body's second marker gets its own row here, as it does there.
    #[func]
    pub fn select(&mut self, ids: PackedInt64Array) -> VarArray {
        let mut rows = Rows::default();
        let mut found: Vec<i32> = Vec::new();
        // The selection's names, rids and ranks go to lists of their own; the core's rows keep theirs.
        let core_names = std::mem::take(&mut self.row_name_ids);
        let core_rids = std::mem::take(&mut self.row_rids);
        let core_ranks = std::mem::take(&mut self.row_ranks);
        let mut markers = std::mem::take(&mut self.markers);
        // A parked marker whose ship flies as a tier row is heard from its row (M4-T23), built on the first miss.
        let mut tier_of: Option<std::collections::HashMap<i64, usize>> = None;
        for (j, id) in ids.as_slice().iter().enumerate() {
            let active = self
                .marker_at
                .get(id)
                .copied()
                .filter(|&at| marker_active(&markers[at], &mut self.sync_reads));
            let Some(at) = active else {
                if self.tier.is_empty() {
                    continue;
                }
                let map = tier_of.get_or_insert_with(|| {
                    self.tier
                        .marker_ids
                        .iter()
                        .enumerate()
                        .map(|(i, &m)| (m, i))
                        .collect()
                });
                if let Some(&i) = map.get(id) {
                    self.tier.push_row(i, &mut rows);
                    self.row_name_ids.push(self.tier_name_ids[i]);
                    found.push(j as i32);
                }
                continue;
            };
            let m = &mut markers[at];
            if m.attrs.is_none() || self.touched.contains(&m.body_id) {
                m.attrs = Some(self.read_attrs(m));
                self.attribute_reads += 1;
            }
            self.push_member(&mut rows, m);
            found.push(j as i32);
        }
        self.markers = markers;
        let names = std::mem::replace(&mut self.row_name_ids, core_names);
        self.row_rids = core_rids;
        self.row_ranks = core_ranks;
        rows.node_count = rows.body_ids.len();
        let mut out = rows.to_array(
            names_of(&names, &self.display_names),
            faction_names(&rows.faction_ix, &self.factions),
            rows.node_count,
            rows.node_count,
        );
        out.push(&PackedInt32Array::from(found.as_slice()).to_variant());
        out
    }

    /// How many hull rows there are (active hulls), without their columns.
    #[func]
    fn hull_count(&self) -> i64 {
        self.hull_rows.len() as i64
    }

    /// The hull rows (an active hull each, in the `damageable` group's order) as `[body_ids, hull_ids, rigid, positions,
    /// velocities, radii, bases, rigid_rows]`: the bases as three columns (x, y and z axes) a hull, and the indices of
    /// the rigid hulls among them. What the resolvers need beside the pairs.
    #[func]
    fn hull_columns(&self) -> VarArray {
        self.columns_of(&self.hull_rows)
    }

    /// `hull_columns` for the hit sweep's rows (M4-T22): the hull rows, then the low-attention tier rows, so the hit
    /// resolver's indices match `ScsHitSweep.pairs_core`'s.
    #[func]
    fn sweep_columns(&self) -> VarArray {
        self.columns_of(&self.sweep_rows)
    }

    // The columns of `list`'s rows, in its order (see `hull_columns`).
    fn columns_of(&self, list: &[u32]) -> VarArray {
        let r = &self.rows;
        let n = list.len();
        let mut body_ids = Vec::with_capacity(n);
        let mut hull_ids = Vec::with_capacity(n);
        let mut rigid = Vec::with_capacity(n);
        let mut positions = Vec::with_capacity(n);
        let mut velocities = Vec::with_capacity(n);
        let mut radii = Vec::with_capacity(n);
        let mut bases = Vec::with_capacity(n * 3);
        let mut rigid_rows: Vec<i32> = Vec::new();
        for (k, &j) in list.iter().enumerate() {
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
    /// last_steps, order]`: a bolt's segment this tick (`end - last_step` to `end`), its hit radius, its kind
    /// (`SimCore.KIND_*`), which bolts are beams, and (M4-T35) what a hit lands with, which rows a hit already spent, how
    /// many rows at the front the core owns, the velocities and the steps themselves, and the bolts in launch order (the
    /// order the resolver lands hits in, as the node path's group order was).
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
        out.push(
            &PackedInt32Array::from(crate::bolt_kernels::launch_order(b).as_slice()).to_variant(),
        );
        out
    }

    /// The hit resolver's bolts for one tick (M5-T32, L2): only the bolts with a live pair, in launch order, and what the
    /// narrow phase reads of them and of the hulls they pair with. `hull_keys` (`bolt * hulls + hull`, ascending, the
    /// hulls in `sweep_rows` order, as `pairs_core` gives them) lose the pairs of spent bolts and of a bolt with its own
    /// shooter's hull; `rock_keys` (`bolt * rock_count + rock`) lose those of spent bolts. Returns `[index, id, start, end,
    /// radius, shooter, faction, damage, color, hull_first, hull_next, rock_first, rock_next, hull_slots, rock_keys, beams,
    /// beam_ids, owned, bolt_count, hull_body_ids, hull_ids, hull_positions, hull_velocities, hull_bases, hull_total]`: one
    /// entry per bolt kept in the first thirteen (ranges into `hull_slots` and `rock_keys`); per kept hull pair the paired
    /// hull's slot in the hull columns that follow (only hulls some kept pair names, bases three columns each); the beams'
    /// indices and ids; the rows the core owns, the bolt count and the hull count.
    #[func]
    fn hit_bolts(&self, hull_keys: PackedInt64Array, rock_keys: PackedInt64Array, rock_count: i64) -> VarArray {
        let b = &self.bolts;
        let n = b.ids.len();
        let hull_total = self.sweep_rows.len();
        let hulls = (hull_total as i64).max(1);
        let rocks = rock_count.max(1);
        // Each bolt's run of kept keys in the filtered lists.
        let mut kept_hulls: Vec<i32> = Vec::with_capacity(hull_keys.len());
        let mut hull_range = vec![(0i32, 0i32); n];
        let mut slot_of_hull: HashMap<usize, i32> = HashMap::new();
        let mut hull_list: Vec<u32> = Vec::new();
        for &key in hull_keys.as_slice() {
            let i = (key / hulls) as usize;
            let j = (key - i as i64 * hulls) as usize;
            if i >= n || b.spent[i] {
                continue;
            }
            let body = self
                .sweep_rows
                .get(j)
                .map_or(0, |&r| self.rows.body_ids[r as usize]);
            if body == b.shooters[i] {
                continue;
            }
            if hull_range[i].1 == hull_range[i].0 {
                hull_range[i] = (kept_hulls.len() as i32, kept_hulls.len() as i32);
            }
            let slot = *slot_of_hull.entry(j).or_insert_with(|| {
                hull_list.push(self.sweep_rows[j]);
                (hull_list.len() - 1) as i32
            });
            kept_hulls.push(slot);
            hull_range[i].1 = kept_hulls.len() as i32;
        }
        let mut kept_rocks: Vec<i64> = Vec::with_capacity(rock_keys.len());
        let mut rock_range = vec![(0i32, 0i32); n];
        for &key in rock_keys.as_slice() {
            let i = (key / rocks) as usize;
            if i >= n || b.spent[i] {
                continue;
            }
            if rock_range[i].1 == rock_range[i].0 {
                rock_range[i] = (kept_rocks.len() as i32, kept_rocks.len() as i32);
            }
            kept_rocks.push(key);
            rock_range[i].1 = kept_rocks.len() as i32;
        }
        let mut index = Vec::new();
        let mut ids = Vec::new();
        let mut starts = Vec::new();
        let mut ends = Vec::new();
        let mut radii = Vec::new();
        let mut shooters = Vec::new();
        let mut factions: Array<StringName> = Array::new();
        let mut damage = Vec::new();
        let mut colors = Vec::new();
        let (mut hf, mut hn, mut rf, mut rn) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
        for i in crate::bolt_kernels::launch_order(b) {
            let i = i as usize;
            let (h0, h1) = hull_range[i];
            let (r0, r1) = rock_range[i];
            if h0 == h1 && r0 == r1 {
                continue;
            }
            index.push(i as i32);
            ids.push(b.ids[i]);
            starts.push(sub(b.positions[i], b.last_steps[i]));
            ends.push(b.positions[i]);
            radii.push(b.radii[i]);
            shooters.push(b.shooters[i]);
            factions.push(&self.factions[b.faction_ix[i] as usize]);
            damage.push(b.damage[i]);
            let c = b.colors[i];
            colors.push(Color::from_rgba(c[0], c[1], c[2], c[3]));
            hf.push(h0);
            hn.push(h1);
            rf.push(r0);
            rn.push(r1);
        }
        let beams: Vec<i32> = (0..n)
            .filter(|&i| b.kinds[i] == KIND_BEAM)
            .map(|i| i as i32)
            .collect();
        let beam_ids: Vec<i64> = beams.iter().map(|&i| b.ids[i as usize]).collect();
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(index.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(starts.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(ends.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(radii.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(shooters.as_slice()).to_variant());
        out.push(&factions.to_variant());
        out.push(&PackedFloat64Array::from(damage.as_slice()).to_variant());
        out.push(&PackedColorArray::from(colors.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(hf.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(hn.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(rf.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(rn.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(kept_hulls.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(kept_rocks.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(beams.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(beam_ids.as_slice()).to_variant());
        out.push(&(b.owned as i64).to_variant());
        out.push(&(n as i64).to_variant());
        let columns = self.columns_of(&hull_list);
        for k in [0, 1, 3, 4, 6] {
            out.push(&columns.at(k));
        }
        out.push(&(hull_total as i64).to_variant());
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

    // The slot and generation of member `key`, made on first sight: a freed slot first, its generation count carried on.
    fn slot_for(&mut self, key: i64) -> (u32, u32) {
        if let Some(&known) = self.slot_of.get(&key) {
            return known;
        }
        let slot = self.free_slots.pop().unwrap_or_else(|| {
            self.slot_generation.push(0);
            (self.slot_generation.len() - 1) as u32
        });
        let generation = self.slot_generation[slot as usize];
        self.slot_of.insert(key, (slot, generation));
        (slot, generation)
    }

    // Gives the slots of the members that left the groups back, so the map holds only the live members; the lowest slot is
    // taken first (the map's order is not a stable one).
    fn free_slots_of(&mut self, gone: impl Iterator<Item = i64>) {
        for key in gone {
            if let Some((slot, _)) = self.slot_of.remove(&key) {
                self.free_slots.push(slot);
            }
        }
        self.free_slots.sort_unstable_by(|a, b| b.cmp(a));
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
            self.slot_generation[m.slot as usize] = m.generation;
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
        // The pose and motion through the node's own getters, as the tree gather reads them.
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
        // The brains' two live reads of a contact (M4-T17), `Damageable.hull.fraction()` and the ship's selection: the
        // values the events last gave (M4-T35), read live only with the attributes.
        Read {
            position: xf.origin,
            basis: xf.basis,
            velocity,
            angular,
            flags,
            hull_fraction: attrs.hull_fraction,
            target_id: attrs.target_id,
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
        self.row_name_ids.push(attrs.name_id);
        self.row_rids.push(m.rid);
        self.row_ranks.push(m.hull_rank);
        rows.hull_ids
            .push(m.hull.as_ref().map_or(0, |h| h.instance_id().to_i64()));
        rows.handles.push(Self::handle(m));
        rows.rigid.push(m.rigid.is_some());
        rows.is_static.push(is_static_kind(attrs.kind));
        rows.is_mine.push(attrs.kind == KIND_MINE);
        rows.hull_fraction.push(read.hull_fraction);
        rows.target_ids.push(read.target_id);
        rows.reach.push(attrs.reach);
        rows.name_ids.push(attrs.key_id);
        rows.roles.push(attrs.role);
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
        self.row_name_ids[r] = attrs.name_id;
        rows.is_static[r] = is_static_kind(attrs.kind);
        rows.is_mine[r] = attrs.kind == KIND_MINE;
        rows.hull_fraction[r] = read.hull_fraction;
        rows.target_ids[r] = read.target_id;
        rows.reach[r] = attrs.reach;
        rows.name_ids[r] = attrs.key_id;
        rows.roles[r] = attrs.role;
    }

    // Reads the bodies touched since the first sync again: a row in place, or a new row at the end for a body that turned
    // active since (a ship back from the pool).
    fn resync_touched(&mut self) {
        self.rows_version += 1;
        let now = self.syncs;
        let mut markers = std::mem::take(&mut self.markers);
        let mut hulls = std::mem::take(&mut self.hulls);
        let mut rows = std::mem::take(&mut self.rows);
        for m in markers.iter_mut().chain(hulls.iter_mut()) {
            if !self.touched.contains(&m.body_id) {
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
                        self.parked_since_sync.insert(m.body_id);
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
        if self.statics_current {
            let mut scratch = std::mem::take(&mut self.id_scratch);
            self.rows
                .index_ids_around(self.rows.node_count, &self.static_sorted, &mut scratch);
            self.id_scratch = scratch;
        } else {
            self.rows.index_ids();
        }
        self.row_of_id.clear();
        self.row_of_handle.clear();
        self.sweep_rows.clear();
        let mut ranked = std::mem::take(&mut self.hull_scratch);
        ranked.clear();
        for i in 0..self.rows.body_ids.len() {
            if self.rows.handles[i] == 0 {
                continue;
            }
            self.row_of_id.insert(self.rows.body_ids[i], i as u32);
            self.row_of_handle.insert(self.rows.handles[i], i as u32);
            if self.rows.flags[i] & FLAG_HULL_ACTIVE != 0 {
                ranked.push((self.row_ranks[i], i as u32));
            }
        }
        ranked.sort_unstable();
        self.hull_rows.clear();
        self.hull_rows.extend(ranked.iter().map(|&(_, i)| i));
        self.hull_scratch = ranked;
        self.sweep_rows.extend_from_slice(&self.hull_rows);
        self.sweep_rows.extend(
            (0..self.rows.body_ids.len())
                .filter(|&i| self.rows.flags[i] & FLAG_TIER != 0)
                .map(|i| i as u32),
        );
        // The rows name their names through the table as it stands now.
        if self.names_stale || self.rows.names.is_none() {
            self.names_shared = Arc::new(self.name_table.clone());
            self.names_stale = false;
        }
        if !self
            .rows
            .names
            .as_ref()
            .is_some_and(|held| Arc::ptr_eq(held, &self.names_shared))
        {
            self.rows.names = Some(Arc::clone(&self.names_shared));
        }
    }

    // The rocks and mines as rows, made once for every sync to copy.
    fn build_static_block(&mut self) {
        let n = self.static_ids.len();
        self.statics_current = false;
        let block = &mut self.static_block;
        block.clear();
        block.body_ids.extend_from_slice(&self.static_ids);
        block.ids.extend_from_slice(&self.static_ids);
        block.faction_ix.extend_from_slice(&self.static_factions);
        block.positions.extend_from_slice(&self.static_positions);
        block.velocities.resize(n, Vector3::ZERO);
        block.bases.resize(n, Basis::IDENTITY);
        block.angular.resize(n, Vector3::ZERO);
        block.radii.extend_from_slice(&self.static_radii);
        block.kinds.extend_from_slice(&self.static_kinds);
        block.flags.resize(n, 0);
        block.hull_ids.resize(n, 0);
        block.handles.resize(n, 0);
        block.rigid.resize(n, false);
        block.is_static.extend(self.static_kinds.iter().map(|&k| is_static_kind(k)));
        block.is_mine.extend(self.static_kinds.iter().map(|&k| k == KIND_MINE));
        block.hull_fraction.resize(n, -1.0);
        block.target_ids.resize(n, -1);
        block.reach.resize(n, 0.0);
        block.name_ids.resize(n, 0);
        block.roles.resize(n, crate::rows::ROLE_COMBAT);
        self.static_sorted.clear();
        self.static_sorted
            .extend(self.static_ids.iter().enumerate().map(|(at, &id)| (id, at as u32)));
        self.static_sorted.sort_unstable();
    }

    // Lists the members by body, so an event finds a body's members without walking them all.
    fn index_members(&mut self) {
        let markers = self.markers.len();
        self.members_by_body.clear();
        self.members_by_body.extend(
            self.markers
                .iter()
                .map(|m| m.body_id)
                .chain(self.hulls.iter().map(|m| m.body_id))
                .enumerate()
                .map(|(at, body_id)| (body_id, at as u32)),
        );
        self.members_by_body.sort_unstable();
        debug_assert!(self.members_by_body.len() == markers + self.hulls.len());
        // A selection is kept only for a body that is still a member or flies in the tier (L9: freed bodies' go).
        let (by_body, tier) = (&self.members_by_body, &self.tier);
        self.latest_target.retain(|body_id, _| {
            by_body.binary_search_by_key(body_id, |e| e.0).is_ok() || tier.index_of(*body_id).is_some()
        });
    }

    // Calls `each` with the attributes of every member of body `body_id` that has them read.
    fn for_attrs_of(&mut self, body_id: i64, mut each: impl FnMut(&mut Attrs)) {
        let first = self.members_by_body.partition_point(|e| e.0 < body_id);
        let markers = self.markers.len();
        for &(body, at) in &self.members_by_body[first..] {
            if body != body_id {
                break;
            }
            let at = at as usize;
            let m = if at < markers {
                &mut self.markers[at]
            } else {
                &mut self.hulls[at - markers]
            };
            if let Some(a) = m.attrs.as_mut() {
                each(a);
            }
        }
    }

    /// The display name with id `id` ("" for 0).
    pub fn display_name(&self, id: u32) -> GString {
        id.checked_sub(1)
            .and_then(|at| self.display_names.get(at as usize))
            .cloned()
            .unwrap_or_default()
    }

    /// The display name of the row whose marker id is `id` ("" for none), for the debug readouts.
    pub fn name_of_marker(&self, id: i64) -> String {
        if id == 0 {
            return String::new();
        }
        self.rows
            .ids
            .iter()
            .position(|&r| r == id)
            .and_then(|r| self.row_name_ids.get(r))
            .map_or_else(String::new, |&name| self.display_name(name).to_string())
    }

    /// The ids of display name `name`: its own, and its lowered form's in the rows' table; given on first sight.
    pub(crate) fn intern_name(&mut self, name: &GString) -> (u32, u32) {
        let text = name.to_string();
        if text.is_empty() {
            return (0, 0);
        }
        if let Some(&id) = self.display_ids.get(&text) {
            return (id, self.display_keys[id as usize - 1]);
        }
        let known = self.name_table.len();
        let key = self.name_table.intern(&text.to_lowercase());
        self.names_stale |= self.name_table.len() != known;
        self.display_names.push(name.clone());
        self.display_keys.push(key);
        let id = self.display_names.len() as u32;
        self.display_ids.insert(text, id);
        (id, key)
    }

    // Drops the names no body carries any more once they are most of the tables (ships come and go under new names over a
    // world's life), giving the ones in use new ids. Only at a first sync, where the rows are made again from the members.
    fn compact_names(&mut self) {
        let holders = self.markers.len() + self.hulls.len() + self.tier.len();
        if self.display_names.len() <= 2 * holders + NAME_SLACK {
            return;
        }
        let old = std::mem::take(&mut self.display_names);
        self.display_keys.clear();
        self.display_ids.clear();
        self.name_table = NameTable::default();
        self.names_stale = true;
        self.scan_cache.valid = false;
        let mut new_ids: Vec<u32> = vec![0; old.len() + 1];
        let mut markers = std::mem::take(&mut self.markers);
        let mut hulls = std::mem::take(&mut self.hulls);
        for m in markers.iter_mut().chain(hulls.iter_mut()) {
            if let Some(a) = m.attrs.as_mut() {
                (a.name_id, a.key_id) = self.renamed(&old, &mut new_ids, a.name_id);
            }
        }
        self.markers = markers;
        self.hulls = hulls;
        for i in 0..self.tier_name_ids.len() {
            let (name, key) = self.renamed(&old, &mut new_ids, self.tier_name_ids[i]);
            self.tier_name_ids[i] = name;
            self.tier.name_ids[i] = key;
        }
    }

    // The new ids of the name that had display id `id` before `compact_names` emptied the tables.
    fn renamed(&mut self, old: &[GString], new_ids: &mut [u32], id: u32) -> (u32, u32) {
        if id == 0 || id as usize > old.len() {
            return (0, 0);
        }
        if new_ids[id as usize] == 0 {
            new_ids[id as usize] = self.intern_name(&old[id as usize - 1]).0;
        }
        let now = new_ids[id as usize];
        (now, now.checked_sub(1).map_or(0, |at| self.display_keys[at as usize]))
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
        let role = if self.turrets.civilians.contains(&m.body_id) {
            crate::rows::ROLE_CIVILIAN
        } else {
            crate::rows::ROLE_COMBAT
        };
        let (name_id, key_id) = self.intern_name(&name);
        Attrs {
            role,
            faction_ix: self.faction_index(faction),
            name_id,
            key_id,
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
// A wall clock read in laps, for the readouts.
struct PartClock(std::time::Instant);

impl PartClock {
    fn new() -> Self {
        Self(std::time::Instant::now())
    }

    // Microseconds since the last lap.
    fn lap(&mut self) -> i64 {
        let now = std::time::Instant::now();
        let us = now.duration_since(self.0).as_micros() as i64;
        self.0 = now;
        us
    }
}

fn clamp01(v: f64) -> f64 {
    v.clamp(0.0, 1.0)
}

impl RowsSnapshot for Rows {
    // The first `count` rows as the `VarArray` `snapshot` documents (forwards and ups from the bases), `node_count` of
    // them nodes, with their names and faction names as the caller made them.
    fn to_array(
        &self,
        names: PackedStringArray,
        faction_names: Array<StringName>,
        count: usize,
        node_count: usize,
    ) -> VarArray {
        let count = count.min(self.body_ids.len());
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
        out.push(&names.to_variant());
        out.push(&PackedInt64Array::from(&self.hull_ids[..count]).to_variant());
        out.push(&(node_count.min(count) as i64).to_variant());
        out.push(&statics.to_variant());
        out
    }
}

// The scan's two columns of engine strings as `snapshot` last made them, with the rows' columns they came from.
#[derive(Default)]
struct ScanCache {
    valid: bool,
    faction_ix: Vec<u32>,
    name_ids: Vec<u32>,
    factions: Option<Array<StringName>>,
    names: PackedStringArray,
    builds: i64,
}

// How many names the tables may hold beyond twice the bodies before the unused ones are dropped.
const NAME_SLACK: usize = 256;

// The factions' names for a column of faction indices.
fn faction_names(faction_ix: &[u32], factions: &[StringName]) -> Array<StringName> {
    faction_ix
        .iter()
        .map(|&f| factions[f as usize].clone())
        .collect()
}

// The display names for a column of name ids.
fn names_of(name_ids: &[u32], display: &[GString]) -> PackedStringArray {
    name_ids
        .iter()
        .map(|&id| {
            id.checked_sub(1)
                .and_then(|at| display.get(at as usize))
                .cloned()
                .unwrap_or_default()
        })
        .collect()
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

// M4-T20: what the weapon rows ask the core beyond its columns.
impl ScsSimCore {
    /// Whether `body_id` was hidden, shown or lost its hull since its row was last read (its row may be stale).
    pub fn is_touched(&self, body_id: i64) -> bool {
        self.touched.contains(&body_id)
    }

    /// Whether a resync found `body_id` parked since the tick's first sync (its row is still there until the next one).
    pub fn parked_since_sync(&self, body_id: i64) -> bool {
        self.parked_since_sync.contains(&body_id)
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
    /// A hull's points changed (`Damageable.damaged`, a heal): its column reads `clamp(hp / max_hp)` from the next sync.
    #[func]
    fn note_hull(&mut self, body_id: i64, hp: f64, max_hp: f64) {
        let fraction = clamp01(hp / max_hp);
        // A tier row reads the hull its body's `Damageable` has left (fix round 2: here, not through a watch of its own).
        if let Some(i) = self.tier.index_of(body_id) {
            self.tier.hull_fraction[i] = fraction;
        }
        self.for_attrs_of(body_id, |a| {
            if a.health.is_some() {
                a.hull_fraction = fraction;
            }
        });
    }

    /// A ship's selection changed (`TargetingController.target_changed`): its column reads it from the next sync.
    #[func]
    fn note_selection(&mut self, body_id: i64, selected_id: i64) {
        let target = if selected_id != 0 { selected_id } else { -1 };
        self.latest_target.insert(body_id, target);
        self.for_attrs_of(body_id, |a| {
            if a.targeting.is_some() {
                a.target_id = target;
            }
        });
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

    /// Runs the selection check of body `body_id`'s AI targeting controller here: its
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

    /// What the player's radar shows (M4-T23): every row with a marker (a targetable in play, not parked since the sync) or
    /// in the low-attention tier, not body `own_body`, within `sensor_range` of `own_position` or its own broadcast reach, as `[marker ids,
    /// positions, faction indices (into `factions`), reach]` in row order. One pass over the rows, near and tier alike, instead of a walk of the
    /// targetable nodes each frame; the positions are the tick's rows.
    #[func]
    fn radar_contacts(&self, own_position: Vector3, own_body: i64, sensor_range: f64) -> VarArray {
        let r = &self.rows;
        let mut ids: Vec<i64> = Vec::new();
        let mut positions: Vec<Vector3> = Vec::new();
        let mut faction_ix: Vec<i32> = Vec::new();
        let mut reach: Vec<f64> = Vec::new();
        for i in 0..r.body_ids.len() {
            let marked =
                r.flags[i] & FLAG_TIER != 0 || (r.ids[i] != r.body_ids[i] && !r.is_static[i]);
            if !marked
                || r.body_ids[i] == own_body
                || self.parked_since_sync.contains(&r.body_ids[i])
            {
                continue;
            }
            let p = r.positions[i];
            let dx = f64::from(p.x) - f64::from(own_position.x);
            let dy = f64::from(p.y) - f64::from(own_position.y);
            let dz = f64::from(p.z) - f64::from(own_position.z);
            if (dx * dx + dy * dy + dz * dz).sqrt() > sensor_range.max(r.reach[i]) {
                continue;
            }
            ids.push(r.ids[i]);
            positions.push(p);
            faction_ix.push(r.faction_ix[i] as i32);
            reach.push(r.reach[i]);
        }
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(positions.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(faction_ix.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(reach.as_slice()).to_variant());
        out
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
            if self.rows.flags[r as usize] & FLAG_TIER != 0 {
                continue; // in the low-attention tier (M4-T21): its controller is parked with it
            }
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
