class_name MenuFrame
extends Control
## The three-panel layout the pause menu, the front end and the settings and controls pages share (architecture §18, D57,
## Q15): the options at the top left, scrolling when long; below them the controller diagram with what each button does
## now; on the right the mission objectives (or the run, or a briefing).
##
## The frame holds a stack of `MenuScreen` pages and shows the top one. Its panels read small providers, so the frame needs
## nothing from a running mission: `bindings_source` for the diagram, `objectives_source` and `request_source` for the right
## panel. A page can put its own content on the right (`MenuScreen.info`), as the mission list does with a briefing.

const SettingsScript := preload("res://src/autoload/settings.gd")
const SOUND_BACK: StringName = &"ui_back"
## The options column's width when the right panel is hidden (the start screen), so a short list is not stretched across.
const SLIM_WIDTH: float = 680.0
## A compact page (M7-T31) sizes every box to what it shows. The options box is never narrower than this, so a page's text wraps
## at a readable width, and the right panel is this wide.
const COMPACT_WIDTH: float = 520.0
const COMPACT_RIGHT_WIDTH: float = 440.0
## What a compact page's options list leaves the rest of the window: the margins, the title and the box's padding.
const COMPACT_CHROME: float = 300.0
## The smallest the compact pad diagram shrinks to, the right panel's narrowest, and the sizes of what sits between the boxes:
## the gap between the columns, between the options and pad boxes, and a panel's padding (the theme's content margins).
const COMPACT_PAD_MIN_WIDTH: float = 240.0
const COMPACT_RIGHT_MIN_WIDTH: float = 160.0
const COLUMN_GAP: float = 24.0
const BOX_GAP: float = 16.0
const PANEL_PAD_X: float = 36.0
const PANEL_PAD_Y: float = 28.0

## The root page asked to go back: the pause menu resumes, the front end ignores it.
signal closed

## A Callable returning the `ControlProfile` the diagram shows. Unset: the profile in the InputMap right now, so a rebind
## shows at once.
var bindings_source: Callable = Callable()
## A Callable returning the running mission's objectives, `Array[Dictionary]` (`ObjectivesModel`). Unset: none.
var objectives_source: Callable = Callable()
## A Callable returning `Game`'s request, for the right panel when no objective shows. Unset: none.
var request_source: Callable = Callable()
## Plays the menu sounds (`play_ui`). Null: silent.
var audio: AudioDirector = null

var _pages: Array[MenuScreen] = []
var _lit_actions: Array[StringName] = []

@onready var _title: Label = %Title
@onready var _host: VBoxContainer = %Host
@onready var _message: Label = %Message
@onready var _pad: PadDiagram = %PadDiagram
@onready var _objectives: ObjectivesPanel = %Objectives
@onready var _margin: MarginContainer = $Margin
@onready var _left: Control = %Left
@onready var _options_panel: Control = %OptionsPanel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _pad_panel: Control = %PadPanel
@onready var _right_panel: Control = %RightPanel
@onready var _detail: Label = %Detail


func _ready() -> void:
	var profiles: Node = get_node_or_null(^"/root/ControlProfiles")
	if profiles != null:
		profiles.applied.connect(_on_profile_applied)
	resized.connect(_apply_layout)
	refresh()


## Replaces every page with `page`, the first of the stack.
func set_root(page: MenuScreen) -> void:
	clear()
	_show_page(page)


## Drops every page (the pause menu does when it closes, so nothing stays focusable behind the game).
func clear() -> void:
	for old: MenuScreen in _pages:
		_drop(old)
	_pages.clear()
	_title.text = ""
	_message.text = ""
	_lit_actions.clear()


## Puts `page` on top of the current one.
func push_screen(page: MenuScreen) -> void:
	if not _pages.is_empty():
		_pages.back().visible = false
	_show_page(page)


## Leaves the top page for the one under it, with the back sound. Returns false when the top page is the root: then
## `closed` is emitted instead, silently (the host decides whether leaving is worth a sound). A page that steps back inside
## itself (`MenuScreen.back_step`) keeps the frame where it is.
func go_back() -> bool:
	if not _pages.is_empty() and _pages.back().back_step():
		return true
	if _pages.size() <= 1:
		closed.emit()
		return false
	_play(SOUND_BACK)
	_drop(_pages.pop_back())
	var below: MenuScreen = _pages.back()
	below.visible = true
	_title.text = below.title
	_lit_actions.clear()
	_apply_layout()
	below.restore_focus()
	refresh()
	return true


func current_page() -> MenuScreen:
	return _pages.back() if not _pages.is_empty() else null


func depth() -> int:
	return _pages.size()


## Says something under the options (a start that was refused); empty clears it.
func show_message(text: String) -> void:
	_message.text = text
	_sync_visibility()


func message() -> String:
	return _message.text


## Lights the pad parts of these game actions (the controls page: the action in focus).
func highlight_actions(actions: Array[StringName]) -> void:
	_lit_actions = actions.duplicate()
	refresh_legend()


## Redraws the diagram and the right panel from their sources.
func refresh() -> void:
	refresh_legend()
	refresh_panel()


func refresh_legend() -> void:
	if _pad == null:
		return
	var profile: ControlProfile = null
	if bindings_source.is_valid():
		profile = bindings_source.call() as ControlProfile
	if profile == null:
		profile = ControlProfile.from_input_map("active")
	var legend: PadLegend = PadLegend.from_profile(profile)
	_pad.set_legend(legend)
	var lit: Array[StringName] = []
	for action: StringName in _lit_actions:
		for widget: StringName in legend.widgets_for(action):
			if not lit.has(widget):
				lit.append(widget)
	_pad.set_highlight(lit)


func refresh_panel() -> void:
	if _objectives != null:
		_objectives.show_content(right_content())
	if _detail != null:
		_detail.text = detail_text()
	_sync_visibility()


## What the right panel should say: the page's own content, else the mission's objectives or the run, else nothing.
func right_content() -> Dictionary:
	var page: MenuScreen = current_page()
	var own: Dictionary = page.info() if page != null else {}
	if not own.is_empty():
		return own
	var objectives: Array[Dictionary] = []
	if objectives_source.is_valid():
		objectives.assign(objectives_source.call())
	var request: Dictionary = request_source.call() if request_source.is_valid() else {}
	if objectives.is_empty() and request.is_empty():
		return {"title": "", "lines": []}
	return ObjectivesModel.content(objectives, request)


## The page's own text, a line per paragraph: under the list while the right panel is hidden, else in the right panel.
func detail_text() -> String:
	var page: MenuScreen = current_page()
	if page == null:
		return ""
	var lines := PackedStringArray()
	for line: Dictionary in (page.info().get("lines", []) as Array):
		lines.append(String(line["text"]))
	return "\n".join(lines)


func pad_diagram() -> PadDiagram:
	return _pad


func objectives_panel() -> ObjectivesPanel:
	return _objectives


func _show_page(page: MenuScreen) -> void:
	_pages.append(page)
	page.back_requested.connect(go_back)
	page.sound_requested.connect(_play)
	page.info_changed.connect(refresh_panel)
	page.highlight_requested.connect(highlight_actions)
	page.push_requested.connect(func(next: MenuScreen) -> void:
		next.cancel_ignores_keys = page.cancel_ignores_keys  # the pause menu's Esc is one edge, whatever the depth
		push_screen(next))
	_lit_actions.clear()
	_host.add_child(page)
	_title.text = page.title
	_apply_layout()
	_message.text = ""
	page.focus_first()
	refresh()


# The panels the top page asks for. Without the right panel the options column keeps a modest width and the page's text sits
# under its list. A compact page shrinks each box to its content and packs them at the top left (M7-T31).
func _apply_layout() -> void:
	if _left == null:
		return
	var page: MenuScreen = current_page()
	var pad_on: bool = page == null or page.show_pad
	var right_on: bool = page == null or page.show_right
	_pad_panel.visible = pad_on
	_detail.add_theme_font_size_override(&"font_size", 16)
	if page != null and page.compact:
		_apply_compact_layout(pad_on, right_on)
	else:
		_apply_filled_layout(right_on)
	_sync_visibility()


func _apply_filled_layout(right_on: bool) -> void:
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL if right_on else Control.SIZE_SHRINK_BEGIN
	_left.custom_minimum_size.x = 0.0 if right_on else SLIM_WIDTH
	_options_panel.size_flags_horizontal = Control.SIZE_FILL
	_options_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_options_panel.custom_minimum_size.x = 0.0
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size.y = 0.0
	_pad_panel.size_flags_horizontal = Control.SIZE_FILL
	_pad_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pad.set_min_width(0.0)
	_right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_panel.size_flags_vertical = Control.SIZE_FILL
	_right_panel.custom_minimum_size.x = 0.0
	_objectives.set_fit_content(false)


func _apply_compact_layout(pad_on: bool, right_on: bool) -> void:
	var edges_y: float = _margin.get_theme_constant(&"margin_top") + _margin.get_theme_constant(&"margin_bottom")
	_left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left.custom_minimum_size.x = 0.0
	_options_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_options_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_options_panel.custom_minimum_size.x = COMPACT_WIDTH
	# The options list is as tall as its buttons unless the window cannot hold them, then it scrolls as before.
	var list_h: float = _host.get_combined_minimum_size().y
	var room: float = maxf(size.y - COMPACT_CHROME, 0.0)
	var fits: bool = size.y <= 0.0 or list_h <= room
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if fits else ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size.y = 0.0 if fits else room
	# The pad box is docked to the lower left corner (the column's spare height is its slot, it sits at the slot's end). The
	# diagram keeps its drawn size where the window has the room and otherwise shrinks, never into the options box above.
	_pad_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_pad_panel.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	var pad_width: float = 0.0
	if pad_on:
		var edges_x: float = _margin.get_theme_constant(&"margin_left") + _margin.get_theme_constant(&"margin_right")
		var room_x: float = size.x - edges_x - PANEL_PAD_X - (COMPACT_RIGHT_MIN_WIDTH + COLUMN_GAP if right_on else 0.0)
		var room_y: float = size.y - edges_y - _options_panel.get_combined_minimum_size().y - BOX_GAP - PANEL_PAD_Y
		pad_width = clampf(minf(room_x, room_y * PadDiagram.DESIGN.x / PadDiagram.DESIGN.y), COMPACT_PAD_MIN_WIDTH, PadDiagram.DESIGN.x)
		if size.x <= 0.0 or size.y <= 0.0:
			pad_width = PadDiagram.DESIGN.x
	_pad.set_min_width(pad_width)
	# The right panel sits beside the left column and gives way, down to a narrow strip, in a narrow window.
	var left_width: float = maxf(COMPACT_WIDTH, pad_width + PANEL_PAD_X if pad_on else 0.0)
	var edges_w: float = _margin.get_theme_constant(&"margin_left") + _margin.get_theme_constant(&"margin_right")
	var right_width: float = COMPACT_RIGHT_WIDTH if size.x <= 0.0 else clampf(size.x - edges_w - COLUMN_GAP - left_width,
			COMPACT_RIGHT_MIN_WIDTH, COMPACT_RIGHT_WIDTH)
	var wide: bool = current_page() != null and current_page().wide_right
	_right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if wide else Control.SIZE_SHRINK_BEGIN
	_right_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_right_panel.custom_minimum_size.x = COMPACT_RIGHT_MIN_WIDTH if wide else right_width
	_objectives.set_fit_content(true, size.y - edges_y - PANEL_PAD_Y if size.y > 0.0 else 0.0)


# What shows depends on the content too: a compact page has no empty box, so no right panel without anything to say, no
# detail line or message without text.
func _sync_visibility() -> void:
	if _left == null:
		return
	var page: MenuScreen = current_page()
	var compact: bool = page != null and page.compact
	var right_on: bool = page == null or page.show_right
	if compact and right_on:
		var content: Dictionary = right_content()
		right_on = not String(content.get("title", "")).is_empty() or not (content.get("lines", []) as Array).is_empty()
	_right_panel.visible = right_on
	var detail_on: bool = not (page == null or page.show_right)
	_detail.visible = detail_on and not (compact and _detail.text.is_empty())
	_message.visible = not (compact and _message.text.is_empty())


func _drop(page: MenuScreen) -> void:
	if is_instance_valid(page):
		_host.remove_child(page)
		page.queue_free()


func _play(sound: StringName) -> void:
	if audio != null:
		audio.play_ui(sound)


func _on_profile_applied(_profile_name: String) -> void:
	refresh_legend()
