// The static rows' shift in native code, behind `StaticRows` (M6-T06, L4): a rebase, and every tick the frame spends off
// its anchor, moves a thousand rocks and mines; done here it costs microseconds and no rebuild. The maths is
// `kernels::statics`.
// gdext's class derive writes `base: base` in the code it generates for this module.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::kernels::statics;

/// Moves `StaticRows`' columns (and its solid rows) by one vector.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsStaticRows {
    base: Base<RefCounted>,
    moved: i64,
}

#[godot_api]
impl ScsStaticRows {
    /// `positions` with `offset` added to every row whose world is `owner` (the rest as they were); `moved` says how many.
    /// Returns them unchanged, after logging why, when the columns differ in length.
    #[func]
    fn shift(
        &mut self,
        positions: PackedVector3Array,
        worlds: PackedInt64Array,
        owner: i64,
        offset: Vector3,
    ) -> PackedVector3Array {
        self.moved = 0;
        if positions.len() != worlds.len() {
            godot_error!(
                "ScsStaticRows.shift: array lengths differ (positions {}, worlds {}); nothing moved",
                positions.len(),
                worlds.len()
            );
            return positions;
        }
        let mut out = positions;
        self.moved =
            statics::shift_owned(out.as_mut_slice(), worlds.as_slice(), owner, offset) as i64;
        out
    }

    /// Rows the last `shift` moved.
    #[func]
    fn moved(&self) -> i64 {
        self.moved
    }
}
