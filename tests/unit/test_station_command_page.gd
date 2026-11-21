extends GutTest
## The comms menu's page of Babylon 5's commands (M8-T34), pure: six entries, Launch wing's ring of the four wings and All, the
## toggles' second lines saying what a pick does, and the payloads the director carries out.


func test_the_page_lists_the_six_commands_one_slice_each() -> void:
	var page: Array[Dictionary] = StationCommands.page(true, false, false)
	var labels: Array[String] = []
	for entry: Dictionary in page:
		labels.append(str(entry["label"]))
	assert_eq(labels, ["LAUNCH WING", "RECALL", "DEFENSE GRID", "FIRE SUPPORT", "SHELTER", "SITREP"] as Array[String])
	var menu := CommsMenu.new()
	menu.set_root_page("BABYLON 5", page)
	menu.open()
	assert_eq(menu.radial.slice_count(), 6)
	for i: int in range(1, page.size()):
		assert_true(StationCommands.is_payload(page[i]["payload"]), labels[i])


func test_launch_wing_opens_a_ring_of_the_four_wings_and_all() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("BABYLON 5", StationCommands.page(true, false, false))
	menu.open()
	menu.radial.set_highlight(0)
	assert_true(menu.select().is_empty(), "a ring, not a pick")
	assert_eq(menu.page_title(), "LAUNCH WING")
	assert_eq(menu.radial.slice_count(), 5, "Alpha, Beta, Delta, Zeta, All")
	menu.radial.set_highlight(4)
	var all: Dictionary = menu.select()
	assert_eq(all["payload"], "station:launch:all")
	assert_false(menu.is_open())


func test_the_toggles_say_what_a_pick_does() -> void:
	var off: Array[Dictionary] = StationCommands.page(true, false, false)
	var on: Array[Dictionary] = StationCommands.page(false, true, true)
	assert_eq(off[2]["sub"], "turn off")
	assert_eq(on[2]["sub"], "turn on")
	assert_eq(off[3]["sub"], "cover me")
	assert_eq(on[3]["sub"], "end")
	assert_eq(off[4]["sub"], "civilians")
	assert_eq(on[4]["sub"], "release civilians")


func test_payloads_and_toggle_words() -> void:
	assert_true(StationCommands.is_payload("station:grid"))
	assert_false(StationCommands.is_payload(AiContext.Order.FORM_ON_ME), "a wing order is not")
	assert_false(StationCommands.is_payload(CommsMenu.PAYLOAD_DOCK))
	assert_true(StationCommands._flip("on", true))
	assert_false(StationCommands._flip("off", false))
	assert_true(StationCommands._flip("", false), "no word flips it")
	assert_false(StationCommands._flip("", true))
