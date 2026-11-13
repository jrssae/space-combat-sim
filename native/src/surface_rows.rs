// The core's shell around the big hulls' surfaces (M7-T06): GDScript hands a body's volumes over once (the station's frame
// and drum), the role column marks its row, and the hit sweep, the rams, avoidance, the fire lane and the brains read them
// from the rows. The maths is `surface`, engine-free.
use std::sync::Arc;

use godot::prelude::*;

use crate::sim_core::ScsSimCore;
use crate::surface;

#[godot_api(secondary)]
impl ScsSimCore {
    /// Gives body `body_id` a surface: its volumes (`surface::VOLUME_LEN` numbers each, in its body frame), the convex hulls
    /// some of them are fitted to (`surface::add_hulls`: volume index, point count, points; empty for none) and its spin
    /// (rad/s about its own +z). Its row reads the role at the next sync. Replaces what the body had.
    #[func]
    fn set_surface(
        &mut self,
        body_id: i64,
        packed: PackedFloat64Array,
        hulls: PackedFloat64Array,
        spin_rad_s: f64,
    ) {
        let mut made = surface::from_packed(packed.as_slice(), spin_rad_s);
        surface::add_hulls(&mut made, hulls.as_slice());
        Arc::make_mut(&mut self.surfaces).insert(body_id, Arc::new(made));
        self.touch(body_id);
    }

    /// Takes body `body_id`'s surface away (its row is an ordinary hull again from the next sync).
    #[func]
    fn clear_surface(&mut self, body_id: i64) {
        if Arc::make_mut(&mut self.surfaces).remove(&body_id).is_some() {
            self.touch(body_id);
        }
    }

    /// How many bodies have a surface, and how many volumes body `body_id`'s has (0 without one).
    #[func]
    fn surface_count(&self) -> i64 {
        self.surfaces.len() as i64
    }

    #[func]
    fn surface_volume_count(&self, body_id: i64) -> i64 {
        self.surfaces
            .get(&body_id)
            .map_or(0, |s| s.volumes.len() as i64)
    }

    /// The distance from World point `p` to row `body_id`'s surface as its row stands (INF when the body has no row or
    /// no surface): what the brains measure ranges to.
    #[func]
    fn surface_distance(&self, body_id: i64, p: Vector3) -> f64 {
        (0..self.rows.body_ids.len())
            .find(|&j| self.rows.body_ids[j] == body_id)
            .and_then(|j| surface::nearest_of_row(&self.rows, j, p))
            .map_or(f64::INFINITY, |(_, d)| d)
    }
}
