// The core's row tables (M4-T15, docs/architecture.md 17.13): plain data, the only thing the kernels import from the
// crate. Nothing here can reach the engine: the columns are value types and the methods clear them.
use godot::builtin::{Basis, GString, Vector3};

/// Row flags: a rigid body (the scan's `is_ship`), an active hull (`Damageable.is_active()`: the sweep and the rams see
/// it), a hull at all, and a row added after the tick's first sync (a ship back from the pool).
pub const FLAG_RIGID: u32 = 1;
pub const FLAG_HULL: u32 = 2;
pub const FLAG_HULL_ACTIVE: u32 = 4;
pub const FLAG_LATE: u32 = 8;

/// The scan's rows, column by column: the bodies in registry order (active markers, then active hulls with no active
/// marker), the static rows, then any row added after the tick's first sync. Read by the kernels through `bind()`.
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
    pub names: Vec<GString>,
    pub hull_ids: Vec<i64>,
    pub handles: Vec<i64>,
    // Derived per row: a rigid body, a rock or mine, a mine (what the contact field asks per candidate).
    pub rigid: Vec<bool>,
    pub is_static: Vec<bool>,
    pub is_mine: Vec<bool>,
    pub node_count: usize,
}

/// The bolts in flight, column by column, in `projectiles` group order.
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
}

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
        self.names.clear();
        self.hull_ids.clear();
        self.handles.clear();
        self.rigid.clear();
        self.is_static.clear();
        self.is_mine.clear();
        self.node_count = 0;
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
    }
}
