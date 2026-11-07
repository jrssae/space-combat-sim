// The bodies the AI's contact scan sees, known once and read natively each tick (M4-T09, docs/architecture.md 17.8).
// Since M4-T15 the registration lives in the simulation core (sim_core.rs); this class is the core without its facade,
// kept for the scan's registry path (`perf_native_core` off), so the two paths can be paired in one process.
// gdext's generated constructor writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::classes::Node;
use godot::prelude::*;

use crate::sim_core::ScsSimCore;

/// The scan's bodies, registered from the `targetable` and `damageable` groups when they change (`set_members`) and read
/// by one `refresh` a tick: which are active, where they are and how they move, through the engine's own getters so every
/// value is the one GDScript reads. Faction, name, kind and radius are read when a body turns active or is `touch`ed.
/// The scan it builds (`snapshot`) is `ContactScan.from_tree`'s bit for bit: the same rows in the same order, then the
/// node-less static rows. A core (`ScsSimCore`) does the work; this class only names its registry face.
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ScsBodyRegistry {
    base: Base<RefCounted>,
    core: Gd<ScsSimCore>,
}

#[godot_api]
impl IRefCounted for ScsBodyRegistry {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base: base,
            core: ScsSimCore::new_gd(),
        }
    }
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
        self.core.bind_mut().set_members(targetables, damageables);
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
        self.core
            .bind_mut()
            .set_statics(ids, positions, radii, factions, kinds)
    }

    /// Marks a body whose faction, name, kind or radius may have changed: they are read again at the next refresh.
    #[func]
    fn touch(&mut self, body_id: i64) {
        self.core.bind_mut().touch(body_id);
    }

    /// Forgets every body's faction, name, kind and radius, so the next refresh reads them all again.
    #[func]
    fn forget_attributes(&mut self) {
        self.core.bind_mut().forget_attributes();
    }

    /// How many times a body's attributes were read (the work count: once per activation, not per tick).
    #[func]
    fn attribute_reads(&self) -> i64 {
        self.core.bind().attribute_reads()
    }

    /// How many refreshes ran.
    #[func]
    fn refreshes(&self) -> i64 {
        self.core.bind().syncs()
    }

    /// Builds this tick's scan: the active marked bodies in marker order, then the active hulls with no active marker,
    /// then the static rows. Returns the row count.
    #[func]
    fn refresh(&mut self) -> i64 {
        let mut core = self.core.bind_mut();
        let tick = core.syncs() + 1;
        core.sync_in(tick, 0.0);
        core.sync_out();
        core.row_count()
    }

    /// The latest scan as `[body_ids, ids, factions, positions, velocities, forwards, ups, radii, is_ship, kinds, names,
    /// hull_ids, node_count, statics]`: the arrays `ContactScan` keeps, how many rows are nodes, and how many are rocks or
    /// mines.
    #[func]
    fn snapshot(&self) -> VarArray {
        self.core.bind().snapshot_all()
    }

    /// The broadcast scan, `ContactScan.from_broadcasters` for the markers `ids` (the broadcasters, in their order): a row
    /// for each one that is active, read now, as `snapshot` gives rows, plus a last entry: the positions in `ids` that gave
    /// a row. A body's second marker gets its own row here, as it does there.
    #[func]
    fn select(&mut self, ids: PackedInt64Array) -> VarArray {
        self.core.bind_mut().select(ids)
    }
}
