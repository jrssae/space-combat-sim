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

mod landing_tests {
    use std::collections::HashMap;

    use godot::builtin::Vector3;

    use super::super::landing::{self as dl, Ctx, LandHit, LandOut, Target};
    use super::super::{DamageStore, Hull};
    use super::ship;

    // Two factions: 0 and 1 hostile, each friendly to itself.
    const RELATION: [u8; 4] = [2, 1, 1, 2];

    fn ctx() -> Ctx<'static> {
        Ctx {
            blast: false,
            friendly_fire: false,
            god_mode: false,
            relation: &RELATION,
            factions: 2,
        }
    }

    fn hit(target: i64, damage: f64, shooter: i64) -> LandHit {
        LandHit {
            target,
            body: target + 100,
            shooter,
            shooter_faction: 0,
            target_faction: Some(1),
            disguise: None,
            damage,
            point: Vector3::new(0.0, 0.0, 0.0),
            volume: -1,
            local: Some(Vector3::new(3.0, 1.0, 0.0)),
        }
    }

    fn fighter(store: &mut DamageStore, hp: f64) -> Target {
        Target {
            hull: store.hulls.add(Hull::new(hp)) as i64,
            summary: 0,
            layout: dl::LAYOUT_X_FIGHTER,
            ..Target::default()
        }
    }

    #[test]
    fn plain_hits_land_in_one_batch_with_one_summary_a_ship_and_every_attacker() {
        let mut store = DamageStore::default();
        let mut targets = HashMap::new();
        let mut t = fighter(&mut store, 100.0);
        t.summary = 7;
        targets.insert(7, t);
        let hits = [hit(7, 10.0, 1), hit(7, 10.0, 2), hit(7, 10.0, 1)];
        let mut out = LandOut::default();
        assert_eq!(dl::land(&mut store, &targets, &hits, 0, &ctx(), &mut out), 3);
        assert_eq!(out.summaries.len(), 1);
        let s = &out.summaries[0];
        assert_eq!(s.attackers, vec![1, 2], "every attacker, in the order each first hit");
        assert_eq!(s.last_shooter, 1);
        assert_eq!((s.hits, s.damage, s.applied), (3, 30.0, 30.0));
        assert_eq!(s.zones, vec![(2, 10.0); 3], "the upper right arm each time");
        assert_eq!(out.sync.len(), dl::OUT_WIDTH, "one coalesced write: the hull's last points");
        assert_eq!(out.sync[3], 70.0);
        assert_eq!(out.attackers.len(), 3);
    }

    #[test]
    fn a_kill_ends_the_batch_and_a_dead_hull_takes_no_more() {
        let mut store = DamageStore::default();
        let mut targets = HashMap::new();
        targets.insert(7, fighter(&mut store, 15.0));
        let hits = [hit(7, 10.0, 1), hit(7, 10.0, 1), hit(7, 10.0, 1)];
        let mut out = LandOut::default();
        let next = dl::land(&mut store, &targets, &hits, 0, &ctx(), &mut out);
        assert_eq!(next, 2, "the killing hit ends the batch");
        assert_eq!(out.kill, Some((1, 5.0, -1)));
        let next = dl::land(&mut store, &targets, &hits, next, &ctx(), &mut out);
        assert_eq!(next, 3);
        assert_eq!(out.hits, 0, "a dead hull takes no more");
    }

    #[test]
    fn a_hull_its_side_may_not_hurt_takes_nothing_and_god_mode_takes_the_hit_but_no_points() {
        let mut store = DamageStore::default();
        let mut targets = HashMap::new();
        let mut t = fighter(&mut store, 100.0);
        t.respects_god_mode = true;
        targets.insert(7, t);
        let mut friend = hit(7, 10.0, 1);
        friend.target_faction = Some(0);
        let mut out = LandOut::default();
        dl::land(&mut store, &targets, &[friend], 0, &ctx(), &mut out);
        assert_eq!(out.hits, 0);
        let god = Ctx { god_mode: true, ..ctx() };
        dl::land(&mut store, &targets, &[hit(7, 10.0, 1)], 0, &god, &mut out);
        assert_eq!(out.hits, 1);
        assert_eq!(out.summaries[0].applied, 0.0);
    }

    #[test]
    fn an_unknown_target_or_volume_is_left_to_gdscript_and_a_disguised_shooter_is_found_out_once() {
        let mut store = DamageStore::default();
        let mut targets = HashMap::new();
        let mut out = LandOut::default();
        assert_eq!(dl::land(&mut store, &targets, &[hit(9, 1.0, 1)], 0, &ctx(), &mut out), 1);
        assert_eq!(out.deferred, Some(0));
        let mut t = fighter(&mut store, 100.0);
        t.is_player = true;
        targets.insert(7, t);
        let mut masked = hit(7, 1.0, 1);
        masked.disguise = Some(1);
        let next = dl::land(&mut store, &targets, &[masked, masked], 0, &ctx(), &mut out);
        assert_eq!((next, out.reveals.clone()), (1, vec![1]), "a hit on the player gives it away and ends the batch");
    }

    #[test]
    fn a_capital_hit_lands_by_its_volumes_section_and_a_lost_section_ends_the_batch() {
        let mut store = DamageStore::default();
        let hull = store.hulls.add(Hull::new(10_000.0)) as i64;
        let ledger = store.capitals.add(ship()) as i64;
        let mut targets = HashMap::new();
        targets.insert(
            5,
            Target {
                hull,
                summary: 5,
                route: dl::ROUTE_CAPITAL,
                ledger,
                volume_sections: vec![0, 2],
                ..Target::default()
            },
        );
        let mut on_bow = hit(5, 100.0, 1);
        on_bow.volume = 0;
        on_bow.local = Some(Vector3::new(0.0, -15.0, 10.0));
        let mut out = LandOut::default();
        assert_eq!(dl::land(&mut store, &targets, &[on_bow, on_bow], 0, &ctx(), &mut out), 1, "damaged: an event");
        assert_eq!(out.summaries[0].sections, vec![0]);
        assert_eq!(dl::land(&mut store, &targets, &[on_bow, on_bow], 1, &ctx(), &mut out), 2);
        assert_eq!(store.capitals.get(ledger).map(|c| c.sections[0].hp), Some(1800.0));
        assert_eq!(store.hulls.get(hull).map(|h| h.hp), Some(9800.0), "the hull takes the section's points");
        let mut magazine = on_bow;
        magazine.volume = 1;
        magazine.damage = 2000.0;
        magazine.local = Some(Vector3::new(0.0, 0.0, 250.0));
        dl::land(&mut store, &targets, &[magazine], 0, &ctx(), &mut out);
        assert!(out.kill.is_some(), "the magazine blew: the whole hull goes");
        assert_eq!(store.hulls.get(hull).map(|h| h.hp), Some(0.0));
        let mut stray = on_bow;
        stray.volume = 4;
        targets.get_mut(&5).unwrap().hull = store.hulls.add(Hull::new(10.0)) as i64;
        dl::land(&mut store, &targets, &[stray], 0, &ctx(), &mut out);
        assert_eq!(out.deferred, Some(0), "a volume it cannot name");
    }
}
