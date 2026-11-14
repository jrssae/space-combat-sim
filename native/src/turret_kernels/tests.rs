// The turret kernels' unit tests (M5-T21), beside the kernels and outside their engine-free guard (test builds only).
use super::*;

const DT: f64 = 1.0 / 60.0;

fn gun() -> Gun {
    Gun {
        muzzle_speed: 1200.0,
        interval_s: 0.8,
        lifetime_s: 2.0,
        damage: 4.0,
        hit_radius: 0.3,
        range_m: 1500.0,
        spread_rad: 0.6_f64.to_radians(),
        traverse_rad_s: 60_f64.to_radians(),
        elevation_rad_s: 45_f64.to_radians(),
        color: [1.0; 4],
        look: 0,
    }
}

// One row per (body, faction, position), all live rigid hulls.
fn rows_of(bodies: &[(i64, u32, Vector3)]) -> Rows {
    let mut rows = Rows::default();
    for &(body, faction, at) in bodies {
        rows.body_ids.push(body);
        rows.ids.push(body);
        rows.faction_ix.push(faction);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.flags.push(FLAG_RIGID | FLAG_HULL_ACTIVE);
        rows.radii.push(10.0);
    }
    rows
}

fn row_finder(rows: &Rows) -> impl Fn(i64) -> i64 + '_ {
    move |b| {
        rows.body_ids
            .iter()
            .position(|&x| x == b)
            .map_or(-1, |r| r as i64)
    }
}

// Factions: 0 the turret's people, 1 raiders (hostile), 2 a neutral people.
fn table() -> Vec<u8> {
    vec![
        REL_FRIENDLY, REL_HOSTILE, REL_NEUTRAL, //
        REL_HOSTILE, REL_FRIENDLY, REL_HOSTILE, //
        REL_NEUTRAL, REL_HOSTILE, REL_FRIENDLY,
    ]
}

fn mount(body: i64) -> PickMount {
    PickMount {
        slot: 0,
        stamp: 1,
        body,
        faction_ix: 0,
        local: Vector3::new(0.0, 5.0, 0.0),
        up: Vector3::new(0.0, 1.0, 0.0),
        min_elevation: (-10_f64).to_radians(),
        reach_m: 1500.0 * PICK_REACH,
        kind: MOUNT_TURRET,
    }
}

#[test]
fn a_turret_picks_only_attackers_of_its_ship() {
    let rows = rows_of(&[
        (1, 0, Vector3::ZERO),
        (2, 1, Vector3::new(0.0, 300.0, -500.0)),
        (3, 1, Vector3::new(0.0, 200.0, -300.0)),
    ]);
    let mut memory = Memory::default();
    let find = row_finder(&rows);
    let t = table();
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 0.0, &[]), 0, "a raider flying past is left alone");
    memory.note(1, 2, 0.0, true);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 1.0, &[]), 2, "the one that shot is picked, not the nearer one");
    memory.note(1, 3, 2.0, true);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 3.0, &[]), 3, "the nearest of two attackers");
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 31.0, &[]), 3, "raider 2 forgotten after 30 s, 3 still remembered");
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 32.5, &[]), 0, "both forgotten");
}

#[test]
fn a_turret_defends_a_civilian_or_ally_within_two_km_only() {
    let rows = rows_of(&[
        (1, 0, Vector3::ZERO),
        (4, 0, Vector3::new(1500.0, 0.0, 0.0)),
        (5, 2, Vector3::new(-1500.0, 0.0, 0.0)),
        (6, 0, Vector3::new(0.0, 0.0, 2600.0)),
        (2, 1, Vector3::new(0.0, 600.0, 0.0)),
    ]);
    let find = row_finder(&rows);
    let t = table();
    let mut memory = Memory::default();
    memory.note(4, 2, 0.0, false);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 0.0, &[]), 2, "an ally 1.5 km away is defended");
    memory.clear();
    memory.note(5, 2, 0.0, true);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 0.0, &[]), 2, "a neutral civilian 1.5 km away is defended");
    memory.clear();
    memory.note(5, 2, 0.0, false);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 0.0, &[]), 0, "a neutral warship is not");
    memory.clear();
    memory.note(6, 2, 0.0, true);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 0.0, &[]), 0, "an ally 2.6 km away is too far");
}

#[test]
fn a_friendly_attacker_out_of_reach_or_dead_is_not_picked() {
    let mut rows = rows_of(&[
        (1, 0, Vector3::ZERO),
        (7, 0, Vector3::new(0.0, 100.0, 0.0)),
        (2, 1, Vector3::new(0.0, 3000.0, 0.0)),
        (3, 1, Vector3::new(0.0, 500.0, 0.0)),
    ]);
    let t = table();
    let mut memory = Memory::default();
    memory.note(1, 7, 0.0, true);
    memory.note(1, 2, 0.0, true);
    memory.note(1, 3, 0.0, true);
    rows.flags[3] = FLAG_RIGID;
    let find = row_finder(&rows);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 0.0, &[]), 0, "friendly fire, out of reach and destroyed: none");
}

#[test]
fn a_target_inside_the_arc_comes_before_a_nearer_one_below_it() {
    let rows = rows_of(&[
        (1, 0, Vector3::ZERO),
        (2, 1, Vector3::new(0.0, -400.0, -100.0)),
        (3, 1, Vector3::new(0.0, 900.0, -900.0)),
    ]);
    let find = row_finder(&rows);
    let mut memory = Memory::default();
    memory.note(1, 2, 0.0, true);
    memory.note(1, 3, 0.0, true);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &table(), 3, 0.0, &[]), 3);
    memory.clear();
    memory.note(1, 2, 0.0, true);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &table(), 3, 0.0, &[]), 2, "below the arc, but the only one");
}

#[test]
fn the_memory_refreshes_prunes_and_forgets_in_order() {
    let mut m = Memory::default();
    m.note(1, 2, 0.0, false);
    m.note(1, 3, 5.0, false);
    m.note(1, 2, 10.0, false);
    m.note(1, 1, 10.0, false);
    assert_eq!(m.len(), 2, "a refresh keeps one entry; a ship never attacks itself");
    assert_eq!(m.until_s[0], 40.0);
    m.prune(36.0);
    assert_eq!((m.len(), m.attacker[0]), (1, 2));
    m.note(4, 5, 36.0, true);
    m.forget(2);
    assert_eq!((m.len(), m.victim[0], m.attacker[0]), (1, 4, 5));
}

fn level_frame() -> Frame {
    frame(
        &Basis::IDENTITY,
        Vector3::ZERO,
        Vector3::ZERO,
        Vector3::new(0.0, 1.0, 0.0),
        Vector3::new(0.0, 0.0, -1.0),
    )
}

#[test]
fn the_angles_and_the_direction_are_inverse() {
    let f = level_frame();
    for &(az, el) in &[(0.0, 0.0), (1.0, 0.3), (-2.5, 1.2), (3.0, -0.15)] {
        let d = direction_of(&f, az, el);
        let (a, e) = angles_of(&f, d);
        assert!((a - az).abs() < 1e-5 && (e - el).abs() < 1e-5, "{az} {el} -> {a} {e}");
    }
    let (a, e) = angles_of(&f, Vector3::new(-1.0, 0.0, 0.0));
    assert!((a - FRAC_PI_2).abs() < 1e-6 && e.abs() < 1e-6, "azimuth turns from the nose toward port: {a}");
}

#[test]
fn the_slew_is_rate_limited_takes_the_short_way_and_stays_in_the_arc() {
    let min_el = (-10_f64).to_radians();
    let (az, el) = slew(0.0, 0.0, 1.0, 0.5, min_el, 0.1, 0.05);
    assert!((az - 0.1).abs() < 1e-12 && (el - 0.05).abs() < 1e-12);
    let (az, _) = slew(3.0, 0.0, -3.0, 0.0, min_el, 0.1, 0.05);
    assert!(az > 3.0 || az < -3.0, "across the back, not the long way round: {az}");
    let (_, el) = slew(0.0, min_el, 0.0, -1.2, min_el, 0.1, 0.5);
    assert_eq!(el, min_el, "never below the base's arc");
    let (_, el) = slew(0.0, 1.5, 0.0, 2.0, min_el, 0.1, 0.5);
    assert_eq!(el, FRAC_PI_2, "never past straight up");
}

#[test]
fn the_aim_converges_on_a_crossing_target_and_the_gate_opens() {
    let g = gun();
    let f = level_frame();
    let (mut az, mut el) = (0.0, 0.0);
    let mut target = Vector3::new(-800.0, 300.0, -600.0);
    let velocity = Vector3::new(60.0, 0.0, 0.0);
    let mut opened = -1;
    for tick in 0..600 {
        let a = aim(&f, Vector3::ZERO, az, el, (-10_f64).to_radians(), &g, target, velocity, DT);
        (az, el) = (a.azimuth, a.elevation);
        if gate(&a, &g, 10.0, f64::NEG_INFINITY, tick as f64 * DT) && opened < 0 {
            opened = tick;
        }
        target = add(target, scale(velocity, DT as f32));
    }
    assert!(opened > 0, "the gate opened once the barrel came round");
    assert!(opened < 240, "within four seconds at 60 degrees a second: tick {opened}");
    let a = aim(&f, Vector3::ZERO, az, el, (-10_f64).to_radians(), &g, target, velocity, DT);
    assert!(a.error_rad < 0.01, "tracking: {} rad off", a.error_rad);
}

#[test]
fn the_gate_shuts_outside_the_arc_out_of_range_off_target_and_while_reloading() {
    let g = gun();
    let f = level_frame();
    let min_el = (-10_f64).to_radians();
    let settled = |target: Vector3| {
        let (mut az, mut el) = (0.0, 0.0);
        let mut last = aim(&f, Vector3::ZERO, az, el, min_el, &g, target, Vector3::ZERO, DT);
        for _ in 0..600 {
            last = aim(&f, Vector3::ZERO, az, el, min_el, &g, target, Vector3::ZERO, DT);
            (az, el) = (last.azimuth, last.elevation);
        }
        last
    };
    let good = settled(Vector3::new(0.0, 200.0, -1000.0));
    assert!(gate(&good, &g, 10.0, 0.0, 1.0));
    assert!(!gate(&good, &g, 10.0, 2.0, 1.0), "reloading");
    let below = settled(Vector3::new(0.0, -600.0, -800.0));
    assert!(!below.in_arc && !gate(&below, &g, 10.0, 0.0, 1.0), "below the base");
    assert!(below.elevation >= min_el - 1e-9, "the barrel waits at the arc's edge");
    let far = settled(Vector3::new(0.0, 200.0, -1700.0));
    assert!(!gate(&far, &g, 10.0, 0.0, 1.0), "out of range");
    let fresh = aim(&f, Vector3::ZERO, PI, 0.0, min_el, &g, Vector3::new(0.0, 200.0, -1000.0), Vector3::ZERO, DT);
    assert!(!gate(&fresh, &g, 10.0, 0.0, 1.0), "still facing away");
}

#[test]
fn the_spread_is_seeded_bounded_and_varies_by_tick() {
    let axis = normalized(Vector3::new(0.3, 0.5, -0.8));
    let s = 0.6_f64.to_radians();
    let a = spread(axis, s, 7, 100);
    assert_eq!(a, spread(axis, s, 7, 100), "the same mount and tick throw the same");
    assert_ne!(a, spread(axis, s, 7, 101));
    assert_ne!(a, spread(axis, s, 8, 100));
    for tick in 0..2000 {
        let d = spread(axis, s, 3, tick);
        let off = f64::from(dot(d, axis)).clamp(-1.0, 1.0).acos();
        assert!(off <= s + 1e-5, "inside the cone at tick {tick}: {off}");
    }
    assert_eq!(spread(axis, 0.0, 3, 5), axis);
}

#[test]
fn a_mount_frame_follows_its_ship_and_its_base() {
    let basis = Basis::from_axis_angle(Vector3::new(0.0, 0.0, 1.0), FRAC_PI_2 as f32);
    let up = Vector3::new(1.0, 0.0, 0.0);
    let f = frame(&basis, Vector3::new(10.0, 0.0, 0.0), Vector3::new(2.0, 0.0, 0.0), up, rest_forward(up));
    assert!(f64::from(dist_sq(f.pivot, Vector3::new(10.0, 2.0, 0.0))) < 1e-8, "{:?}", f.pivot);
    assert!(f64::from(dist_sq(f.up, Vector3::new(0.0, 1.0, 0.0))) < 1e-8, "a flank mount's base turns with the ship");
    assert!(f64::from(dist_sq(f.forward, Vector3::new(0.0, 0.0, -1.0))) < 1e-8, "its rest along the nose");
    let flat = rest_forward(Vector3::new(0.0, 0.0, -1.0));
    assert!(f64::from(dist_sq(flat, Vector3::new(0.0, 1.0, 0.0))) < 1e-8, "a base facing the nose rests toward the top");
}

#[test]
fn the_mounts_reuse_a_freed_slot_and_change_its_stamp() {
    let mut m = Mounts::default();
    let a = m.add(1, 1, 10, 0, Vector3::ZERO, Vector3::new(0.0, 1.0, 0.0), 200.0, 3.0, gun());
    let b = m.add(2, 1, 11, 0, Vector3::ZERO, Vector3::new(0.0, 1.0, 0.0), 220.0, 3.0, gun());
    assert_eq!((a, b, m.count()), (0, 1, 2));
    assert!((m.min_elevation[0] - (-10_f64).to_radians()).abs() < 1e-12, "200 degrees: 10 below the base");
    assert!((m.min_elevation[1] - (-20_f64).to_radians()).abs() < 1e-12);
    let stamp = m.stamp[0];
    m.remove(0);
    assert_ne!(m.stamp[0], stamp);
    assert_eq!(m.add(3, 9, 12, 0, Vector3::ZERO, Vector3::new(0.0, 1.0, 0.0), 200.0, 3.0, gun()), 0);
    let mut job = PickJob::default();
    m.live[1] = false;
    job.take_from(&m, &Memory::default(), &table(), 3, &Hulls::default(), &Latch::default(), &[]);
    assert_eq!(job.mounts.len(), 1, "only live mounts are picked for");
    assert_eq!((job.mounts[0].slot, job.mounts[0].stamp), (0, 9));
}

#[test]
fn the_pick_over_a_job_answers_every_live_mount_with_its_stamp() {
    let rows = rows_of(&[(1, 0, Vector3::ZERO), (2, 1, Vector3::new(0.0, 400.0, 0.0))]);
    let mut m = Mounts::default();
    m.add(1, 4, 1, 0, Vector3::ZERO, Vector3::new(0.0, 1.0, 0.0), 200.0, 3.0, gun());
    m.add(2, 6, 1, 0, Vector3::ZERO, Vector3::new(0.0, -1.0, 0.0), 200.0, 3.0, gun());
    let mut memory = Memory::default();
    memory.note(1, 2, 0.0, true);
    let mut job = PickJob::default();
    job.take_from(&m, &memory, &table(), 3, &Hulls::default(), &Latch::default(), &[]);
    pick_all(&rows, row_finder(&rows), 0.0, &mut job, &Grid::default());
    assert_eq!(
        job.picks,
        vec![
            Pick { slot: 0, stamp: 4, target: 2 },
            Pick { slot: 1, stamp: 6, target: 2 }
        ]
    );
}

// --- the own hull's line of fire (Q33) ------------------------------------------------------------------------------

fn boxv(origin: (f32, f32, f32), half: [f64; 3]) -> Volume {
    Volume::new(false, Basis::IDENTITY, Vector3::new(origin.0, origin.1, origin.2), half)
}

#[test]
fn a_segment_through_a_box_is_blocked_one_past_it_is_not() {
    let v = boxv((0.0, 0.0, 0.0), [10.0, 2.0, 30.0]);
    assert!(segment_hits([0.0, 10.0, 0.0], [0.0, -10.0, 0.0], &v), "straight through");
    assert!(segment_hits([20.0, 0.0, 0.0], [-20.0, 1.9, 5.0], &v), "slanting through");
    assert!(!segment_hits([0.0, 10.0, 0.0], [0.0, 2.01, 0.0], &v), "stopping short of the top face");
    assert!(!segment_hits([11.0, 10.0, 0.0], [11.0, -10.0, 0.0], &v), "beside it");
    assert!(!segment_hits([0.0, 0.0, 0.0], [0.0, 50.0, 0.0], &v), "starting inside: the mount's own block does not count");
    assert!(segment_hits([0.0, 3.0, -40.0], [0.0, 1.0, 40.0], &v), "grazing in along its length");
}

#[test]
fn a_segment_near_a_capsule_is_blocked_inside_its_radius_only() {
    // Along z, radius 3, half segment 20: the capsule's own y axis turned onto z.
    let turn = Basis::from_cols(Vector3::new(1.0, 0.0, 0.0), Vector3::new(0.0, 0.0, 1.0), Vector3::new(0.0, -1.0, 0.0));
    let v = Volume::new(true, turn, Vector3::new(0.0, 0.0, 50.0), [20.0, 3.0, 0.0]);
    assert!((v.reach - 23.0).abs() < 1e-9);
    assert!(segment_hits([-10.0, 2.9, 50.0], [10.0, 2.9, 50.0], &v), "2.9 m from the axis");
    assert!(!segment_hits([-10.0, 3.1, 50.0], [10.0, 3.1, 50.0], &v), "3.1 m from the axis");
    assert!(segment_hits([0.0, 0.0, 80.0], [0.0, 0.0, 20.0], &v), "end to end through both caps");
    assert!(!segment_hits([0.0, 0.0, 74.0], [0.0, 0.0, 99.0], &v), "behind the far cap");
    assert!(segment_hits([0.0, -10.0, 72.5], [0.0, 10.0, 72.5], &v), "through the end cap's sphere");
    assert!(!segment_hits([0.0, 0.0, 50.0], [0.0, 30.0, 50.0], &v), "starting inside");
}

#[test]
fn the_line_is_tested_in_the_ships_turned_frame() {
    // A 200 m spine along the ship's z; the ship turned 90 degrees about y and moved: its spine lies along World x.
    let spine = boxv((0.0, 0.0, 0.0), [5.0, 5.0, 100.0]);
    let yaw = Basis::from_cols(Vector3::new(0.0, 0.0, -1.0), Vector3::new(0.0, 1.0, 0.0), Vector3::new(1.0, 0.0, 0.0));
    let at = Vector3::new(1000.0, 0.0, 0.0);
    let above = Vector3::new(1000.0, 8.0, 0.0);
    assert!(line_blocked(&yaw, at, above, Vector3::new(1050.0, -300.0, 0.0), &[spine]), "down through the spine");
    assert!(!line_blocked(&yaw, at, above, Vector3::new(1000.0, -300.0, 600.0), &[spine]), "down past its side");
    assert!(!line_blocked(&yaw, at, above, Vector3::new(1050.0, -300.0, 0.0), &[]), "no volumes, nothing blocks");
}

#[test]
fn a_turret_skips_an_attacker_its_own_hull_hides() {
    // The mount on the ship's top; raider 2 right below the ship (behind its hull), raider 3 farther off to the side.
    let rows = rows_of(&[
        (1, 0, Vector3::ZERO),
        (2, 1, Vector3::new(0.0, -400.0, 0.0)),
        (3, 1, Vector3::new(900.0, 100.0, 0.0)),
    ]);
    let hull = [boxv((0.0, 0.0, 0.0), [10.0, 4.0, 40.0])];
    let mut memory = Memory::default();
    memory.note(1, 2, 0.0, true);
    memory.note(1, 3, 0.0, true);
    let find = row_finder(&rows);
    let t = table();
    let mut low = mount(1);
    low.min_elevation = -FRAC_PI_2; // a full sphere: only the hull hides the raider below
    assert_eq!(pick(&rows, &find, &low, &memory, &t, 3, 1.0, &[]), 2, "with no hull the nearer one");
    assert_eq!(pick(&rows, &find, &low, &memory, &t, 3, 1.0, &hull), 3, "the hull hides the one below");
    memory.forget(3);
    assert_eq!(pick(&rows, &find, &low, &memory, &t, 3, 1.0, &hull), 0, "and with nothing else, no target at all");
}

#[test]
fn the_hull_table_unpacks_and_versions() {
    let mut h = Hulls::default();
    let mut packed = vec![0.0; VOLUME_LEN * 2];
    for (k, v) in [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 1.0, 2.0, 3.0].iter().enumerate() {
        packed[1 + k] = *v;
    }
    packed[VOLUME_LEN] = 1.0;
    packed[VOLUME_LEN + 13] = 5.0;
    packed[VOLUME_LEN + 14] = 2.0;
    h.set(7, &packed);
    assert_eq!(h.version, 1);
    let v = h.of(7);
    assert_eq!(v.len(), 2);
    assert!(!v[0].capsule && v[1].capsule);
    assert_eq!(v[0].origin, Vector3::new(2.0, 3.0, 4.0));
    assert_eq!(v[0].half, [1.0, 2.0, 3.0]);
    assert!((v[1].reach - 7.0).abs() < 1e-9);
    assert!(h.of(8).is_empty());
}

#[test]
fn a_friend_that_fired_on_a_civilian_it_had_selected_is_answered_by_that_civilians_turrets_only() {
    // Ship 1 the civilian with the turret, 7 a friend 400 m above it, 8 another civilian of the same people nearby.
    let rows = rows_of(&[
        (1, 0, Vector3::ZERO),
        (7, 0, Vector3::new(0.0, 400.0, 0.0)),
        (8, 0, Vector3::new(600.0, 0.0, 0.0)),
    ]);
    let find = row_finder(&rows);
    let t = table();
    let mut memory = Memory::default();
    // A friend's hit, as with friendly fire on: never answered.
    memory.note(1, 7, 0.0, true);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 0.0, &[]), 0, "a friend is not a target");
    assert!(!memory.is_provoked(1, 7, 0.0));
    assert_eq!(memory.provoked_count(), 0);
    // It fired close with the civilian selected: the civilian's own turret answers.
    memory.note_provoked(1, 7, 1.0);
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 1.0, &[]), 7, "the provoked civilian's turret picks it");
    assert!(memory.is_provoked(1, 7, 1.0), "and its bolts may land on it");
    assert!(!memory.is_provoked(7, 1, 1.0), "not the other way round");
    assert!(!memory.is_provoked(8, 7, 1.0), "nor from anyone else");
    assert_eq!(memory.provoked_count(), 1);
    // A neighbour's turret does not join in against a friend.
    assert_eq!(pick(&rows, &find, &mount(8), &memory, &t, 3, 1.0, &[]), 0, "the civilian beside it stays silent");
    // A later ordinary hit keeps the provocation; the memory's time ends it.
    memory.note(1, 7, 2.0, true);
    assert!(memory.is_provoked(1, 7, 2.0));
    memory.prune(2.0 + MEMORY_S + 1.0);
    assert_eq!(memory.provoked_count(), 0, "forgotten with the memory");
    assert_eq!(pick(&rows, &find, &mount(1), &memory, &t, 3, 40.0, &[]), 0);
}
