// The ram resolver's broad phase on the core's rows (M4-T15, docs/architecture.md 17.13); `RamBroadPhase` (GDScript,
// M4-T03) stays the reference. The pass itself is `kernels::ram`; this class only binds the core and hands the keys over.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::kernels::ram;
use crate::sim_core::ScsSimCore;

/// Which pairs of the core's hull rows could come near each other in the coming tick: each hull's bounding sphere swept
/// along its path through the tick, boxed; the boxes sorted along x and swept once. Repeats `RamBroadPhase.pairs` step
/// for step (32-bit vectors, the same box, the same sort and the same keys), so both give the same pairs in the same
/// order. Reads the rows, never the engine.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsRamPhase {
    base: Base<RefCounted>,
    scratch: ram::Scratch,
}

#[godot_api]
impl ScsRamPhase {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// `RamBroadPhase.pairs` over the core's hull rows (in their order), `always` (the same form) added.
    #[func]
    fn pairs(
        &mut self,
        core: Gd<ScsSimCore>,
        delta: f64,
        always: PackedInt64Array,
    ) -> PackedInt64Array {
        let core = core.bind();
        let keys = ram::pairs(
            &mut self.scratch,
            &core.rows,
            &core.hull_rows,
            delta,
            always.as_slice(),
        );
        PackedInt64Array::from(keys)
    }
}
