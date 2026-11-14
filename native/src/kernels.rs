//! The kernels: every query and step over the core's rows (M4-T15, docs/architecture.md 17.13), with no engine type in
//! this file. A kernel takes plain Rust data (the core's rows and bolts, slices, its own structs) and Godot's maths
//! builtins, and returns plain data; every engine read and write stays in the core's sync points and in the flight step's
//! force application. `test_sim_core` reads this file and fails on any engine type, so a kernel cannot grow an engine
//! call unnoticed (T18's threads need exactly that).
#![allow(clippy::too_many_arguments)]

/// The contact scan's queries over one tick's rows (`ScsContactField`, M4-T05b, M4-T09, M4-T29).
pub mod contact {
    use std::cmp::Ordering;

    use godot::builtin::Vector3;

    use crate::v3::{dist_sq, dot, length, length_squared, sub};

    // The closest-approach test of incoming fire, as `ContactScan` defines it.
    const INCOMING_MISS_M: f64 = 15.0;
    const INCOMING_HORIZON_S: f64 = 2.0;
    // Grid queries pad their box so a body the 32-bit range test accepts is never in an unvisited cell.
    const PAD_REL: f64 = 1e-6;
    const PAD_M: f64 = 1.0;

    /// One tick's scan as the queries read it: columns in scan order, bolts in group order.
    pub struct View<'a> {
        pub body_ids: &'a [i64],
        pub positions: &'a [Vector3],
        pub body_faction: &'a [u32],
        pub is_ship: &'a [bool],
        pub reach: &'a [f64],
        pub is_static: &'a [bool],
        pub is_mine: &'a [bool],
        pub radii: &'a [f64],
        pub bolt_positions: &'a [Vector3],
        pub bolt_velocities: &'a [Vector3],
        pub bolt_faction: &'a [u32],
        pub bolt_shooters: &'a [i64],
    }

    /// The grid over the scan: built once per rows version and only read by the queries, so every worker shares it
    /// (M4-T18).
    #[derive(Default)]
    pub struct Grid {
        pub max_static_radius: f64,
        pub cell_m: f64,
        // Bodies sorted by grid cell, then by scan index.
        pub cells: Vec<((i32, i32, i32), u32)>,
    }

    /// The scratch one query fills: one per worker, never shared (M4-T18).
    #[derive(Default)]
    pub struct Query {
        pub visited: i64,
        pub candidates: Vec<u32>,
        pub in_range: Vec<(f32, u32)>,
        pub in_reach: Vec<(f64, u32)>,
        pub ranked: Vec<(f32, u32)>,
    }

    /// What a query works with: the shared grid and its caller's own scratch.
    pub struct Work<'a> {
        pub grid: &'a Grid,
        pub query: &'a mut Query,
    }

    /// Every body by its grid cell, sorted by cell then by scan index, into the caller's list (no allocation once it has
    /// grown, M4-T17).
    pub fn sorted_cells_into(
        positions: &[Vector3],
        cell_m: f64,
        cells: &mut Vec<((i32, i32, i32), u32)>,
    ) {
        cells.clear();
        cells.extend(positions.iter().enumerate().map(|(i, p)| {
            let key = (
                cell_of(f64::from(p.x), cell_m),
                cell_of(f64::from(p.y), cell_m),
                cell_of(f64::from(p.z), cell_m),
            );
            (key, i as u32)
        }));
        cells.sort_unstable();
    }

    /// `ContactScan.contacts_for`: the bodies within `range` of `at`, not `own_body_id`, in scan order.
    pub fn contacts(
        view: &View,
        work: &mut Work<'_>,
        own_body_id: i64,
        at: Vector3,
        range: f64,
    ) -> Vec<i32> {
        let mut out = Vec::new();
        contacts_into(view, work, own_body_id, at, range, &mut out);
        out
    }

    /// `contacts` into the caller's list (no allocation per call, M4-T17).
    pub fn contacts_into(
        view: &View,
        work: &mut Work<'_>,
        own_body_id: i64,
        at: Vector3,
        range: f64,
        out: &mut Vec<i32>,
    ) {
        let range_sq = range * range;
        gather(view, work, own_body_id, at, range, |_, d_sq| {
            f64::from(d_sq) <= range_sq
        });
        out.clear();
        out.extend(work.query.in_range.iter().map(|&(_, i)| i as i32));
    }

    /// `ContactScan.nearest_for` before its keeper: with `k` or fewer in range (or `k` 0 or less), all of them in scan
    /// order; otherwise the nearest `k` (equal ranges to the earlier body) plus the nearest hostile ship, then -1 to say
    /// the cut left something out. `hostile` flags the factions hostile to the asking one, in faction-table order.
    pub fn nearest(
        view: &View,
        work: &mut Work<'_>,
        hostile: Option<&[bool]>,
        own_body_id: i64,
        at: Vector3,
        k: i64,
        range: f64,
    ) -> Vec<i32> {
        let mut out = Vec::new();
        nearest_into(view, work, hostile, own_body_id, at, k, range, &mut out);
        out
    }

    /// `nearest` into the caller's list (no allocation per call, M4-T17).
    pub fn nearest_into(
        view: &View,
        work: &mut Work<'_>,
        hostile: Option<&[bool]>,
        own_body_id: i64,
        at: Vector3,
        k: i64,
        range: f64,
        out: &mut Vec<i32>,
    ) {
        let range_sq = range * range;
        // GDScript's nearest loop skips only what is beyond the range, so its test is "not greater".
        gather(view, work, own_body_id, at, range, |_, d_sq| {
            f64::from(d_sq).partial_cmp(&range_sq) != Some(Ordering::Greater)
        });
        rank_nearest(view, work.query, hostile, k, out);
    }

    /// `nearest_into` over `candidates` (row indices in scan order, a superset of the bodies in range) instead of the
    /// grid's cells (M4-T22 fix round 2: the brains walk the ships' rows directly when the sensor range spans most of
    /// the battle, which spares sorting the cells' candidates); the same answer.
    #[allow(clippy::too_many_arguments)]
    pub fn nearest_among(
        view: &View,
        query: &mut Query,
        candidates: &[u32],
        hostile: Option<&[bool]>,
        own_body_id: i64,
        at: Vector3,
        k: i64,
        range: f64,
        out: &mut Vec<i32>,
    ) {
        let range_sq = range * range;
        query.in_range.clear();
        for &i in candidates {
            let j = i as usize;
            if view.is_static[j] {
                continue;
            }
            let d_sq = dist_sq(view.positions[j], at);
            if f64::from(d_sq).partial_cmp(&range_sq) != Some(Ordering::Greater)
                && view.body_ids[j] != own_body_id
            {
                query.in_range.push((d_sq, i));
            }
        }
        query.visited = candidates.len() as i64;
        rank_nearest(view, query, hostile, k, out);
    }

    // The nearest `k` of the query's bodies in range, as `nearest_into` describes them.
    fn rank_nearest(
        view: &View,
        query: &mut Query,
        hostile: Option<&[bool]>,
        k: i64,
        out: &mut Vec<i32>,
    ) {
        out.clear();
        let in_range = &query.in_range;
        // k of 0 or less means no cut: every contact in range, as `ContactScan.nearest_for` defines it.
        if k <= 0 || in_range.len() <= k as usize {
            out.extend(in_range.iter().map(|&(_, i)| i as i32));
            return;
        }
        let mut nearest_hostile: Option<(f32, u32)> = None;
        for &(d_sq, i) in in_range {
            let j = i as usize;
            let is_hostile =
                view.is_ship[j] && hostile.is_some_and(|row| flagged(row, view.body_faction[j]));
            if is_hostile && nearest_hostile.is_none_or(|(best, _)| d_sq < best) {
                nearest_hostile = Some((d_sq, i));
            }
        }
        // Ranked by range, then by scan index (in_range is in scan order, so a stable sort keeps that).
        let k = k as usize;
        query.ranked.clear();
        query.ranked.extend_from_slice(&query.in_range);
        query
            .ranked
            .select_nth_unstable_by(k - 1, |a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
        out.extend(query.ranked[..k].iter().map(|&(_, i)| i as i32));
        if let Some((_, h)) = nearest_hostile
            && !out.contains(&(h as i32))
        {
            out.push(h as i32);
        }
        out.push(-1);
    }

    /// `ContactScan.statics_for`: the rocks and mines whose surface is within `range` of `at`, not `own_body_id`; with
    /// `k` or fewer, all of them, otherwise the `k` nearest by surface distance (equal ones to the earlier row); in scan
    /// order. A mine counts only when `friendly` holds its faction (Q27); with no row, none do.
    pub fn statics(
        view: &View,
        work: &mut Work<'_>,
        friendly: &[bool],
        own_body_id: i64,
        at: Vector3,
        k: i64,
        range: f64,
    ) -> Vec<i32> {
        let mut out = Vec::new();
        statics_into(view, work, friendly, own_body_id, at, k, range, &mut out);
        out
    }

    /// `statics` into the caller's list (no allocation per call, M4-T17).
    pub fn statics_into(
        view: &View,
        work: &mut Work<'_>,
        friendly: &[bool],
        own_body_id: i64,
        at: Vector3,
        k: i64,
        range: f64,
        out: &mut Vec<i32>,
    ) {
        out.clear();
        if k <= 0 {
            return;
        }
        let reach = range.abs();
        work.query.in_reach.clear();
        let pad = reach + work.grid.max_static_radius;
        collect_candidates(view, work, at, pad, reach.is_finite());
        for &i in &work.query.candidates {
            let j = i as usize;
            if !view.is_static[j] || view.body_ids[j] == own_body_id {
                continue;
            }
            if view.is_mine[j] && !flagged(friendly, view.body_faction[j]) {
                continue; // another side's mine: unknown to this one
            }
            // `position.distance_to(at) - radius`, with GDScript's 32-bit length.
            let surface = f64::from(length(sub(at, view.positions[j]))) - view.radii[j];
            if surface <= reach {
                work.query.in_reach.push((surface, i));
            }
        }
        let k = k as usize;
        if work.query.in_reach.len() > k {
            work.query
                .in_reach
                .select_nth_unstable_by(k - 1, |a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
            work.query.in_reach.truncate(k);
            work.query.in_reach.sort_unstable_by_key(|e| e.1);
        }
        out.extend(work.query.in_reach.iter().map(|&(_, i)| i as i32));
    }

    /// `ContactScan.broadcasts_for`: the bodies beyond `near` and within their own reach, not `own_body_id`, in scan order.
    pub fn broadcasts(view: &View, own_body_id: i64, at: Vector3, near: f64) -> Vec<i32> {
        let mut out = Vec::new();
        broadcasts_into(view, own_body_id, at, near, &mut out);
        out
    }

    /// `broadcasts` into the caller's list (no allocation per call, M4-T17).
    pub fn broadcasts_into(
        view: &View,
        own_body_id: i64,
        at: Vector3,
        near: f64,
        out: &mut Vec<i32>,
    ) {
        out.clear();
        for i in 0..view.positions.len() {
            if broadcast_one(view, i, own_body_id, at, near) {
                out.push(i as i32);
            }
        }
    }

    /// `broadcasts_into` over the rows `broadcasters` (in row order: the rows with a reach, listed once per tick), the
    /// same list since a row without a reach is never heard.
    pub fn broadcasts_among(
        view: &View,
        broadcasters: &[u32],
        own_body_id: i64,
        at: Vector3,
        near: f64,
        out: &mut Vec<i32>,
    ) {
        out.clear();
        for &i in broadcasters {
            if broadcast_one(view, i as usize, own_body_id, at, near) {
                out.push(i as i32);
            }
        }
    }

    // Whether row `i` is heard from `at`: beyond `near`, within its own reach, not the ship's own body.
    fn broadcast_one(view: &View, i: usize, own_body_id: i64, at: Vector3, near: f64) -> bool {
        if view.body_ids[i] == own_body_id {
            return false;
        }
        let d_sq = f64::from(dist_sq(view.positions[i], at));
        let reach = view.reach.get(i).copied().unwrap_or(0.0);
        d_sq > near * near && d_sq <= reach * reach
    }

    /// `ContactScan.incoming_fire`: hostile bolts, not this ship's own, that pass within 15 m in the next 2 s.
    pub fn incoming(
        view: &View,
        hostile: &[bool],
        own_body_id: i64,
        at: Vector3,
        velocity: Vector3,
    ) -> i64 {
        (0..view.bolt_positions.len())
            .filter(|&i| incoming_one(view, i, hostile, own_body_id, at, velocity))
            .count() as i64
    }

    /// Whether bolt `i` counts as incoming fire for a ship at `at` moving at `velocity` (one bolt of `incoming`).
    pub fn incoming_one(
        view: &View,
        i: usize,
        hostile: &[bool],
        own_body_id: i64,
        at: Vector3,
        velocity: Vector3,
    ) -> bool {
        if !flagged(hostile, view.bolt_faction[i]) || view.bolt_shooters[i] == own_body_id {
            return false;
        }
        let rel_pos = sub(view.bolt_positions[i], at);
        let rel_vel = sub(view.bolt_velocities[i], velocity);
        let reach = f64::from(length(rel_vel)) * INCOMING_HORIZON_S + INCOMING_MISS_M + 1.0;
        if f64::from(length_squared(rel_pos)) > reach * reach {
            return false;
        }
        closest_approach(rel_pos, rel_vel, INCOMING_HORIZON_S) < INCOMING_MISS_M
    }

    /// The shooter (a body id) of a bolt of any side, not `own_body_id`'s, that passes within `miss_m` of a ship at `at`
    /// in the incoming-fire horizon (M7-T29: a civilian is frightened by fire that comes close, whoever fires it); the
    /// earliest bolt row among them, 0 for none. Walks the bolts near enough through the grid of their cells, as
    /// `incoming_near` does.
    #[allow(clippy::too_many_arguments)]
    pub fn close_fire_from(
        view: &View,
        own_body_id: i64,
        at: Vector3,
        velocity: Vector3,
        miss_m: f64,
        bolt_cells: &[((i32, i32, i32), u32)],
        cell_m: f64,
        reach_max: f64,
        candidates: &mut Vec<u32>,
    ) -> i64 {
        candidates.clear();
        let pad = reach_max * (1.0 + PAD_REL) + PAD_M;
        let lo = |v: f32| cell_of(f64::from(v) - pad, cell_m);
        let hi = |v: f32| cell_of(f64::from(v) + pad, cell_m);
        let (lx, ly, lz) = (lo(at.x), lo(at.y), lo(at.z));
        let (hx, hy, hz) = (hi(at.x), hi(at.y), hi(at.z));
        let span = |l: i32, h: i32| i64::from(h) - i64::from(l) + 1;
        let columns = span(lx, hx).checked_mul(span(ly, hy));
        if cell_m > 0.0 && reach_max.is_finite() && columns.is_some_and(|c| c <= bolt_cells.len() as i64) {
            for cx in lx..=hx {
                for cy in ly..=hy {
                    let start = bolt_cells.partition_point(|e| e.0 < (cx, cy, lz));
                    let end = bolt_cells.partition_point(|e| e.0 <= (cx, cy, hz));
                    candidates.extend(bolt_cells[start..end].iter().map(|e| e.1));
                }
            }
        } else {
            candidates.extend(0..view.bolt_positions.len() as u32);
        }
        let mut first: Option<u32> = None;
        for &i in candidates.iter() {
            let b = i as usize;
            let shooter = view.bolt_shooters[b];
            if shooter == own_body_id || shooter == 0 || first.is_some_and(|f| f <= i) {
                continue;
            }
            let rel_pos = sub(view.bolt_positions[b], at);
            let rel_vel = sub(view.bolt_velocities[b], velocity);
            let reach = f64::from(length(rel_vel)) * INCOMING_HORIZON_S + miss_m + 1.0;
            if f64::from(length_squared(rel_pos)) <= reach * reach
                && closest_approach(rel_pos, rel_vel, INCOMING_HORIZON_S) < miss_m
            {
                first = Some(i);
            }
        }
        first.map_or(0, |i| view.bolt_shooters[i as usize])
    }

    /// `incoming` over the bolts a grid of their cells (`sorted_cells_into`) puts within `reach_max` of `at`: the same count
    /// when no bolt can be incoming from farther than `reach_max` (the caller bounds it by the fastest bolt plus the
    /// ship's own speed, times the horizon, plus the miss distance). `candidates` is the caller's scratch.
    pub fn incoming_near(
        view: &View,
        hostile: &[bool],
        own_body_id: i64,
        at: Vector3,
        velocity: Vector3,
        bolt_cells: &[((i32, i32, i32), u32)],
        cell_m: f64,
        reach_max: f64,
        candidates: &mut Vec<u32>,
    ) -> i64 {
        candidates.clear();
        let pad = reach_max * (1.0 + PAD_REL) + PAD_M;
        let lo = |v: f32| cell_of(f64::from(v) - pad, cell_m);
        let hi = |v: f32| cell_of(f64::from(v) + pad, cell_m);
        let (lx, ly, lz) = (lo(at.x), lo(at.y), lo(at.z));
        let (hx, hy, hz) = (hi(at.x), hi(at.y), hi(at.z));
        let span = |l: i32, h: i32| i64::from(h) - i64::from(l) + 1;
        let columns = span(lx, hx).checked_mul(span(ly, hy));
        let grid_usable = cell_m > 0.0
            && reach_max.is_finite()
            && columns.is_some_and(|c| c <= bolt_cells.len() as i64);
        if grid_usable {
            for cx in lx..=hx {
                for cy in ly..=hy {
                    let start = bolt_cells.partition_point(|e| e.0 < (cx, cy, lz));
                    let end = bolt_cells.partition_point(|e| e.0 <= (cx, cy, hz));
                    candidates.extend(bolt_cells[start..end].iter().map(|e| e.1));
                }
            }
        } else {
            candidates.extend(0..view.bolt_positions.len() as u32);
        }
        candidates
            .iter()
            .filter(|&&i| incoming_one(view, i as usize, hostile, own_body_id, at, velocity))
            .count() as i64
    }

    // Fills `in_range` with the bodies near `at` that `accept` takes by squared distance, but not `own_body_id` and never
    // a rock or mine, in scan order.
    fn gather(
        view: &View,
        work: &mut Work<'_>,
        own_body_id: i64,
        at: Vector3,
        range: f64,
        accept: impl Fn(usize, f32) -> bool,
    ) {
        work.query.in_range.clear();
        collect_candidates(view, work, at, range.abs(), range.is_finite());
        for &i in &work.query.candidates {
            let j = i as usize;
            if view.is_static[j] {
                continue;
            }
            let d_sq = dist_sq(view.positions[j], at);
            if accept(j, d_sq) && view.body_ids[j] != own_body_id {
                work.query.in_range.push((d_sq, i));
            }
        }
    }

    // Fills `candidates` with the bodies in the grid cells within `reach` of `at`, in scan order, or every body when
    // that box would hold more cells than bodies. Counts them as the latest query's visits.
    fn collect_candidates(view: &View, work: &mut Work<'_>, at: Vector3, reach: f64, finite: bool) {
        work.query.candidates.clear();
        let pad = reach * (1.0 + PAD_REL) + PAD_M;
        let cell_m = work.grid.cell_m;
        let lo = |v: f32| cell_of(f64::from(v) - pad, cell_m);
        let hi = |v: f32| cell_of(f64::from(v) + pad, cell_m);
        let (lx, ly, lz) = (lo(at.x), lo(at.y), lo(at.z));
        let (hx, hy, hz) = (hi(at.x), hi(at.y), hi(at.z));
        // A huge range saturates the cell indices, so the box can hold more cells than a 64-bit count: too many to walk.
        let span = |l: i32, h: i32| i64::from(h) - i64::from(l) + 1;
        let columns = span(lx, hx).checked_mul(span(ly, hy));
        let grid_usable =
            cell_m > 0.0 && finite && columns.is_some_and(|c| c <= work.grid.cells.len() as i64);
        if grid_usable {
            let cells = &work.grid.cells;
            let candidates = &mut work.query.candidates;
            for cx in lx..=hx {
                for cy in ly..=hy {
                    let start = cells.partition_point(|e| e.0 < (cx, cy, lz));
                    let end = cells.partition_point(|e| e.0 <= (cx, cy, hz));
                    candidates.extend(cells[start..end].iter().map(|e| e.1));
                }
            }
            candidates.sort_unstable();
        } else {
            work.query.candidates.extend(0..view.positions.len() as u32);
        }
        work.query.visited = work.query.candidates.len() as i64;
    }

    // Whether faction `index` is flagged in `row` (hostile, or friendly for a friendly row); a row too short says no.
    fn flagged(row: &[bool], index: u32) -> bool {
        row.get(index as usize).copied().unwrap_or(false)
    }

    // The grid cell holding coordinate `v`.
    fn cell_of(v: f64, cell_m: f64) -> i32 {
        if cell_m > 0.0 {
            (v / cell_m).floor() as i32
        } else {
            0
        }
    }

    // `AvoidanceMath.closest_approach`: 64-bit scalars around 32-bit vectors, as GDScript evaluates it.
    fn closest_approach(rel_pos: Vector3, rel_vel: Vector3, horizon_s: f64) -> f64 {
        let speed_sq = f64::from(length_squared(rel_vel));
        if speed_sq < 1e-12 {
            return f64::from(length(rel_pos));
        }
        let raw = -f64::from(dot(rel_pos, rel_vel)) / speed_sq;
        let t = if raw < 0.0 {
            0.0
        } else if raw > horizon_s {
            horizon_s
        } else {
            raw
        };
        // A Vector3 times a float rounds the float to 32 bits first.
        let t32 = t as f32;
        let at = Vector3::new(
            rel_pos.x + rel_vel.x * t32,
            rel_pos.y + rel_vel.y * t32,
            rel_pos.z + rel_vel.z * t32,
        );
        f64::from(length(at))
    }
}

/// The hit resolver's broad phase (`ScsHitSweep`, M4-T08, M4-T29): hulls in a grid of levels, projectiles swept over it.
pub mod sweep {
    use godot::builtin::Vector3;

    use crate::rows::{Bolts, FLAG_RIGID, Rows};
    use crate::v3::length;

    /// The core's hull rows as the hit resolver's spheres: `global_position + velocity * (0.5 * delta)`, reach
    /// `bounding_radius + velocity.length() * delta * 0.5`, in GDScript's precision and order.
    pub fn hull_spheres(
        rows: &Rows,
        hull_rows: &[u32],
        delta: f64,
        mids: &mut Vec<Vector3>,
        reach: &mut Vec<f64>,
    ) {
        mids.clear();
        reach.clear();
        let half = (0.5 * delta) as f32;
        for &row in hull_rows {
            let j = row as usize;
            let v = rows.velocities[j];
            let at = rows.positions[j];
            mids.push(Vector3::new(
                at.x + v.x * half,
                at.y + v.y * half,
                at.z + v.z * half,
            ));
            reach.push(rows.radii[j] + f64::from(length(v)) * delta * 0.5);
        }
    }

    /// The core's bolts as the resolver's spheres: `start + last_step * 0.5`, reach `last_step.length() * 0.5 + hit_radius`.
    pub fn bolt_spheres(bolts: &Bolts, mids: &mut Vec<Vector3>, reach: &mut Vec<f64>) {
        mids.clear();
        reach.clear();
        for i in 0..bolts.ids.len() {
            let step = bolts.last_steps[i];
            let end = bolts.positions[i];
            let start = Vector3::new(end.x - step.x, end.y - step.y, end.z - step.z);
            mids.push(Vector3::new(
                start.x + step.x * 0.5,
                start.y + step.y * 0.5,
                start.z + step.z * 0.5,
            ));
            reach.push(f64::from(length(step)) * 0.5 + bolts.radii[i]);
        }
    }

    /// The core's rigid hull rows as the ram resolver's moving spheres against the rocks: hull `k` (the k-th rigid row in
    /// hull order) moves from its position to `position + velocity * delta`, and is `(start + end) * 0.5` with reach
    /// `|end - start| * 0.5 + radius + margin`.
    pub fn rigid_spheres(
        rows: &Rows,
        hull_rows: &[u32],
        delta: f64,
        margin_m: f64,
        mids: &mut Vec<Vector3>,
        reach: &mut Vec<f64>,
    ) {
        mids.clear();
        reach.clear();
        let dt = delta as f32;
        for &row in hull_rows {
            let j = row as usize;
            if rows.flags[j] & FLAG_RIGID == 0 {
                continue;
            }
            let start = rows.positions[j];
            let v = rows.velocities[j];
            let end = Vector3::new(start.x + v.x * dt, start.y + v.y * dt, start.z + v.z * dt);
            let sum = Vector3::new(start.x + end.x, start.y + end.y, start.z + end.z);
            mids.push(Vector3::new(sum.x * 0.5, sum.y * 0.5, sum.z * 0.5));
            let travel = Vector3::new(end.x - start.x, end.y - start.y, end.z - start.z);
            reach.push(f64::from(length(travel)) * 0.5 + rows.radii[j] + margin_m);
        }
    }
}

/// The ram resolver's broad phase on the rows (`ScsRamPhase`; `RamBroadPhase` in GDScript is the reference).
pub mod ram {
    use std::cmp::Ordering;

    use godot::builtin::Vector3;

    use crate::rows::{FLAG_RIGID, Rows};
    use crate::v3::{add, max_cw as max, min_cw as min, scale, sub};

    // `RamResolver.MARGIN_M` (and `RamBroadPhase.MARGIN_M`): room round every box, metres.
    pub const MARGIN_M: f64 = 1.0;

    /// The scratch the pass reuses between ticks.
    #[derive(Default)]
    pub struct Scratch {
        lows: Vec<Vector3>,
        highs: Vec<Vector3>,
        order: Vec<(f32, u32)>,
        keys: Vec<i64>,
    }

    /// `RamBroadPhase.pairs` over the hull rows (in their order): hull `i` moves from its position to `position +
    /// velocity * delta` through the tick (a prop, which moved itself already, from `position - velocity * delta` to its
    /// position) inside its bounding sphere. The pairs as `i * count + j` with `i < j`, ascending, `always` (the same
    /// form) added.
    pub fn pairs<'a>(
        s: &'a mut Scratch,
        rows: &Rows,
        hull_rows: &[u32],
        delta: f64,
        always: &[i64],
    ) -> &'a [i64] {
        let count = hull_rows.len();
        s.lows.clear();
        s.highs.clear();
        s.order.clear();
        let dt = delta as f32;
        for (i, &row) in hull_rows.iter().enumerate() {
            let j = row as usize;
            let at = rows.positions[j];
            let step = scale(rows.velocities[j], dt);
            let (start, end) = if rows.flags[j] & FLAG_RIGID != 0 {
                (at, add(at, step))
            } else {
                (sub(at, step), at)
            };
            // `Vector3.ONE * (radius + MARGIN_M)`: the radius as the 32-bit float the resolver packs, then one 32-bit scale.
            let grow_s = (f64::from(rows.radii[j] as f32) + MARGIN_M) as f32;
            let grow = Vector3::new(grow_s, grow_s, grow_s);
            let low = sub(min(start, end), grow);
            s.lows.push(low);
            s.highs.push(add(max(start, end), grow));
            s.order.push((low.x, i as u32));
        }
        s.order.sort_by(|a, b| {
            a.0.partial_cmp(&b.0)
                .unwrap_or(Ordering::Equal)
                .then(a.1.cmp(&b.1))
        });
        s.keys.clear();
        s.keys.extend_from_slice(always);
        let count_i = count as i64;
        for a in 0..count {
            let i = s.order[a].1 as usize;
            let low_i = s.lows[i];
            let high_i = s.highs[i];
            for b in (a + 1)..count {
                let j = s.order[b].1 as usize;
                let low_j = s.lows[j];
                if low_j.x > high_i.x {
                    break; // every later box starts farther along x
                }
                let high_j = s.highs[j];
                if low_j.y > high_i.y
                    || low_i.y > high_j.y
                    || low_j.z > high_i.z
                    || low_i.z > high_j.z
                {
                    continue;
                }
                let (lo, hi) = if i < j { (i, j) } else { (j, i) };
                s.keys.push(lo as i64 * count_i + hi as i64);
            }
        }
        s.keys.sort_unstable();
        s.keys.dedup();
        &s.keys
    }

    // Room the reject keeps for the resolver's 32-bit sums: metres, and a share of how far out the two rows sit.
    const APART_PAD_M: f64 = 0.05;
    const APART_PAD_REL: f64 = 4e-6;

    /// Whether rows `a` and `b` stay clearly apart through the tick (M5-T33): their bounding spheres never come within
    /// the pad of each other along the tick's relative motion, so the resolver's own sphere test (`RamResolver.
    /// _sweep_pair`, in 32 bits and in one hull's frame) is sure to say the same. Never true for a pair that test would
    /// pass on: it only spares GDScript the pairs whose answer is no ram.
    pub fn clearly_apart(rows: &Rows, a: usize, b: usize, delta: f64) -> bool {
        let wide = |v: Vector3| [f64::from(v.x), f64::from(v.y), f64::from(v.z)];
        // A rigid row is read before its step, a prop after it: both cover `velocity * delta` in the tick.
        let start = |j: usize| {
            let (at, v) = (wide(rows.positions[j]), wide(rows.velocities[j]));
            if rows.flags[j] & FLAG_RIGID != 0 {
                at
            } else {
                [at[0] - v[0] * delta, at[1] - v[1] * delta, at[2] - v[2] * delta]
            }
        };
        let (start_a, start_b) = (start(a), start(b));
        let (v_a, v_b) = (wide(rows.velocities[a]), wide(rows.velocities[b]));
        let mut gap = [0.0; 3];
        let mut step = [0.0; 3];
        let mut far = 0.0;
        for k in 0..3 {
            gap[k] = start_a[k] - start_b[k];
            step[k] = (v_a[k] - v_b[k]) * delta;
            far += start_a[k].abs() + start_b[k].abs() + step[k].abs();
        }
        let along = gap[0] * step[0] + gap[1] * step[1] + gap[2] * step[2];
        let step_sq = step[0] * step[0] + step[1] * step[1] + step[2] * step[2];
        let t = if step_sq > 0.0 {
            (-along / step_sq).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let mut nearest_sq = 0.0;
        for k in 0..3 {
            let d = gap[k] + step[k] * t;
            nearest_sq += d * d;
        }
        let reach = (rows.radii[a] + rows.radii[b]).max(0.0) + APART_PAD_M + APART_PAD_REL * far;
        // A row that is not a number anywhere is left to the resolver.
        nearest_sq.is_finite() && reach.is_finite() && nearest_sq > reach * reach
    }

    // `RamResolver.SWEEP_CULL_PAD_M`, and the room the reject adds for the resolver's 32-bit sums.
    pub const SWEEP_CULL_PAD_M: f64 = 0.05;
    const REACH_PAD_M: f64 = 0.02;

    /// Whether row `a`'s bounding sphere (`radius_a`) cannot reach row `b`'s box (`low_b` to `high_b`, in `b`'s own
    /// frame) through the tick (M5-T33): the resolver's second reject (`RamResolver._sphere_reaches` in `_sweep_pair`,
    /// the first hull's sphere swept in the second's frame), with room so that it is never true where that test, in
    /// 32 bits, would let the pair on. It spares GDScript a fighter passing a capital's bounding sphere but not its hull.
    pub fn cannot_reach(
        rows: &Rows,
        a: usize,
        b: usize,
        delta: f64,
        radius_a: f64,
        low_b: [f64; 3],
        high_b: [f64; 3],
    ) -> bool {
        let wide = |v: Vector3| [f64::from(v.x), f64::from(v.y), f64::from(v.z)];
        let start = |j: usize| {
            let (at, v) = (wide(rows.positions[j]), wide(rows.velocities[j]));
            if rows.flags[j] & FLAG_RIGID != 0 {
                at
            } else {
                [at[0] - v[0] * delta, at[1] - v[1] * delta, at[2] - v[2] * delta]
            }
        };
        let (start_a, start_b) = (start(a), start(b));
        let (v_a, v_b) = (wide(rows.velocities[a]), wide(rows.velocities[b]));
        let mut gap = [0.0; 3];
        let mut step = [0.0; 3];
        let mut far = 0.0;
        for k in 0..3 {
            gap[k] = start_a[k] - start_b[k];
            step[k] = (v_a[k] - v_b[k]) * delta;
            far += start_a[k].abs() + start_b[k].abs() + step[k].abs();
        }
        let reach = radius_a.abs() + SWEEP_CULL_PAD_M + REACH_PAD_M + APART_PAD_REL * far;
        if !reach.is_finite() {
            return false;
        }
        // Into `b`'s frame: axis k of the box is `b`'s basis column k.
        let basis = &rows.bases[b];
        let columns = [
            [basis.rows[0].x, basis.rows[1].x, basis.rows[2].x],
            [basis.rows[0].y, basis.rows[1].y, basis.rows[2].y],
            [basis.rows[0].z, basis.rows[1].z, basis.rows[2].z],
        ];
        let mut apart = false;
        for (k, column) in columns.iter().enumerate() {
            let axis = [f64::from(column[0]), f64::from(column[1]), f64::from(column[2])];
            let at = gap[0] * axis[0] + gap[1] * axis[1] + gap[2] * axis[2];
            let moved = at + step[0] * axis[0] + step[1] * axis[1] + step[2] * axis[2];
            if !(at.is_finite() && moved.is_finite() && low_b[k] <= high_b[k]) {
                return false; // not a number, or no box: the resolver decides
            }
            apart |= at.min(moved) - reach > high_b[k] || at.max(moved) + reach < low_b[k];
        }
        apart
    }
}

/// The flight force step's maths (`ScsFlightStep`, M4-T10, N4): `FlightModel.compute`, the `SpeedGovernor` and the forces
/// `Ship._physics_process` applies, as values the step then applies through the physics server.
pub mod flight {
    use godot::builtin::{Basis, Vector3};

    use crate::v3::{
        AXIS_SIGN, add, clamp_cw, clampf, div_s, dot, is_zero_approx, length, maxf, minf, mul_cw,
        neg, normalized, scale, signf, sub, xform, xform_inv,
    };

    pub const GROUPS: usize = 4;
    // `FlightAssist.FACE_DECEL_FRACTION`.
    pub const FACE_DECEL_FRACTION: f64 = 0.5;

    /// A ship's type and nozzles, as `register` snapshots them: what the maths reads.
    pub struct Body {
        pub spec: Spec,
        pub nozzle_groups: Vec<usize>,
        pub nozzle_positions: Vec<Vector3>,
        pub nozzle_exhausts: Vec<Vector3>,
        pub torque_axes: [Vector3; GROUPS],
        pub main_total: f64,
        pub retro_total: f64,
    }

    /// What a ship's speed is read against (D67): its reference's velocity in the local frame and that reference's own
    /// acceleration. The brake, the thrust fade, the assist's safe speed and the hard ceiling read `v - velocity`, and the
    /// brake holds station on the reference with `accel` as feed-forward. Zero while the frame rides its anchor and the
    /// anchor is the reference, where every result keeps its old bits.
    #[derive(Clone, Copy, Debug, Default, PartialEq)]
    pub struct Rest {
        pub velocity: Vector3,
        pub accel: Vector3,
    }

    impl Rest {
        pub const ZERO: Rest = Rest { velocity: Vector3::ZERO, accel: Vector3::ZERO };

        pub fn is_zero(&self) -> bool {
            self.velocity == Vector3::ZERO && self.accel == Vector3::ZERO
        }
    }

    /// What one tick gives the step to apply and to hand back: the RCS force, the torque, the assist's cap, the environment
    /// force, the velocity after the hard ceiling (when it clamps), and the output rows. The nozzle forces at their world
    /// positions go into the buffer the caller passes `tick` (its own scratch, so a thread owns one).
    pub struct Applied {
        pub rcs_w: Vector3,
        pub torque_w: Vector3,
        pub cap: Option<Vector3>,
        pub env_force: Vector3,
        pub clamped: Option<Vector3>,
        pub out_vectors: [Vector3; 10],
        pub out_scalars: [f64; 12],
    }

    /// One tick for one ship: the model in the body frame, then the ship's force application in the world frame
    /// (`Ship._physics_process`), with the pod-yaw assist state carried in `pod_yaw` and the nozzle forces (force, world
    /// position) written into `nozzle_forces`, the caller's buffer. `env_w` is the pull the ship feels; `rest` is what its
    /// speed is read against (M6-T08).
    #[allow(clippy::too_many_arguments)]
    pub fn tick(
        body: &Body,
        pod_yaw: &mut f64,
        cmd: &Cmd,
        basis: &Basis,
        v_w: Vector3,
        w_w: Vector3,
        env_w: Vector3,
        rest: Rest,
        assist_on: bool,
        dt: f64,
        has_propellant: bool,
        nozzle_forces: &mut Vec<(Vector3, Vector3)>,
    ) -> Applied {
        // Speed against the reference; the brake's feed-forward is the pull less what the reference itself falls with.
        let at_rest = rest.is_zero();
        let v_rel = if at_rest { v_w } else { sub(v_w, rest.velocity) };
        let env_ff = if at_rest { env_w } else { sub(env_w, rest.accel) };
        let v_b = xform_inv(basis, v_rel);
        let w_b = xform_inv(basis, w_w);
        let env_b = xform_inv(basis, env_ff);
        let out = compute(
            body,
            pod_yaw,
            cmd,
            v_b,
            w_b,
            env_b,
            assist_on,
            dt,
            has_propellant,
        );
        let spec = &body.spec;
        // The ship's part: the governor's gain on every thrust, the forces at the nozzles, the assist's speed cap and the
        // environment, then the hard ceiling.
        let mass_f = spec.mass as f32;
        let env_force = scale(env_w, mass_f);
        let mut applied = env_force;
        let gain = thrust_gain(f64::from(length(v_rel)), spec.speed_limit_mps) as f32;
        nozzle_forces.clear();
        for k in 0..body.nozzle_groups.len() {
            let level = out.levels[body.nozzle_groups[k]];
            let magnitude = level * group_thrust(spec, body.nozzle_groups[k]);
            let force_b = scale(neg(body.nozzle_exhausts[k]), magnitude as f32);
            let force_w = scale(xform(basis, force_b), gain);
            let at_w = xform(basis, body.nozzle_positions[k]);
            nozzle_forces.push((force_w, at_w));
            applied = add(applied, force_w);
        }
        let rcs_w = scale(xform(basis, out.rcs_force), gain);
        applied = add(applied, rcs_w);
        let torque_w = xform(basis, out.tau_rcs);
        let cap = if assist_on {
            let net = scale(xform(basis, add(out.pod_force, out.rcs_force)), gain);
            let cap = assist_cap_correction(net, v_rel, spec.assist_speed_max_mps);
            applied = add(applied, cap);
            Some(cap)
        } else {
            None
        };
        let mut v_after = v_w;
        let mut clamped = None;
        if spec.speed_limit_mps > 0.0 && f64::from(length(v_rel)) > spec.speed_limit_mps {
            let capped = scale(normalized(v_rel), spec.speed_limit_mps as f32);
            v_after = if at_rest { capped } else { add(rest.velocity, capped) };
            clamped = Some(v_after);
        }
        Applied {
            rcs_w,
            torque_w,
            cap,
            env_force,
            clamped,
            out_vectors: [
                applied,
                torque_w,
                out.pod_force,
                out.tau_pods,
                out.rcs_force,
                out.tau_rcs,
                level_of(out.rcs_force, spec.rcs_force_max),
                level_of(out.tau_rcs, spec.rcs_torque_max),
                out.rate_target,
                v_after,
            ],
            out_scalars: [
                out.levels[0],
                out.levels[1],
                out.levels[2],
                out.levels[3],
                out.trim,
                out.pod_yaw_cmd,
                out.mass_flow,
                out.face_error,
                f64::from(u8::from(out.braking)),
                f64::from(u8::from(out.facing)),
                f64::from(u8::from(out.tracking)),
                f64::from(u8::from(!has_propellant)),
            ],
        }
    }

    // A ship type as `ShipSpec` holds it, in the units the flight model reads.
    pub struct Spec {
        pub mass: f64,
        pub pod_main_thrust: f64,
        pub pod_retro_thrust: f64,
        pub assist_gain_k: f64,
        pub pod_yaw_gain: f64,
        pub pod_yaw_deadzone: f64,
        pub pod_yaw_smoothing_s: f64,
        pub brake_gain_k: f64,
        pub exhaust_velocity: f64,
        pub speed_limit_mps: f64,
        pub assist_speed_max_mps: f64,
        pub inertia: Vector3,
        pub rcs_force_max: Vector3,
        pub rcs_torque_max: Vector3,
        pub rate_max_rad: Vector3,
    }

    // One tick's command for one ship, in pilot terms as `FlightCommand` carries them.
    pub struct Cmd {
        pub levels: [f64; GROUPS],
        pub strafe: Vector3,
        pub rot: Vector3,
        pub track_dir_b: Vector3,
        pub track_rate_b: Vector3,
        pub face_dir_b: Vector3,
        pub brake: bool,
        pub autotrack: bool,
    }

    // What `FlightModel.compute` reports, the parts the batch hands back.
    pub struct ModelOut {
        pub levels: [f64; GROUPS],
        pub pod_force: Vector3,
        pub tau_pods: Vector3,
        pub rcs_force: Vector3,
        pub tau_rcs: Vector3,
        pub rate_target: Vector3,
        pub trim: f64,
        pub pod_yaw_cmd: f64,
        pub mass_flow: f64,
        pub face_error: f64,
        pub braking: bool,
        pub facing: bool,
        pub tracking: bool,
    }

    // `FlightModel.compute`: one tick of architecture 5.2, body frame. The maths repeats GDScript's: 32-bit vectors,
    // 64-bit scalars, a scalar rounded to 32 bits before it scales a vector, the engine's order of operations and no fused
    // multiply-add, so both paths give the same forces bit for bit.
    #[allow(clippy::too_many_arguments)]
    pub fn compute(
        body: &Body,
        pod_yaw: &mut f64,
        cmd: &Cmd,
        v_b: Vector3,
        w_b: Vector3,
        env_b: Vector3,
        assist_on: bool,
        dt: f64,
        has_propellant: bool,
    ) -> ModelOut {
        let spec = &body.spec;
        // 1. Pilot demand per nozzle group and RCS translation.
        let mut levels = cmd.levels;
        let mut rcs_force = Vector3::new(
            (f64::from(cmd.strafe.x) * f64::from(spec.rcs_force_max.x)) as f32,
            (f64::from(cmd.strafe.y) * f64::from(spec.rcs_force_max.y)) as f32,
            0.0,
        );
        // 2. Brake overrides all translational demand: symmetric sides, so zero pod torque.
        if cmd.brake {
            let a_des = sub(scale(v_b, (-spec.brake_gain_k) as f32), env_b);
            let f_z = clampf(
                spec.mass * f64::from(a_des.z),
                -body.main_total,
                body.retro_total,
            );
            let main_level = if f_z < 0.0 && body.main_total > 0.0 {
                -f_z / body.main_total
            } else {
                0.0
            };
            let retro_level = if f_z > 0.0 && body.retro_total > 0.0 {
                f_z / body.retro_total
            } else {
                0.0
            };
            levels = [main_level, main_level, retro_level, retro_level];
            rcs_force = clamp_cw(
                scale(Vector3::new(a_des.x, a_des.y, 0.0), spec.mass as f32),
                neg(spec.rcs_force_max),
                spec.rcs_force_max,
            );
        }
        // 2b. No reaction mass: nothing that burns it can fire.
        if !has_propellant {
            levels = [0.0; GROUPS];
            rcs_force = Vector3::ZERO;
        }
        // 3. Pod torque about the centre of mass at the demanded levels.
        let mut group_torque_y = [0.0f64; GROUPS];
        let mut tau_pods = pod_torque(body, &levels, &mut group_torque_y);
        // 4. Rotation.
        let tracking = cmd.autotrack && !cmd.brake && !is_zero_approx(cmd.track_dir_b);
        let mut lam = 1.0;
        let mut rate_target = Vector3::ZERO;
        let mut facing = false;
        let mut face_error = 0.0;
        let mut pod_yaw_cmd = 0.0;
        if assist_on {
            update_pod_yaw(spec, pod_yaw, cmd, dt);
        }
        let tau_rcs;
        if cmd.brake {
            // 4c. All stop, or the nose onto `face_dir_b`; RCS supplies the whole rate-controller torque.
            let w_face = face_rate_target(spec, cmd.face_dir_b);
            tau_rcs = clamp_cw(
                sub(rate_torque(spec, w_face, w_b), tau_pods),
                neg(spec.rcs_torque_max),
                spec.rcs_torque_max,
            );
            rate_target = w_face;
            facing = !is_zero_approx(cmd.face_dir_b);
            face_error = f64::from(length(face_error_vector(cmd.face_dir_b)));
        } else if assist_on || tracking {
            let mut w_target;
            if tracking {
                w_target = track_rate_target(spec, cmd.track_dir_b, cmd.track_rate_b);
                w_target.z = (f64::from(cmd.rot.z)
                    * f64::from(AXIS_SIGN.z)
                    * f64::from(spec.rate_max_rad.z)) as f32;
                facing = true;
                face_error = f64::from(length(face_error_vector(cmd.track_dir_b)));
            } else {
                let rot = Vector3::new(
                    cmd.rot.x,
                    clampf(
                        f64::from(cmd.rot.y) + pod_yaw_command(spec, *pod_yaw),
                        -1.0,
                        1.0,
                    ) as f32,
                    cmd.rot.z,
                );
                w_target = mul_cw(mul_cw(rot, AXIS_SIGN), spec.rate_max_rad);
            }
            // 4b. Rate controller with the pods' torque as feed-forward; the groups fighting an RCS overflow are trimmed.
            let tau_des = rate_torque(spec, w_target, w_b);
            let mut residual = sub(tau_des, tau_pods);
            let overflow = sub(
                residual,
                clamp_cw(residual, neg(spec.rcs_torque_max), spec.rcs_torque_max),
            );
            if overflow.y != 0.0 {
                let overflow_y = f64::from(overflow.y);
                lam = yaw_trim_factor(overflow_y, &group_torque_y);
                if lam < 1.0 {
                    for g in 0..GROUPS {
                        if is_trim_cause(group_torque_y[g], overflow_y) {
                            levels[g] *= lam;
                        }
                    }
                    tau_pods = pod_torque(body, &levels, &mut group_torque_y);
                    residual = sub(tau_des, tau_pods);
                }
            }
            tau_rcs = clamp_cw(residual, neg(spec.rcs_torque_max), spec.rcs_torque_max);
            rate_target = w_target;
            if assist_on {
                pod_yaw_cmd = pod_yaw_command(spec, *pod_yaw);
            }
        } else {
            // Raw: the stick commands RCS torque directly.
            tau_rcs = mul_cw(mul_cw(cmd.rot, AXIS_SIGN), spec.rcs_torque_max);
        }
        // 5. Outputs.
        let mut pod_force = Vector3::ZERO;
        let mut thrust_sum = 0.0;
        for k in 0..body.nozzle_groups.len() {
            let g = body.nozzle_groups[k];
            let magnitude = levels[g] * group_thrust(spec, g);
            pod_force = add(
                pod_force,
                scale(neg(body.nozzle_exhausts[k]), magnitude as f32),
            );
            thrust_sum += magnitude.abs();
        }
        let mass_flow = if spec.exhaust_velocity > 0.0 {
            (thrust_sum + f64::from(length(rcs_force))) / spec.exhaust_velocity
        } else {
            0.0
        };
        ModelOut {
            levels,
            pod_force,
            tau_pods,
            rcs_force,
            tau_rcs,
            rate_target,
            trim: 1.0 - lam,
            pod_yaw_cmd,
            mass_flow,
            face_error,
            braking: cmd.brake,
            facing,
            tracking,
        }
    }

    fn group_thrust(spec: &Spec, group: usize) -> f64 {
        if group < 2 {
            spec.pod_main_thrust
        } else {
            spec.pod_retro_thrust
        }
    }

    // `FlightModel._pod_torque`: the groups' torque about the centre of mass, and each group's yaw part for the trim.
    fn pod_torque(
        body: &Body,
        levels: &[f64; GROUPS],
        group_torque_y: &mut [f64; GROUPS],
    ) -> Vector3 {
        let mut total = Vector3::ZERO;
        for g in 0..GROUPS {
            let tau_g = scale(
                body.torque_axes[g],
                (levels[g] * group_thrust(&body.spec, g)) as f32,
            );
            group_torque_y[g] = f64::from(tau_g.y);
            total = add(total, tau_g);
        }
        total
    }

    // `FlightAssist.update_pod_yaw`: the smoothed pod-yaw command, one tick on.
    fn update_pod_yaw(spec: &Spec, pod_yaw: &mut f64, cmd: &Cmd, dt: f64) {
        let raw = if cmd.brake {
            0.0
        } else {
            (cmd.levels[1] - cmd.levels[0]) + (cmd.levels[2] - cmd.levels[3])
        };
        let deadzone = clampf(spec.pod_yaw_deadzone, 0.0, 0.999);
        let shaped = signf(raw) * maxf(0.0, raw.abs() - deadzone) / (1.0 - deadzone);
        let target = clampf(shaped, -1.0, 1.0);
        let tau = spec.pod_yaw_smoothing_s;
        let mut alpha = 1.0;
        if tau > 0.0 && dt > 0.0 {
            alpha = 1.0 - (-dt / tau).exp();
        } else if dt <= 0.0 {
            alpha = 0.0;
        }
        (*pod_yaw) += (target - (*pod_yaw)) * alpha;
    }

    fn pod_yaw_command(spec: &Spec, smoothed: f64) -> f64 {
        spec.pod_yaw_gain * smoothed
    }

    // `FlightAssist.rate_torque`: the P rate controller's torque.
    fn rate_torque(spec: &Spec, w_target: Vector3, w_b: Vector3) -> Vector3 {
        mul_cw(
            spec.inertia,
            scale(sub(w_target, w_b), spec.assist_gain_k as f32),
        )
    }

    fn turn_accel_max(spec: &Spec) -> f64 {
        let pitch = if spec.inertia.x > 0.0 {
            f64::from(spec.rcs_torque_max.x) / f64::from(spec.inertia.x)
        } else {
            0.0
        };
        let yaw = if spec.inertia.y > 0.0 {
            f64::from(spec.rcs_torque_max.y) / f64::from(spec.inertia.y)
        } else {
            0.0
        };
        maxf(0.0, minf(pitch, yaw))
    }

    // `FlightAssist.face_rate_target`: the rate that swings the nose onto `dir_b`, stoppable within RCS authority.
    fn face_rate_target(spec: &Spec, dir_b: Vector3) -> Vector3 {
        let error = face_error_vector(dir_b);
        let angle = f64::from(length(error));
        if angle == 0.0 {
            return Vector3::ZERO;
        }
        let decel = FACE_DECEL_FRACTION * turn_accel_max(spec);
        let rate = minf(
            spec.assist_gain_k / 4.0 * angle,
            (2.0 * decel * angle).sqrt(),
        );
        let w = scale(div_s(error, angle as f32), rate as f32);
        let cap = spec.rate_max_rad;
        let mut s = 1.0;
        if f64::from(w.x.abs()) > f64::from(cap.x) {
            s = minf(s, f64::from(cap.x) / f64::from(w.x.abs()));
        }
        if f64::from(w.y.abs()) > f64::from(cap.y) {
            s = minf(s, f64::from(cap.y) / f64::from(w.y.abs()));
        }
        scale(w, s as f32)
    }

    // `FlightAssist.track_rate_target`: the face correction plus the rate the lead direction itself turns at.
    fn track_rate_target(spec: &Spec, dir_b: Vector3, dir_rate_b: Vector3) -> Vector3 {
        let mut w = face_rate_target(spec, dir_b);
        w.x = (f64::from(w.x) + f64::from(dir_rate_b.x)) as f32;
        w.y = (f64::from(w.y) + f64::from(dir_rate_b.y)) as f32;
        let cap = spec.rate_max_rad;
        w.x = clampf(f64::from(w.x), -f64::from(cap.x), f64::from(cap.x)) as f32;
        w.y = clampf(f64::from(w.y), -f64::from(cap.y), f64::from(cap.y)) as f32;
        w
    }

    // `FlightAssist.face_error_vector`: the shortest rotation that puts the nose on `dir_b`; pitch and yaw only.
    fn face_error_vector(dir_b: Vector3) -> Vector3 {
        if is_zero_approx(dir_b) {
            return Vector3::ZERO;
        }
        let d = normalized(dir_b);
        let axis = Vector3::new(d.y, -d.x, 0.0);
        let sine = f64::from(length(axis));
        let angle = sine.atan2(f64::from(-d.z));
        if angle == 0.0 {
            return Vector3::ZERO;
        }
        if sine < 1e-9 {
            return Vector3::new(angle as f32, 0.0, 0.0);
        }
        scale(axis, (angle / sine) as f32)
    }

    // `FlightAssist.yaw_trim_factor`: how far the groups causing an RCS overflow are scaled down.
    fn yaw_trim_factor(overflow_y: f64, group_torque_y: &[f64; GROUPS]) -> f64 {
        if overflow_y == 0.0 {
            return 1.0;
        }
        let mut cause_total = 0.0;
        for &t in group_torque_y {
            if is_trim_cause(t, overflow_y) {
                cause_total += t.abs();
            }
        }
        if cause_total <= 0.0 {
            return 1.0;
        }
        maxf(0.0, 1.0 - overflow_y.abs() / cause_total)
    }

    fn is_trim_cause(torque_y: f64, overflow_y: f64) -> bool {
        overflow_y != 0.0 && torque_y != 0.0 && signf(torque_y) == -signf(overflow_y)
    }

    // `SpeedGovernor.thrust_gain`: the share of the thrust that reaches the hull at this speed.
    fn thrust_gain(speed: f64, limit: f64) -> f64 {
        if limit <= 0.0 {
            return 1.0;
        }
        let ratio = clampf(speed / limit, 0.0, 1.0);
        (1.0 - ratio * ratio).sqrt()
    }

    // `SpeedGovernor.assist_cap_correction`: cancels the part of the force that would speed the ship past the cap.
    fn assist_cap_correction(force: Vector3, velocity: Vector3, cap: f64) -> Vector3 {
        if cap <= 0.0 {
            return Vector3::ZERO;
        }
        let speed = f64::from(length(velocity));
        if speed < cap {
            return Vector3::ZERO;
        }
        let heading = div_s(velocity, speed as f32);
        let along = f64::from(dot(force, heading));
        if along <= 0.0 {
            return Vector3::ZERO;
        }
        scale(neg(heading), along as f32)
    }

    // `FlightModel._level_of`: a vector as a share of its per-axis limit.
    fn level_of(value: Vector3, limit: Vector3) -> Vector3 {
        let part = |v: f32, l: f32| {
            if l > 0.0 {
                (f64::from(v) / f64::from(l)) as f32
            } else {
                0.0
            }
        };
        Vector3::new(
            part(value.x, limit.x),
            part(value.y, limit.y),
            part(value.z, limit.z),
        )
    }
}

/// The AI pilot's per-contact loops (`ScsPilotKernels`, M4-T16): avoidance over the contacts and statics, the fire lane,
/// and the context lists. Each is a pure function of the rows and one ship's inputs and writes only that ship's result,
/// so T18 can run the ships of a tick on worker threads. The maths repeats `AvoidanceMath`, `FireLane` and
/// `AiContext.refresh` step for step: 32-bit vectors, 64-bit scalars, a scalar rounded to 32 bits before it scales a
/// vector, the engine's order of operations, so both paths give the same bits.
pub mod pilot {
    use std::f64::consts::PI;

    use godot::builtin::Vector3;

    use crate::rows::Rows;
    use crate::surface;
    use crate::v3::{
        FORWARD, RIGHT, UP, add, clampf, cross, div_s, dot, length, length_squared, maxf, minf,
        normalized, rotated, scale, sub,
    };

    // `AvoidanceMath`'s constants.
    pub const MARGIN_M: f64 = 15.0;
    const HORIZON_MIN_S: f64 = 4.0;
    const MATCHED_MPS: f64 = 3.0;
    const PUSH_S: f64 = 2.0;
    const AIM_PAST_M: f64 = 1.0;
    const TIE_M: f64 = 0.1;
    const TIE_SPREAD_DEG: f64 = 40.0;
    const URGENT_SETTLE_S: f64 = 1.0;
    const MIN_TIME_S: f64 = 0.25;
    // `FireLane.CLEARANCE_M`.
    pub const CLEARANCE_M: f64 = 5.0;

    /// `Factions.Relation` values, as the relation rows hold them (one per faction of the core's table).
    pub const FRIENDLY: u8 = 0;
    pub const NEUTRAL: u8 = 1;
    pub const HOSTILE: u8 = 2;

    /// The thinking ship as avoidance sees it: its pose, size, what it can do, and its tie-break (`hash(seed)`, passed in
    /// so the kernel holds no hash of its own).
    pub struct Ship {
        pub position: Vector3,
        pub velocity: Vector3,
        pub radius: f64,
        pub a_retro: f64,
        pub rate_max_x: f64,
        pub rate_max_y: f64,
        pub a_rcs_x: f64,
        pub a_rcs_y: f64,
        pub tie_hash: i64,
    }

    /// `AvoidanceMath.filter`'s answer: the wish with every threat's dodge added, and whether a dodge is urgent.
    pub struct Avoided {
        pub v_des: Vector3,
        pub urgent: bool,
        /// The ship is closing on a big hull faster than its side thrusters can stop it in the room left (M7-T10): it
        /// must turn its nose and burn for `v_des` with everything.
        pub pull_out: bool,
    }

    /// `AiContext.refresh`'s lists for one ship: the hostile ships (their places in the contact list), their offsets and
    /// ranges, the friendly ids (the ship's own first), and the leader's place, or -1. The caller owns it and reuses it.
    #[derive(Default)]
    pub struct Lists {
        pub hostiles: Vec<i32>,
        pub offsets: Vec<Vector3>,
        pub ranges: Vec<f64>,
        pub friendly_ids: Vec<i64>,
        pub leader: i32,
    }

    /// `AvoidanceMath.filter` over the rows `contacts` (but the one whose id is `exempt_id`, a rammer's target) and then
    /// the rows `statics`. A row the table does not hold is no threat.
    pub fn avoid(
        rows: &Rows,
        ship: &Ship,
        contacts: &[i32],
        statics: &[i32],
        exempt_id: i64,
        v_des: Vector3,
    ) -> Avoided {
        let mut dodge = Vector3::new(0.0, 0.0, 0.0);
        let mut urgent = false;
        let mut pull_out = false;
        // The big hulls near enough to shape the wish: each one's outward normal here, how much of a way in it forbids
        // (0..1), its velocity and how far it is. A handful at most (the station's frame and drum).
        let mut walls: [(Vector3, f32, Vector3, f32); 4] = [(Vector3::ZERO, 0.0, Vector3::ZERO, 0.0); 4];
        let mut wall_count = 0;
        let a_stop = maxf(ship.a_retro, 0.01);
        let turn_rate = maxf(minf(ship.rate_max_x, ship.rate_max_y), 0.01);
        let urgent_s = 0.5 * PI / turn_rate + URGENT_SETTLE_S;
        let a_side = maxf(minf(ship.a_rcs_x, ship.a_rcs_y), 0.01);
        let listed = contacts
            .iter()
            .filter_map(|&r| row(rows, r))
            .filter(|&j| exempt_id == 0 || rows.ids[j] != exempt_id)
            .chain(statics.iter().filter_map(|&r| row(rows, r)));
        for j in listed {
            let c_velocity = rows.velocities[j];
            if let Some(surface) = rows.surface(j) {
                // A big hull (M7-T06): each of its volumes near enough to matter is a threat at its nearest point, so a
                // ship goes round the station's skin, not its 4 km bounding sphere, and keeps off a tunnel's walls.
                let reach = ship.radius + MARGIN_M;
                // Near the skin a wish that heads into it is turned along it (M7-T10), so a ship whose way is through
                // the hull goes round instead of hanging beside it with its wish cancelled.
                let (slid, pull, wall) = slide_along(rows, j, ship, v_des, reach, a_stop, urgent_s);
                if wall.1 > 0.0 && wall_count < walls.len() {
                    walls[wall_count] = (wall.0, 1.0, c_velocity, wall.2);
                    wall_count += 1;
                }
                pull_out = pull_out || pull;
                urgent = urgent || pull;
                dodge = add(dodge, sub(slid, v_des));
                let w = sub(slid, c_velocity);
                let speed = f64::from(length(w));
                let relative = f64::from(length(sub(ship.velocity, c_velocity)));
                let horizon = maxf(
                    maxf(HORIZON_MIN_S, maxf(speed, relative) / a_stop),
                    (2.0 * reach / a_side).sqrt() + URGENT_SETTLE_S,
                );
                // A turning hull is kept off where its parts sweep (the drum's arms come round at 40 m/s), not where
                // they are this tick.
                let within = reach + speed * horizon;
                let mut meet = |near: Vector3, _: f64| {
                    if let Some((push, hurry)) =
                        threat(ship, near, c_velocity, 0.0, true, slid, a_stop, a_side, urgent_s)
                    {
                        dodge = add(dodge, push);
                        urgent = urgent || hurry;
                    }
                };
                if surface.spin_rad_s != 0.0 {
                    surface::near_swept(rows, j, ship.position, within, &mut meet);
                } else {
                    surface::near_volumes(rows, j, ship.position, within, &mut meet);
                }
                continue;
            }
            let Some((push, hurry)) = threat(
                ship,
                rows.positions[j],
                c_velocity,
                rows.radii[j],
                rows.is_static[j] || rows.is_civilian(j),
                v_des,
                a_stop,
                a_side,
                urgent_s,
            ) else {
                continue;
            };
            dodge = add(dodge, push);
            urgent = urgent || hurry;
        }
        // Between two hulls (the drum under the spine) one's dodge must not lead into the other: what is left of a way
        // in to each is taken out of the sum, twice round so the second does not undo the first.
        // The nearest hull has the last word.
        walls[..wall_count].sort_by(|a, b| b.3.total_cmp(&a.3));
        let mut v_out = add(v_des, dodge);
        for _ in 0..2 {
            for &(n, share, c_velocity, _) in &walls[..wall_count] {
                let into = -dot(sub(v_out, c_velocity), n);
                if into > 0.0 {
                    v_out = add(v_out, scale(n, into * share));
                }
            }
        }
        Avoided {
            v_des: v_out,
            urgent,
            pull_out,
        }
    }

    /// How far outside a big hull's keep-off distance a wish into it starts to turn along the skin, m.
    pub const SLIDE_BAND_M: f64 = 60.0;
    // A wish this much along the skin already is kept; under it (head on) the ship's seeded side picks the way round.
    const SLIDE_HEAD_ON: f64 = 0.25;

    // The wish `v_des` as big hull `j` lets it stand (M7-T10), and whether the ship must pull out. Within `SLIDE_BAND_M` of
    // its keep-off distance `reach`, the part of the wish that heads into the nearest skin is turned along it, wholly at
    // `reach`, at the wish's own speed. A ship already falling at the skin faster than it can be stopped in the room
    // left (a turn of `turn_s`, then `a_stop`) pulls out: its wish loses all of its way in, wherever it is.
    // A wish that does not close on the skin, and a ship farther out, keep theirs.
    fn slide_along(
        rows: &Rows,
        j: usize,
        ship: &Ship,
        v_des: Vector3,
        reach: f64,
        a_stop: f64,
        turn_s: f64,
    ) -> (Vector3, bool, (Vector3, f32, f32)) {
        let Some((near, d)) = surface::nearest_to_avoid(rows, j, ship.position) else {
            return (v_des, false, (Vector3::ZERO, 0.0, 0.0));
        };
        // Inside a turning hull's swept ring the point given marks the way out; inside a volume at rest there is none.
        let off = sub(ship.position, near);
        if f64::from(length(off)) < 1e-3 {
            return (v_des, false, (Vector3::ZERO, 0.0, 0.0));
        }
        let c_velocity = rows.velocities[j];
        let n = normalized(off);
        let falling = -f64::from(dot(sub(ship.velocity, c_velocity), n));
        let pull = falling > MATCHED_MPS
            && d - reach <= falling * turn_s + falling * falling / (2.0 * a_stop);
        let soft = reach + SLIDE_BAND_M;
        let share = if pull {
            1.0
        } else {
            clampf((soft - d) / SLIDE_BAND_M, 0.0, 1.0) as f32
        };
        let wall = (n, share, d as f32);
        let w = sub(v_des, c_velocity);
        let into = -f64::from(dot(w, n));
        if into <= MATCHED_MPS || (d >= soft && !pull) {
            return (v_des, pull, wall);
        }
        let speed = f64::from(length(w));
        let mut along = add(w, scale(n, into as f32));
        if f64::from(length(along)) < SLIDE_HEAD_ON * speed {
            along = tie_direction(scale(n, -1.0), ship.tie_hash);
        }
        let along = scale(normalized(along), speed as f32);
        (
            add(c_velocity, add(scale(w, 1.0 - share), scale(along, share))),
            pull,
            wall,
        )
    }

    // One threat's dodge for `AvoidanceMath.filter` and whether it is urgent: a body at `c_position` moving at `c_velocity`
    // with `c_radius`; `early` sees it soon enough to go round (a rock, a mine, a big hull).
    #[allow(clippy::too_many_arguments)]
    fn threat(
        ship: &Ship,
        c_position: Vector3,
        c_velocity: Vector3,
        c_radius: f64,
        early: bool,
        v_des: Vector3,
        a_stop: f64,
        a_side: f64,
        urgent_s: f64,
    ) -> Option<(Vector3, bool)> {
        let reach = ship.radius + c_radius + MARGIN_M;
        let s = sub(ship.position, c_position);
        let w = sub(v_des, c_velocity);
        let d = f64::from(length(s));
        if d < reach {
            let out_dir = if d > TIE_M {
                div_s(s, d as f32)
            } else {
                tie_direction(w, ship.tie_hash)
            };
            let closing = -f64::from(dot(w, out_dir));
            let push = (reach - d) / PUSH_S + maxf(closing, 0.0);
            return Some((scale(out_dir, push as f32), closing > MATCHED_MPS));
        }
        let speed_sq = f64::from(length_squared(w));
        if speed_sq < MATCHED_MPS * MATCHED_MPS {
            return None;
        }
        let t_star = -f64::from(dot(s, w)) / speed_sq;
        if t_star <= 0.0 {
            return None; // opening
        }
        let speed = speed_sq.sqrt();
        let relative = f64::from(length(sub(ship.velocity, c_velocity)));
        let mut horizon = maxf(HORIZON_MIN_S, maxf(speed, relative) / a_stop);
        // A rock, a mine or a big hull (M5-T16, M7-T06) is seen early enough to go round: at least the time a sideways
        // burn takes to clear its reach.
        if early {
            horizon = maxf(horizon, (2.0 * reach / a_side).sqrt() + URGENT_SETTLE_S);
        }
        if t_star > horizon {
            return None;
        }
        let offset = add(s, scale(w, t_star as f32));
        let miss = f64::from(length(offset));
        if miss >= reach {
            return None;
        }
        let side = if miss > TIE_M {
            div_s(offset, miss as f32)
        } else {
            tie_direction(w, ship.tie_hash)
        };
        let x = sideways_speed(miss, speed * t_star, reach + AIM_PAST_M, speed, t_star);
        Some((scale(side, x as f32), t_star < urgent_s))
    }

    /// `FireLane.clear` over the rows `contacts`: true when nothing that must not be hit sits in the lane from `position`
    /// along `aim_dir`, short of `range_m`. `relations` is the shooter's relation to each faction of the table.
    pub fn fire_lane(
        rows: &Rows,
        relations: &[u8],
        contacts: &[i32],
        position: Vector3,
        aim_dir: Vector3,
        range_m: f64,
        target_id: i64,
        friendly_fire: bool,
    ) -> bool {
        if f64::from(length_squared(aim_dir)) < 1e-12 || range_m <= 0.0 {
            return true;
        }
        let dir = normalized(aim_dir);
        for j in contacts.iter().filter_map(|&r| row(rows, r)) {
            if rows.ids[j] == target_id
                || !protected(relation(rows, relations, j), rows.rigid[j], friendly_fire)
            {
                continue;
            }
            if rows.surface(j).is_some() {
                // A big hull (M7-T06) is in the lane where its volumes are, not across its bounding sphere.
                let end = add(position, scale(dir, range_m as f32));
                if surface::segment_enters(rows, j, position, end, CLEARANCE_M) {
                    return false;
                }
                continue;
            }
            let rel = sub(rows.positions[j], position);
            let along = f64::from(dot(rel, dir));
            if along <= 0.0 || along >= range_m {
                continue;
            }
            let width = rows.radii[j] + CLEARANCE_M;
            if f64::from(length_squared(sub(rel, scale(dir, along as f32)))) < width * width {
                return false;
            }
        }
        true
    }

    /// `AiContext.refresh`'s split of the rows `contacts` into `out`: hostile ships with their offsets and ranges from
    /// `position`, the friendly ids after `self_id` (when not 0), and the place of the friendly whose id is `leader_id`.
    pub fn context_lists(
        rows: &Rows,
        relations: &[u8],
        contacts: &[i32],
        position: Vector3,
        self_id: i64,
        leader_id: i64,
        out: &mut Lists,
    ) {
        out.hostiles.clear();
        out.offsets.clear();
        out.ranges.clear();
        out.friendly_ids.clear();
        out.leader = -1;
        if self_id != 0 {
            out.friendly_ids.push(self_id);
        }
        for (k, &r) in contacts.iter().enumerate() {
            let Some(j) = row(rows, r) else {
                continue;
            };
            match relation(rows, relations, j) {
                HOSTILE => {
                    if rows.rigid[j] {
                        let offset = sub(rows.positions[j], position);
                        out.hostiles.push(k as i32);
                        out.offsets.push(offset);
                        out.ranges.push(f64::from(length(offset)));
                    }
                }
                FRIENDLY => {
                    out.friendly_ids.push(rows.ids[j]);
                    if rows.ids[j] == leader_id {
                        out.leader = k as i32;
                    }
                }
                _ => {}
            }
        }
    }

    // The row index `r` names, when the table holds it.
    fn row(rows: &Rows, r: i32) -> Option<usize> {
        usize::try_from(r).ok().filter(|&j| j < rows.ids.len())
    }

    // How the asking ship regards row `j`'s faction; a faction its row does not reach is neutral.
    fn relation(rows: &Rows, relations: &[u8], j: usize) -> u8 {
        relations
            .get(rows.faction_ix[j] as usize)
            .copied()
            .unwrap_or(NEUTRAL)
    }

    // `FireLane._protected`: a friendly always, any ship but a hostile with friendly fire on.
    fn protected(relation: u8, is_ship: bool, friendly_fire: bool) -> bool {
        relation == FRIENDLY || (friendly_fire && is_ship && relation != HOSTILE)
    }

    // `AvoidanceMath.tie_direction`: "right" of the relative velocity with world up (world right when it is nearly
    // vertical), turned about it by the seeded angle, so two ships dead on dodge apart for any pair of seeds.
    fn tie_direction(rel_vel: Vector3, tie_hash: i64) -> Vector3 {
        let axis = if f64::from(length_squared(rel_vel)) > 1e-12 {
            normalized(rel_vel)
        } else {
            FORWARD
        };
        let reference = if f64::from(dot(axis, UP)).abs() < 0.9 {
            UP
        } else {
            RIGHT
        };
        let base = normalized(cross(axis, reference));
        rotated(base, axis, tie_angle(tie_hash) as f32)
    }

    /// The tie's seeded turn, rad: `deg_to_rad(TIE_SPREAD_DEG) * (2 * unit - 1)`. The engine's `deg_to_rad` multiplies by
    /// the factor `PI / 180` (not by `PI`, then divides), so the double is the same bits.
    pub fn tie_angle(tie_hash: i64) -> f64 {
        let unit = tie_hash.rem_euclid(65536) as f64 / 65535.0;
        TIE_SPREAD_DEG * (PI / 180.0) * (2.0 * unit - 1.0)
    }

    // `AvoidanceMath._sideways_speed`: the sideways speed that lifts the straight-line miss to `target`, at most `speed`.
    fn sideways_speed(miss: f64, along: f64, target: f64, speed: f64, t_star: f64) -> f64 {
        let x = if along > target + 1e-3 {
            let distance_sq = along * along + miss * miss;
            speed * (target * (distance_sq - target * target).sqrt() - miss * along)
                / (along * along - target * target)
        } else {
            (target - miss) / maxf(t_star, MIN_TIME_S)
        };
        clampf(x, 0.0, speed)
    }
}

/// The static rows' shift (M6-T06, L4): a rebase or the frame's drift moves one world's rocks and mines by one vector, in
/// place, so a pure shift costs one pass and no rebuild.
pub mod statics {
    use godot::builtin::Vector3;

    /// Adds `offset` to every position whose world is `owner`, in 32-bit as GDScript's `+=` does, so the result is the
    /// same bits a row registered there would hold. Returns how many moved; none when the columns differ in length.
    pub fn shift_owned(positions: &mut [Vector3], worlds: &[i64], owner: i64, offset: Vector3) -> usize {
        if positions.len() != worlds.len() {
            return 0;
        }
        let mut moved = 0;
        for (p, &world) in positions.iter_mut().zip(worlds) {
            if world == owner {
                *p = Vector3::new(p.x + offset.x, p.y + offset.y, p.z + offset.z);
                moved += 1;
            }
        }
        moved
    }
}

/// Which rocks live as Jolt bodies (`ScsRockStream`, M6-T21): the ones a rigid hull could reach soon. The rest stay static
/// rows only, so a rebase, or a tick off the anchor, moves only the few that live. Promoted and demoted with hysteresis, as
/// the tier is, so a rock on the line does not flip every tick.
pub mod rock_stream {
    use godot::builtin::{Basis, Vector3};

    use crate::rows::{FLAG_RIGID, Rows};
    use crate::v3::{dist_sq, length, sub, xform_inv};

    // The grid's smallest cell, metres, and the most cells it holds: a hull's look then covers a handful of cells.
    const CELL_M: f32 = 512.0;
    const MAX_CELLS: usize = 1 << 15;

    /// The rigid hull rows as spheres in the rocks' own frame (their owner at `origin` with the orthonormal `basis`): each
    /// hull swept over `lookahead` s at its velocity against the rocks (which move at `rest`), as the swept segment's
    /// middle with reach `|segment| / 2 + radius + margin`.
    pub fn hull_spheres(
        rows: &Rows,
        hull_rows: &[u32],
        origin: Vector3,
        basis: &Basis,
        rest: Vector3,
        lookahead: f64,
        margin_m: f64,
        mids: &mut Vec<Vector3>,
        reach: &mut Vec<f64>,
    ) {
        mids.clear();
        reach.clear();
        let half = (0.5 * lookahead) as f32;
        for &row in hull_rows {
            let j = row as usize;
            if rows.flags[j] & FLAG_RIGID == 0 {
                continue;
            }
            let at = xform_inv(basis, sub(rows.positions[j], origin));
            let v = xform_inv(basis, sub(rows.velocities[j], rest));
            mids.push(Vector3::new(at.x + v.x * half, at.y + v.y * half, at.z + v.z * half));
            reach.push(f64::from(length(v)) * f64::from(half) + rows.radii[j] + margin_m);
        }
    }

    /// The rocks in a dense grid of equal cells over their bounds, each rock listed in every cell its sphere's box
    /// touches. Built once: the rocks never move in their owner's frame.
    #[derive(Default)]
    pub struct Grid {
        low: Vector3,
        cell: f32,
        dims: [usize; 3],
        start: Vec<u32>,
        items: Vec<u32>,
    }

    impl Grid {
        pub fn build(rocks: &[Vector3], radii: &[f64]) -> Grid {
            let mut grid = Grid::default();
            if rocks.is_empty() {
                return grid;
            }
            let (mut low, mut high) = (Vector3::splat(f32::MAX), Vector3::splat(f32::MIN));
            for (p, &r) in rocks.iter().zip(radii) {
                let r = r as f32;
                low = Vector3::new(low.x.min(p.x - r), low.y.min(p.y - r), low.z.min(p.z - r));
                high = Vector3::new(high.x.max(p.x + r), high.y.max(p.y + r), high.z.max(p.z + r));
            }
            let mut cell = CELL_M;
            let size = sub(high, low);
            let count = |c: f32| -> [usize; 3] {
                [size.x, size.y, size.z].map(|s| ((s / c).floor() as usize).saturating_add(1))
            };
            while count(cell).iter().product::<usize>() > MAX_CELLS {
                cell *= 2.0;
            }
            grid.low = low;
            grid.cell = cell;
            grid.dims = count(cell);
            let total: usize = grid.dims.iter().product();
            let mut counts = vec![0u32; total + 1];
            for (p, &r) in rocks.iter().zip(radii) {
                grid.each_cell(*p, r, |c| counts[c] += 1);
            }
            let mut running = 0u32;
            grid.start = Vec::with_capacity(total + 1);
            for &c in &counts[..total] {
                grid.start.push(running);
                running += c;
            }
            grid.start.push(running);
            grid.items = vec![0; running as usize];
            let mut fill: Vec<u32> = grid.start[..total].to_vec();
            for (s, (p, &r)) in rocks.iter().zip(radii).enumerate() {
                let (items, fill) = (&mut grid.items, &mut fill);
                Self::cells_of(grid.low, grid.cell, grid.dims, *p, r, |c| {
                    items[fill[c] as usize] = s as u32;
                    fill[c] += 1;
                });
            }
            grid
        }

        /// Calls `f` with every rock listed in a cell that the box of the sphere (`at`, `reach`) touches; a rock may come
        /// more than once.
        pub fn each_near(&self, at: Vector3, reach: f64, mut f: impl FnMut(u32)) {
            if self.items.is_empty() {
                return;
            }
            self.each_cell(at, reach, |c| {
                for &s in &self.items[self.start[c] as usize..self.start[c + 1] as usize] {
                    f(s);
                }
            });
        }

        fn each_cell(&self, at: Vector3, reach: f64, f: impl FnMut(usize)) {
            Self::cells_of(self.low, self.cell, self.dims, at, reach, f);
        }

        // The cells the box of the sphere (`at`, `reach`) touches, clamped to the grid; none when it misses the grid.
        fn cells_of(low: Vector3, cell: f32, dims: [usize; 3], at: Vector3, reach: f64, mut f: impl FnMut(usize)) {
            let r = reach as f32;
            let lo = [at.x - r - low.x, at.y - r - low.y, at.z - r - low.z];
            let hi = [at.x + r - low.x, at.y + r - low.y, at.z + r - low.z];
            let mut a = [0usize; 3];
            let mut b = [0usize; 3];
            for k in 0..3 {
                let last = dims[k] as f32 - 1.0;
                let (from, to) = ((lo[k] / cell).floor(), (hi[k] / cell).floor());
                if !(to >= 0.0 && from <= last) {
                    return; // outside the grid on this axis (or not a number)
                }
                a[k] = from.max(0.0) as usize;
                b[k] = to.min(last) as usize;
            }
            for x in a[0]..=b[0] {
                for y in a[1]..=b[1] {
                    for z in a[2]..=b[2] {
                        f((x * dims[1] + y) * dims[2] + z);
                    }
                }
            }
        }
    }

    /// The rocks, their grid, the live flags and the scratch of the last step.
    #[derive(Default)]
    pub struct Stream {
        pub live: Vec<bool>,
        /// Hull and rock pairs the last step put to the sphere test (the work count).
        pub visited: usize,
        rocks: Vec<Vector3>,
        radii: Vec<f64>,
        grid: Grid,
        // The step that last found each rock inside a hull's demotion reach, and inside its promotion reach.
        kept: Vec<u32>,
        wanted: Vec<u32>,
        stamp: u32,
        // The hull that last listed each rock, so a rock in several cells is tested once a hull.
        seen: Vec<u32>,
        look: u32,
    }

    impl Stream {
        /// Holds `rocks` (centres in the owner's frame) and `radii`, none live. False, holding none, when they differ in
        /// length.
        pub fn reset(&mut self, rocks: &[Vector3], radii: &[f64]) -> bool {
            let ok = rocks.len() == radii.len();
            let n = if ok { rocks.len() } else { 0 };
            self.rocks = rocks[..n].to_vec();
            self.radii = radii[..n].to_vec();
            self.grid = Grid::build(&self.rocks, &self.radii);
            self.live = vec![false; n];
            self.kept = vec![0; n];
            self.wanted = vec![0; n];
            self.seen = vec![0; n];
            self.stamp = 0;
            self.look = 0;
            ok
        }

        pub fn live_count(&self) -> usize {
            self.live.iter().filter(|&&l| l).count()
        }

        /// One step over the hulls (`mids` and promotion `reach`, from `hull_spheres`). A hull wants every rock inside its
        /// promotion reach and keeps every live one inside that reach times `keep_scale`. A dormant rock that is wanted is
        /// promoted; a live rock no hull kept for more than `hold` steps is demoted (a hull destroyed against it leaves the
        /// rows before it leaves Jolt). The changes go to `changes` in rock order: a promotion as the rock's index, a
        /// demotion as `-(index + 1)`.
        pub fn step(&mut self, mids: &[Vector3], reach: &[f64], keep_scale: f64, hold: u32, changes: &mut Vec<i64>) {
            changes.clear();
            self.visited = 0;
            let n = self.rocks.len();
            if n == 0 {
                return;
            }
            self.stamp = self.stamp.wrapping_add(1).max(1);
            let stamp = self.stamp;
            for (k, &at) in mids.iter().enumerate() {
                let promote = reach[k];
                let keep = promote * keep_scale;
                self.look = self.look.wrapping_add(1);
                if self.look == 0 {
                    self.seen.iter_mut().for_each(|s| *s = 0);
                    self.look = 1;
                }
                let look = self.look;
                let (rocks, radii, seen, kept, wanted) =
                    (&self.rocks, &self.radii, &mut self.seen, &mut self.kept, &mut self.wanted);
                let visited = &mut self.visited;
                self.grid.each_near(at, keep, |s| {
                    let s = s as usize;
                    if seen[s] == look {
                        return;
                    }
                    seen[s] = look;
                    *visited += 1;
                    let d2 = f64::from(dist_sq(at, rocks[s]));
                    let keep_r = keep + radii[s];
                    if d2 > keep_r * keep_r {
                        return;
                    }
                    kept[s] = stamp;
                    let promote_r = promote + radii[s];
                    if d2 <= promote_r * promote_r {
                        wanted[s] = stamp;
                    }
                });
            }
            for s in 0..n {
                if !self.live[s] && self.wanted[s] == stamp {
                    self.live[s] = true;
                    self.kept[s] = stamp;
                    changes.push(s as i64);
                } else if self.live[s] && stamp.wrapping_sub(self.kept[s]) > hold {
                    self.live[s] = false;
                    changes.push(-(s as i64) - 1);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests;
