use std::collections::HashMap;

use godot::builtin::{Basis, Vector3};

use super::*;
use crate::damage_store::landing::{self as dl, Ctx, LandHit, LandOut, Target};
use crate::damage_store::{DamageStore, Hull};

fn spec() -> Spec {
    Spec {
        d0: 100.0,
        radius: 50.0,
        impulse: 2000.0,
        cap: 50.0,
    }
}

fn identity_shape(capsule: bool, origin: Vector3) -> Shape {
    Shape {
        capsule,
        basis: Basis::IDENTITY,
        origin,
        inv_basis: Basis::IDENTITY,
        inv_origin: Vector3::new(-origin.x, -origin.y, -origin.z),
        half: Vector3::new(1.0, 2.0, 3.0),
        radius: 1.0,
        half_segment: 2.0,
    }
}

#[test]
fn the_falloff_is_one_at_the_centre_and_eases_to_nothing_at_the_radius() {
    assert_eq!(falloff(0.0, 50.0), 1.0);
    assert_eq!(falloff(-5.0, 50.0), 1.0, "inside a hull counts as the centre");
    assert_eq!(falloff(25.0, 50.0), 0.5625);
    assert_eq!(falloff(50.0, 50.0), 0.0);
    assert_eq!(falloff(10.0, 0.0), 0.0);
    assert_eq!(falloff(10.0, f64::NAN), 0.0, "NaN is no blast");
    let s = spec();
    assert_eq!(s.damage_at(25.0), 56.25);
    assert_eq!(s.push_at(25.0, 10.0, 0.0), 0.0, "no mass, no push");
    assert_eq!(s.push_at(25.0, 10.0, 1000.0), 2000.0 * 0.5625 * 10.0 / 1000.0);
    assert_eq!(s.push_at(0.0, 1000.0, 1.0), 50.0, "capped");
    assert_eq!(s.push_at(0.0, -4.0, 1.0), 0.0, "a negative area pushes nothing");
}

#[test]
fn a_box_and_a_capsule_give_their_nearest_points() {
    let b = identity_shape(false, Vector3::new(10.0, 0.0, 0.0));
    assert_eq!(b.nearest_point(Vector3::new(20.0, 5.0, 0.0)), Vector3::new(11.0, 2.0, 0.0));
    assert_eq!(b.nearest_point(Vector3::new(10.5, 0.0, 0.0)), Vector3::new(10.5, 0.0, 0.0), "inside: the point itself");
    let c = identity_shape(true, Vector3::ZERO);
    assert_eq!(c.nearest_point(Vector3::new(4.0, 0.0, 0.0)), Vector3::new(1.0, 0.0, 0.0));
    assert_eq!(c.nearest_point(Vector3::new(0.0, 9.0, 0.0)), Vector3::new(0.0, 3.0, 0.0), "past the end: the cap");
}

#[test]
fn a_shape_unpacks_from_its_thirty_numbers() {
    let mut n = vec![1.0];
    for _ in 0..2 {
        n.extend_from_slice(&[1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]);
    }
    n.extend_from_slice(&[1.0, 2.0, 3.0, 1.0, 2.0]);
    assert_eq!(n.len(), SHAPE_LEN);
    assert_eq!(Shape::unpack(&n), Some(identity_shape(true, Vector3::ZERO)));
    assert_eq!(Shape::unpack(&n[..10]), None);
}

#[test]
fn the_nearest_hit_volume_is_measured_in_the_bodys_frame() {
    let shapes = [identity_shape(false, Vector3::ZERO), identity_shape(false, Vector3::new(0.0, 0.0, -20.0))];
    let origin = Vector3::new(100.0, 0.0, 0.0);
    let (d, p) = nearest_on(&shapes, &Basis::IDENTITY, origin, Vector3::new(100.0, 0.0, -40.0)).unwrap();
    assert_eq!(d, 17.0, "the far box, 17 m beyond its face");
    assert_eq!(p, Vector3::new(100.0, 0.0, -23.0));
    assert_eq!(nearest_on(&[], &Basis::IDENTITY, origin, Vector3::ZERO), None);
}

#[test]
fn each_ship_is_picked_once_by_its_nearest_piece_in_the_order_first_reached() {
    let r = |index: u32, owner: i64, distance: f64| Reach {
        index,
        hull: i64::from(index),
        owner,
        distance,
        point: Vector3::ZERO,
        volume: -1,
        place: Vector3::ZERO,
    };
    let mut out = Vec::new();
    pick(&[r(0, 5, 30.0), r(1, 6, 10.0), r(2, 5, 20.0), r(3, 5, 25.0)], &mut out);
    assert_eq!(out.iter().map(|p| p.index).collect::<Vec<_>>(), vec![2, 1], "the capital's nearer rotor in its first place");
}

fn hit(target: i64, damage: f64, shooter: i64) -> LandHit {
    LandHit {
        target,
        body: target + 100,
        shooter,
        shooter_faction: 0,
        target_faction: Some(0),
        disguise: Some(0),
        damage,
        point: Vector3::ZERO,
        volume: -1,
        local: None,
    }
}

#[test]
fn a_blast_hurts_its_own_side_names_no_attacker_for_a_death_and_shares_one_batch() {
    let mut store = DamageStore::default();
    let mut targets = HashMap::new();
    let t = Target {
        hull: store.hulls.add(Hull::new(100.0)) as i64,
        summary: 7,
        ..Target::default()
    };
    targets.insert(7, t);
    let relation = [2u8];
    let ctx = Ctx {
        blast: true,
        friendly_fire: false,
        god_mode: false,
        relation: &relation,
        factions: 1,
    };
    let mut out = LandOut::default();
    out.clear();
    dl::land_more(&mut store, &targets, &[hit(7, 10.0, 3)], 0, &ctx, &mut out);
    assert!(!out.stopped);
    dl::land_more(&mut store, &targets, &[hit(7, 5.0, 0)], 0, &ctx, &mut out);
    out.finish();
    assert_eq!(out.summaries.len(), 1, "two blasts, one summary");
    let s = &out.summaries[0];
    assert_eq!((s.hits, s.damage), (2, 15.0), "a friendly hull is hurt: a blast is friend or foe alike");
    assert_eq!(s.last_shooter, 3, "a death's blast (no shooter) does not hide the last shooter");
    assert!(out.attackers.is_empty(), "no attacker for the turrets to remember");
    assert!(out.reveals.is_empty(), "a blast gives no disguise away");
    assert_eq!(out.sync.len(), dl::OUT_WIDTH);
    assert_eq!(out.sync[3], 85.0);
}
