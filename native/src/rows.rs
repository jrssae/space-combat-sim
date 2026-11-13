// The core's row tables (M4-T15, docs/architecture.md 17.13): plain data, the only thing the kernels import from the
// crate. Nothing here can reach the engine: the columns are value types and the methods clear them.
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::{Basis, Vector3};

/// Row flags: a rigid body in Jolt (the flight step's and the ram phase's), an active hull (`Damageable.is_active()`: the
/// sweep and the rams see it), a hull at all, a row added after the tick's first sync (a ship back from the pool), a
/// low-attention tier row with no body and no node (M4-T21: integrated by the tier, skipped by the kernels that write to
/// a body or fire from one), and a hulk (a tier row that drifts with no brain and no force).
pub const FLAG_RIGID: u32 = 1;
pub const FLAG_HULL: u32 = 2;
pub const FLAG_HULL_ACTIVE: u32 = 4;
pub const FLAG_LATE: u32 = 8;
pub const FLAG_TIER: u32 = 16;
pub const FLAG_HULK: u32 = 32;

/// A row's role (M5-T16, Q24): what the ship is for, beside its faction and kind. A civilian is a big non-combat hull (a
/// freighter up to 260 m) that the brains, the raiders' picks, the turrets, avoidance and the tier treat by its size.
pub const ROLE_COMBAT: u8 = 0;
pub const ROLE_CIVILIAN: u8 = 1;

/// The scan's rows, column by column: the bodies in registry order (active markers, then active hulls with no active
/// marker), the static rows, then any row added after the tick's first sync. Read by the kernels through `bind()`, from
/// several threads at once (M4-T18): every column is plain data the threads may share; the display names, an engine
/// string, live beside the rows in the core.
#[derive(Default)]
pub struct Rows {
    pub body_ids: Vec<i64>,
    pub ids: Vec<i64>,
    pub faction_ix: Vec<u32>,
    pub positions: Vec<Vector3>,
    pub velocities: Vec<Vector3>,
    pub bases: Vec<Basis>,
    pub angular: Vec<Vector3>,
    pub radii: Vec<f64>,
    pub kinds: Vec<u8>,
    pub flags: Vec<u32>,
    pub hull_ids: Vec<i64>,
    pub handles: Vec<i64>,
    // Derived per row: a ship (the scan's `is_ship`: a rigid body, or a tier row that is a ship), a rock or mine, a mine
    // (what the contact field asks per candidate).
    pub rigid: Vec<bool>,
    pub is_static: Vec<bool>,
    pub is_mine: Vec<bool>,
    // What the brains read of a contact (M4-T17): the hull 0..1 (-1 without a hull), the selection (`Contact.target_id`,
    // -1 for none), the broadcast range, and the lowered name as an id of `names` (M5-T35; 0 for no name) for the brains'
    // name matching.
    pub hull_fraction: Vec<f64>,
    pub target_ids: Vec<i64>,
    pub reach: Vec<f64>,
    pub name_ids: Vec<u32>,
    // The lowered names the ids stand for, shared with whoever filled the rows; `clear` keeps it.
    pub names: Option<Arc<NameTable>>,
    // The row's role (M5-T16): fed when a body turns active or is touched, never gathered per tick; rows built without the
    // column (hand-made ones in tests) are combat rows (`role`).
    pub roles: Vec<u8>,
    // The rows by marker id, sorted by id, rebuilt with the rows (M4-T17): a kernel finds a contact by its id in a binary
    // search instead of a scan.
    pub id_rows: Vec<(i64, u32)>,
    pub node_count: usize,
    // The low-attention tier's rows at the end (M4-T21): the scan GDScript holds stops before them.
    pub tier_rows: usize,
}

/// The bolts in flight, column by column: first the rows the core owns (M4-T35, stepped by `bolt_kernels`, in launch
/// order), then the projectiles still read from nodes, in `projectiles` group order.
#[derive(Default)]
pub struct Bolts {
    pub ids: Vec<i64>,
    pub positions: Vec<Vector3>,
    pub velocities: Vec<Vector3>,
    pub last_steps: Vec<Vector3>,
    pub faction_ix: Vec<u32>,
    pub shooters: Vec<i64>,
    pub kinds: Vec<u8>,
    pub radii: Vec<f64>,
    // What a hit lands with and what the renderer draws (M4-T35): the damage, the flash tint, the look it is drawn with
    // (`LOOK_NONE` for a projectile a node draws), when it expires, the tick it was launched (no step on that tick),
    // and whether a hit spent it (gone at the tick's end).
    pub damage: Vec<f64>,
    pub colors: Vec<[f32; 4]>,
    pub looks: Vec<u8>,
    pub expires_at: Vec<f64>,
    pub launched: Vec<i64>,
    pub spent: Vec<bool>,
    /// How many rows at the front the core owns.
    pub owned: usize,
    // The multimesh instance each owned bolt is drawn in (-1 for none): a bolt keeps its slot for life, so instance k
    // follows the same bolt tick to tick (T38's motion vectors pair a slot's two frames), and a freed slot is reused.
    pub draw_slots: Vec<i32>,
    // Per look, which slots are taken; a look's slot count is its instance count.
    slots_used: Vec<Vec<bool>>,
    // The step's keep flags, kept between ticks so a step allocates nothing.
    pub(crate) keep_scratch: Vec<bool>,
}

/// Lowered display names as small ids (M5-T35), so a row carries a number instead of its own copy of the string and a
/// name is matched by comparing numbers. Id 0 is the empty name, which no wanted name matches.
#[derive(Default, Clone, Debug)]
pub struct NameTable {
    count: u32,
    ids: HashMap<Arc<str>, u32>,
}

impl NameTable {
    /// The id of `key`, or 0 when it is empty or no row was ever given it.
    pub fn id_of(&self, key: &str) -> u32 {
        if key.is_empty() || self.is_empty() {
            return 0;
        }
        self.ids.get(key).copied().unwrap_or(0)
    }

    /// The id of `key`, given one on first sight (0 for the empty name).
    pub fn intern(&mut self, key: &str) -> u32 {
        if key.is_empty() {
            return 0;
        }
        if let Some(&id) = self.ids.get(key) {
            return id;
        }
        self.count += 1;
        self.ids.insert(Arc::from(key), self.count);
        self.count
    }

    /// How many names have an id.
    pub fn len(&self) -> usize {
        self.count as usize
    }

    pub fn is_empty(&self) -> bool {
        self.count == 0
    }
}

// Copies into the columns a copy already holds, so a job's snapshot reuses its memory tick after tick. The pattern names
// every field: a new column that is not copied does not compile.
impl Clone for Rows {
    fn clone(&self) -> Self {
        let mut out = Self::default();
        out.clone_from(self);
        out
    }

    fn clone_from(&mut self, source: &Self) {
        let Rows {
            body_ids,
            ids,
            faction_ix,
            positions,
            velocities,
            bases,
            angular,
            radii,
            kinds,
            flags,
            hull_ids,
            handles,
            rigid,
            is_static,
            is_mine,
            hull_fraction,
            target_ids,
            reach,
            name_ids,
            names,
            roles,
            id_rows,
            node_count,
            tier_rows,
        } = source;
        self.body_ids.clone_from(body_ids);
        self.ids.clone_from(ids);
        self.faction_ix.clone_from(faction_ix);
        self.positions.clone_from(positions);
        self.velocities.clone_from(velocities);
        self.bases.clone_from(bases);
        self.angular.clone_from(angular);
        self.radii.clone_from(radii);
        self.kinds.clone_from(kinds);
        self.flags.clone_from(flags);
        self.hull_ids.clone_from(hull_ids);
        self.handles.clone_from(handles);
        self.rigid.clone_from(rigid);
        self.is_static.clone_from(is_static);
        self.is_mine.clone_from(is_mine);
        self.hull_fraction.clone_from(hull_fraction);
        self.target_ids.clone_from(target_ids);
        self.reach.clone_from(reach);
        self.name_ids.clone_from(name_ids);
        self.names.clone_from(names);
        self.roles.clone_from(roles);
        self.id_rows.clone_from(id_rows);
        self.node_count = *node_count;
        self.tier_rows = *tier_rows;
    }
}

impl Clone for Bolts {
    fn clone(&self) -> Self {
        let mut out = Self::default();
        out.clone_from(self);
        out
    }

    fn clone_from(&mut self, source: &Self) {
        let Bolts {
            ids,
            positions,
            velocities,
            last_steps,
            faction_ix,
            shooters,
            kinds,
            radii,
            damage,
            colors,
            looks,
            expires_at,
            launched,
            spent,
            owned,
            draw_slots,
            slots_used,
            keep_scratch: _,
        } = source;
        self.ids.clone_from(ids);
        self.positions.clone_from(positions);
        self.velocities.clone_from(velocities);
        self.last_steps.clone_from(last_steps);
        self.faction_ix.clone_from(faction_ix);
        self.shooters.clone_from(shooters);
        self.kinds.clone_from(kinds);
        self.radii.clone_from(radii);
        self.damage.clone_from(damage);
        self.colors.clone_from(colors);
        self.looks.clone_from(looks);
        self.expires_at.clone_from(expires_at);
        self.launched.clone_from(launched);
        self.spent.clone_from(spent);
        self.owned = *owned;
        self.draw_slots.clone_from(draw_slots);
        self.slots_used.clone_from(slots_used);
    }
}

/// A bolt row no multimesh draws (a node draws it, or nothing does).
pub const LOOK_NONE: u8 = 255;

impl Rows {
    pub fn clear(&mut self) {
        self.body_ids.clear();
        self.ids.clear();
        self.faction_ix.clear();
        self.positions.clear();
        self.velocities.clear();
        self.bases.clear();
        self.angular.clear();
        self.radii.clear();
        self.kinds.clear();
        self.flags.clear();
        self.hull_ids.clear();
        self.handles.clear();
        self.rigid.clear();
        self.is_static.clear();
        self.is_mine.clear();
        self.hull_fraction.clear();
        self.target_ids.clear();
        self.reach.clear();
        self.name_ids.clear();
        self.roles.clear();
        self.id_rows.clear();
        self.node_count = 0;
        self.tier_rows = 0;
    }

    /// Rebuilds `id_rows` from `ids`.
    pub fn index_ids(&mut self) {
        self.id_rows.clear();
        self.id_rows
            .extend(self.ids.iter().enumerate().map(|(r, &id)| (id, r as u32)));
        self.id_rows.sort_unstable();
    }

    /// `index_ids` when the rows `first..first + sorted.len()` are a block whose `(id, place in the block)` pairs are
    /// already sorted (`sorted`, the rocks and mines: the same every tick): only the other rows are sorted, then the two
    /// lists are merged. `scratch` is the caller's, kept between ticks.
    pub fn index_ids_around(&mut self, first: usize, sorted: &[(i64, u32)], scratch: &mut Vec<(i64, u32)>) {
        let end = first + sorted.len();
        if sorted.is_empty() || end > self.ids.len() {
            self.index_ids();
            return;
        }
        scratch.clear();
        scratch.extend(
            self.ids
                .iter()
                .enumerate()
                .filter(|(r, _)| *r < first || *r >= end)
                .map(|(r, &id)| (id, r as u32)),
        );
        scratch.sort_unstable();
        self.id_rows.clear();
        self.id_rows.reserve(self.ids.len());
        let (mut a, mut b) = (0, 0);
        while a < scratch.len() && b < sorted.len() {
            let block = (sorted[b].0, sorted[b].1 + first as u32);
            if scratch[a] < block {
                self.id_rows.push(scratch[a]);
                a += 1;
            } else {
                self.id_rows.push(block);
                b += 1;
            }
        }
        self.id_rows.extend_from_slice(&scratch[a..]);
        self.id_rows
            .extend(sorted[b..].iter().map(|&(id, at)| (id, at + first as u32)));
    }

    /// Appends every row of `block` (its columns only: the lookups and counts are the caller's to rebuild).
    pub fn extend_from(&mut self, block: &Rows) {
        self.body_ids.extend_from_slice(&block.body_ids);
        self.ids.extend_from_slice(&block.ids);
        self.faction_ix.extend_from_slice(&block.faction_ix);
        self.positions.extend_from_slice(&block.positions);
        self.velocities.extend_from_slice(&block.velocities);
        self.bases.extend_from_slice(&block.bases);
        self.angular.extend_from_slice(&block.angular);
        self.radii.extend_from_slice(&block.radii);
        self.kinds.extend_from_slice(&block.kinds);
        self.flags.extend_from_slice(&block.flags);
        self.hull_ids.extend_from_slice(&block.hull_ids);
        self.handles.extend_from_slice(&block.handles);
        self.rigid.extend_from_slice(&block.rigid);
        self.is_static.extend_from_slice(&block.is_static);
        self.is_mine.extend_from_slice(&block.is_mine);
        self.hull_fraction.extend_from_slice(&block.hull_fraction);
        self.target_ids.extend_from_slice(&block.target_ids);
        self.reach.extend_from_slice(&block.reach);
        self.name_ids.extend_from_slice(&block.name_ids);
        self.roles.extend_from_slice(&block.roles);
    }

    /// The id of the lowered name `key` in these rows' table (0: empty, or no row was ever given it).
    pub fn name_id(&self, key: &str) -> u32 {
        self.names.as_ref().map_or(0, |table| table.id_of(key))
    }

    /// Row `r`'s role (`ROLE_COMBAT` for a row without one).
    pub fn role(&self, r: usize) -> u8 {
        self.roles.get(r).copied().unwrap_or(ROLE_COMBAT)
    }

    /// Whether row `r` is a civilian hull.
    pub fn is_civilian(&self, r: usize) -> bool {
        self.role(r) == ROLE_CIVILIAN
    }

    /// The row whose marker id is `id`, or -1.
    pub fn row_of_id(&self, id: i64) -> i32 {
        match self.id_rows.binary_search_by_key(&id, |e| e.0) {
            Ok(k) => self.id_rows[k].1 as i32,
            Err(_) => -1,
        }
    }
}

impl Bolts {
    pub fn clear(&mut self) {
        self.ids.clear();
        self.positions.clear();
        self.velocities.clear();
        self.last_steps.clear();
        self.faction_ix.clear();
        self.shooters.clear();
        self.kinds.clear();
        self.radii.clear();
        self.damage.clear();
        self.colors.clear();
        self.looks.clear();
        self.expires_at.clear();
        self.launched.clear();
        self.spent.clear();
        self.draw_slots.clear();
        self.slots_used.clear();
        self.keep_scratch.clear();
        self.owned = 0;
    }

    /// The instances a look's multimesh draws: its highest taken slot plus one.
    pub fn slot_count(&self, look: u8) -> usize {
        self.slots_used
            .get(usize::from(look))
            .map_or(0, |used| used.len())
    }

    // The lowest free slot of `look`, taken (none for a bolt no multimesh draws).
    fn take_slot(&mut self, look: u8) -> i32 {
        if look == LOOK_NONE {
            return -1;
        }
        let ix = usize::from(look);
        if self.slots_used.len() <= ix {
            self.slots_used.resize(ix + 1, Vec::new());
        }
        let used = &mut self.slots_used[ix];
        if let Some(slot) = used.iter().position(|&taken| !taken) {
            used[slot] = true;
            slot as i32
        } else {
            used.push(true);
            (used.len() - 1) as i32
        }
    }

    // Gives a bolt's slot back; the look's count shrinks past the free slots at its top.
    fn free_slot(&mut self, look: u8, slot: i32) {
        let Ok(slot) = usize::try_from(slot) else {
            return;
        };
        if let Some(used) = self.slots_used.get_mut(usize::from(look)) {
            if slot < used.len() {
                used[slot] = false;
            }
            while used.last() == Some(&false) {
                used.pop();
            }
        }
    }

    /// Drops the rows read from nodes, keeping the core's own (a sync point reads the nodes again after it).
    pub fn truncate_to_owned(&mut self) {
        let n = self.owned;
        self.ids.truncate(n);
        self.positions.truncate(n);
        self.velocities.truncate(n);
        self.last_steps.truncate(n);
        self.faction_ix.truncate(n);
        self.shooters.truncate(n);
        self.kinds.truncate(n);
        self.radii.truncate(n);
        self.damage.truncate(n);
        self.colors.truncate(n);
        self.looks.truncate(n);
        self.expires_at.truncate(n);
        self.launched.truncate(n);
        self.spent.truncate(n);
        self.draw_slots.truncate(n);
    }

    /// Adds a bolt the core owns, after the owned rows and before the node rows, in launch order.
    #[allow(clippy::too_many_arguments)]
    pub fn insert_owned(
        &mut self,
        id: i64,
        position: Vector3,
        velocity: Vector3,
        faction_ix: u32,
        shooter: i64,
        kind: u8,
        radius: f64,
        damage: f64,
        color: [f32; 4],
        look: u8,
        expires_at: f64,
        launched: i64,
    ) -> usize {
        let at = self.owned;
        let slot = self.take_slot(look);
        self.draw_slots.insert(at, slot);
        self.ids.insert(at, id);
        self.positions.insert(at, position);
        self.velocities.insert(at, velocity);
        self.last_steps.insert(at, Vector3::ZERO);
        self.faction_ix.insert(at, faction_ix);
        self.shooters.insert(at, shooter);
        self.kinds.insert(at, kind);
        self.radii.insert(at, radius);
        self.damage.insert(at, damage);
        self.colors.insert(at, color);
        self.looks.insert(at, look);
        self.expires_at.insert(at, expires_at);
        self.launched.insert(at, launched);
        self.spent.insert(at, false);
        self.owned += 1;
        at
    }

    /// Removes the owned rows `keep` says to drop (one flag per owned row), keeping the order of the rest and the node rows.
    pub fn retain_owned(&mut self, keep: &[bool]) {
        let owned = self.owned;
        let kept = keep.iter().filter(|&&k| k).count();
        if kept == owned {
            return;
        }
        for (i, &kept) in keep.iter().enumerate().take(owned) {
            if !kept {
                let (look, slot) = (self.looks[i], self.draw_slots[i]);
                self.free_slot(look, slot);
            }
        }
        compact(&mut self.draw_slots, owned, keep);
        compact(&mut self.ids, owned, keep);
        compact(&mut self.positions, owned, keep);
        compact(&mut self.velocities, owned, keep);
        compact(&mut self.last_steps, owned, keep);
        compact(&mut self.faction_ix, owned, keep);
        compact(&mut self.shooters, owned, keep);
        compact(&mut self.kinds, owned, keep);
        compact(&mut self.radii, owned, keep);
        compact(&mut self.damage, owned, keep);
        compact(&mut self.colors, owned, keep);
        compact(&mut self.looks, owned, keep);
        compact(&mut self.expires_at, owned, keep);
        compact(&mut self.launched, owned, keep);
        compact(&mut self.spent, owned, keep);
        self.owned = kept;
    }
}

// Keeps the first `owned` entries `keep` marks and every entry after them, in order.
fn compact<T: Copy>(column: &mut Vec<T>, owned: usize, keep: &[bool]) {
    let mut w = 0;
    for i in 0..column.len() {
        if i >= owned || keep[i] {
            column[w] = column[i];
            w += 1;
        }
    }
    column.truncate(w);
}

impl Rows {
    /// A velocity rebase: every row with a body or a tier row behind it loses `dv`. A static row has no velocity to
    /// change: it is tied to the anchor.
    pub fn boost(&mut self, dv: Vector3) {
        for (v, &handle) in self.velocities.iter_mut().zip(&self.handles) {
            if handle != 0 {
                *v -= dv;
            }
        }
    }
}

impl Rows {
    /// Takes new positions for the same rows (M6-T06: the statics after a shift), every other column kept. False, with
    /// nothing changed, when the count differs.
    pub fn take_positions(&mut self, from: &[Vector3]) -> bool {
        if from.len() != self.positions.len() {
            return false;
        }
        self.positions.copy_from_slice(from);
        true
    }
}

impl Bolts {
    /// A velocity rebase: every bolt loses `dv`. Its last step stays: that displacement was flown in the old frame.
    pub fn boost(&mut self, dv: Vector3) {
        for v in self.velocities.iter_mut() {
            *v -= dv;
        }
    }
}

#[cfg(test)]
mod tests;
