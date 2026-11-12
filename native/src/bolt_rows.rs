// The core's own bolts (M4-T35, docs/architecture.md 17.13): the bolt table's front rows are the core's, added by the cannon kernel and the stand-ins, stepped by `bolt_kernels::step` once a tick between the
// cannons and the hit resolver, spent by the resolver and dropped at the tick's end. The rows read from nodes (beams and
// missiles, which still have one) follow them at each sync point.
use godot::prelude::*;

use crate::bolt_kernels;
use crate::sim_core::{KIND_BOLT, ScsSimCore, kind_of};

impl ScsSimCore {
    /// Adds a bolt the core owns and returns its id (negative, never an instance id). `launched` is the core's tick, so
    /// the bolt does not move on it (its launch tick sweeps only its muzzle).
    #[allow(clippy::too_many_arguments)]
    pub fn add_owned_bolt(
        &mut self,
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
    ) -> i64 {
        self.next_bolt_id -= 1;
        let id = self.next_bolt_id;
        self.bolts.insert_owned(
            id, position, velocity, faction_ix, shooter, kind, radius, damage, color, look,
            expires_at, self.tick,
        );
        id
    }
}

#[godot_api(secondary)]
impl ScsSimCore {
    /// Adds a bolt row (a stand-in's gun bolt, a test's) and returns its id: `kind` is `SimCore.KIND_*` or its name,
    /// `look` the renderer's look index (`LOOK_NONE` for none), `lifetime_s` from `now_s`.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn add_bolt(
        &mut self,
        position: Vector3,
        velocity: Vector3,
        faction: StringName,
        shooter_id: i64,
        kind: Variant,
        hit_radius_m: f64,
        damage: f64,
        color: Color,
        look: i64,
        lifetime_s: f64,
        now_s: f64,
    ) -> i64 {
        let faction_ix = self.faction_index(faction);
        let kind = if kind.is_nil() {
            KIND_BOLT
        } else {
            kind_of(&kind)
        };
        self.add_owned_bolt(
            position,
            velocity,
            faction_ix,
            shooter_id,
            kind,
            hit_radius_m,
            damage,
            [color.r, color.g, color.b, color.a],
            u8::try_from(look).unwrap_or(crate::rows::LOOK_NONE),
            now_s + lifetime_s,
        )
    }

    /// Marks the owned bolt `id` spent (a hit took it); it stays in the columns, flagged, until the next tick's first sync
    /// drops it (a spent node is listed until it is freed at its frame's end). False when no owned bolt has that id.
    #[func]
    fn spend_bolt(&mut self, id: i64) -> bool {
        let b = &mut self.bolts;
        for i in 0..b.owned {
            if b.ids[i] == id {
                b.spent[i] = true;
                return true;
            }
        }
        false
    }

    /// `spend_bolt` by the bolt's row in the table (the hit resolver's index).
    #[func]
    fn spend_bolt_row(&mut self, row: i64) -> bool {
        match usize::try_from(row) {
            Ok(i) if i < self.bolts.owned => {
                self.bolts.spent[i] = true;
                true
            }
            _ => false,
        }
    }

    /// Whether the bolt in `row` is still live (an owned row not spent; a node row is live while listed).
    #[func]
    fn bolt_live(&self, row: i64) -> bool {
        match usize::try_from(row) {
            Ok(i) if i < self.bolts.ids.len() => !self.bolts.spent[i],
            _ => false,
        }
    }

    /// Steps the owned bolts for one tick at sim time `now_s`: expires the ones whose time is up, moves the rest (not the
    /// ones launched this tick). Returns how many expired.
    #[func]
    fn step_bolts(&mut self, now_s: f64, delta: f64) -> i64 {
        bolt_kernels::step(&mut self.bolts, delta, now_s, self.tick) as i64
    }

    /// Owned bolt rows now.
    #[func]
    fn owned_bolts(&self) -> i64 {
        self.bolts.owned as i64
    }

    /// The multimesh buffer of the owned bolts drawn with `look`: `INSTANCE_FLOATS` per instance, the bolts drawn
    /// `fraction` of the way from their last tick's place to this one, the capsule mesh's own basis `child` under each,
    /// enlarged by `visual_scale`, padded with zeros to `min_instances` (a multimesh takes a buffer of exactly its
    /// instance count). `bolt_instances` says how many are drawn.
    #[func]
    fn bolt_transforms(
        &mut self,
        look: i64,
        fraction: f64,
        visual_scale: f64,
        child: Basis,
        min_instances: i64,
    ) -> PackedFloat32Array {
        let look = u8::try_from(look).unwrap_or(crate::rows::LOOK_NONE);
        let mut out: Vec<f32> = Vec::new();
        let drawn = bolt_kernels::instance_transforms(
            &self.bolts,
            look,
            fraction as f32,
            visual_scale as f32,
            &child,
            &mut out,
        );
        let wanted = usize::try_from(min_instances).unwrap_or(0).max(drawn);
        out.resize(wanted * bolt_kernels::INSTANCE_FLOATS, 0.0);
        PackedFloat32Array::from(out.as_slice())
    }

    /// Every constant the native code mirrors from GDScript, `"Class.CONST[@module][#size]" -> value` (`FlightModel.AXIS_SIGN`
    /// is the one vector); `tests/unit/test_native_constants.gd` compares each with its twin.
    #[func]
    fn constants(&self) -> VarDictionary {
        let mut table = VarDictionary::new();
        for (key, value) in crate::constants::numbers() {
            table.set(key, value);
        }
        table.set("FlightModel.AXIS_SIGN", crate::constants::axis_sign());
        table
    }

    /// `BoltSlotQuarantine.filter` for the motion vectors: `[buffer with every slot new since `last` collapsed, how many]`.
    /// `forward` is the bolts' flight direction in an instance's own frame.
    #[func]
    fn bolt_quarantine(
        &self,
        buffer: PackedFloat32Array,
        last: PackedFloat32Array,
        forward: Vector3,
    ) -> VarArray {
        let mut out: Vec<f32> = Vec::new();
        let collapsed = bolt_kernels::quarantine(
            buffer.as_slice(),
            last.as_slice(),
            [forward.x, forward.y, forward.z],
            &mut out,
        );
        let mut result = VarArray::new();
        result.push(&PackedFloat32Array::from(out.as_slice()).to_variant());
        result.push(&(collapsed as i64).to_variant());
        result
    }

    /// How many instances `bolt_transforms(look, ...)` fills now: the look's highest draw slot plus one (a slot stays
    /// a bolt's for life, so a freed one in the middle is drawn empty until a new bolt takes it).
    #[func]
    fn bolt_instances(&self, look: i64) -> i64 {
        let look = u8::try_from(look).unwrap_or(crate::rows::LOOK_NONE);
        self.bolts.slot_count(look) as i64
    }
}
