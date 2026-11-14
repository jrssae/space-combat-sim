class_name ObjectivesPanel
extends VBoxContainer
## The menu frame's right panel (architecture §18, D57, Q15): a heading and the lines of an `ObjectivesModel` content. It only
## draws what it is given; the frame decides whether that is a mission's objectives, the run, or a briefing.

const DONE_COLOR: Color = Color(0.4, 0.75, 0.5)
const FAILED_COLOR: Color = Color(1.0, 0.42, 0.36)
const OPTIONAL_COLOR: Color = Color(0.55, 1.0, 0.65, 0.7)
## A content with `compact: true` (the debrief, which is the longest) sets its lines smaller and closer together.
const LINE_SEPARATION: int = 10
const COMPACT_SEPARATION: int = 4
const COMPACT_FONT_SIZE: int = 18

## What is showing now (tests).
var content: Dictionary = {"title": "", "lines": []}

var _heading: Label = null
var _scroll: ScrollContainer = null
var _lines: VBoxContainer = null
var _rule: HSeparator = null
var _fit: bool = false
var _max_height: float = 0.0


func _ready() -> void:
	_heading = Label.new()
	_heading.theme_type_variation = &"Heading"
	add_child(_heading)
	_rule = HSeparator.new()
	add_child(_rule)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_lines = VBoxContainer.new()
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_theme_constant_override(&"separation", LINE_SEPARATION)
	_scroll.add_child(_lines)
	_lines.minimum_size_changed.connect(_refit)
	show_content(content)


## Whether the panel is as tall as its lines (a compact page) instead of scrolling inside a box the frame stretches. With
## `max_height` (> 0) a longer text stops at that height and scrolls, so nothing is clipped.
func set_fit_content(fit: bool, max_height: float = 0.0) -> void:
	_fit = fit
	_max_height = max_height
	_refit()


# Fits the scroll area to the lines: as tall as they are, or at the most height the panel may take.
func _refit() -> void:
	if _scroll == null:
		return
	var scrolls: bool = false
	var visible_h: float = 0.0
	if _fit and _max_height > 0.0:
		var chrome: float = _heading.get_combined_minimum_size().y + _rule.get_combined_minimum_size().y \
				+ 2.0 * get_theme_constant(&"separation")
		var allowed: float = maxf(_max_height - chrome, 0.0)
		scrolls = _lines.get_combined_minimum_size().y > allowed
		visible_h = allowed
	var mode: ScrollContainer.ScrollMode = ScrollContainer.SCROLL_MODE_AUTO if (scrolls or not _fit) \
			else ScrollContainer.SCROLL_MODE_DISABLED
	if _scroll.vertical_scroll_mode != mode:
		_scroll.vertical_scroll_mode = mode
	var min_h: float = visible_h if scrolls else 0.0
	if not is_equal_approx(_scroll.custom_minimum_size.y, min_h):
		_scroll.custom_minimum_size.y = min_h


func show_content(new_content: Dictionary) -> void:
	content = new_content
	if _lines == null:
		return
	_heading.text = String(content.get("title", ""))
	var compact: bool = bool(content.get("compact", false))
	_lines.add_theme_constant_override(&"separation", COMPACT_SEPARATION if compact else LINE_SEPARATION)
	for child: Node in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	for line: Dictionary in content.get("lines", []):
		var label := Label.new()
		var mark: String = String(line.get("mark", ""))
		label.text = "%s %s" % [mark, line["text"]] if not mark.is_empty() else String(line["text"])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if compact:
			label.add_theme_font_size_override(&"font_size", COMPACT_FONT_SIZE)
		match StringName(line.get("state", &"")):
			&"done":
				label.add_theme_color_override(&"font_color", DONE_COLOR)
			&"failed":
				label.add_theme_color_override(&"font_color", FAILED_COLOR)
			_:
				if bool(line.get("optional", false)):
					label.add_theme_color_override(&"font_color", OPTIONAL_COLOR)
		_lines.add_child(label)


## The scroll area and the height the lines want, for tests.
func scroll_container() -> ScrollContainer:
	return _scroll


func content_height() -> float:
	return _lines.get_combined_minimum_size().y if _lines != null else 0.0


## The text of every line as it is drawn, for tests.
func shown_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if _lines != null:
		for child: Node in _lines.get_children():
			if not child.is_queued_for_deletion():
				out.append((child as Label).text)
	return out
