// A trivial native class: proves the library loads, and measures what a call from GDScript costs.
use godot::prelude::*;

/// Smoke test and boundary probe for the native seam (M4-T05a). GDScript reaches it through `NativeProbe`.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsNativeProbe {
    base: Base<RefCounted>,
}

#[godot_api]
impl ScsNativeProbe {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Returns its argument: the cost of one call with one scalar each way.
    #[func]
    fn echo(&self, value: i64) -> i64 {
        value
    }

    /// Indices of the points within `range` of `origin`, in order: the shape of the contact queries T05b moves here.
    /// Repeats GDScript's precision: a 32-bit squared distance against a 64-bit squared range.
    #[func]
    fn in_range(
        &self,
        positions: PackedVector3Array,
        origin: Vector3,
        range: f64,
    ) -> PackedInt32Array {
        let range_sq = range * range;
        // Collected in Rust and handed over once: a push per element would cross into the engine each time.
        let found: Vec<i32> = positions
            .as_slice()
            .iter()
            .enumerate()
            .filter(|(_, p)| f64::from(p.distance_squared_to(origin)) <= range_sq)
            .map(|(i, _)| i as i32)
            .collect();
        PackedInt32Array::from(found.as_slice())
    }
}
