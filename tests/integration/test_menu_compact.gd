extends GutTest
## The start and pause menus' boxes fit what they show (M7-T31): the options box is as tall as its title and buttons plus its
## padding, not the window, and Settings keeps the full layout.

const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")
## What the box may keep beyond its content: the panel's padding and the gap above the last line.
const SLACK: float = 40.0

var game: RecordingGame


func before_each() -> void:
	get_tree().paused = false
	game = RecordingGame.new()
	autofree(game)


func _front_end() -> FrontEnd:
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = game
	front.mission_entries = func() -> Array[Dictionary]: return []
	front.quit_game = func() -> void: pass
	add_child_autofree(front)
	front.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	front.size = Vector2(1920.0, 1080.0)  # the headless window is tiny; the layout is judged at the game's size
	await wait_process_frames(3)
	return front


func _pad(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await wait_process_frames(2)


func _box(frame: MenuFrame) -> Control:
	return frame.get_node("%OptionsPanel") as Control


## The bottom of the page's last option, in the box's own coordinates.
func _last_option_bottom(frame: MenuFrame) -> float:
	var page: MenuScreen = frame.current_page()
	var last: Control = page.get_child(page.get_child_count() - 1) as Control
	return last.global_position.y + last.size.y - _box(frame).global_position.y


func test_the_start_menu_box_is_as_tall_as_its_content() -> void:
	var front: FrontEnd = await _front_end()
	var frame: MenuFrame = front.frame()
	var box: Control = _box(frame)
	assert_almost_eq(box.size.y, box.get_combined_minimum_size().y, 1.0, "the box is its content's height")
	assert_lt(box.size.y, frame.size.y * 0.5, "not the window's")
	assert_lt(box.size.y - _last_option_bottom(frame), SLACK, "no empty space under the last button")
	assert_lt(box.size.x, frame.size.x * 0.4, "and not the window's width either")


func test_new_game_and_free_flight_fit_their_content() -> void:
	var front: FrontEnd = await _front_end()
	await _pad(&"ui_accept")
	assert_eq(front.frame().current_page().title, "New game")
	var box: Control = _box(front.frame())
	assert_lt(box.size.y, front.frame().size.y * 0.7)
	assert_almost_eq(box.size.y, box.get_combined_minimum_size().y, 1.0)
	await _pad(&"ui_cancel")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(front.frame().current_page().title, "Free flight")
	assert_almost_eq(box.size.y, box.get_combined_minimum_size().y, 1.0)
	assert_lt(box.size.y, front.frame().size.y * 0.5)


func test_settings_keeps_the_full_layout() -> void:
	var front: FrontEnd = await _front_end()
	await _pad(&"ui_down")
	await _pad(&"ui_down")  # the greyed Load game is skipped: Free flight, then Settings
	await _pad(&"ui_accept")
	assert_eq(front.frame().current_page().title, "Settings")
	assert_false(front.frame().current_page().compact)
	assert_gt(_box(front.frame()).size.y, front.frame().size.y * 0.4, "the box still fills the column")
	assert_true(front.frame().objectives_panel().is_visible_in_tree())
	assert_true(front.frame().pad_diagram().is_visible_in_tree())


func test_going_back_to_a_compact_page_shrinks_the_box_again() -> void:
	var front: FrontEnd = await _front_end()
	var start_height: float = _box(front.frame()).size.y
	await _pad(&"ui_down")
	await _pad(&"ui_down")  # the greyed Load game is skipped: Free flight, then Settings
	await _pad(&"ui_accept")  # Settings: the big layout
	await _pad(&"ui_cancel")
	assert_almost_eq(_box(front.frame()).size.y, start_height, 1.0)


# --- The pause list's pad box is docked to the lower left corner ------------------------------------------------------

const FrameScene: PackedScene = preload("res://src/frontend/menu_frame.tscn")
## The window sizes the pause list is judged at: 16:9, 16:10, 4K, and two narrow ones that squeeze the pad box.
const WINDOWS: Array[Vector2] = [Vector2(1920, 1080), Vector2(1920, 1200), Vector2(3840, 2160), Vector2(1100, 700), Vector2(800, 600)]
const MARGIN_LEFT: float = 48.0
const MARGIN_TOP: float = 40.0
const MARGIN_BOTTOM: float = 40.0
const MARGIN_RIGHT: float = 48.0


# A frame at `window` size showing a compact pause-like list with the pad and the objectives.
func _pause_frame(window: Vector2) -> MenuFrame:
	var frame: MenuFrame = FrameScene.instantiate() as MenuFrame
	frame.objectives_source = func() -> Array[Dictionary]:
		return [{"id": &"a", "text": "Escort the freighter to NAV BETA", "primary": true, "state": &"active"}]
	add_child_autofree(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	frame.size = window
	var page := ChoiceListScreen.new()
	page.setup("PAUSED", PauseMenu.ENTRIES)
	page.compact = true
	frame.set_root(page)
	await wait_process_frames(4)
	return frame


func _rect(node: Control) -> Rect2:
	return Rect2(node.global_position, node.size)


func test_the_pad_box_sits_at_the_lower_left_corner_at_every_window_size() -> void:
	for window: Vector2 in WINDOWS:
		var frame: MenuFrame = await _pause_frame(window)
		var pad: Rect2 = _rect(frame.get_node("%PadPanel") as Control)
		var options: Rect2 = _rect(_box(frame))
		assert_almost_eq(pad.position.x, MARGIN_LEFT, 1.0, "pad box on the left margin at %s" % window)
		assert_almost_eq(pad.end.y, window.y - MARGIN_BOTTOM, 1.0, "pad box on the bottom margin at %s" % window)
		assert_almost_eq(options.position, Vector2(MARGIN_LEFT, MARGIN_TOP), Vector2.ONE, "options box top left at %s" % window)
		assert_false(pad.intersects(options), "the pad box never overlaps the options box at %s" % window)
		assert_lte(options.end.y, pad.position.y, "the pad box is under the options box at %s" % window)


func test_the_pad_box_shrinks_in_a_small_window_and_keeps_its_size_in_a_big_one() -> void:
	var big: MenuFrame = await _pause_frame(Vector2(1920, 1080))
	assert_almost_eq(big.pad_diagram().size.x, PadDiagram.DESIGN.x, 1.0, "the drawn size where there is room")
	var small: MenuFrame = await _pause_frame(Vector2(800, 600))
	assert_lt(small.pad_diagram().size.x, PadDiagram.DESIGN.x, "squeezed in a small window")
	assert_gte(small.pad_diagram().size.x, MenuFrame.COMPACT_PAD_MIN_WIDTH - 1.0)


func test_the_objectives_box_stays_beside_the_left_column_inside_the_window() -> void:
	for window: Vector2 in WINDOWS:
		var frame: MenuFrame = await _pause_frame(window)
		var right: Rect2 = _rect(frame.objectives_panel().get_parent() as Control)
		var pad: Rect2 = _rect(frame.get_node("%PadPanel") as Control)
		var options: Rect2 = _rect(_box(frame))
		assert_true(frame.objectives_panel().is_visible_in_tree())
		assert_gte(right.position.x, maxf(pad.end.x, options.end.x), "no overlap with the left column at %s" % window)
		assert_lte(right.end.x, window.x, "inside the window at %s" % window)
		assert_almost_eq(right.position.y, MARGIN_TOP, 1.0, "top aligned at %s" % window)
		if window.x >= 1920.0:
			assert_almost_eq(right.size.x, MenuFrame.COMPACT_RIGHT_WIDTH, 1.0, "the pause objectives box keeps its width at %s" % window)


# --- A page's description sits in a box of its own beside the list ----------------------------------------------------


# A frame at `window` size on a compact page without the pad whose entries carry these description lines.
func _described_frame(window: Vector2, descriptions: Array[String]) -> MenuFrame:
	var frame: MenuFrame = FrameScene.instantiate() as MenuFrame
	add_child_autofree(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	frame.size = window
	var entries: Array[Dictionary] = []
	for i: int in descriptions.size():
		entries.append({"id": StringName("e%d" % i), "text": "Entry %d" % i,
				"info": ObjectivesModel.briefing("Entry %d" % i, descriptions[i])})
	var page := ChoiceListScreen.new()
	page.setup("New game", entries)
	page.compact = true
	page.wide_right = true
	page.show_pad = false
	frame.set_root(page)
	await wait_process_frames(5)
	return frame


func _description_box(frame: MenuFrame) -> Control:
	return frame.objectives_panel().get_parent() as Control


func _long_text() -> String:
	var paragraphs: Array[String] = []
	for i: int in 40:
		paragraphs.append("Paragraph %d: a long briefing line that wraps in the narrow box and keeps going for a while." % i)
	return "\n".join(paragraphs)


func test_a_short_description_box_is_exactly_as_tall_as_its_text() -> void:
	var frame: MenuFrame = await _described_frame(Vector2(1920, 1080), ["Escort the freighter.\nHold the line."])
	var box: Rect2 = _rect(_description_box(frame))
	var panel: MenuFrame = frame
	assert_true(panel.objectives_panel().is_visible_in_tree())
	assert_almost_eq(box.size.y, _description_box(frame).get_combined_minimum_size().y, 1.0, "the box is its content's height")
	var scroll: ScrollContainer = frame.objectives_panel().scroll_container()
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "nothing to scroll")
	assert_almost_eq(scroll.size.y, frame.objectives_panel().content_height(), 1.0, "no empty space under the last line")
	assert_almost_eq(box.position.y, MARGIN_TOP, 1.0, "top aligned with the options box")
	assert_lt(box.size.y, 300.0)


func test_a_long_description_stops_at_the_window_and_scrolls() -> void:
	var window := Vector2(1920, 1080)
	var frame: MenuFrame = await _described_frame(window, [_long_text()])
	var box: Rect2 = _rect(_description_box(frame))
	var scroll: ScrollContainer = frame.objectives_panel().scroll_container()
	assert_almost_eq(box.end.y, window.y - MARGIN_BOTTOM, 2.0, "the box takes the height the window allows")
	assert_almost_eq(box.position.y, MARGIN_TOP, 1.0)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	var content: float = frame.objectives_panel().content_height()
	assert_gt(content, scroll.size.y, "the text is longer than the box")
	assert_gte(scroll.get_v_scroll_bar().max_value, content - 1.0, "every line can be scrolled to, none is clipped")


func test_the_description_follows_the_focus_and_the_box_refits() -> void:
	var frame: MenuFrame = await _described_frame(Vector2(1920, 1080), ["Short.", _long_text()])
	var short_h: float = _description_box(frame).size.y
	var page: ChoiceListScreen = frame.current_page() as ChoiceListScreen
	page.button_of(&"e1").grab_focus()
	await wait_process_frames(4)
	assert_gt(_description_box(frame).size.y, short_h, "the long text takes more room")
	page.button_of(&"e0").grab_focus()
	await wait_process_frames(4)
	assert_almost_eq(_description_box(frame).size.y, short_h, 1.0, "and the box shrinks back for the short one")
	assert_eq(frame.objectives_panel().scroll_container().vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)


func test_the_description_box_never_overlaps_the_options_or_leaves_the_window() -> void:
	for window: Vector2 in WINDOWS:
		for text: String in ["Short text.\nTwo lines.", _long_text()]:
			var frame: MenuFrame = await _described_frame(window, [text])
			var box: Rect2 = _rect(_description_box(frame))
			var options: Rect2 = _rect(_box(frame))
			assert_false(box.intersects(options), "no overlap at %s" % window)
			assert_gte(box.position.x, options.end.x, "right of the options box at %s" % window)
			assert_almost_eq(box.position.x, options.end.x + MenuFrame.COLUMN_GAP, 1.0, "the usual gap at %s" % window)
			assert_almost_eq(box.size.x, window.x - options.end.x - MenuFrame.COLUMN_GAP - MARGIN_RIGHT, 1.0,
					"the box takes the width that is left, to the right margin, at %s" % window)
			assert_lte(box.end.x, window.x, "inside the window at %s" % window)
			assert_lte(box.end.y, window.y - MARGIN_BOTTOM + 1.0, "inside the window at %s" % window)
			assert_almost_eq(box.position.y, MARGIN_TOP, 1.0, "top aligned at %s" % window)
