// The cell grid's unit tests (M5-T33): a look bounded by the held cells finds what a walk over every hull finds.
use super::*;

// A small seeded generator: the tests need spread, not quality.
fn next(state: &mut u64) -> f32 {
    *state = state
        .wrapping_mul(6_364_136_223_846_793_005)
        .wrapping_add(1_442_695_040_888_963_407);
    ((*state >> 40) as f32) / (1u64 << 24) as f32
}

#[test]
fn a_look_bounded_by_the_held_cells_finds_every_pair() {
    let mut seed = 7u64;
    let mut hulls = Vec::new();
    let mut hull_reach = Vec::new();
    for _ in 0..400 {
        hulls.push(Vector3::new(
            next(&mut seed) * 3000.0 - 500.0,
            next(&mut seed) * 800.0,
            next(&mut seed) * 3000.0 - 4000.0,
        ));
        hull_reach.push(f64::from(2.0 + next(&mut seed) * 300.0));
    }
    // Projectiles inside the slab, at its edges and far outside it.
    let mut bolts = Vec::new();
    let mut bolt_reach = Vec::new();
    for _ in 0..600 {
        bolts.push(Vector3::new(
            next(&mut seed) * 9000.0 - 3500.0,
            next(&mut seed) * 4000.0 - 1600.0,
            next(&mut seed) * 9000.0 - 7000.0,
        ));
        bolt_reach.push(f64::from(1.0 + next(&mut seed) * 40.0));
    }
    let mut grid = CellGrid::default();
    grid.place(&hulls, &hull_reach);
    let mut candidates = Vec::new();
    let mut plain_visited = 0;
    let plain = sweep(
        &grid,
        &bolts,
        &bolt_reach,
        &hulls,
        &hull_reach,
        &mut candidates,
        &mut plain_visited,
    );
    // A kept grid marks its cells: the same pairs and the same work count.
    grid.mark_cells();
    let mut visited = 0;
    let found = sweep(
        &grid,
        &bolts,
        &bolt_reach,
        &hulls,
        &hull_reach,
        &mut candidates,
        &mut visited,
    );
    let mut every = Vec::new();
    for (i, &at) in bolts.iter().enumerate() {
        for (j, &hull) in hulls.iter().enumerate() {
            let reach = bolt_reach[i] + hull_reach[j];
            if f64::from(dist_sq(at, hull)) <= reach * reach {
                every.push((i * hulls.len() + j) as i64);
            }
        }
    }
    assert!(!every.is_empty());
    assert_eq!(found, every);
    assert_eq!(plain, every);
    assert_eq!(visited, plain_visited);
    assert!(visited < (bolts.len() * hulls.len()) as i64 / 4);
}

#[test]
fn a_look_far_from_every_hull_tests_none() {
    // A row of small hulls and a row of large ones, enough a level that a look walks cells, not hulls.
    let mut hulls = Vec::new();
    let mut hull_reach = Vec::new();
    for k in 0..60 {
        hulls.push(Vector3::new(k as f32 * 70.0, 0.0, 0.0));
        hull_reach.push(20.0);
        hulls.push(Vector3::new(k as f32 * 70.0, 600.0, 0.0));
        hull_reach.push(100.0);
    }
    let mut grid = CellGrid::default();
    grid.place(&hulls, &hull_reach);
    let mut candidates = vec![9];
    let unlisted = grid.look(Vector3::new(30_000.0, 0.0, 0.0), 25.0, &mut candidates);
    assert!(candidates.is_empty());
    assert_eq!(
        unlisted, 0,
        "a level that walks its cells stands for no hull it does not list"
    );
    grid.look(Vector3::new(40.0, 0.0, 0.0), 25.0, &mut candidates);
    assert!(candidates.contains(&0) && candidates.contains(&2));
    assert!(candidates.len() < 12);
}

#[test]
fn a_sparse_level_far_away_is_counted_but_not_listed() {
    // Two hulls a level: too few for the cells, so a look takes the whole level, and far from it only counts it.
    let hulls = vec![Vector3::new(0.0, 0.0, 0.0), Vector3::new(500.0, 0.0, 0.0)];
    let hull_reach = vec![20.0, 150.0];
    let mut grid = CellGrid::default();
    grid.place(&hulls, &hull_reach);
    let mut candidates = vec![9];
    let far = grid.look(Vector3::new(30_000.0, 0.0, 0.0), 25.0, &mut candidates);
    assert!(candidates.is_empty());
    assert_eq!(far, 2);
    let near = grid.look(Vector3::new(40.0, 0.0, 0.0), 25.0, &mut candidates);
    assert_eq!(
        (candidates.clone(), near),
        (vec![0], 1),
        "each level by its own box"
    );
    // Just outside the large hull's sphere: still listed, the sphere test decides.
    let edge = grid.look(Vector3::new(675.5, 0.0, 0.0), 25.0, &mut candidates);
    assert_eq!((candidates.clone(), edge), (vec![1], 1));
    let mut visited = 0;
    let found = sweep(
        &grid,
        &[
            Vector3::new(30_000.0, 0.0, 0.0),
            Vector3::new(660.0, 0.0, 0.0),
        ],
        &[25.0, 25.0],
        &hulls,
        &hull_reach,
        &mut candidates,
        &mut visited,
    );
    assert_eq!(found, vec![3]);
    assert_eq!(
        visited, 4,
        "the work count is what a walk over both levels would be"
    );
}

#[test]
fn a_kept_sparse_level_lists_only_the_hulls_near_along_x() {
    // Twenty small hulls in a row along x and a look as wide as a capital: too many cells for the level, so the look
    // takes the level, but lists only the hulls its sphere could reach along x.
    let hulls: Vec<Vector3> = (0..20)
        .map(|k| Vector3::new(k as f32 * 1000.0, 0.0, 0.0))
        .collect();
    let hull_reach = vec![25.0; 20];
    let bolts = [
        Vector3::new(5020.0, 300.0, 0.0),
        Vector3::new(5020.0, 630.0, 0.0),
    ];
    let bolt_reach = [600.0, 600.0];
    let mut grid = CellGrid::default();
    grid.place(&hulls, &hull_reach);
    let mut candidates = Vec::new();
    let mut plain_visited = 0;
    let plain = sweep(
        &grid,
        &bolts,
        &bolt_reach,
        &hulls,
        &hull_reach,
        &mut candidates,
        &mut plain_visited,
    );
    assert_eq!(plain, vec![5]);
    assert_eq!(
        plain_visited, 40,
        "unmarked, the look lists the whole level"
    );
    grid.mark_cells();
    let unlisted = grid.look(bolts[0], 600.0, &mut candidates);
    assert_eq!((candidates.clone(), unlisted), (vec![5], 19));
    let mut visited = 0;
    let kept = sweep(
        &grid,
        &bolts,
        &bolt_reach,
        &hulls,
        &hull_reach,
        &mut candidates,
        &mut visited,
    );
    assert_eq!((kept, visited), (plain, plain_visited));
}
