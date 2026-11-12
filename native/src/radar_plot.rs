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
        let m = p.order.len();
        let mut order = PackedInt32Array::new();
        let mut drawn_ids = PackedInt64Array::new();
        let mut cols = PackedColorArray::new();
        let mut stalk_cols = PackedColorArray::new();
        let mut units = PackedVector2Array::new();
        let mut stalks = PackedVector2Array::new();
        order.resize(m);
        drawn_ids.resize(m);
        cols.resize(m);
        stalk_cols.resize(m);
        units.resize(m);
        stalks.resize(2 * m);
        let (order_s, ids_s, cols_s) = (order.as_mut_slice(), drawn_ids.as_mut_slice(), cols.as_mut_slice());
        let (stalk_cols_s, units_s, stalks_s) = (stalk_cols.as_mut_slice(), units.as_mut_slice(), stalks.as_mut_slice());
        for (k, &i) in p.order.iter().enumerate() {
            let c = if p.unknown[k] == 1 {
                unknown_colour
            } else {
                colour_of(i)
            };
            let (ux, uy) = p.units[k];
            order_s[k] = i as i32;
            ids_s[k] = id_list[i as usize];
            cols_s[k] = c;
            stalk_cols_s[k] = Color::from_rgba(c.r, c.g, c.b, 0.5);
            units_s[k] = Vector2::new(ux, uy);
            stalks_s[2 * k] = Vector2::new(p.feet[k].0, p.feet[k].1);
            stalks_s[2 * k + 1] = Vector2::new(ux, uy);
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

    /// The multimesh buffers of a plot's dots on a screen radar (`radar_kernel::fill_dots`): `[plain buffer, plain count,
    /// rim buffer, rim count, backing buffer, backing count]`. `units` and `colours` are the plot's, `rims` its rim flags;
    /// `held` the three multimeshes' instance counts now (plain, rim, backing), so a buffer comes sized for the multimesh
    /// that will hold it (`grown_capacity`) and the painter hands it over whole. An empty buffer for no dots.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn dot_buffers(
        &self,
        units: PackedVector2Array,
        colours: PackedColorArray,
        rims: PackedByteArray,
        selected_index: i64,
        centre: Vector2,
        radius_px: f64,
        backing_radius: f64,
        dot_radius: f64,
        backing_colour: Color,
        backings: bool,
        held: PackedInt32Array,
    ) -> VarArray {
        let n = units.len().min(colours.len()).min(rims.len());
        let selected = i32::try_from(selected_index).unwrap_or(-1);
        let counts = radar_kernel::dot_counts(&rims.as_slice()[..n], selected, backings);
        let held_of = |k: usize| held.as_slice().get(k).map_or(0, |&h| h.max(0) as usize);
        let sized = |count: usize, k: usize| {
            let mut buffer = PackedFloat32Array::new();
            buffer.resize(radar_kernel::grown_capacity(held_of(k), count) * radar_kernel::DOT_STRIDE);
            buffer
        };
        let mut plain = sized(counts.plain, 0);
        let mut rim = sized(counts.rim, 1);
        let mut backing = sized(counts.backing, 2);
        radar_kernel::fill_dots(
            &units.as_slice()[..n],
            &colours.as_slice()[..n],
            &rims.as_slice()[..n],
            selected,
            centre,
            radius_px as f32,
            (backing_radius as f32, dot_radius as f32),
            backing_colour,
            plain.as_mut_slice(),
            rim.as_mut_slice(),
            backing.as_mut_slice(),
        );
        let mut out = VarArray::new();
        out.push(&plain.to_variant());
        out.push(&(counts.plain as i64).to_variant());
        out.push(&rim.to_variant());
        out.push(&(counts.rim as i64).to_variant());
        out.push(&backing.to_variant());
        out.push(&(counts.backing as i64).to_variant());
        out
    }
}
