// The shell around the radar kernel (M4-T23): `RadarModel.plot` hands its packed contacts here once a frame.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::radar_kernel::{self, Plot};

/// The radar sphere's plot for the HUD (`RadarModel.plot`, M4-T23). Stateless but for its scratch.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsRadarPlot {
    plot: Plot,
    base: Base<RefCounted>,
}

#[godot_api]
impl ScsRadarPlot {
    /// The plot of contacts `ids` at World `positions` with broadcast `reach`, each coloured `colours[colour_ix[i]]`, seen
    /// from a ship at `own_position` with attitude `own_basis`, `selected_id` drawn last: `[order (contact indices, far to
    /// near), their ids, points, ranges, colours, rims, point units, stalk units (foot, point), stalk colours, selected
    /// index]`. A contact beyond `ident_range_m` with no reach is drawn in `unknown_colour` instead (M5-T25), unless it is
    /// `known_id`.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn plot(
        &mut self,
        ids: PackedInt64Array,
        positions: PackedVector3Array,
        reach: PackedFloat64Array,
        colour_ix: PackedInt32Array,
        colours: PackedColorArray,
        own_position: Vector3,
        own_basis: Basis,
        selected_id: i64,
        ident_range_m: f64,
        unknown_colour: Color,
        known_id: i64,
    ) -> VarArray {
        radar_kernel::plot(
            ids.as_slice(),
            positions.as_slice(),
            reach.as_slice(),
            own_position,
            &own_basis,
            selected_id,
            ident_range_m,
            known_id,
            &mut self.plot,
        );
        let p = &self.plot;
        let palette = colours.as_slice();
        let ix = colour_ix.as_slice();
        let colour_of = |i: u32| {
            ix.get(i as usize)
                .and_then(|&k| palette.get(k.max(0) as usize))
                .copied()
                .unwrap_or(Color::WHITE)
        };
        let id_list = ids.as_slice();
        let mut order = PackedInt32Array::new();
        let mut drawn_ids = PackedInt64Array::new();
        let mut cols = PackedColorArray::new();
        let mut stalk_cols = PackedColorArray::new();
        let mut units = PackedVector2Array::new();
        let mut stalks = PackedVector2Array::new();
        for (k, &i) in p.order.iter().enumerate() {
            order.push(i as i32);
            drawn_ids.push(id_list[i as usize]);
            let c = if p.unknown[k] == 1 {
                unknown_colour
            } else {
                colour_of(i)
            };
            cols.push(c);
            stalk_cols.push(Color::from_rgba(c.r, c.g, c.b, 0.5));
            units.push(Vector2::new(p.units[k].0, p.units[k].1));
            stalks.push(Vector2::new(p.feet[k].0, p.feet[k].1));
            stalks.push(Vector2::new(p.units[k].0, p.units[k].1));
        }
        let mut out = VarArray::new();
        out.push(&order.to_variant());
        out.push(&drawn_ids.to_variant());
        out.push(&PackedVector3Array::from(p.points.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(p.ranges.as_slice()).to_variant());
        out.push(&cols.to_variant());
        out.push(&PackedByteArray::from(p.rims.as_slice()).to_variant());
        out.push(&units.to_variant());
        out.push(&stalks.to_variant());
        out.push(&stalk_cols.to_variant());
        out.push(&i64::from(p.selected).to_variant());
        out
    }
}
