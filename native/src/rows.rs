// The core's row tables (M4-T15, docs/architecture.md 17.13): plain data, the only thing the kernels import from the
// crate. Nothing here can reach the engine: the columns are value types and the methods clear them.
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

/// The scan's rows, column by column: the bodies in registry order (active markers, then active hulls with no active
/// marker), the static rows, then any row added after the tick's first sync. Read by the kernels through `bind()`, from
/// several threads at once (M4-T18): every column is plain data the threads may share; the display names, an engine
/// string, live beside the rows in the core.
#[derive(Default, Clone)]
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
    // -1 for none), the broadcast range, and the name lowered once for the brains' name matching.
    pub hull_fraction: Vec<f64>,
    pub target_ids: Vec<i64>,
    pub reach: Vec<f64>,
    pub name_keys: Vec<String>,
    // The rows by marker id, sorted by id, rebuilt with the rows (M4-T17): a kernel finds a contact by its id in a binary
    // search instead of a scan.
    pub id_rows: Vec<(i64, u32)>,
    pub node_count: usize,
}

/// The bolts in flight, column by column: first the rows the core owns (M4-T35, stepped by `bolt_kernels`, in launch
/// order), then the projectiles still read from nodes, in `projectiles` group order.
#[derive(Default, Clone)]
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
        self.name_keys.clear();
        self.id_rows.clear();
        self.node_count = 0;
    }

    /// Rebuilds `id_rows` from `ids`.
    pub fn index_ids(&mut self) {
        self.id_rows.clear();
        self.id_rows
            .extend(self.ids.iter().enumerate().map(|(r, &id)| (id, r as u32)));
        self.id_rows.sort_unstable();
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
        self.owned = 0;
    }

    /// Drops the rows the core owns (the bolt rows switched off), their draw slots with them.
    pub fn drop_owned(&mut self) {
        self.owned = 0;
        self.truncate_to_owned();
        self.slots_used.clear();
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
