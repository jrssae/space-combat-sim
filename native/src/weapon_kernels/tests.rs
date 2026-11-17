// The mines' kernels (M7-T64): a hostile inside the trigger sets a mine off and a friend does not; a touch of the body sets
// it off whoever's it is, also when a fast hull passes through between ticks; a blast reaches the mines round it.
use super::*;

const FRIEND: u32 = 0;
const FOE: u32 = 1;

// Mines at `at` (offsets from the belt's node), all of side `FRIEND`'s layer and in play.
fn belt(at: &[Vector3]) -> Mines {
    let local = at.to_vec();
    Mines {
        cells: mine_cells(&local),
        faction_ix: vec![FRIEND; local.len()],
        alive: vec![true; local.len()],
        local,
    }
}

// The hostility column of a hull of side `side` against the mines' layers.
fn column(side: u32) -> Vec<bool> {
    vec![side != FRIEND, side == FRIEND]
}

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

#[test]
fn a_hostile_inside_the_trigger_sets_a_mine_off_and_a_friend_does_not() {
    let origin = v(1000.0, -20.0, 300.0);
    let mines = belt(&[v(0.0, 0.0, 0.0)]);
    let hull = add(origin, v(0.0, 40.0, 0.0)); // 40 m off, radius 12: inside the 50 m trigger, far from the body
    let mut out = Vec::new();
    mine_hits(&mines, 0, origin, hull, 12.0, &column(FOE), &mut out);
    assert_eq!(out, vec![0], "a hostile inside the trigger");
    out.clear();
    mine_hits(&mines, 0, origin, hull, 12.0, &column(FRIEND), &mut out);
    assert!(out.is_empty(), "a friend inside the trigger sets nothing off");
    mine_touches(&mines, origin, hull, Vector3::ZERO, 12.0, &mut out);
    assert!(out.is_empty(), "nor does it touch the body");
}

#[test]
fn a_touch_sets_off_a_mine_of_any_side_on_any_tick() {
    let origin = v(0.0, 0.0, 0.0);
    let mut mines = belt(&[v(0.0, 0.0, -500.0), v(1.0, 0.0, 500.0)]);
    mines.faction_ix[1] = FOE;
    let reach = BODY_RADIUS_M + 12.0;
    for (m, centre) in [(0u32, v(0.0, 0.0, -500.0)), (1u32, v(1.0, 0.0, 500.0))] {
        let mut out = Vec::new();
        let inside = add(centre, v(0.0, (reach - 0.01) as f32, 0.0));
        mine_touches(&mines, origin, inside, Vector3::ZERO, 12.0, &mut out);
        assert_eq!(out, vec![m], "a hull whose sphere reaches mine {m}'s body touches it, whatever its side");
        out.clear();
        let outside = add(centre, v(0.0, (reach + 0.01) as f32, 0.0));
        mine_touches(&mines, origin, outside, Vector3::ZERO, 12.0, &mut out);
        assert!(out.is_empty(), "one just short of it does not");
    }
    mines.alive[0] = false;
    let mut out = Vec::new();
    mine_touches(&mines, origin, v(0.0, 0.0, -500.0), Vector3::ZERO, 12.0, &mut out);
    assert!(out.is_empty(), "a spent mine is not touched");
}

#[test]
fn a_fast_hull_passing_through_between_ticks_touches_the_mine() {
    let origin = v(0.0, 0.0, 0.0);
    let mines = belt(&[v(0.0, 0.0, 0.0), v(0.0, 400.0, 0.0)]);
    // 3 000 m/s across one 60 Hz tick: 50 m a tick, from 30 m before the mine to 20 m past it.
    let end = v(0.0, 2.0, -20.0);
    let step = v(0.0, 0.0, -50.0);
    let mut out = Vec::new();
    mine_touches(&mines, origin, end, step, 2.0, &mut out);
    assert_eq!(out, vec![0], "the move crossed the body");
    out.clear();
    mine_touches(&mines, origin, end, Vector3::ZERO, 2.0, &mut out);
    assert!(out.is_empty(), "where it ends alone is clear of the body");
    out.clear();
    mine_touches(&mines, origin, v(0.0, 10.0, -20.0), step, 2.0, &mut out);
    assert!(out.is_empty(), "a move that passes 10 m off a 3 m body with a 2 m hull does not touch");
}

#[test]
fn a_blast_reaches_the_mines_round_it_and_no_further() {
    let origin = v(-250.0, 10.0, 75.0);
    let edge = (BLAST_RADIUS_M + BODY_RADIUS_M) as f32;
    let mut mines = belt(&[
        v(0.0, 0.0, 0.0),
        v(edge - 0.01, 0.0, 0.0),
        v(0.0, edge + 0.01, 0.0),
        v(0.0, 0.0, -60.0),
        v(450.0, 0.0, 0.0),
    ]);
    mines.alive[0] = false; // the one going off
    let mut out = Vec::new();
    mines_in_blast(&mines, origin, origin, &mut out);
    assert_eq!(out, vec![1, 3], "the mines in play within the blast of their bodies, ascending");
}

#[test]
fn the_trigger_still_checks_a_third_of_the_mines_a_tick() {
    let origin = Vector3::ZERO;
    let mines = belt(&[v(0.0, 0.0, 0.0), v(0.0, 0.0, 1.0), v(0.0, 0.0, 2.0)]);
    for phase in 0..3usize {
        let mut out = Vec::new();
        mine_hits(&mines, phase, origin, v(0.0, 30.0, 0.0), 5.0, &column(FOE), &mut out);
        assert_eq!(out, vec![phase as u32], "phase {phase} checks mine {phase} alone");
    }
}
