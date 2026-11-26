use godot::builtin::Vector3;

use super::capital::{self as cap, Capital, Part, Rules, Section};
use super::station::{self as st, GridMounts, Station, StationSections};
use super::{DamageStore, Hull, Log, LOG_WIDTH};

const RULES: Rules = Rules {
    subsystem_hull_share: 0.5,
    power_stage_at: 0.5,
    power_stage_level: 0.5,
    reactor_shutdown_at: 0.1,
    hulk_below: 0.1,
};

fn section(kind: u8, hp: f64, z: f32) -> Section {
    Section {
        kind,
        max_hp: hp,
        hp,
        state: cap::INTACT,
        lo: Vector3::new(-20.0, -20.0, z),
        end: Vector3::new(20.0, 20.0, z + 100.0),
        mounts: vec![],
        engines: vec![],
        bays: vec![],
    }
}

fn part(section: i32, z: f32, reach: f64, hp: f64) -> Part {
    Part {
        section,
        pos: Vector3::new(0.0, 20.0, z),
        reach,
        max_hp: hp,
        hp,
        alive: true,
    }
}

// Bow (plain), bridge, magazine, reactor along z; a turret on the bow, an engine on the reactor section.
fn ship() -> Capital {
    let sections = vec![
        section(0, 2000.0, 0.0),
        section(cap::KIND_BRIDGE, 500.0, 100.0),
        section(cap::KIND_MAGAZINE, 1000.0, 200.0),
        section(cap::KIND_REACTOR, 1500.0, 300.0),
    ];
    Capital::new(RULES, sections, vec![part(0, 50.0, 10.0, 800.0)], vec![part(3, 350.0, 12.0, 1500.0)], vec![], 10_000.0)
}

fn codes(log: &Log) -> Vec<u8> {
    log.entries.chunks(LOG_WIDTH).map(|e| e[0] as u8).collect()
}

#[test]
fn a_hull_takes_what_it_has_and_dies_once() {
    let mut h = Hull::new(100.0);
    assert_eq!(h.apply(30.0), 30.0);
    assert_eq!(h.apply(f64::NAN), 0.0);
    assert_eq!(h.apply(-4.0), 0.0);
    assert_eq!(h.apply(500.0), 70.0);
    assert!(h.destroyed && h.destroyed_now);
    assert_eq!(h.apply(5.0), 0.0);
    assert!(!h.destroyed_now, "only the hit that crossed zero says so");
    h.restore();
    assert_eq!(h.hp, 100.0);
    assert_eq!(Hull::new(0.0).max_hp, super::MIN_MAX_HP);
}

#[test]
fn a_hit_in_a_parts_reach_takes_it_in_full_and_the_hull_half() {
    let mut c = ship();
    let mut log = Log::default();
    let removed = c.hit(0, Vector3::new(0.0, 18.0, 52.0), 300.0, &mut log);
    assert_eq!(removed, 150.0);
    assert_eq!(c.mounts[0].hp, 500.0);
    assert_eq!(c.sections[0].hp, 2000.0, "only the part hit");
    assert_eq!(c.hull_hp, 9850.0);
    assert_eq!(codes(&log), vec![cap::PART_HP, cap::HULL_HP]);
}

#[test]
fn a_plain_hit_lowers_its_section_and_the_total_and_marks_it_damaged() {
    let mut c = ship();
    let mut log = Log::default();
    assert_eq!(c.hit(0, Vector3::new(0.0, -15.0, 10.0), 400.0, &mut log), 400.0);
    assert_eq!(c.sections[0].hp, 1600.0);
    assert_eq!(c.sections[0].state, cap::DAMAGED);
    assert_eq!(codes(&log), vec![cap::SEC_HP, cap::SECTION_CHANGED, cap::HULL_HP]);
}

#[test]
fn an_unknown_section_takes_the_hit_on_the_nearest() {
    let mut c = ship();
    let mut log = Log::default();
    c.hit(-1, Vector3::new(0.0, 0.0, 150.0), 100.0, &mut log);
    assert_eq!(c.sections[1].hp, 400.0, "the bridge, a subsystem, in full");
    assert_eq!(c.hull_hp, 9950.0, "and half off the hull");
}

#[test]
fn a_lost_section_takes_its_parts_and_a_magazine_blows() {
    let mut c = ship();
    let mut log = Log::default();
    c.hit(0, Vector3::new(0.0, -15.0, 10.0), 5000.0, &mut log);
    assert!(!c.mounts[0].alive, "the bow's turret goes with it");
    assert_eq!(c.sections[0].state, cap::DISABLED);
    log.clear();
    c.hit(2, Vector3::new(0.0, 0.0, 250.0), 1000.0, &mut log);
    assert!(c.destroyed);
    assert_eq!(c.blown, 2);
    assert_eq!(
        codes(&log),
        vec![cap::SEC_HP, cap::SEC_STATE, cap::SECTION_CHANGED, cap::SECTION_CHANGED, cap::BLEW]
    );
    assert_eq!(c.hit(0, Vector3::ZERO, 50.0, &mut log), 0.0, "a wreck takes nothing more");
}

#[test]
fn the_bridge_at_zero_or_the_reactor_at_a_tenth_makes_a_hulk() {
    let mut c = ship();
    let mut log = Log::default();
    c.hit_part(cap::PART_SECTION, 1, 500.0, &mut log);
    assert!(c.disabled, "the bridge lost");
    assert_eq!(c.power(), 0.0);
    let mut d = ship();
    d.hit_part(cap::PART_SECTION, 3, 1400.0, &mut log);
    assert!(d.disabled && !d.destroyed, "the reactor shut down at a tenth (Q78)");
}

#[test]
fn an_engine_lost_changes_the_drive_and_scuttle_disables_once() {
    let mut c = ship();
    let mut log = Log::default();
    c.hit_part(cap::PART_ENGINE, 0, 1500.0, &mut log);
    assert!(!c.engines[0].alive);
    assert_eq!(codes(&log), vec![cap::PART_HP, cap::PART_LOST, cap::DRIVE_CHANGED, cap::HULL_HP]);
    log.clear();
    assert!(c.scuttle(&mut log));
    assert!(!c.scuttle(&mut log));
    c.restore();
    assert!(c.engines[0].alive && !c.disabled && c.hull_hp == 10_000.0);
}

fn station() -> (StationSections, GridMounts, Station) {
    let secs = StationSections {
        body: vec![0, 0, 0],
        lo: (0..3).map(|i| Vector3::new(100.0 * i as f32, -20.0, -20.0)).collect(),
        end: (0..3).map(|i| Vector3::new(100.0 * i as f32 + 100.0, 20.0, 20.0)).collect(),
        health: vec![1000.0; 3],
        max_health: vec![1000.0; 3],
    };
    let mounts = GridMounts {
        body: vec![0],
        pos: vec![Vector3::new(150.0, 20.0, 0.0)],
        radius: vec![30.0],
        health: vec![300.0],
        max_health: vec![300.0],
    };
    let station = Station {
        sections: 0,
        mounts: Some(0),
        kinds: vec![st::KIND_BRIDGE, st::KIND_PLAIN, st::KIND_REACTOR],
        subsystem_hull_share: 0.5,
        hulk_below: 0.1,
        reactor_shutdown_at: 0.1,
        hull_max: 3000.0,
        hull_hp: 3000.0,
        disabled: false,
        destroyed: false,
        blown: -1,
    };
    (secs, mounts, station)
}

#[test]
fn a_grid_mount_in_reach_takes_the_hit_and_is_knocked_out() {
    let (mut secs, mut mounts, mut s) = station();
    let mut log = Log::default();
    assert_eq!(s.hit(&mut secs, Some(&mut mounts), 0, Vector3::new(150.0, 15.0, 0.0), 400.0, &mut log), 200.0);
    assert_eq!(mounts.health[0], 0.0);
    assert_eq!(secs.health[1], 1000.0, "its section none");
    assert_eq!(codes(&log), vec![st::MOUNT_HEALTH, st::MOUNT_OUT, st::HULL_HP]);
}

#[test]
fn the_reactor_at_zero_destroys_the_station_and_the_command_at_zero_leaves_a_hulk() {
    let (mut secs, mut mounts, mut s) = station();
    let mut log = Log::default();
    s.hit_section(&mut secs, 0, 1000.0, &mut log);
    assert!(s.disabled && !s.destroyed);
    s.hit(&mut secs, Some(&mut mounts), 0, Vector3::new(250.0, 0.0, 0.0), 1000.0, &mut log);
    assert!(s.destroyed);
    assert_eq!(s.blown, 2);
    assert_eq!(s.hull_hp, 0.0);
}

#[test]
fn a_point_out_of_every_box_snaps_to_the_nearest_within_reach() {
    let (secs, _, _) = station();
    assert_eq!(secs.section_at(0, Vector3::new(50.0, 0.0, 60.0)), 0, "40 m off the box");
    assert_eq!(secs.section_at(0, Vector3::new(50.0, 0.0, 90.0)), -1, "70 m off: none");
    assert_eq!(secs.section_at(1, Vector3::new(50.0, 0.0, 0.0)), -1, "another body's boxes");
}

#[test]
fn the_store_hands_out_slots_again_once_freed() {
    let mut store = DamageStore::default();
    let a = store.hulls.add(Hull::new(10.0));
    let b = store.hulls.add(Hull::new(20.0));
    assert!(store.hulls.remove(a as i64));
    assert!(!store.hulls.remove(a as i64), "freed once");
    assert_eq!(store.hulls.add(Hull::new(30.0)), a);
    assert_eq!(store.hulls.live(), 2);
    assert_eq!(store.hulls.get(b as i64).map(|h| h.max_hp), Some(20.0));
}
