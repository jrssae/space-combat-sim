// The bodies the AI's contact scan sees, known once and read natively each tick (M4-T09, docs/architecture.md 17.8).
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::collections::{HashMap, HashSet};

use godot::classes::{Node, Node3D, Object, RigidBody3D};
use godot::prelude::*;

// `BodyKind` (src/ai/body_kind.gd): the names in value order.
const KIND_NAMES: [&str; 7] = [
    "ship", "capital", "turret", "missile", "mine", "static", "prop",
];
const KIND_SHIP: u8 = 0;

// What a body's components say about it, read when it turns active (or is touched), not every tick.
#[derive(Clone)]
struct Attrs {
    faction: StringName,
    name: GString,
    kind: u8,
    radius: f64,
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
    // The refresh this member was last in the scan.
    active_at: u64,
}

/// The scan's bodies, registered from the `targetable` and `damageable` groups when they change (`set_members`) and read
/// by one `refresh` a tick: which are active, where they are and how they move, through the engine's own getters so every
/// value is the one GDScript reads. Faction, name, kind and radius are read when a body turns active or is `touch`ed.
/// The scan it builds (`snapshot`) is `ContactScan.from_tree`'s bit for bit: the same rows in the same order, then the
/// node-less static rows. Hull and selection are left to the facade, which reads them when a contact is first handed out.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsBodyRegistry {
    base: Base<RefCounted>,
    markers: Vec<Member>,
    hulls: Vec<Member>,
    // A marker's instance id -> its place in `markers` (the broadcasters' lookup).
    marker_at: HashMap<i64, usize>,
    touched: HashSet<i64>,
    seen: HashSet<i64>,
    refreshes: u64,
    attribute_reads: i64,
    static_ids: Vec<i64>,
    static_positions: Vec<Vector3>,
    static_radii: Vec<f64>,
    static_factions: Vec<StringName>,
    static_kinds: Vec<u8>,
    // The latest snapshot.
    rows: Rows,
}

// A scan's rows, column by column, as `ContactScan` keeps them.
#[derive(Default)]
struct Rows {
    body_ids: Vec<i64>,
    ids: Vec<i64>,
    factions: Vec<StringName>,
    positions: Vec<Vector3>,
    velocities: Vec<Vector3>,
    forwards: Vec<Vector3>,
    ups: Vec<Vector3>,
    radii: Vec<f64>,
    is_ship: Vec<u8>,
    kinds: Vec<u8>,
    names: Vec<GString>,
    hull_ids: Vec<i64>,
    node_count: usize,
}

#[godot_api]
impl ScsBodyRegistry {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Takes the tree's markers and hulls, each list in group (tree) order. What was known of a body stays known.
    #[func]
    fn set_members(&mut self, targetables: Array<Gd<Node>>, damageables: Array<Gd<Node>>) {
        let mut known: HashMap<i64, (Option<Attrs>, u64)> = HashMap::new();
        for m in self.markers.drain(..).chain(self.hulls.drain(..)) {
            known.insert(m.key, (m.attrs, m.active_at));
        }
        self.marker_at.clear();
        // A body's hull is the first `Damageable` under it in group order, which is child order: what both the tree
        // gather's group lookup and `Damageable.of(body)` (the broadcast scan's) take.
        let mut first_hull: HashMap<i64, Gd<Node>> = HashMap::new();
        for hull in damageables.iter_shared() {
            if let Some(parent) = hull.get_parent() {
                first_hull
                    .entry(parent.instance_id().to_i64())
                    .or_insert(hull);
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
            self.marker_at.insert(key, self.markers.len());
            self.markers.push(Member {
                key,
                rigid: body.clone().try_cast::<RigidBody3D>().ok(),
                hull: first_hull.get(&body_id).cloned(),
                body,
                body_id,
                marker: Some(marker),
                attrs,
                active_at,
            });
        }
        for hull in damageables.iter_shared() {
            let Some(body) = hull.get_parent().and_then(|p| p.try_cast::<Node3D>().ok()) else {
                continue;
            };
            let key = hull.instance_id().to_i64();
            let (attrs, active_at) = known.remove(&key).unwrap_or((None, 0));
            self.hulls.push(Member {
                key,
                rigid: body.clone().try_cast::<RigidBody3D>().ok(),
                body_id: body.instance_id().to_i64(),
                body,
                marker: None,
                hull: Some(hull),
                attrs,
                active_at,
            });
        }
    }

    /// Takes the node-less static rows (rocks by RID, mines): ids, positions, radii, factions and kinds, in order. Returns
    /// false, after logging why, when the arrays do not line up; the registry then holds none.
    #[func]
    fn set_statics(
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
                "ScsBodyRegistry.set_statics: array lengths differ (ids {n}, positions {}, radii {}, factions {}, kinds {}); \
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
        self.static_factions = factions.iter_shared().collect();
        self.static_kinds = kinds.as_slice().to_vec();
        true
    }

    /// Marks a body whose faction, name, kind or radius may have changed: they are read again at the next refresh.
    #[func]
    fn touch(&mut self, body_id: i64) {
        self.touched.insert(body_id);
    }

    /// Forgets every body's faction, name, kind and radius, so the next refresh reads them all again.
    #[func]
    fn forget_attributes(&mut self) {
        for m in self.markers.iter_mut().chain(self.hulls.iter_mut()) {
            m.attrs = None;
        }
    }

    /// How many times a body's attributes were read (the work count: once per activation, not per tick).
    #[func]
    fn attribute_reads(&self) -> i64 {
        self.attribute_reads
    }

    /// How many refreshes ran.
    #[func]
    fn refreshes(&self) -> i64 {
        self.refreshes as i64
    }

    /// Builds this tick's scan: the active marked bodies in marker order, then the active hulls with no active marker,
    /// then the static rows. Returns the row count.
    #[func]
    fn refresh(&mut self) -> i64 {
        self.refreshes += 1;
        let now = self.refreshes;
        let mut rows = std::mem::take(&mut self.rows);
        rows.clear();
        self.seen.clear();
        let mut markers = std::mem::take(&mut self.markers);
        for m in markers.iter_mut() {
            if !marker_active(m) || !self.seen.insert(m.body_id) {
                continue;
            }
            self.fresh_attrs(m, now);
            rows.push(m);
        }
        self.markers = markers;
        let mut hulls = std::mem::take(&mut self.hulls);
        for m in hulls.iter_mut() {
            if self.seen.contains(&m.body_id) || !m.body.is_instance_valid() {
                continue;
            }
            let Some(hull) = m.hull.as_ref() else {
                continue;
            };
            if !hull.is_instance_valid() {
                continue;
            }
            // `Damageable.is_active()`, the destroyed flag last since it is a script read.
            if !(hull.is_inside_tree() && m.body.is_visible_in_tree() && m.body.can_process())
                || destroyed(hull)
            {
                continue;
            }
            self.seen.insert(m.body_id);
            self.fresh_attrs(m, now);
            rows.push(m);
        }
        self.hulls = hulls;
        rows.node_count = rows.body_ids.len();
        for s in 0..self.static_ids.len() {
            rows.body_ids.push(self.static_ids[s]);
            rows.ids.push(self.static_ids[s]);
            rows.factions.push(self.static_factions[s].clone());
            rows.positions.push(self.static_positions[s]);
            rows.velocities.push(Vector3::ZERO);
            rows.forwards.push(Vector3::new(0.0, 0.0, -1.0));
            rows.ups.push(Vector3::new(0.0, 1.0, 0.0));
            rows.radii.push(self.static_radii[s]);
            rows.is_ship.push(0);
            rows.kinds.push(self.static_kinds[s]);
            rows.names.push(GString::new());
            rows.hull_ids.push(0);
        }
        self.touched.clear();
        self.rows = rows;
        self.rows.body_ids.len() as i64
    }

    /// The latest scan as `[body_ids, ids, factions, positions, velocities, forwards, ups, radii, is_ship, kinds, names,
    /// hull_ids, node_count, statics]`: the arrays `ContactScan` keeps, how many rows are nodes, and how many are rocks or
    /// mines.
    #[func]
    fn snapshot(&self) -> VarArray {
        self.rows.to_array()
    }

    /// The broadcast scan, `ContactScan.from_broadcasters` for the markers `ids` (the broadcasters, in their order): a row
    /// for each one that is active, read now, as `snapshot` gives rows, plus a last entry: the positions in `ids` that gave
    /// a row. A body's second marker gets its own row here, as it does there.
    #[func]
    fn select(&mut self, ids: PackedInt64Array) -> VarArray {
        let mut rows = Rows::default();
        let mut found: Vec<i32> = Vec::new();
        let mut markers = std::mem::take(&mut self.markers);
        for (j, id) in ids.as_slice().iter().enumerate() {
            let Some(&at) = self.marker_at.get(id) else {
                continue;
            };
            let m = &mut markers[at];
            if !marker_active(m) {
                continue;
            }
            if m.attrs.is_none() || self.touched.contains(&m.body_id) {
                m.attrs = Some(read_attrs(m));
                self.attribute_reads += 1;
            }
            rows.push(m);
            found.push(j as i32);
        }
        self.markers = markers;
        rows.node_count = rows.body_ids.len();
        let mut out = rows.to_array();
        out.push(&PackedInt32Array::from(found.as_slice()).to_variant());
        out
    }
}

impl ScsBodyRegistry {
    // Reads member `m`'s attributes again when it has just turned active or was touched, and marks it active now.
    fn fresh_attrs(&mut self, m: &mut Member, now: u64) {
        if m.attrs.is_none() || m.active_at + 1 != now || self.touched.contains(&m.body_id) {
            m.attrs = Some(read_attrs(m));
            self.attribute_reads += 1;
        }
        m.active_at = now;
    }
}

impl Rows {
    fn clear(&mut self) {
        self.body_ids.clear();
        self.ids.clear();
        self.factions.clear();
        self.positions.clear();
        self.velocities.clear();
        self.forwards.clear();
        self.ups.clear();
        self.radii.clear();
        self.is_ship.clear();
        self.kinds.clear();
        self.names.clear();
        self.hull_ids.clear();
        self.node_count = 0;
    }

    // Appends member `m`'s body as the tree gather's `_add` reads it (its attributes already read).
    fn push(&mut self, m: &Member) {
        let attrs = m
            .attrs
            .as_ref()
            .expect("attributes are read before a row is made");
        let xf = m.body.get_global_transform();
        let velocity = match (&m.rigid, &m.marker) {
            (Some(rigid), _) => rigid.get_linear_velocity(),
            (None, Some(marker)) => marker
                .get("velocity")
                .try_to::<Vector3>()
                .unwrap_or(Vector3::ZERO),
            (None, None) => Vector3::ZERO,
        };
        self.body_ids.push(m.body_id);
        self.ids
            .push(if m.marker.is_some() { m.key } else { m.body_id });
        self.factions.push(attrs.faction.clone());
        self.positions.push(xf.origin);
        self.velocities.push(velocity);
        self.forwards.push(neg(normalized(xf.basis.col_c())));
        self.ups.push(normalized(xf.basis.col_b()));
        self.radii.push(attrs.radius);
        self.is_ship.push(u8::from(m.rigid.is_some()));
        self.kinds.push(attrs.kind);
        self.names.push(attrs.name.clone());
        self.hull_ids
            .push(m.hull.as_ref().map_or(0, |h| h.instance_id().to_i64()));
    }

    // The columns as the `VarArray` `snapshot` documents.
    fn to_array(&self) -> VarArray {
        let factions: Array<StringName> = self.factions.iter().cloned().collect();
        let statics = self.kinds.iter().filter(|&&k| is_static_kind(k)).count() as i64;
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(self.body_ids.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(self.ids.as_slice()).to_variant());
        out.push(&factions.to_variant());
        out.push(&PackedVector3Array::from(self.positions.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(self.velocities.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(self.forwards.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(self.ups.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(self.radii.as_slice()).to_variant());
        out.push(&PackedByteArray::from(self.is_ship.as_slice()).to_variant());
        out.push(&PackedByteArray::from(self.kinds.as_slice()).to_variant());
        out.push(&PackedStringArray::from(self.names.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(self.hull_ids.as_slice()).to_variant());
        out.push(&(self.node_count as i64).to_variant());
        out.push(&statics.to_variant());
        out
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

// Faction, name, kind and radius as the tree gather reads them: from the marker, or from the hull when there is none.
fn read_attrs(m: &Member) -> Attrs {
    let radius = m
        .hull
        .as_ref()
        .filter(|h| h.is_instance_valid())
        .map_or(0.0, |h| {
            h.get("bounding_radius").try_to::<f64>().unwrap_or(0.0)
        });
    match &m.marker {
        Some(marker) => Attrs {
            faction: marker
                .get("faction")
                .try_to::<StringName>()
                .unwrap_or_default(),
            name: marker
                .get("display_name")
                .try_to::<GString>()
                .unwrap_or_default(),
            kind: kind_of(&marker.get("kind")),
            radius,
        },
        None => Attrs {
            faction: m
                .hull
                .as_ref()
                .map(|h| h.get("faction").try_to::<StringName>().unwrap_or_default())
                .unwrap_or_default(),
            name: GString::new(),
            kind: KIND_SHIP,
            radius,
        },
    }
}

// `BodyKind.from_variant`: a value in range, or a name in any case; anything else is a ship.
fn kind_of(value: &Variant) -> u8 {
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
fn is_static_kind(kind: u8) -> bool {
    kind == 4 || kind == 5
}

// Whether a `Damageable`'s hull is destroyed (`hull.destroyed`).
fn destroyed(hull: &Gd<Node>) -> bool {
    hull.get("hull")
        .try_to::<Gd<Object>>()
        .is_ok_and(|h| h.get("destroyed").try_to::<bool>().unwrap_or(false))
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
