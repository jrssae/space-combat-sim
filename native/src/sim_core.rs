// The native simulation core (M4-T15, docs/architecture.md 17.13): one store of rows for every simulated entity, filled
// from the engine at the tick's sync points and read by every native kernel.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::collections::{HashMap, HashSet};

use godot::classes::{Node, Node3D, Object, RigidBody3D};
use godot::prelude::*;

// `BodyKind` (src/ai/body_kind.gd) in value order, then the projectile kinds the core adds (`SimCore.KIND_*`).
const KIND_NAMES: [&str; 9] = [
    "ship", "capital", "turret", "missile", "mine", "static", "prop", "bolt", "beam",
];
pub const KIND_SHIP: u8 = 0;
pub const KIND_MINE: u8 = 4;
pub const KIND_STATIC: u8 = 5;
pub const KIND_BOLT: u8 = 7;
pub const KIND_BEAM: u8 = 8;

/// Row flags: a rigid body (the scan's `is_ship`), an active hull (`Damageable.is_active()`: the sweep and the rams see
/// it), a hull at all, and a row added after the tick's first sync (a ship back from the pool).
pub const FLAG_RIGID: u32 = 1;
pub const FLAG_HULL: u32 = 2;
pub const FLAG_HULL_ACTIVE: u32 = 4;
pub const FLAG_LATE: u32 = 8;

// The script properties the core reads, as StringNames made once: a name built per read costs as much as the read.
struct Names {
    velocity: StringName,
    last_step: StringName,
    faction: StringName,
    shooter_id: StringName,
    kind: StringName,
    hit_radius_m: StringName,
    bounding_radius: StringName,
    display_name: StringName,
    hull: StringName,
    destroyed: StringName,
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
            bounding_radius: StringName::from("bounding_radius"),
            display_name: StringName::from("display_name"),
            hull: StringName::from("hull"),
            destroyed: StringName::from("destroyed"),
        }
    }
}

// What a body's components say about it, read when it turns active (or is touched), not every tick.
#[derive(Clone)]
struct Attrs {
    faction_ix: u32,
    name: GString,
    kind: u8,
    radius: f64,
    destroyed: bool,
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
}

/// The scan's rows, column by column: the bodies in registry order (active markers, then active hulls with no active
/// marker), the static rows, then any row added after the tick's first sync. Read by the kernels through `bind()`.
#[derive(Default)]
pub struct Rows {
    pub body_ids: Vec<i64>,
    pub ids: Vec<i64>,
    pub faction_ix: Vec<u32>,
    pub positions: Vec<Vector3>,
    pub velocities: Vec<Vector3>,
    pub bases: Vec<Basis>,
    pub angular: Vec<Vector3>,
    pub radii: Vec<f64>,
    pub kinds: Vec<u8>,
    pub flags: Vec<u32>,
    pub names: Vec<GString>,
    pub hull_ids: Vec<i64>,
    pub handles: Vec<i64>,
    // Derived per row: a rigid body, a rock or mine, a mine (what the contact field asks per candidate).
    pub rigid: Vec<bool>,
    pub is_static: Vec<bool>,
    pub is_mine: Vec<bool>,
    pub node_count: usize,
}

/// The bolts in flight, column by column, in `projectiles` group order.
#[derive(Default)]
pub struct Bolts {
    pub ids: Vec<i64>,
    pub positions: Vec<Vector3>,
    pub velocities: Vec<Vector3>,
    pub last_steps: Vec<Vector3>,
    pub faction_ix: Vec<u32>,
    pub shooters: Vec<i64>,
    pub kinds: Vec<u8>,
    pub radii: Vec<f64>,
}

// What one read of a body gives: its pose, motion and flags.
struct Read {
    position: Vector3,
    basis: Basis,
    velocity: Vector3,
    angular: Vector3,
    flags: u32,
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
    /// The rows with an active hull, in the `damageable` group's order: what the sweep and the ram phase walk.
    pub hull_rows: Vec<u32>,
    row_of_id: HashMap<i64, u32>,
    row_of_handle: HashMap<i64, u32>,
    data: Vec<DataRow>,
    next_data_handle: i64,
    sync_reads: i64,
    kernel_reads: i64,
    last_calls: [i64; 2],
    tick: i64,
    bolt_tick: i64,
    open: bool,
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
            self.markers.push(Member {
                key,
                rigid: body.clone().try_cast::<RigidBody3D>().ok(),
                hull,
                body,
                body_id,
                marker: Some(marker),
                attrs,
                active_at,
                generation,
                hull_rank,
                slot,
            });
        }
        for (rank, hull) in damageables.iter_shared().enumerate() {
            let Some(body) = hull.get_parent().and_then(|p| p.try_cast::<Node3D>().ok()) else {
                continue;
            };
            let key = hull.instance_id().to_i64();
            let (attrs, active_at) = known.remove(&key).unwrap_or((None, 0));
            let (slot, generation) = self.slot_for(key);
            self.hulls.push(Member {
                key,
                rigid: body.clone().try_cast::<RigidBody3D>().ok(),
                body_id: body.instance_id().to_i64(),
                body,
                marker: None,
                hull: Some(hull),
                attrs,
                active_at,
                generation,
                hull_rank: rank as i64,
                slot,
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
        self.open = true;
        self.tick = tick;
        self.syncs += 1;
        let now = self.syncs;
        let mut rows = std::mem::take(&mut self.rows);
        rows.clear();
        self.seen.clear();
        let mut markers = std::mem::take(&mut self.markers);
        for m in markers.iter_mut() {
            self.sync_reads += 1;
            if !marker_active(m) || !self.seen.insert(m.body_id) {
                continue;
            }
            self.fresh_attrs(m, now);
            self.push_member(&mut rows, m);
        }
        self.markers = markers;
        let mut hulls = std::mem::take(&mut self.hulls);
        for m in hulls.iter_mut() {
            self.sync_reads += 1;
            let names = self.names.get_or_insert_with(Names::new);
            if self.seen.contains(&m.body_id) || !hull_only_active(m, names) {
                continue;
            }
            self.sync_reads += 1;
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
            rows.names.push(GString::new());
            rows.hull_ids.push(0);
            rows.handles.push(0);
            rows.rigid.push(false);
            rows.is_static.push(is_static_kind(self.static_kinds[s]));
            rows.is_mine.push(self.static_kinds[s] == KIND_MINE);
        }
        self.rows = rows;
        self.touched.clear();
        self.index_rows();
        self.read_bolts(projectiles, delta, true, false);
        self.rows.node_count as i64
    }

    /// The tick's later sync point (the hit resolver's, after the bolts moved): reads the bolts again (their positions
    /// and last steps; the velocities are the first sync's, for the scan), and the bodies that were touched since the
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
        bolts.clear();
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
                self.sync_reads += 4;
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
                let bolt = Bolt {
                    node: node3d,
                    faction_ix: self.faction_index(faction),
                    shooter,
                    kind,
                    radius,
                    velocity: launch_velocity,
                    plain: kind == KIND_BOLT,
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
            } else if bolt.plain {
                // `Projectile._physics_process`: `last_step = velocity * delta`, the float rounded to 32 bits first.
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
        }
        self.bolt_known.retain(|id, _| live.contains(id));
        self.bolts = bolts;
        self.bolts.ids.len() as i64
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
        for i in 0..self.rows.positions.len() {
            if self.rows.handles[i] != 0 {
                self.rows.positions[i] = add(self.rows.positions[i], offset);
            }
        }
        for p in self.bolts.positions.iter_mut() {
            *p = add(*p, offset);
        }
    }

    /// Engine calls of the last closed tick: `[sync, kernels]`. The sync's grow with the bodies and bolts; the kernels'
    /// must stay 0.
    #[func]
    pub fn engine_calls(&self) -> PackedInt64Array {
        PackedInt64Array::from(&self.last_calls[..])
    }

    /// Engine calls so far in the open tick: `[sync, kernels]`.
    #[func]
    fn engine_calls_open(&self) -> PackedInt64Array {
        PackedInt64Array::from(&[self.sync_reads, self.kernel_reads][..])
    }

    /// Counts an engine call a kernel had to make (the flight step's fallback to the physics server).
    #[func]
    pub fn note_kernel_read(&mut self, calls: i64) {
        self.kernel_reads += calls;
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
            .map_or_else(GString::new, |r| self.rows.names[r].clone())
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
        self.rows
            .to_array(self.rows.node_count, self.rows.node_count, &self.factions)
    }

    /// `snapshot` with the static rows too (the registry's face, M4-T09), late rows left out.
    #[func]
    pub fn snapshot_all(&self) -> VarArray {
        let count = self.rows.node_count + self.static_ids.len();
        self.rows
            .to_array(count, self.rows.node_count, &self.factions)
    }

    /// The broadcast scan, `ContactScan.from_broadcasters` for the markers `ids` (the broadcasters, in their order): a row
    /// for each one that is active, read now, as `snapshot` gives rows, plus a last entry: the positions in `ids` that gave
    /// a row. A body's second marker gets its own row here, as it does there.
    #[func]
    pub fn select(&mut self, ids: PackedInt64Array) -> VarArray {
        let mut rows = Rows::default();
        let mut found: Vec<i32> = Vec::new();
        let mut markers = std::mem::take(&mut self.markers);
        for (j, id) in ids.as_slice().iter().enumerate() {
            let Some(&at) = self.marker_at.get(id) else {
                continue;
            };
            let m = &mut markers[at];
            self.sync_reads += 1;
            if !marker_active(m) {
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
        rows.node_count = rows.body_ids.len();
        let mut out = rows.to_array(rows.node_count, rows.node_count, &self.factions);
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

    /// The bolts as `[ids, starts, ends, radii, kinds, beams]`: a bolt's segment this tick (`end - last_step` to `end`),
    /// its hit radius, its kind (`SimCore.KIND_*`) and which bolts are beams.
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
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(b.ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(starts.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(b.positions.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(b.radii.as_slice()).to_variant());
        out.push(&PackedByteArray::from(b.kinds.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(beams.as_slice()).to_variant());
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
        let get = |key: &str| row.get(key);
        self.data.push(DataRow {
            handle,
            kind: get("kind").map_or(KIND_SHIP, |v| v.to::<i64>() as u8),
            id: get("id").map_or(0, |v| v.to::<i64>()),
            faction: get("faction").map_or_else(StringName::default, |v| v.to::<StringName>()),
            radius: get("radius").map_or(0.0, |v| v.to::<f64>()),
            flags: get("flags").map_or(0, |v| v.to::<i64>()),
            position: get("position").map_or(Vector3::ZERO, |v| v.to::<Vector3>()),
            velocity: get("velocity").map_or(Vector3::ZERO, |v| v.to::<Vector3>()),
            basis: get("basis").map_or(Basis::IDENTITY, |v| v.to::<Basis>()),
            angular: get("angular").map_or(Vector3::ZERO, |v| v.to::<Vector3>()),
            command: get("command").map_or_else(Vec::new, |v| {
                v.to::<PackedFloat64Array>().as_slice().to_vec()
            }),
            state: get("state").map_or_else(Vec::new, |v| {
                v.to::<PackedFloat64Array>().as_slice().to_vec()
            }),
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
        self.sync_reads += 2;
        let xf = m.body.get_global_transform();
        let (velocity, angular) = match (&m.rigid, &m.marker) {
            (Some(rigid), _) => {
                self.sync_reads += 1;
                (rigid.get_linear_velocity(), rigid.get_angular_velocity())
            }
            (None, Some(marker)) => (
                marker
                    .get(&self.names.get_or_insert_with(Names::new).velocity)
                    .try_to::<Vector3>()
                    .unwrap_or(Vector3::ZERO),
                Vector3::ZERO,
            ),
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
        Read {
            position: xf.origin,
            basis: xf.basis,
            velocity,
            angular,
            flags,
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
        rows.names.push(attrs.name.clone());
        rows.hull_ids
            .push(m.hull.as_ref().map_or(0, |h| h.instance_id().to_i64()));
        rows.handles.push(Self::handle(m));
        rows.rigid.push(m.rigid.is_some());
        rows.is_static.push(is_static_kind(attrs.kind));
        rows.is_mine.push(attrs.kind == KIND_MINE);
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
        rows.names[r] = attrs.name.clone();
        rows.is_static[r] = is_static_kind(attrs.kind);
        rows.is_mine[r] = attrs.kind == KIND_MINE;
    }

    // Reads the bodies touched since the first sync again: a row in place, or a new row at the end for a body that turned
    // active since (a ship back from the pool).
    fn resync_touched(&mut self) {
        let now = self.syncs;
        let touched: Vec<i64> = self.touched.iter().copied().collect();
        let mut markers = std::mem::take(&mut self.markers);
        let mut hulls = std::mem::take(&mut self.hulls);
        let mut rows = std::mem::take(&mut self.rows);
        for m in markers.iter_mut().chain(hulls.iter_mut()) {
            if !touched.contains(&m.body_id) {
                continue;
            }
            self.sync_reads += 1;
            let active = if m.marker.is_some() {
                marker_active(m)
            } else {
                hull_only_active(m, self.names.get_or_insert_with(Names::new))
            };
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

    // Rebuilds the lookups over the rows: by body id, by handle, and the hull rows in the resolvers' order.
    fn index_rows(&mut self) {
        self.row_of_id.clear();
        self.row_of_handle.clear();
        let mut hull_rows: Vec<(i64, u32)> = Vec::new();
        let ranks: HashMap<i64, i64> = self
            .markers
            .iter()
            .chain(self.hulls.iter())
            .map(|m| (m.body_id, m.hull_rank))
            .collect();
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
        self.last_calls = [self.sync_reads, self.kernel_reads];
        self.sync_reads = 0;
        self.kernel_reads = 0;
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
        self.sync_reads += 4;
        let names = self.names.get_or_insert_with(Names::new);
        let hull = m.hull.as_ref().filter(|h| h.is_instance_valid());
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
        Attrs {
            faction_ix: self.faction_index(faction),
            name,
            kind,
            radius,
            destroyed,
        }
    }
}

impl Rows {
    fn clear(&mut self) {
        self.body_ids.clear();
        self.ids.clear();
        self.faction_ix.clear();
        self.positions.clear();
        self.velocities.clear();
        self.bases.clear();
        self.angular.clear();
        self.radii.clear();
        self.kinds.clear();
        self.flags.clear();
        self.names.clear();
        self.hull_ids.clear();
        self.handles.clear();
        self.rigid.clear();
        self.is_static.clear();
        self.is_mine.clear();
        self.node_count = 0;
    }

    // The first `count` rows as the `VarArray` `snapshot` documents (forwards and ups from the bases), `node_count` of
    // them nodes.
    fn to_array(&self, count: usize, node_count: usize, factions: &[StringName]) -> VarArray {
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
        out.push(&PackedStringArray::from(&self.names[..count]).to_variant());
        out.push(&PackedInt64Array::from(&self.hull_ids[..count]).to_variant());
        out.push(&(node_count.min(count) as i64).to_variant());
        out.push(&statics.to_variant());
        out
    }
}

impl Bolts {
    fn clear(&mut self) {
        self.ids.clear();
        self.positions.clear();
        self.velocities.clear();
        self.last_steps.clear();
        self.faction_ix.clear();
        self.shooters.clear();
        self.kinds.clear();
        self.radii.clear();
    }
}

// `Targetable.is_active()` for member `m`'s marker (in the tree, visible, its body processing), and both still exist.
fn marker_active(m: &Member) -> bool {
    let Some(marker) = m.marker.as_ref() else {
        return false;
    };
    marker.is_instance_valid()
        && m.body.is_instance_valid()
        && marker.is_inside_tree()
        && marker.is_visible_in_tree()
        && m.body.can_process()
}

// `Damageable.is_active()` for a member with no active marker: the hull in the tree, the body visible and processing, the
// hull not destroyed (a script read, last).
fn hull_only_active(m: &Member, names: &Names) -> bool {
    if !m.body.is_instance_valid() {
        return false;
    }
    let Some(hull) = m.hull.as_ref() else {
        return false;
    };
    hull.is_instance_valid()
        && hull.is_inside_tree()
        && m.body.is_visible_in_tree()
        && m.body.can_process()
        && !destroyed(hull, names)
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
