// Which rocks live as Jolt bodies, behind `RockBodies` (M6-T21): the rocks a rigid hull of the core could reach soon. The
// rocks sit in a grid in their owner's frame, which no rebase or drift changes, so the grid is built once; each step looks
// up the core's rigid hulls in it. The policy and the grid are `kernels::rock_stream`.
// gdext's class derive writes `base: base` in the code it generates for this module.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::kernels::rock_stream::{self, Stream};
use crate::sim_core::ScsSimCore;

/// One owner's rocks (a field or a belt) and which of them live as Jolt bodies.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsRockStream {
    base: Base<RefCounted>,
    stream: Stream,
    mids: Vec<Vector3>,
    reach: Vec<f64>,
    changes: Vec<i64>,
}

#[godot_api]
impl ScsRockStream {
    /// Holds the rocks (centres in the owner's frame, radii), none live. False, after logging why, when the arrays do not
    /// line up; nothing is held then.
    #[func]
    fn keep(&mut self, rocks: PackedVector3Array, radii: PackedFloat64Array) -> bool {
        let ok = self.stream.reset(rocks.as_slice(), radii.as_slice());
        if !ok {
            godot_error!(
                "ScsRockStream.keep: array lengths differ (rocks {}, radii {}); nothing kept",
                rocks.len(),
                radii.len()
            );
        }
        ok
    }

    /// One step over the core's rigid hulls: the owner stands at `origin` with `basis`, the rocks move at `rest` (local
    /// m/s). A hull wants the rocks it could reach within `lookahead` s plus `margin_m`, and keeps the live ones within
    /// that reach times `1 + hysteresis`, demoting one only after `hold_ticks` steps with no hull in that reach. Returns
    /// the changes in rock order: a promotion as the rock's index, a demotion as `-(index + 1)`.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn step(
        &mut self,
        core: Gd<ScsSimCore>,
        origin: Vector3,
        basis: Basis,
        rest: Vector3,
        lookahead: f64,
        margin_m: f64,
        hysteresis: f64,
        hold_ticks: i64,
    ) -> PackedInt64Array {
        {
            let core = core.bind();
            rock_stream::hull_spheres(
                &core.rows,
                &core.hull_rows,
                origin,
                &basis,
                rest,
                lookahead,
                margin_m,
                &mut self.mids,
                &mut self.reach,
            );
        }
        self.stream.step(
            &self.mids,
            &self.reach,
            1.0 + hysteresis.max(0.0),
            hold_ticks.clamp(0, i64::from(u32::MAX)) as u32,
            &mut self.changes,
        );
        PackedInt64Array::from(self.changes.as_slice())
    }

    /// Whether rock `i` lives as a body now.
    #[func]
    fn is_live(&self, i: i64) -> bool {
        usize::try_from(i)
            .ok()
            .and_then(|i| self.stream.live.get(i).copied())
            .unwrap_or(false)
    }

    /// Rocks that live as bodies now.
    #[func]
    fn live_count(&self) -> i64 {
        self.stream.live_count() as i64
    }

    /// Hull and rock pairs the last step put to the sphere test (the work count).
    #[func]
    fn visited(&self) -> i64 {
        self.stream.visited as i64
    }
}
