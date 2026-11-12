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

// The dot buffers (M5-T34): a backing under every contact, plain and hollow dots without the selection, in the plot's order.
fn dots_of(rims: &[u8], selected: i32, backings: bool) -> (DotCounts, Vec<f32>, Vec<f32>, Vec<f32>) {
    let units: Vec<Vector2> = (0..rims.len()).map(|i| Vector2::new(i as f32, -(i as f32))).collect();
    let colours: Vec<Color> = (0..rims.len()).map(|i| Color::from_rgba(i as f32, 0.5, 0.25, 1.0)).collect();
    let counts = dot_counts(rims, selected, backings);
    let mut plain = vec![0.0; counts.plain * DOT_STRIDE];
    let mut rim = vec![0.0; counts.rim * DOT_STRIDE];
    let mut backing = vec![0.0; counts.backing * DOT_STRIDE];
    fill_dots(
        &units,
        &colours,
        rims,
        selected,
        Vector2::new(100.0, 50.0),
        10.0,
        (5.5, 3.0),
        Color::from_rgba(0.0, 0.0, 0.0, 0.8),
        &mut plain,
        &mut rim,
        &mut backing,
    );
    (counts, plain, rim, backing)
}

#[test]
fn the_counts_leave_out_the_selection_and_the_backings_cover_all() {
    let rims = [0_u8, 1, 0, 1, 0];
    assert_eq!(dot_counts(&rims, -1, true), DotCounts { plain: 3, rim: 2, backing: 5 });
    assert_eq!(dot_counts(&rims, 1, false), DotCounts { plain: 3, rim: 1, backing: 0 });
    assert_eq!(dot_counts(&rims, 4, true), DotCounts { plain: 2, rim: 2, backing: 5 });
    assert_eq!(dot_counts(&rims, 9, true), DotCounts { plain: 3, rim: 2, backing: 5 });
    assert_eq!(dot_counts(&[], -1, true), DotCounts::default());
}

#[test]
fn the_buffers_hold_each_dot_where_the_screen_puts_it() {
    let (counts, plain, rim, backing) = dots_of(&[0, 1, 0, 1, 0], 2, true);
    assert_eq!((counts.plain, counts.rim, counts.backing), (2, 2, 5));
    // Contact 4 is the second plain dot: unit (4, -4) at centre (100, 50), radius 10 px, dot radius 3.
    let d = &plain[DOT_STRIDE..2 * DOT_STRIDE];
    assert_eq!(d, &[3.0, 0.0, 0.0, 140.0, 0.0, 3.0, 0.0, 10.0, 4.0, 0.5, 0.25, 1.0]);
    // The rim ones are contacts 1 and 3.
    assert_eq!(rim[3], 110.0);
    assert_eq!(rim[DOT_STRIDE + 3], 130.0);
    // The backings: all five, the selection's among them, in the shadow colour and its radius.
    assert_eq!(backing[2 * DOT_STRIDE], 5.5);
    assert_eq!(backing[2 * DOT_STRIDE + 3], 120.0);
    assert_eq!(backing[2 * DOT_STRIDE + 11], 0.8);
}

#[test]
fn a_multimesh_grows_only_when_it_must() {
    assert_eq!(grown_capacity(0, 0), 0);
    assert_eq!(grown_capacity(64, 0), 0);
    assert_eq!(grown_capacity(64, 40), 64);
    assert_eq!(grown_capacity(64, 65), 128);
    assert_eq!(grown_capacity(8, 100), 100);
    assert_eq!(grown_capacity(0, 7), 7);
}

// Code review (M5-T47): a short column refuses the whole plot instead of dropping the contacts past its end.
#[test]
fn columns_of_different_lengths_plot_nothing() {
    let ids = [1_i64, 2, 3];
    let positions = [Vector3::new(0.0, 0.0, -100.0), Vector3::new(0.0, 0.0, -200.0)];
    let mut out = Plot::default();
    out.order.push(7);
    let ok = plot(&ids, &positions, &[0.0, 0.0, 0.0], Vector3::ZERO, &Basis::IDENTITY, 0, 5000.0, 0, &mut out);
    assert!(!ok);
    assert!(out.order.is_empty());
    assert_eq!(out.selected, -1);
}

// Code review (M5-T47): a second plot reuses the first one's buffers and gives the same answer.
#[test]
fn a_second_plot_reuses_its_buffers_and_matches_the_first() {
    let first = plot_of(&[0.0, 0.0, 0.0], 0);
    let mut again = first;
    let ids = [1_i64, 2, 3];
    let positions = [
        Vector3::new(0.0, 0.0, -4000.0),
        Vector3::new(0.0, 0.0, -6000.0),
        Vector3::new(0.0, 0.0, -9000.0),
    ];
    let capacity = again.scratch_keys.capacity();
    assert!(plot(&ids, &positions, &[0.0, 0.0, 0.0], Vector3::ZERO, &Basis::IDENTITY, 0, 5000.0, 0, &mut again));
    assert_eq!(again.order, vec![2, 1, 0]);
    assert_eq!(again.unknown, vec![1, 1, 0]);
    assert!(capacity >= 3 && again.scratch_keys.capacity() == capacity, "no new key buffer");
}

