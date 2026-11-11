// The radar kernel's unit tests (M5-T25), beside the kernel and outside its engine-free guard (test builds only): which
// contacts the plot flags as unidentified.
use super::*;

fn plot_of(reach: &[f64], known_id: i64) -> Plot {
    let ids = [1_i64, 2, 3];
    let positions = [
        Vector3::new(0.0, 0.0, -4000.0),
        Vector3::new(0.0, 0.0, -6000.0),
        Vector3::new(0.0, 0.0, -9000.0),
    ];
    let mut out = Plot::default();
    plot(
        &ids,
        &positions,
        reach,
        Vector3::ZERO,
        &Basis::IDENTITY,
        0,
        5000.0,
        known_id,
        &mut out,
    );
    out
}

// Drawn far to near: ids 3, 2, 1.
#[test]
fn a_silent_contact_beyond_the_identification_range_is_unknown() {
    let p = plot_of(&[0.0, 0.0, 0.0], 0);
    assert_eq!(p.order, vec![2, 1, 0]);
    assert_eq!(p.unknown, vec![1, 1, 0]);
}

#[test]
fn a_broadcast_or_an_identified_selection_is_known_at_any_range() {
    let p = plot_of(&[0.0, 15000.0, 0.0], 3);
    assert_eq!(p.unknown, vec![0, 0, 0]);
    let p = plot_of(&[0.0, 0.0, 0.0], 2);
    assert_eq!(p.unknown, vec![1, 0, 0]);
}
