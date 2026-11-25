// The shared battery model (M10-T13, Q81): toughness in the pulse sweep and the cover, the choice's order with a class, a
// capital battery's barrels. The grid's own tests (`grid_kernels/tests.rs`) run the same kernel through its wrappers.
use super::*;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

// Bolts by `(kind, faction, at, last step, radius, hits left)`, each living 5 s.
fn bolts_of(list: &[(u8, u32, Vector3, Vector3, f64, u8)]) -> Bolts {
    let mut b = Bolts::default();
    for (k, &(kind, faction, at, step, radius, hits)) in list.iter().enumerate() {
        b.ids.push(-(k as i64) - 1);
        b.positions.push(at);
        b.velocities.push(scale(step, 60.0));
        b.last_steps.push(step);
        b.faction_ix.push(faction);
        b.shooters.push(1);
        b.kinds.push(kind);
        b.radii.push(radius);
        b.damage.push(6.0);
        b.colors.push([1.0; 4]);
        b.expires_at.push(5.0);
        b.spent.push(false);
        b.hits_left.push(hits);
    }
    b.owned = list.len();
    b
}

fn hostile(b: &Bolts) -> impl Fn(usize, usize) -> bool + '_ {
    |p, q| b.faction_ix[p] != b.faction_ix[q]
}

#[test]
fn a_torpedo_takes_three_pulses_and_a_heavy_bolt_two() {
    // Three station pulses (faction 0) that each swept 33 m along +x through a torpedo (3 hits) and past a heavy bolt (2).
    let mut bolts = bolts_of(&[
        (KIND_INTERCEPT, 0, v(33.0, 0.0, 0.0), v(33.0, 0.0, 0.0), 2.5, 1),
        (KIND_INTERCEPT, 0, v(33.0, 0.3, 0.0), v(33.0, 0.0, 0.0), 2.5, 1),
        (KIND_INTERCEPT, 0, v(33.0, -0.3, 0.0), v(33.0, 0.0, 0.0), 2.5, 1),
        (KIND_MISSILE, 1, v(14.0, 0.0, 0.0), v(-2.0, 0.0, 0.0), 2.0, 3),
    ]);
    let mut scratch = PulseScratch::default();
    let mut hits = Vec::new();
    pulse_hits_by(&bolts, |_| true, hostile(&bolts), &mut scratch, &mut hits);
    assert_eq!(hits.iter().map(|h| (h.pulse, h.target, h.downed)).collect::<Vec<_>>(), vec![(0, 3, false), (1, 3, false), (2, 3, true)]);
    apply_hits(&mut bolts, &hits);
    assert!(bolts.spent[0] && bolts.spent[1] && bolts.spent[2] && bolts.spent[3], "every pulse spent, the torpedo down");
    // Two pulses on a heavy bolt the same tick bring it down; one alone leaves it flying with one hit left.
    let mut heavy = bolts_of(&[
        (KIND_INTERCEPT, 0, v(33.0, 0.0, 0.0), v(33.0, 0.0, 0.0), 2.5, 1),
        (KIND_BOLT, 1, v(14.0, 0.0, 0.0), v(-2.0, 0.0, 0.0), 0.5, 2),
    ]);
    pulse_hits_by(&heavy, |_| true, hostile(&heavy), &mut scratch, &mut hits);
    assert_eq!(hits.iter().map(|h| h.downed).collect::<Vec<_>>(), vec![false]);
    apply_hits(&mut heavy, &hits);
    assert!(heavy.spent[0] && !heavy.spent[1], "the pulse is spent, the heavy bolt flies on");
    assert_eq!(heavy.hits_left_of(1), 1);
}

#[test]
fn only_the_owners_pulses_meet_in_its_sweep() {
    let bolts = bolts_of(&[
        (KIND_INTERCEPT, 0, v(33.0, 0.0, 0.0), v(33.0, 0.0, 0.0), 2.5, 1),
        (KIND_INTERCEPT, 0, v(33.0, 0.3, 0.0), v(33.0, 0.0, 0.0), 2.5, 1),
        (KIND_BOLT, 1, v(14.0, 0.0, 0.0), v(-2.0, 0.0, 0.0), 0.5, 1),
    ]);
    let mut scratch = PulseScratch::default();
    let mut hits = Vec::new();
    // The grid owns pulse 1 only: pulse 0 (a capital's) is left to its own sweep.
    pulse_hits_by(&bolts, |p| p == 1, hostile(&bolts), &mut scratch, &mut hits);
    assert_eq!(hits.iter().map(|h| (h.pulse, h.target)).collect::<Vec<_>>(), vec![(1, 2)]);
}

#[test]
fn cover_counts_as_many_pulses_as_the_shot_has_hits_left() {
    let mut cover = PulseCover::default();
    cover.add(-7, 1.2);
    assert!(cover.covered(-7, 1, 1.5), "one pulse covers a bolt");
    assert!(!cover.covered(-7, 1, 1.0), "not one that hits before the pulse gets there");
    assert!(!cover.covered(-7, 2, 1.5), "a heavy bolt needs two");
    cover.add(-7, 1.4);
    assert!(cover.covered(-7, 2, 1.5));
    assert!(!cover.covered(-7, 3, 1.5), "a torpedo needs three");
    cover.add(-7, 0.9);
    assert!(cover.covered(-7, 3, 1.5));
    assert!(cover.covered(-7, 1, 1.0), "the earliest kept first");
    assert!(!cover.covered(-8, 1, 9.0), "another shot is not covered");
}

#[test]
fn the_choice_takes_a_missile_first_then_the_class_then_the_soonest() {
    let c = |bolt: u32, missile: bool, hit_in_s: f64| Incoming { bolt, missile, hit_in_s };
    // Bolts 0 and 1 at a friend (class 1), 2 and 3 at the battery's own hull (class 0); 4 a missile at the friend.
    let list = [c(0, false, 0.5), c(1, false, 0.4), c(2, false, 2.0), c(3, false, 1.5), c(4, true, 5.0)];
    let class = |i: &Incoming| u8::from(i.bolt < 2 || i.bolt == 4);
    assert_eq!(choose_by(&list, class, |_| true).map(|i| i.bolt), Some(4), "a missile first, wherever it goes");
    assert_eq!(choose_by(&list, class, |i| !i.missile).map(|i| i.bolt), Some(3), "then the own hull, soonest");
    assert_eq!(choose_by(&list, class, |i| i.bolt < 2).map(|i| i.bolt), Some(1), "then a friend, soonest");
    assert_eq!(choose_by(&list, |_| 0, |i| !i.missile).map(|i| i.bolt), Some(1), "one class: the soonest (the grid)");
}

#[test]
fn a_capital_battery_fires_its_barrels_side_by_side_in_turn() {
    let mut b = Battery::row(4, 3.0, 0.25);
    assert_eq!(b.count, 4);
    assert!((b.recharge_s - 1.0).abs() < 1e-12, "each barrel once in the four intervals");
    assert!((b.muzzles[0].x + 0.9).abs() < 1e-6 && (b.muzzles[3].x - 0.9).abs() < 1e-6 && b.muzzles[1].z == -3.0);
    let fired: Vec<usize> = (0..4).map(|k| b.fire(f64::from(k) * 0.25)).collect();
    assert_eq!(fired, vec![0, 1, 2, 3]);
    assert!(b.barrel_ready(1.0) && !b.barrel_ready(0.9));
    let pod = Battery::row(2, 3.0, 0.5);
    assert_eq!((pod.count, pod.recharge_s), (2, 1.0));
}
