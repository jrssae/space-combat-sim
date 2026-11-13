// The tier fire's unit tests (M7-T16), beside the kernel and outside its engine-free guard (test builds only).
use super::*;

// M7-T16: a fighter's shot sees 0.78 of the target's bounding radius (refitted for the raider's hull), a far gun still 0.7.
#[test]
fn a_fighter_shot_sees_the_refitted_share_of_the_bounding_radius() {
    let (range, radius, hit) = (600.0, 8.4, 0.25);
    let got = hit_chance(range, radius, hit, 1000.0, 0.0, 0.01, 12.0, 4000.0, 0.0);
    let flight = range / 1000.0;
    let aim = range * 0.01 * AIM_SPREAD;
    let gate = 12.0 * GATE_SPREAD;
    let nose = range * NOSE_SPREAD_RAD;
    let dodge = 0.5 * DODGE_ACCEL_MPS2 * flight * flight;
    let sigma2 = aim * aim + gate * gate + nose * nose + dodge * dodge + MISS_FLOOR_M * MISS_FLOOR_M;
    assert_eq!(got.to_bits(), offset_disc_chance(radius * 0.78 + hit, sigma2, 0.0).to_bits());
    let gun_gate = range * GUN_GATE_RAD.tan() * GATE_SPREAD;
    let gun_dodge = 0.5 * GUN_DODGE_ACCEL_MPS2 * flight * flight;
    let gun_sigma2 = gun_gate * gun_gate + gun_dodge * gun_dodge + MISS_FLOOR_M * MISS_FLOOR_M;
    assert_eq!(turret_chance(range, radius).to_bits(), disc_chance(radius * 0.7, gun_sigma2).to_bits());
}
