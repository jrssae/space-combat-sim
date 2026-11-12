// The row tables' unit tests (M5-T35), outside the engine-free guard (test builds only): the name ids, the id lookup built
// round a sorted block, the block append, the copy into held columns and the tier's column-wise append.
use godot::builtin::{Basis, Vector3};

use super::*;
use crate::tier::TierRows;

// Rows with the given marker ids, every other column filled from the row's place.
fn rows_with(ids: &[i64]) -> Rows {
    let mut rows = Rows::default();
    for (at, &id) in ids.iter().enumerate() {
        let f = at as f32;
        rows.body_ids.push(id + 1000);
        rows.ids.push(id);
        rows.faction_ix.push(at as u32 % 3);
        rows.positions.push(Vector3::new(f, 2.0 * f, -f));
        rows.velocities.push(Vector3::new(-f, 0.5, f));
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::new(0.0, f, 0.0));
        rows.radii.push(1.0 + f64::from(f));
        rows.kinds.push(at as u8 % 5);
        rows.flags.push(at as u32);
        rows.hull_ids.push(id + 2000);
        rows.handles.push(id + 3000);
        rows.rigid.push(at % 2 == 0);
        rows.is_static.push(at % 3 == 0);
        rows.is_mine.push(at % 4 == 0);
        rows.hull_fraction.push(0.5);
        rows.target_ids.push(-1);
        rows.reach.push(f64::from(f) * 10.0);
        rows.name_ids.push(at as u32);
        rows.roles.push(at as u8 % 2);
    }
    rows.node_count = ids.len();
    rows
}

// Every column of `rows` as one string, so two tables compare in one assert.
fn dump(rows: &Rows) -> String {
    format!(
        "{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{:?}{}/{}",
        rows.body_ids,
        rows.ids,
        rows.faction_ix,
        rows.positions,
        rows.velocities,
        rows.bases,
        rows.angular,
        rows.radii,
        rows.kinds,
        rows.flags,
        rows.hull_ids,
        rows.handles,
        rows.rigid,
        rows.is_static,
        rows.is_mine,
        rows.hull_fraction,
        rows.target_ids,
        rows.reach,
        rows.name_ids,
        rows.roles,
        rows.id_rows,
        rows.node_count,
        rows.tier_rows
    )
}

#[test]
fn a_name_gets_one_id_and_the_empty_name_none() {
    let mut names = NameTable::default();
    assert_eq!(names.id_of("raider 1"), 0, "a name no row was given has no id");
    assert_eq!(names.intern(""), 0, "the empty name is id 0");
    let first = names.intern("raider 1");
    let second = names.intern("raider 2");
    assert_ne!(first, 0);
    assert_ne!(first, second);
    assert_eq!(names.intern("raider 1"), first, "the same name, the same id");
    assert_eq!(names.id_of("raider 2"), second);
    assert_eq!(names.id_of("Raider 2"), 0, "the table holds lowered names; the caller lowers");
    assert_eq!(names.id_of(""), 0);
    assert_eq!(names.len(), 2);
    assert!(!names.is_empty());
}

#[test]
fn rows_find_a_name_through_their_table_and_nothing_without_one() {
    let mut rows = rows_with(&[5, 6]);
    assert_eq!(rows.name_id("raider 1"), 0, "rows with no table match no name");
    let mut names = NameTable::default();
    let id = names.intern("raider 1");
    rows.names = Some(Arc::new(names));
    assert_eq!(rows.name_id("raider 1"), id);
    assert_eq!(rows.name_id("nobody"), 0);
    rows.clear();
    assert_eq!(rows.name_id("raider 1"), id, "clearing the rows keeps their table");
}

#[test]
fn the_id_lookup_round_a_sorted_block_is_the_plain_one() {
    // Rows before the block, the block (ids in no order, one shared with a row outside), rows after it.
    let block_ids: [i64; 6] = [40, -7, 12, 99, 3, 12];
    let cases: [(&[i64], &[i64]); 4] = [
        (&[50, 2, 77, 12], &[8, 1000, -3]),
        (&[], &[8, 1]),
        (&[9, 4], &[]),
        (&[], &[]),
    ];
    let mut scratch = Vec::new();
    for (before, after) in cases {
        let mut ids: Vec<i64> = before.to_vec();
        ids.extend_from_slice(&block_ids);
        ids.extend_from_slice(after);
        let mut plain = rows_with(&ids);
        plain.index_ids();
        let mut sorted: Vec<(i64, u32)> = block_ids
            .iter()
            .enumerate()
            .map(|(at, &id)| (id, at as u32))
            .collect();
        sorted.sort_unstable();
        let mut merged = rows_with(&ids);
        merged.index_ids_around(before.len(), &sorted, &mut scratch);
        assert_eq!(merged.id_rows, plain.id_rows, "before {before:?}, after {after:?}");
        for &id in &ids {
            assert_eq!(merged.ids[merged.row_of_id(id) as usize], id);
        }
    }
    // No block, or a block that does not fit the rows: the plain lookup.
    let mut rows = rows_with(&[3, 1, 2]);
    rows.index_ids_around(1, &[], &mut scratch);
    assert_eq!(rows.id_rows, vec![(1, 1), (2, 2), (3, 0)]);
    rows.index_ids_around(2, &[(7, 0), (8, 1)], &mut scratch);
    assert_eq!(rows.id_rows, vec![(1, 1), (2, 2), (3, 0)]);
}

#[test]
fn a_block_appended_whole_is_its_rows_pushed_one_by_one() {
    let head = rows_with(&[1, 2]);
    let block = rows_with(&[10, 11, 12]);
    let mut whole = head.clone();
    whole.extend_from(&block);
    let mut all = rows_with(&[1, 2, 10, 11, 12]);
    // `rows_with` fills from the row's place, so the block's rows are placed as they were in the block.
    for (at, from) in (2..5).zip(0..3) {
        all.body_ids[at] = block.body_ids[from];
        all.faction_ix[at] = block.faction_ix[from];
        all.positions[at] = block.positions[from];
        all.velocities[at] = block.velocities[from];
        all.angular[at] = block.angular[from];
        all.radii[at] = block.radii[from];
        all.kinds[at] = block.kinds[from];
        all.flags[at] = block.flags[from];
        all.rigid[at] = block.rigid[from];
        all.is_static[at] = block.is_static[from];
        all.is_mine[at] = block.is_mine[from];
        all.reach[at] = block.reach[from];
        all.name_ids[at] = block.name_ids[from];
        all.roles[at] = block.roles[from];
    }
    all.node_count = head.node_count;
    assert_eq!(dump(&whole), dump(&all));
}

#[test]
fn a_copy_into_held_columns_is_the_source_and_keeps_its_memory() {
    let mut source = rows_with(&[4, 9, 2, 7]);
    source.index_ids();
    source.tier_rows = 1;
    source.names = Some(Arc::new(NameTable::default()));
    let mut held = rows_with(&[1, 2, 3, 4, 5, 6, 7, 8]);
    held.index_ids();
    let (at, capacity) = (held.positions.as_ptr(), held.positions.capacity());
    held.clone_from(&source);
    assert_eq!(dump(&held), dump(&source));
    assert!(Arc::ptr_eq(held.names.as_ref().unwrap(), source.names.as_ref().unwrap()), "the names are shared, not copied");
    assert_eq!((held.positions.as_ptr(), held.positions.capacity()), (at, capacity), "no new column was allocated");
    assert_eq!(dump(&source.clone()), dump(&source));

    let mut bolts = Bolts::default();
    for i in 0..3 {
        bolts.insert_owned(-1 - i, Vector3::ZERO, Vector3::ONE, 0, 5, 7, 0.1, 2.0, [1.0; 4], 0, 9.0, i);
    }
    let mut held = Bolts::default();
    for i in 0..9 {
        held.insert_owned(-100 - i, Vector3::ONE, Vector3::ZERO, 1, 6, 7, 0.2, 3.0, [0.5; 4], 1, 4.0, i);
    }
    held.clone_from(&bolts);
    assert_eq!(held.ids, bolts.ids);
    assert_eq!(held.owned, 3);
    assert_eq!(held.draw_slots, bolts.draw_slots);
    assert_eq!(held.slot_count(0), 3);
    assert_eq!(held.slot_count(1), 0, "the copy's old slots are gone");
    assert_eq!(held.insert_owned(-9, Vector3::ZERO, Vector3::ZERO, 0, 5, 7, 0.1, 2.0, [1.0; 4], 0, 9.0, 4), 3);
    assert_eq!(held.draw_slots[3], 3, "the copy hands out slots as the source would");
}

#[test]
fn the_tier_appends_its_rows_column_by_column_as_it_pushes_them() {
    let mut tier = TierRows::default();
    for i in 0..5_i64 {
        let f = i as f32;
        tier.add(
            (i % 2) as u8,
            100 + i,
            200 + i,
            -1 - i,
            0,
            Vector3::new(f, 1.0, 2.0),
            Vector3::new(0.0, f, 0.0),
            Basis::IDENTITY,
            Vector3::new(0.1, 0.2, f),
            i,
        );
        let at = i as usize;
        tier.marker_ids[at] = 300 + i;
        tier.faction_ix[at] = i as u32 % 3;
        tier.radii[at] = 5.0 + f64::from(f);
        tier.reach[at] = 100.0 * f64::from(f);
        tier.hull_fraction[at] = 0.25 * f64::from(f);
        tier.name_ids[at] = i as u32;
        tier.roles[at] = (i % 2) as u8;
        tier.hulk[at] = i == 3;
    }
    let mut pushed = rows_with(&[1, 2]);
    for i in 0..tier.len() {
        tier.push_row(i, &mut pushed);
    }
    pushed.tier_rows = tier.len();
    let mut appended = rows_with(&[1, 2]);
    tier.append_to(&mut appended);
    assert_eq!(dump(&appended), dump(&pushed));
    assert_eq!(appended.flags[5], FLAG_TIER | FLAG_HULL | FLAG_HULK, "a hulk stays a hulk");
    assert!(!appended.rigid[5]);
}

// --- the velocity rebase (M6-T05) -----------------------------------------------------------------------------------

#[test]
fn a_boost_takes_dv_off_every_row_with_a_body_and_leaves_a_static_row_alone() {
    let mut rows = rows_with(&[7, 8, 9]);
    rows.handles[1] = 0; // a rock: tied to the anchor, no velocity of its own
    let before = rows.velocities.clone();
    let positions = rows.positions.clone();
    let dv = Vector3::new(1500.0, -20.0, 800.0);
    rows.boost(dv);
    assert_eq!(rows.velocities[0], before[0] - dv);
    assert_eq!(rows.velocities[1], before[1]);
    assert_eq!(rows.velocities[2], before[2] - dv);
    assert_eq!(rows.positions, positions, "a boost moves nothing");
}

#[test]
fn a_boost_takes_dv_off_every_bolt_and_keeps_the_step_it_flew() {
    let mut bolts = Bolts::default();
    for i in 0..3_i64 {
        let f = i as f32;
        bolts.insert_owned(i, Vector3::new(f, 0.0, 0.0), Vector3::new(0.0, 0.0, -1500.0 - f), 0, 1, 0, 0.3, 10.0, [1.0; 4], 0, 9.0, 0);
    }
    bolts.last_steps[1] = Vector3::new(0.0, 0.0, -25.0);
    let dv = Vector3::new(0.0, 0.0, -2000.0);
    bolts.boost(dv);
    for i in 0..3 {
        assert_eq!(bolts.velocities[i], Vector3::new(0.0, 0.0, 500.0 - i as f32));
        assert_eq!(bolts.positions[i], Vector3::new(i as f32, 0.0, 0.0));
    }
    assert_eq!(bolts.last_steps[1], Vector3::new(0.0, 0.0, -25.0));
}

#[test]
fn a_boost_takes_dv_off_the_tier_rows_and_off_the_cruise_a_capital_holds() {
    use crate::tier::{KIND_CAPITAL, KIND_FIGHTER};
    let mut tier = TierRows::default();
    for (i, kind) in [KIND_FIGHTER, KIND_CAPITAL].into_iter().enumerate() {
        let id = i as i64;
        tier.add(kind, 100 + id, 200 + id, -1 - id, 0, Vector3::new(5.0, 6.0, 7.0), Vector3::new(40.0, 0.0, 0.0),
            Basis::IDENTITY, Vector3::ZERO, id);
    }
    tier.cruise[1] = Vector3::new(40.0, 0.0, 0.0);
    let dv = Vector3::new(2000.0, 0.0, -10.0);
    tier.boost(dv);
    assert_eq!(tier.velocities[0], Vector3::new(-1960.0, 0.0, 10.0));
    assert_eq!(tier.velocities[1], Vector3::new(-1960.0, 0.0, 10.0));
    assert_eq!(tier.cruise[0], Vector3::ZERO, "a fighter holds no cruise");
    assert_eq!(tier.cruise[1], Vector3::new(-1960.0, 0.0, 10.0), "the capital still cruises at 40 m/s against the anchor");
    assert_eq!(tier.positions[0], Vector3::new(5.0, 6.0, 7.0));
}
