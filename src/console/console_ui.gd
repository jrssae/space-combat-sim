class_name ConsoleUI
extends CanvasLayer
## The console's log and prompt (architecture §6.4): top 40 % of the screen, translucent, monospace, prompt `>`.
## Keyboard only: Enter runs the line, Up/Down browse history, Tab completes (repeated Tab cycles), PageUp/PageDown
## scroll. Joypad events are swallowed while it is open so pad buttons never navigate or press the prompt;
## gameplay polls devices and is unaffected. The ` and Esc keys are handled by DebugConsole before this sees them.
## Holds a 1000-line ring buffer of what was printed, and drains the ConsoleLogger queue into it every frame (engine
## errors in red, warnings in yellow), open or not.

signal submitted(line: String)

enum LineKind { OUTPUT, ECHO, ERROR, WARNING }

const MAX_LINES: int = 1000
const KIND_COLORS: Dictionary = {
	LineKind.OUTPUT: Color(0.86, 0.9, 0.95),
	LineKind.ECHO: Color(0.55, 0.75, 1.0),
	LineKind.ERROR: Color(1.0, 0.42, 0.38),
	LineKind.WARNING: Color(1.0, 0.85, 0.3),
}

## Up/Down browsing (shared with DebugConsole, which persists it).
var history: ConsoleHistory = null
## Callable(partial: String) -> PackedStringArray of whole candidate lines (ConsoleRegistry.complete).
var completer: Callable = Callable()
## Engine errors and warnings queued off the main thread (DebugConsole registers it with OS.add_logger).
var logger: ConsoleLogger = null

var _lines: Array[Dictionary] = []  # {"text": String, "kind": LineKind}
var _dirty: bool = false
var _cycle: PackedStringArray = PackedStringArray()
var _cycle_index: int = -1
var _cycle_text: String = ""

@onready var log_view: RichTextLabel = %Log
@onready var prompt: LineEdit = %Prompt


func _ready() -> void:
	visible = false
	prompt.text_submitted.connect(_on_text_submitted)
	prompt.gui_input.connect(_on_prompt_gui_input)


func _process(_delta: float) -> void:
	if logger != null:
		for entry: Dictionary in logger.drain():
			append(entry["text"], LineKind.WARNING if entry["warning"] else LineKind.ERROR)
	if _dirty and visible:
		_render()


func _input(event: InputEvent) -> void:
	if visible and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	visible = open
	_reset_cycle()
	if open:
		_render()
		prompt.grab_focus()
		prompt.edit()
	else:
		prompt.unedit()
		prompt.release_focus()


func is_open() -> bool:
	return visible


## Adds output; multi-line text becomes several log lines. The oldest lines beyond MAX_LINES are dropped.
func append(text: String, kind: LineKind = LineKind.OUTPUT) -> void:
	for part: String in text.split("\n"):
		_lines.append({"text": part, "kind": kind})
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_dirty = true


func clear_log() -> void:
	_lines.clear()
	_dirty = true


## The log as plain text, oldest first.
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in _lines:
		out.append(entry["text"])
	return out


## Tab: replaces the prompt with the next completion candidate. Returns the candidates it cycles through.
func complete_prompt() -> PackedStringArray:
	if not completer.is_valid():
		return PackedStringArray()
	if _cycle_index >= 0 and prompt.text == _cycle_text and _cycle.size() > 1:
		_cycle_index = (_cycle_index + 1) % _cycle.size()
	else:
		var found: Variant = completer.call(prompt.text)
		_cycle = found if found is PackedStringArray else PackedStringArray()
		_cycle_index = 0 if not _cycle.is_empty() else -1
		if _cycle.size() > 1:
			append("  ".join(_short_candidates(_cycle)), LineKind.ECHO)
	if _cycle_index >= 0:
		_cycle_text = _cycle[_cycle_index]
		prompt.text = _cycle_text
		prompt.caret_column = prompt.text.length()
	return _cycle


func _on_text_submitted(text: String) -> void:
	prompt.clear()
	_reset_cycle()
	if history != null:
		history.add(text)
		history.save_file()
	if not text.strip_edges().is_empty():
		submitted.emit(text)
	prompt.edit()


func _on_prompt_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_TAB:
			complete_prompt()
		KEY_UP:
			if history != null:
				_set_prompt(history.older(prompt.text))
		KEY_DOWN:
			if history != null:
				_set_prompt(history.newer(prompt.text))
		KEY_PAGEUP:
			_scroll_pages(-1.0)
		KEY_PAGEDOWN:
			_scroll_pages(1.0)
		_:
			return
	prompt.accept_event()


func _set_prompt(text: String) -> void:
	prompt.text = text
	prompt.caret_column = text.length()
	_reset_cycle()


func _scroll_pages(direction: float) -> void:
	var bar: VScrollBar = log_view.get_v_scroll_bar()
	bar.value = clampf(bar.value + direction * bar.page * 0.9, bar.min_value, bar.max_value)


func _reset_cycle() -> void:
	_cycle = PackedStringArray()
	_cycle_index = -1
	_cycle_text = ""


func _render() -> void:
	_dirty = false
	var parts := PackedStringArray()
	for entry: Dictionary in _lines:
		var color: Color = KIND_COLORS.get(entry["kind"], Color.WHITE)
		parts.append("[color=#%s]%s[/color]" % [color.to_html(false), String(entry["text"]).replace("[", "[lb]")])
	log_view.text = "\n".join(parts)


# Last tokens of each candidate line, for the one-line hint printed on the first Tab.
static func _short_candidates(candidates: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for candidate: String in candidates:
		var words: PackedStringArray = candidate.strip_edges().split(" ")
		out.append(words[words.size() - 1] if not words.is_empty() else candidate)
	return out
