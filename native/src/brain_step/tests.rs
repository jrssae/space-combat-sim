// The tier events a parked driver is handed (M8-T17).
use super::*;

#[test]
fn a_tier_think_mirrors_a_route_it_flies() {
    assert_eq!(tier_events(0, 0, 7), EVENT_SETTLE, "follow path in control: the parked driver settles its mirror");
    assert_eq!(tier_events(0, 0, 3), 0, "attacking with nothing new to select: nothing");
    assert_eq!(tier_events(0, 0, 0), 0, "a ram in the tier is the tier's own: no settle");
}

#[test]
fn a_tier_think_selects_the_target_its_pilot_wants() {
    assert_eq!(tier_events(42, 0, 3), EVENT_SELECT);
    assert_eq!(tier_events(42, 42, 3), 0, "already selected");
    assert_eq!(tier_events(-1, 42, 3), EVENT_SELECT, "none wanted, one selected: drop it");
    assert_eq!(tier_events(42, 0, 7), EVENT_SELECT | EVENT_SETTLE, "both at once");
}
