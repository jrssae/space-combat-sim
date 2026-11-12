// What each AI ship perceives this tick, answered natively behind ContactScan (M4-T05b, docs/architecture.md 17.5).
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::obj::InstanceId;
use godot::prelude::*;

use crate::kernels::contact::{self, Grid, Query, View, Work};
use crate::sim_core::ScsSimCore;

// `BodyKind` values of the rows that are obstacles, not contacts (src/ai/body_kind.gd).
const KIND_MINE: u8 = 4;
const KIND_STATIC: u8 = 5;

// The field's own load of a scan (`load`), when it does not read the core.
#[derive(Default)]
struct Own {
    body_ids: Vec<i64>,
    positions: Vec<Vector3>,
    body_faction: Vec<u32>,
    is_ship: Vec<bool>,
    reach: Vec<f64>,
    factions: Vec<StringName>,
    bolt_positions: Vec<Vector3>,
    bolt_velocities: Vec<Vector3>,
    bolt_faction: Vec<u32>,
    bolt_shooters: Vec<i64>,
    // Rocks and mines (M4-T09): never contacts, found by `statics` by their surface distance.
    is_static: Vec<bool>,
    is_mine: Vec<bool>,
    radii: Vec<f64>,
}

/// One tick's bodies and bolts, handed over once by `ContactScan` (or read from the core, M4-T15), with per-ship queries
/// that return body indices in scan order. The maths repeats GDScript's: 32-bit vectors, 64-bit scalars, the engine's
/// order of operations and no fused multiply-add, so both paths give the same answers bit for bit. Never calls
/// `Factions`: the facade sends each querying faction's hostility row.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsContactField {
    base: Base<RefCounted>,
    // The core this field reads, or none: then `own` holds the field's own load.
    core: Option<Gd<ScsSimCore>>,
    own: Own,
    grid: Grid,
    query: Query,
    hostile_rows: Vec<(StringName, Vec<bool>)>,
    // Per querying faction, the factions whose mines it knows: its own and its friends' (M4-T29, Q27).
    friendly_rows: Vec<(StringName, Vec<bool>)>,
}

#[godot_api]
impl ScsContactField {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Takes this tick's scan: bodies (with each one's broadcast reach, empty when not a broadcast scan), bolts, and
    /// the grid's cell size (the sensor range). Returns false, after logging why, when the arrays do not line up; the
    /// field then holds an empty scan, so every query answers nothing and the caller can fall back to GDScript.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn load(
        &mut self,
        body_ids: PackedInt64Array,
        positions: PackedVector3Array,
        factions: Array<StringName>,
        is_ship: PackedByteArray,
        reach: PackedFloat64Array,
        bolt_positions: PackedVector3Array,
        bolt_velocities: PackedVector3Array,
        bolt_factions: Array<StringName>,
        bolt_shooters: PackedInt64Array,
        cell_m: f64,
    ) -> bool {
        let n = body_ids.len();
        let lined_up = positions.len() == n
            && factions.len() == n
            && is_ship.len() == n
            && (reach.is_empty() || reach.len() == n)
            && bolt_velocities.len() == bolt_positions.len()
            && bolt_factions.len() == bolt_positions.len()
            && bolt_shooters.len() == bolt_positions.len();
        if !lined_up {
            godot_error!(
                "ScsContactField.load: array lengths differ (bodies {n}, positions {}, factions {}, is_ship {}, reach {}, \
                 bolts {}, velocities {}, bolt factions {}, shooters {}); the scan is dropped",
                positions.len(),
                factions.len(),
                is_ship.len(),
                reach.len(),
                bolt_positions.len(),
                bolt_velocities.len(),
                bolt_factions.len(),
                bolt_shooters.len()
            );
            self.clear();
            return false;
        }
        self.clear();
        let own = &mut self.own;
        own.body_ids = body_ids.as_slice().to_vec();
        own.positions = positions.as_slice().to_vec();
        own.is_ship = is_ship.as_slice().iter().map(|&b| b == 1).collect();
        own.reach = reach.as_slice().to_vec();
        own.body_faction = factions
            .iter_shared()
            .map(|f| faction_index(&mut own.factions, f))
            .collect();
        own.bolt_positions = bolt_positions.as_slice().to_vec();
        own.bolt_velocities = bolt_velocities.as_slice().to_vec();
        own.bolt_faction = bolt_factions
            .iter_shared()
            .map(|f| faction_index(&mut own.factions, f))
            .collect();
        own.bolt_shooters = bolt_shooters.as_slice().to_vec();
        own.is_static = vec![false; n];
        own.is_mine = vec![false; n];
        self.grid.cell_m = cell_m;
        contact::sorted_cells_into(&own.positions, cell_m, &mut self.grid.cells);
        true
    }

    /// Takes this tick's scan from the core (M4-T15) instead of arrays: the field then reads the core's rows (bodies,
    /// statics and bolts, with their kinds and radii) on every query and keeps no copy; only its grid is its own. The
    /// hostility rows index the core's faction table (`factions()`).
    #[func]
    fn attach_core(&mut self, core: Gd<ScsSimCore>, cell_m: f64) -> bool {
        self.clear();
        self.grid.cell_m = cell_m;
        {
            let c = core.bind();
            let n = scan_len(&c);
            contact::sorted_cells_into(&c.rows.positions[..n], cell_m, &mut self.grid.cells);
            self.grid.max_static_radius = (0..n)
                .filter(|&i| c.rows.is_static[i])
                .map(|i| c.rows.radii[i].abs())
                .fold(0.0, f64::max);
        }
        self.core = Some(core);
        true
    }

    /// Whether the field reads the core.
    #[func]
    fn on_core(&self) -> bool {
        self.core.is_some()
    }

    /// Says which loaded bodies are rocks or mines (`BodyKind` values, M4-T09) and every body's radius: those rows are
    /// never contacts, and `statics` finds them. Returns false, after logging why, when the arrays do not match the
    /// loaded bodies; the field then holds an empty scan, as a rejected `load` does. A field on the core knows them.
    #[func]
    fn set_kinds(&mut self, kinds: PackedByteArray, radii: PackedFloat64Array) -> bool {
        if self.core.is_some() {
            return true;
        }
        let n = self.own.body_ids.len();
        if kinds.len() != n || radii.len() != n {
            godot_error!(
                "ScsContactField.set_kinds: array lengths differ (bodies {n}, kinds {}, radii {}); the scan is dropped",
                kinds.len(),
                radii.len()
            );
            self.clear();
            return false;
        }
        let own = &mut self.own;
        own.is_static = kinds
            .as_slice()
            .iter()
            .map(|&k| k == KIND_MINE || k == KIND_STATIC)
            .collect();
        own.is_mine = kinds.as_slice().iter().map(|&k| k == KIND_MINE).collect();
        own.radii = radii.as_slice().to_vec();
        self.grid.max_static_radius = (0..n)
            .filter(|&i| own.is_static[i])
            .map(|i| own.radii[i].abs())
            .fold(0.0, f64::max);
        true
    }

    /// Every faction in the scan (the core's whole table when attached), in the order `set_hostile_row` expects.
    #[func]
    fn factions(&self) -> Array<StringName> {
        match &self.core {
            Some(core) => core.bind().factions.iter().cloned().collect(),
            None => self.own.factions.iter().cloned().collect(),
        }
    }

    /// Which factions (in `factions()` order) are hostile to `faction`.
    #[func]
    fn set_hostile_row(&mut self, faction: StringName, row: PackedByteArray) {
        let flags: Vec<bool> = row.as_slice().iter().map(|&b| b == 1).collect();
        self.hostile_rows.retain(|(f, _)| *f != faction);
        self.hostile_rows.push((faction, flags));
    }

    /// Which factions (in `factions()` order) are friendly to `faction`, its own included: whose mines it knows (Q27).
    #[func]
    fn set_friendly_row(&mut self, faction: StringName, row: PackedByteArray) {
        let flags: Vec<bool> = row.as_slice().iter().map(|&b| b == 1).collect();
        self.friendly_rows.retain(|(f, _)| *f != faction);
        self.friendly_rows.push((faction, flags));
    }

    /// Whether every body in the scan still exists (a core scan's facade watches the tree instead: always true here).
    #[func]
    fn bodies_alive(&self) -> bool {
        if self.core.is_some() {
            return true;
        }
        self.own
            .body_ids
            .iter()
            .all(|&id| InstanceId::try_from_i64(id).is_some_and(|i| i.lookup_validity()))
    }

    /// Bodies the latest contact or nearest query tested against its range (the work count).
    #[func]
    fn visited(&self) -> i64 {
        self.query.visited
    }

    /// `ContactScan.contacts_for`: the bodies within `range` of `at`, not `own_body_id`, in scan order.
    #[func]
    fn contacts(&mut self, own_body_id: i64, at: Vector3, range: f64) -> PackedInt32Array {
        let guard = self.core.as_ref().map(|c| c.bind());
        let view = view_of(&guard, &self.own);
        let out = contact::contacts(
            &view,
            &mut Work {
                grid: &self.grid,
                query: &mut self.query,
            },
            own_body_id,
            at,
            range,
        );
        PackedInt32Array::from(out.as_slice())
    }

    /// `ContactScan.nearest_for` before its keeper: with `k` or fewer in range (or `k` 0 or less), all of them in scan order; otherwise
    /// the nearest `k` (equal ranges to the earlier body) plus the nearest hostile ship, in any order, then -1 to say
    /// the cut left something out.
    #[func]
    fn nearest(
        &mut self,
        own_body_id: i64,
        at: Vector3,
        faction: StringName,
        k: i64,
        range: f64,
    ) -> PackedInt32Array {
        let hostile = self
            .hostile_rows
            .iter()
            .find(|(f, _)| *f == faction)
            .map(|(_, row)| row.as_slice());
        let guard = self.core.as_ref().map(|c| c.bind());
        let view = view_of(&guard, &self.own);
        let out = contact::nearest(
            &view,
            &mut Work {
                grid: &self.grid,
                query: &mut self.query,
            },
            hostile,
            own_body_id,
            at,
            k,
            range,
        );
        PackedInt32Array::from(out.as_slice())
    }

    /// `ContactScan.statics_for`: the rocks and mines whose surface is within `range` of `at`, not `own_body_id`; with `k`
    /// or fewer, all of them, otherwise the `k` nearest by surface distance (equal ones to the earlier row); in scan order.
    /// A mine counts only when `faction`'s friendly row (`set_friendly_row`) holds its faction (Q27); with no row, none do.
    #[func]
    fn statics(
        &mut self,
        own_body_id: i64,
        at: Vector3,
        faction: StringName,
        k: i64,
        range: f64,
    ) -> PackedInt32Array {
        let friendly: &[bool] = self
            .friendly_rows
            .iter()
            .find(|(f, _)| *f == faction)
            .map_or(&[], |(_, row)| row.as_slice());
        let guard = self.core.as_ref().map(|c| c.bind());
        let view = view_of(&guard, &self.own);
        let out = contact::statics(
            &view,
            &mut Work {
                grid: &self.grid,
                query: &mut self.query,
            },
            friendly,
            own_body_id,
            at,
            k,
            range,
        );
        PackedInt32Array::from(out.as_slice())
    }

    /// `ContactScan.broadcasts_for`: the bodies beyond `near` and within their own reach, not `own_body_id`, in scan order.
    #[func]
    fn broadcasts(&self, own_body_id: i64, at: Vector3, near: f64) -> PackedInt32Array {
        let guard = self.core.as_ref().map(|c| c.bind());
        let view = view_of(&guard, &self.own);
        let out = contact::broadcasts(&view, own_body_id, at, near);
        PackedInt32Array::from(out.as_slice())
    }

    /// `ContactScan.incoming_fire`: hostile bolts, not this ship's own, that pass within 15 m in the next 2 s.
    #[func]
    fn incoming(
        &self,
        own_body_id: i64,
        at: Vector3,
        velocity: Vector3,
        faction: StringName,
    ) -> i64 {
        let Some(hostile) = self
            .hostile_rows
            .iter()
            .find(|(f, _)| *f == faction)
            .map(|(_, row)| row.as_slice())
        else {
            return 0;
        };
        let guard = self.core.as_ref().map(|c| c.bind());
        let view = view_of(&guard, &self.own);
        contact::incoming(&view, hostile, own_body_id, at, velocity)
    }
}

impl ScsContactField {
    // Forgets the whole scan, so a rejected load leaves nothing for a query to index.
    fn clear(&mut self) {
        self.core = None;
        self.own = Own::default();
        self.hostile_rows.clear();
        self.friendly_rows.clear();
        // The grid's cell list keeps its allocation for the next attach.
        let mut cells = std::mem::take(&mut self.grid.cells);
        cells.clear();
        self.grid = Grid::default();
        self.grid.cells = cells;
        self.query = Query::default();
    }
}

// The core's rows the GDScript scan holds (the bodies and statics; M4-T21): its indices never reach a tier row.
// A late row (a pool ship returned mid-tick) sits after the tier rows until the next sync, so for that tick the slice
// runs into the first tier rows by the late rows' count; the grid only holds indices below the scan length, so no query
// reads them.
fn scan_len(c: &ScsSimCore) -> usize {
    c.rows.body_ids.len() - c.rows.tier_rows
}

// The scan the queries read: the core's rows when attached, else the field's own.
fn view_of<'a>(core: &'a Option<GdRef<'a, ScsSimCore>>, own: &'a Own) -> View<'a> {
    match core {
        Some(c) => {
            let n = scan_len(c);
            View {
                body_ids: &c.rows.body_ids[..n],
                positions: &c.rows.positions[..n],
                body_faction: &c.rows.faction_ix[..n],
                is_ship: &c.rows.rigid[..n],
                reach: &c.rows.reach[..n.min(c.rows.reach.len())],
                is_static: &c.rows.is_static[..n],
                is_mine: &c.rows.is_mine[..n],
                radii: &c.rows.radii[..n],
                bolt_positions: &c.bolts.positions,
                bolt_velocities: &c.bolts.velocities,
                bolt_faction: &c.bolts.faction_ix,
                bolt_shooters: &c.bolts.shooters,
            }
        }
        None => View {
            body_ids: &own.body_ids,
            positions: &own.positions,
            body_faction: &own.body_faction,
            is_ship: &own.is_ship,
            reach: &own.reach,
            is_static: &own.is_static,
            is_mine: &own.is_mine,
            radii: &own.radii,
            bolt_positions: &own.bolt_positions,
            bolt_velocities: &own.bolt_velocities,
            bolt_faction: &own.bolt_faction,
            bolt_shooters: &own.bolt_shooters,
        },
    }
}

// The index of `faction` in `table`, added on first sight.
fn faction_index(table: &mut Vec<StringName>, faction: StringName) -> u32 {
    if let Some(at) = table.iter().position(|f| *f == faction) {
        return at as u32;
    }
    table.push(faction);
    (table.len() - 1) as u32
}
