// The ram tracker's unit tests (M5-T33): its rules without Jolt, a tick a list of bodies.
use super::*;

const DT: f64 = 1.0 / 60.0;
const A: i64 = 101;
const B: i64 = 202;
const C: i64 = 303;
const LIMITS: [f64; 2] = [5.0, 18.0];

// One body as read this tick: its id, velocity along z, and the bodies it touches.
struct Body(i64, f32, Vec<i64>);

// One contact phase: the feed, then the same limits for every window asked.
fn contacts(tracker: &mut Tracker, bodies: &[Body]) -> Vec<Ram> {
    let ids: Vec<i64> = bodies.iter().map(|b| b.0).collect();
    let velocities: Vec<Vector3> = bodies.iter().map(|b| Vector3::new(0.0, 0.0, b.1)).collect();
    let accels = vec![Vector3::ZERO; bodies.len()];
    let mut touched = Vec::new();
    let mut starts = Vec::new();
    let mut others = Vec::new();
    for (k, b) in bodies.iter().enumerate() {
        if b.2.is_empty() {
            continue;
        }
        touched.push(k as u32);
        starts.push(others.len() as u32);
        others.extend_from_slice(&b.2);
    }
    starts.push(others.len() as u32);
    let points = vec![Vector3::new(0.0, 0.0, -5.0); others.len()];
    let normals = vec![Vector3::new(0.0, 0.0, -1.0); others.len()];
    let asked = tracker.feed(
        &Feed {
            ids: &ids,
            velocities: &velocities,
            accels: &accels,
            touched: &touched,
            starts: &starts,
            others: &others,
            points: &points,
            normals: &normals,
        },
        DT,
    );
    let limits: Vec<f64> = asked.iter().flat_map(|_| LIMITS).collect();
    tracker.land(&limits)
}

fn tick(tracker: &mut Tracker, bodies: &[Body]) -> Vec<Ram> {
    let rams = contacts(tracker, bodies);
    tracker.end_tick();
    rams
}

// A head-on at 30 m/s closing: approaching on tick 1, stopped against each other from tick 2 on.
fn head_on(tracker: &mut Tracker, ticks: usize) -> Vec<Ram> {
    let mut all = tick(tracker, &[Body(A, -15.0, vec![]), Body(B, 15.0, vec![])]);
    for _ in 1..ticks {
        all.extend(tick(
            tracker,
            &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![A])],
        ));
    }
    all
}

#[test]
fn a_bounce_lands_one_ram_per_body_when_the_window_closes() {
    let mut tracker = Tracker::default();
    assert!(head_on(&mut tracker, 3).is_empty(), "still measuring");
    tracker.reset();
    let rams = head_on(&mut tracker, 4);
    assert_eq!(rams.len(), 2);
    assert_eq!((rams[0].hull_id, rams[0].other_id), (A, B));
    assert_eq!((rams[1].hull_id, rams[1].other_id), (B, A));
    for ram in &rams {
        assert_eq!(ram.dv, 15.0);
        assert_eq!(ram.relative_speed, 30.0);
        assert_eq!(ram.severity, severity(15.0, 5.0, 18.0));
    }
    assert_eq!(tracker.open_windows(), 0);
    tracker.reset();
    assert_eq!(
        head_on(&mut tracker, 60).len(),
        2,
        "a held contact is one collision"
    );
}

#[test]
fn a_lethal_change_lands_at_once() {
    let mut tracker = Tracker::default();
    tick(
        &mut tracker,
        &[Body(A, -40.0, vec![]), Body(B, 0.0, vec![])],
    );
    let rams = tick(&mut tracker, &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![])]);
    assert_eq!(rams.len(), 1);
    assert_eq!(rams[0].severity, 1.0);
    assert_eq!(tracker.open_windows(), 0);
}

#[test]
fn a_body_first_seen_touching_opens_no_window() {
    let mut tracker = Tracker::default();
    tick(&mut tracker, &[Body(A, 0.0, vec![])]);
    tick(
        &mut tracker,
        &[Body(A, 0.0, vec![B]), Body(B, 20.0, vec![A])],
    );
    assert_eq!(
        tracker.open_windows(),
        1,
        "only the body seen the tick before"
    );
    assert!(tracker.in_contact(B, A));
}

#[test]
fn a_body_that_leaves_loses_its_windows() {
    let mut tracker = Tracker::default();
    tick(
        &mut tracker,
        &[Body(A, -15.0, vec![]), Body(B, 15.0, vec![])],
    );
    tick(
        &mut tracker,
        &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![A])],
    );
    assert_eq!(tracker.open_windows(), 2);
    let rams = tick(&mut tracker, &[Body(B, 0.0, vec![])]);
    assert!(rams.is_empty());
    assert_eq!(tracker.open_windows(), 1);
}

#[test]
fn a_swept_ram_is_one_ram_per_meeting_and_cancels_the_contact_windows() {
    let mut tracker = Tracker::default();
    tick(&mut tracker, &[Body(A, -6.0, vec![]), Body(B, 6.0, vec![])]);
    contacts(
        &mut tracker,
        &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![A])],
    );
    assert_eq!(tracker.open_windows(), 2);
    assert!(tracker.swept_meeting(A, B));
    assert_eq!(tracker.open_windows(), 0);
    assert!(!tracker.swept_meeting(B, A), "the same meeting");
    tracker.end_tick();
    // Jolt's contact for the same collision opens no window during the grace, and the held pair is not swept again.
    for _ in 0..SWEPT_GRACE_TICKS {
        let rams = contacts(
            &mut tracker,
            &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![A])],
        );
        assert!(rams.is_empty());
        assert_eq!(tracker.open_windows(), 0);
        tracker.keep_touching(A, B);
        tracker.end_tick();
    }
    contacts(
        &mut tracker,
        &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![A])],
    );
    assert!(
        !tracker.swept_meeting(A, B),
        "kept touching through the grace"
    );
    tracker.end_tick();
    // Apart for a tick, then meeting again: a second ram.
    tick(&mut tracker, &[Body(A, 0.0, vec![]), Body(B, 0.0, vec![])]);
    for _ in 0..SWEPT_GRACE_TICKS {
        tick(&mut tracker, &[Body(A, 0.0, vec![]), Body(B, 0.0, vec![])]);
    }
    contacts(&mut tracker, &[Body(A, 0.0, vec![]), Body(B, 0.0, vec![])]);
    assert!(tracker.swept_meeting(A, B));
}

#[test]
fn a_third_body_keeps_its_own_window() {
    let mut tracker = Tracker::default();
    tick(
        &mut tracker,
        &[
            Body(A, -15.0, vec![]),
            Body(B, 15.0, vec![]),
            Body(C, 15.0, vec![]),
        ],
    );
    contacts(
        &mut tracker,
        &[
            Body(A, 0.0, vec![B, C, B]),
            Body(B, 0.0, vec![A]),
            Body(C, 0.0, vec![A]),
        ],
    );
    assert_eq!(
        tracker.open_windows(),
        4,
        "a pair's second report opens nothing"
    );
    assert!(tracker.swept_meeting(A, B));
    assert_eq!(tracker.open_windows(), 2, "A and C keep theirs");
}

#[test]
fn a_reset_forgets_everything() {
    let mut tracker = Tracker::default();
    head_on(&mut tracker, 2);
    tracker.swept_meeting(A, C);
    tracker.reset();
    assert_eq!(tracker.open_windows(), 0);
    assert!(!tracker.in_contact(A, B));
    let rams = tick(
        &mut tracker,
        &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![A])],
    );
    assert!(rams.is_empty());
    assert_eq!(
        tracker.open_windows(),
        0,
        "no body was seen the tick before"
    );
    assert!(tracker.swept_meeting(A, C), "the grace went too");
}

#[test]
fn a_shift_moves_the_open_windows_points() {
    let mut tracker = Tracker::default();
    tick(&mut tracker, &[Body(A, -6.0, vec![]), Body(B, 6.0, vec![])]);
    tick(&mut tracker, &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![])]);
    tracker.shift(Vector3::new(100.0, 0.0, 0.0));
    tick(&mut tracker, &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![])]);
    let rams = tick(&mut tracker, &[Body(A, 0.0, vec![B]), Body(B, 0.0, vec![])]);
    assert_eq!(rams.len(), 1);
    assert_eq!(rams[0].point, Vector3::new(-100.0, 0.0, -5.0));
}
