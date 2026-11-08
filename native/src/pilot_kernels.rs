// The AI pilot's per-contact loops on the core's rows (M4-T16, docs/architecture.md 17.13): avoidance, the fire lane and
// the context lists, one call per thinking ship. The maths is `kernels::pilot`; this class only binds the rows (the core's,
// or a perception's own lists, `PilotRows`) and hands the answers over. `AiContext` keeps its own GDScript loop.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::kernels::pilot::{self, Lists, Ship};
use crate::rows::Rows;
use crate::sim_core::ScsSimCore;

// `BodyKind` values of the rows that are obstacles (src/ai/body_kind.gd).
const KIND_MINE: u8 = 4;
const KIND_STATIC: u8 = 5;

/// One ship's avoidance, fire lane and context lists over the rows the scan handed it out of, by row index, so a think
/// costs one call per question instead of a GDScript loop over its contacts. Reads the core's rows (`attach_core`) or rows
/// loaded from arrays (`load`); never calls the engine or `Factions`: the caller passes the ship's relation to each faction
/// of the table and its tie-break.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsPilotKernels {
    base: Base<RefCounted>,
    core: Option<Gd<ScsSimCore>>,
    own: Rows,
    lists: Lists,
}

#[godot_api]
impl ScsPilotKernels {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Reads the core's rows from now on (their order is the scan's, so the scan's indices name them).
    #[func]
    fn attach_core(&mut self, core: Gd<ScsSimCore>) -> bool {
        self.own = Rows::default();
        self.core = Some(core);
        true
    }

    /// Takes rows from arrays instead of the core (the differential tests): ids, positions, velocities, radii, `BodyKind`
    /// values, faction indices and rigid-body flags, one entry per row. Returns false, after logging why, when the arrays
    /// do not line up; the kernels then hold no rows, so every row index names nothing.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn load(
        &mut self,
        ids: PackedInt64Array,
        positions: PackedVector3Array,
        velocities: PackedVector3Array,
        radii: PackedFloat64Array,
        kinds: PackedByteArray,
        factions: PackedInt32Array,
        is_ship: PackedByteArray,
    ) -> bool {
        self.core = None;
        self.own = Rows::default();
        let n = ids.len();
        let lined_up = positions.len() == n
            && velocities.len() == n
            && radii.len() == n
            && kinds.len() == n
            && factions.len() == n
            && is_ship.len() == n;
        if !lined_up {
            godot_error!(
                "ScsPilotKernels.load: array lengths differ (ids {n}, positions {}, velocities {}, radii {}, kinds {}, \
                 factions {}, is_ship {}); no rows are kept",
                positions.len(),
                velocities.len(),
                radii.len(),
                kinds.len(),
                factions.len(),
                is_ship.len()
            );
            return false;
        }
        let own = &mut self.own;
        own.ids = ids.as_slice().to_vec();
        own.body_ids = own.ids.clone();
        own.positions = positions.as_slice().to_vec();
        own.velocities = velocities.as_slice().to_vec();
        own.radii = radii.as_slice().to_vec();
        own.kinds = kinds.as_slice().to_vec();
        own.faction_ix = factions
            .as_slice()
            .iter()
            .map(|&f| u32::try_from(f).unwrap_or(u32::MAX))
            .collect();
        own.rigid = is_ship.as_slice().iter().map(|&b| b == 1).collect();
        own.is_static = own
            .kinds
            .iter()
            .map(|&k| k == KIND_MINE || k == KIND_STATIC)
            .collect();
        own.is_mine = own.kinds.iter().map(|&k| k == KIND_MINE).collect();
        own.node_count = n;
        true
    }

    /// `AvoidanceMath.filter` for one ship over the rows `contacts` (but `exempt_id`, a rammer's target) and `statics`:
    /// the filtered velocity in x, y and z, and 1 in w when the dodge is urgent (0 otherwise). `tie_hash` is
    /// `hash(seed)`, the tie-break the GDScript computes.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn avoid(
        &self,
        contacts: PackedInt32Array,
        statics: PackedInt32Array,
        exempt_id: i64,
        position: Vector3,
        velocity: Vector3,
        radius: f64,
        v_des: Vector3,
        a_retro: f64,
        rate_max: Vector3,
        a_rcs: Vector2,
        tie_hash: i64,
    ) -> Vector4 {
        let ship = Ship {
            position,
            velocity,
            radius,
            a_retro,
            rate_max_x: f64::from(rate_max.x),
            rate_max_y: f64::from(rate_max.y),
            a_rcs_x: f64::from(a_rcs.x),
            a_rcs_y: f64::from(a_rcs.y),
            tie_hash,
        };
        let guard = self.core.as_ref().map(|c| c.bind());
        let rows = rows_of(&guard, &self.own);
        let out = pilot::avoid(
            rows,
            &ship,
            contacts.as_slice(),
            statics.as_slice(),
            exempt_id,
            v_des,
        );
        Vector4::new(
            out.v_des.x,
            out.v_des.y,
            out.v_des.z,
            if out.urgent { 1.0 } else { 0.0 },
        )
    }

    /// `FireLane.clear` for one shot over the rows `contacts`; `relations` holds the shooter's `Factions.Relation` to each
    /// faction of the table, in its order.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn fire_lane(
        &self,
        contacts: PackedInt32Array,
        relations: PackedByteArray,
        position: Vector3,
        aim_dir: Vector3,
        range_m: f64,
        target_id: i64,
        friendly_fire: bool,
    ) -> bool {
        let guard = self.core.as_ref().map(|c| c.bind());
        let rows = rows_of(&guard, &self.own);
        pilot::fire_lane(
            rows,
            relations.as_slice(),
            contacts.as_slice(),
            position,
            aim_dir,
            range_m,
            target_id,
            friendly_fire,
        )
    }

    /// The tie's seeded turn for `tie_hash` (`hash(seed)`), rad: what the differential test compares with the engine's
    /// `deg_to_rad`.
    #[func]
    fn tie_angle(tie_hash: i64) -> f64 {
        pilot::tie_angle(tie_hash)
    }

    /// `AiContext.refresh`'s lists over the rows `contacts`, as `[hostiles (places in the contact list), offsets, ranges,
    /// friendly ids (self_id first unless 0), the leader's place or -1]`. Kept for T17's native brains and the
    /// differential test: the GDScript facade stays on its own loop, which is faster than taking these arrays apart.
    #[func]
    fn context_lists(
        &mut self,
        contacts: PackedInt32Array,
        relations: PackedByteArray,
        position: Vector3,
        self_id: i64,
        leader_id: i64,
    ) -> VarArray {
        let Self {
            core, own, lists, ..
        } = self;
        let guard = core.as_ref().map(|c| c.bind());
        let rows = rows_of(&guard, own);
        pilot::context_lists(
            rows,
            relations.as_slice(),
            contacts.as_slice(),
            position,
            self_id,
            leader_id,
            lists,
        );
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(lists.hostiles.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(lists.offsets.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(lists.ranges.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(lists.friendly_ids.as_slice()).to_variant());
        out.push(&lists.leader.to_variant());
        out
    }
}

// The rows the kernels read: the core's when attached, else the class's own load.
fn rows_of<'a>(core: &'a Option<GdRef<'a, ScsSimCore>>, own: &'a Rows) -> &'a Rows {
    match core {
        Some(c) => &c.rows,
        None => own,
    }
}
