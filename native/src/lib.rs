// Entry point of the game's native library: registers every native class with Godot.
use godot::prelude::*;

mod bolt_kernels;
mod bolt_rows;
mod brain;
mod brain_behaviours;
mod brain_maths;
mod brain_step;
mod cannons;
mod civilian;
mod constants;
mod contact_field;
mod flight_step;
mod hit_sweep;
mod kernels;
mod native_probe;
mod pilot_kernels;
mod ram_phase;
mod row_commands;
mod rows;
mod sim_core;
mod threads;
mod v3;
mod weapon_kernels;
mod weapon_rows;

struct ScsNative;

#[gdextension]
unsafe impl ExtensionLibrary for ScsNative {}

// M4-T34: the cheaper bolt read at the core's sync points.
mod bolt_sync;

// M4-T34: the hit broad phase's grid with hashed cells, an engine-free kernel.
mod sweep_cells;

// M4-T21: the low-attention tier's rows and integrator, and the core's shell around them.
mod tier;
mod tier_rows;

// M4-T22: the low-attention tier's fire, an engine-free kernel.
mod tier_fire;

// M5-T21: the defensive turrets, engine-free kernels and the core's shell around them.
mod turret_kernels;
mod turret_rows;

// M5-T28: the engine voices' ship query, an engine-free kernel and the core's shell around it.
mod voice_kernels;
mod voice_rows;
// M4-T23: the player's radar sphere, an engine-free kernel, and its shell.
mod radar_kernel;
mod radar_plot;

// M6-T02: the ephemeris and the gravity on test particles, engine-free kernels (wired in by M6-T04).
mod ephemeris;
mod gravity;

// M6-T03: the ephemeris's binding for GDScript.
mod ephemeris_binding;

// M6-T04: the free-falling frame, an engine-free kernel, and its shell on the core.
mod frame;
mod frame_rows;

// M5-T33: the ram tracker, an engine-free kernel, and its shell over Jolt's contacts and the core's rows.
mod ram_contacts;
mod ram_tracker;

// M6-T06: the static rows' shift (L4).
mod static_rows;

// M6-T21: which rocks live as Jolt bodies, an engine-free kernel and its shell over the core's rows.
mod rock_stream;
