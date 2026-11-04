extends GutTest
## MenuFrame (architecture §18, D57, Q15): the three panels read their providers, the stack of pages goes forward and back,
## and a rebind reaches the diagram at once. The pause menu and the front end are tested through it in their own files.

const FrameScene: PackedScene = preload("res://src/frontend/menu_frame.tscn")

var profile: ControlProfile
var objectives: Array[Dictionary] = []
var request: Dictionary = {}
var sounds: Array[StringName] = []


func before_each() -> void:
	profile = ControlProfile.new()
	profile.bindings[&"fire"] = ["pad:button:0", "key:Space"]
	profile.bindings[&"toggle_camera"] = ["pad:button:3"]
	objectives = []
	request = {}
	sounds = []


func after_each() -> void:
	ControlProfiles.use(ControlProfile.DEFAULT_NAME)  # a test that rebinds leaves the project's map as it found it


func _frame() -> MenuFrame:
	var frame: MenuFrame = FrameScene.instantiate() as MenuFrame
	frame.bindings_source = func() -> ControlProfile: return profile
	frame.objectives_source = func() -> Array[Dictionary]: return objectives
	frame.request_source = func() -> Dictionary: return request
	add_child_autofree(frame)
	return frame


func _page(title: String, options: Array[String]) -> ChoiceListScreen:
	var page := ChoiceListScreen.new()
	var entries: Array[Dictionary] = []
	for text: String in options:
		entries.append({"id": StringName(text.to_lower()), "text": text})
	page.setup(title, entries)
	return page


func test_the_diagram_reads_the_bindings_source() -> void:
	var frame: MenuFrame = _frame()
	assert_eq(frame.pad_diagram().legend.label_for(&"a"), "Fire")
	assert_eq(frame.pad_diagram().legend.label_for(&"y"), "Camera")


func test_the_legend_follows_a_rebind() -> void:
	var frame: MenuFrame = _frame()
	profile.bindings[&"fire"] = ["pad:button:2", "key:Space"]  # fire moves from A to X
	frame.refresh()
	assert_eq(frame.pad_diagram().legend.label_for(&"a"), "", "A no longer fires")
	assert_eq(frame.pad_diagram().legend.label_for(&"x"), "Fire")
	assert_has(frame.pad_diagram().rows_text(), "X  Fire")


func test_the_legend_follows_the_live_input_map_without_a_source() -> void:
	var frame: MenuFrame = FrameScene.instantiate() as MenuFrame
	add_child_autofree(frame)
	assert_eq(frame.pad_diagram().legend.label_for(&"a"), "Fire", "the project's own map")
	assert_true(ControlProfiles.bind(&"fire", "pad:button:2")["ok"])
	assert_string_contains(frame.pad_diagram().legend.label_for(&"x"), "Fire")
	assert_true(ControlProfiles.use(ControlProfile.DEFAULT_NAME)["ok"])  # and back
	assert_eq(frame.pad_diagram().legend.label_for(&"a"), "Fire")
	assert_eq(frame.pad_diagram().legend.label_for(&"x"), "Auto-track")


func test_highlighting_an_action_lights_its_buttons() -> void:
	var frame: MenuFrame = _frame()
	frame.highlight_actions([&"fire"] as Array[StringName])
	assert_eq(frame.pad_diagram().highlighted(), [&"a"] as Array[StringName])
	frame.highlight_actions([] as Array[StringName])
	assert_eq(frame.pad_diagram().highlighted().size(), 0)


func test_the_right_panel_prefers_the_objectives_then_the_run_then_nothing() -> void:
	var frame: MenuFrame = _frame()
	frame.set_root(_page("Root", ["One"]))
	assert_eq(frame.right_content()["lines"].size(), 0, "nothing to say")
	request = GameFlow.make_request(&"free_flight", &"free_flight", true)
	assert_eq(frame.right_content()["lines"][0]["text"], "Free flight")
	objectives = [{"id": &"a", "text": "Do it", "primary": true, "state": &"active"}]
	assert_eq(frame.right_content()["lines"][0]["text"], "Do it", "objectives win over the run")


func test_pages_stack_and_go_back() -> void:
	var frame: MenuFrame = _frame()
	var closed: Array[bool] = []
	frame.closed.connect(func() -> void: closed.append(true))
	var root: ChoiceListScreen = _page("Root", ["One", "Two"])
	frame.set_root(root)
	frame.push_screen(_page("Child", ["Three"]))
	assert_eq(frame.depth(), 2)
	assert_eq(frame.current_page().title, "Child")
	assert_false(root.visible, "the page below is hidden")
	assert_true(frame.go_back())
	assert_eq(frame.depth(), 1)
	assert_true(root.visible)
	assert_false(frame.go_back(), "the root cannot be left")
	assert_eq(closed.size(), 1, "asking to leave the root closes the frame")
	assert_eq(frame.depth(), 1)


func test_a_page_that_asks_to_go_back_goes_back() -> void:
	var frame: MenuFrame = _frame()
	frame.set_root(_page("Root", ["One"]))
	var child: ChoiceListScreen = _page("Child", ["Two"])
	frame.push_screen(child)
	child.back_requested.emit()
	assert_eq(frame.current_page().title, "Root")


func test_leaving_the_root_closes_the_frame_without_a_sound() -> void:
	var frame: MenuFrame = _frame()
	frame.set_root(_page("Root", ["One"]))
	var closed: Array[bool] = []
	frame.closed.connect(func() -> void: closed.append(true))
	assert_false(frame.go_back())
	assert_eq(closed.size(), 1)


func test_clear_drops_every_page() -> void:
	var frame: MenuFrame = _frame()
	frame.set_root(_page("A", ["One"]))
	frame.push_screen(_page("B", ["Two"]))
	frame.clear()
	assert_eq(frame.depth(), 0)
	assert_null(frame.current_page())
	assert_eq(frame.right_content()["lines"].size(), 0, "a frame with no page still answers")


func test_the_page_title_heads_the_options() -> void:
	var frame: MenuFrame = _frame()
	frame.set_root(_page("PAUSED", ["Resume"]))
	assert_eq((frame.get_node(^"%Title") as Label).text, "PAUSED")


func test_set_root_replaces_every_page() -> void:
	var frame: MenuFrame = _frame()
	frame.set_root(_page("A", ["One"]))
	frame.push_screen(_page("B", ["Two"]))
	frame.set_root(_page("C", ["Three"]))
	assert_eq(frame.depth(), 1)
	assert_eq(frame.current_page().title, "C")
