// The keep-out's maths (M8-T17): a ship inside leaves, the exempt and the clear are left alone, a wish through is turned.
use godot::builtin::Vector3;

use super::*;

fn gate() -> KeepOut {
    KeepOut { a: [0.0, 0.0, 0.0], b: [0.0, 0.0, 1200.0], velocity: [0.0; 3], radius: 1500.0, exempt: vec![7] }
}

fn ship(at: Vector3, v: Vector3, id: i64) -> Ship {
    Ship { position: at, velocity: v, radius: 10.0, a_brake: 40.0, body_id: id, tie_hash: 3 }
}

#[test]
fn a_ship_inside_leaves() {
    let s = ship(Vector3::new(100.0, 0.0, 600.0), Vector3::ZERO, 1);
    let (v, urgent) = steer(&[gate()], [0.0; 3], &s, Vector3::ZERO).expect("asked to leave");
    assert!(urgent);
    assert!(v.x > 70.0, "out, away from the axis: {v:?}");
}

#[test]
fn the_exempt_and_the_clear_are_left_alone() {
    let k = gate();
    let inside = ship(Vector3::new(100.0, 0.0, 600.0), Vector3::ZERO, 7);
    assert!(steer(std::slice::from_ref(&k), [0.0; 3], &inside, Vector3::ZERO).is_none(), "its own ship");
    let far = ship(Vector3::new(5000.0, 0.0, 0.0), Vector3::ZERO, 1);
    assert!(steer(&[k], [0.0; 3], &far, Vector3::new(0.0, 100.0, 0.0)).is_none(), "nowhere near");
}

#[test]
fn a_wish_through_it_is_turned_round_it() {
    let s = ship(Vector3::new(-2500.0, 0.0, 600.0), Vector3::new(100.0, 0.0, 0.0), 1);
    let (v, _) = steer(&[gate()], [0.0; 3], &s, Vector3::new(100.0, 0.0, 0.0)).expect("turned");
    assert!((f64::from(v.length()) - 100.0).abs() < 1.0, "at its speed");
    assert!(v.y.abs() + v.z.abs() > 5.0, "sideways: {v:?}");
}

#[test]
fn the_origin_moves_the_volume_into_the_local_frame() {
    let s = ship(Vector3::new(100.0, 0.0, 600.0), Vector3::ZERO, 1);
    assert!(steer(&[gate()], [10000.0, 0.0, 0.0], &s, Vector3::ZERO).is_none(), "the volume is 10 km off here");
}

#[test]
fn unpack_reads_the_flat_arrays() {
    let floats = [0.0, 0.0, 0.0, 0.0, 0.0, 1200.0, 0.0, 0.0, 0.0, 1500.0, 2.0];
    let outs = unpack(&floats, &[9, 4]);
    assert_eq!(outs.len(), 1);
    assert_eq!(outs[0].exempt, vec![4, 9]);
}
