// The hit resolver's broad phase in native code, behind HitBroadPhase (M4-T08, docs/architecture.md 17.7). The grid and
// the sweep are `sweep_cells`; this class holds the grids between calls and crosses the boundary.
// gdext's class derive writes `base: base` in the code it generates for this module.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::kernels::sweep;
use crate::sim_core::ScsSimCore;
use crate::sweep_cells::{self, CellGrid};

/// Which projectile and hull pairs pass the hit resolver's bounding-sphere test this tick, found through a grid of levels so
/// a 10 m fighter and a 1 km hull are both found cheaply (the sphere test in 32-bit vectors and 64-bit scalars). Hulls that stay put (rocks, M4-T29) can be kept in a grid of their own between calls (`keep`).
/// With the core (M4-T15) the hulls and bolts come from its rows.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsHitSweep {
    base: Base<RefCounted>,
    visited: i64,
    kept_mids: Vec<Vector3>,
    kept_reach: Vec<f64>,
    candidates: Vec<u32>,
    // The core's rows as spheres, filled per call: the hulls' and the bolts' mids and reaches.
    hull_mids: Vec<Vector3>,
    hull_reach: Vec<f64>,
    bolt_mids: Vec<Vector3>,
    bolt_reach: Vec<f64>,
    cell_grid: CellGrid,
    cell_kept: CellGrid,
}

#[godot_api]
impl ScsHitSweep {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Pairs the latest call put to the sphere test (the work count), or -1 when it refused its arrays.
    #[func]
    fn visited(&self) -> i64 {
        self.visited
    }

    #[func]
    fn pairs(
        &mut self,
        bolt_mids: PackedVector3Array,
        bolt_reach: PackedFloat64Array,
        hull_mids: PackedVector3Array,
        hull_reach: PackedFloat64Array,
    ) -> PackedInt64Array {
        self.visited = 0;
        if bolt_reach.len() != bolt_mids.len() || hull_reach.len() != hull_mids.len() {
            godot_error!(
                "ScsHitSweep.pairs: array lengths differ (bolts {} and {}, hulls {} and {}); no pairs",
                bolt_mids.len(),
                bolt_reach.len(),
                hull_mids.len(),
                hull_reach.len()
            );
            self.visited = -1;
            return PackedInt64Array::new();
        }
        let hulls = hull_mids.as_slice();
        let hull_reach = hull_reach.as_slice();
        if hulls.is_empty() || bolt_mids.is_empty() {
            return PackedInt64Array::new();
        }
        let out = self.placed_sweep(
            bolt_mids.as_slice(),
            bolt_reach.as_slice(),
            hulls,
            hull_reach,
        );
        PackedInt64Array::from(out.as_slice())
    }

    /// `pairs` over the core's rows (M4-T15): the hull rows as the resolver's spheres against the bolts' segments, keys as
    /// `bolt * hulls + hull`, ascending.
    #[func]
    fn pairs_core(&mut self, core: Gd<ScsSimCore>, delta: f64) -> PackedInt64Array {
        self.visited = 0;
        {
            let core = core.bind();
            sweep::hull_spheres(
                &core.rows,
                &core.sweep_rows,
                delta,
                &mut self.hull_mids,
                &mut self.hull_reach,
            );
            sweep::bolt_spheres(&core.bolts, &mut self.bolt_mids, &mut self.bolt_reach);
        }
        if self.hull_mids.is_empty() || self.bolt_mids.is_empty() {
            return PackedInt64Array::new();
        }
        let bolt_mids = std::mem::take(&mut self.bolt_mids);
        let bolt_reach = std::mem::take(&mut self.bolt_reach);
        let hull_mids = std::mem::take(&mut self.hull_mids);
        let hull_reach = std::mem::take(&mut self.hull_reach);
        let out = self.placed_sweep(&bolt_mids, &bolt_reach, &hull_mids, &hull_reach);
        self.bolt_mids = bolt_mids;
        self.bolt_reach = bolt_reach;
        self.hull_mids = hull_mids;
        self.hull_reach = hull_reach;
        PackedInt64Array::from(out.as_slice())
    }

    /// `kept_pairs` with the bolts read from the core's rows (M4-T15).
    #[func]
    fn kept_pairs_core(&mut self, core: Gd<ScsSimCore>) -> PackedInt64Array {
        self.visited = 0;
        sweep::bolt_spheres(
            &core.bind().bolts,
            &mut self.bolt_mids,
            &mut self.bolt_reach,
        );
        self.kept_sweep()
    }

    /// `kept_pairs` with the core's rigid hull rows as the moving spheres (M4-T15, the ram resolver's rocks): keys as
    /// `k * kept + hull`, `k` counting the rigid hulls in the core's hull order.
    #[func]
    fn kept_pairs_hulls_core(
        &mut self,
        core: Gd<ScsSimCore>,
        delta: f64,
        margin_m: f64,
    ) -> PackedInt64Array {
        self.visited = 0;
        {
            let core = core.bind();
            sweep::rigid_spheres(
                &core.rows,
                &core.hull_rows,
                delta,
                margin_m,
                &mut self.bolt_mids,
                &mut self.bolt_reach,
            );
        }
        self.kept_sweep()
    }

    /// `HitBroadPhase.keep`: holds hulls that stay put, in their own grid, for `kept_pairs`. Returns false, after logging
    /// why, when the arrays do not line up; nothing is kept then.
    #[func]
    fn keep(&mut self, hull_mids: PackedVector3Array, hull_reach: PackedFloat64Array) -> bool {
        self.kept_mids.clear();
        self.kept_reach.clear();
        if hull_reach.len() != hull_mids.len() {
            godot_error!(
                "ScsHitSweep.keep: array lengths differ (hulls {} and {}); nothing kept",
                hull_mids.len(),
                hull_reach.len()
            );
            self.cell_kept.place(&[], &[]);
            return false;
        }
        self.kept_mids = hull_mids.as_slice().to_vec();
        self.kept_reach = hull_reach.as_slice().to_vec();
        self.cell_kept.place(&self.kept_mids, &self.kept_reach);
        self.cell_kept.mark_cells();
        true
    }

    /// `HitBroadPhase.kept_pairs`: `pairs` against the kept hulls, as `bolt * kept + hull`, ascending.
    #[func]
    fn kept_pairs(
        &mut self,
        bolt_mids: PackedVector3Array,
        bolt_reach: PackedFloat64Array,
    ) -> PackedInt64Array {
        self.visited = 0;
        if bolt_reach.len() != bolt_mids.len() {
            godot_error!(
                "ScsHitSweep.kept_pairs: array lengths differ (bolts {} and {}); no pairs",
                bolt_mids.len(),
                bolt_reach.len()
            );
            self.visited = -1;
            return PackedInt64Array::new();
        }
        self.bolt_mids = bolt_mids.as_slice().to_vec();
        self.bolt_reach = bolt_reach.as_slice().to_vec();
        self.kept_sweep()
    }
}

impl ScsHitSweep {
    // The bolt spheres held in `bolt_mids` and `bolt_reach` against the kept grid.
    fn kept_sweep(&mut self) -> PackedInt64Array {
        if self.kept_mids.is_empty() || self.bolt_mids.is_empty() {
            return PackedInt64Array::new();
        }
        let out = sweep_cells::sweep(
            &self.cell_kept,
            &self.bolt_mids,
            &self.bolt_reach,
            &self.kept_mids,
            &self.kept_reach,
            &mut self.candidates,
            &mut self.visited,
        );
        PackedInt64Array::from(out.as_slice())
    }

    // Places the hulls in this call's grid and sweeps the bolts against it.
    fn placed_sweep(
        &mut self,
        bolts: &[Vector3],
        bolt_reach: &[f64],
        hulls: &[Vector3],
        hull_reach: &[f64],
    ) -> Vec<i64> {
        self.cell_grid.place(hulls, hull_reach);
        sweep_cells::sweep(
            &self.cell_grid,
            bolts,
            bolt_reach,
            hulls,
            hull_reach,
            &mut self.candidates,
            &mut self.visited,
        )
    }
}
