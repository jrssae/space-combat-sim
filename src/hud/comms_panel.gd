class_name CommsPanel
extends CanvasLayer
## The comms panel (architecture §18 D53, M5-T06): the line a mission is speaking, as a subtitle at the bottom of the window with
## the speaker's callsign above it in their faction's colour, in both camera views. `DialogQueue` decides what is showing; this
## node only draws it and plays the squelches that frame each line (`radio_open` as it starts, `radio_close` as it ends by
## itself; a cut line makes no close). `CommsLayout` places it. It sits on its own layer, above the HUD (40) and below the pause
## menu (60), so it neither fades with the chase view's HUD nor vanishes when the HUD is switched off: a cinematic hides the
## HUD and still needs its subtitles. The cockpit's right screen keeps the wing roster and the acknowledgements.
##
## Console: provider `dialog` (`showing`, `line`, `speaker`, `text`, `queued`, `remaining_s`, `lines_shown`).

const LAYER: int = 41
const PLATE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.62)
const TEXT_COLOR: Color = Color(0.94, 0.98, 0.96)
const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)
## The squelches' level: quieter than the menu sounds, they sit under a voice.
const SQUELCH_DB: float = -6.0

var queue: DialogQueue = null
var book: DialogBook = null
var audio: AudioDirector = null
## The viewer whose view of a speaker's faction picks the callsign colour.
var viewer_faction: StringName = Factions.EARTH_ALLIANCE

## What the last draw put on screen (tests read it): the plate, the callsign and its colour, the text, and how many draws.
var drawn_plate: Rect2 = Rect2()
var drawn_callsign: String = ""
var drawn_color: Color = Color.WHITE
var drawn_text: String = ""
var draws: int = 0
## Lines started so far, and squelches played.
var lines_shown: int = 0

var _canvas: CommsCanvas = null


## Gives the panel the queue to show, the book that names the speakers and the audio director for the squelches.
func bind(p_queue: DialogQueue, p_book: DialogBook, p_audio: AudioDirector) -> void:
	_unbind()
	queue = p_queue
	book = p_book
	audio = p_audio
	if queue != null:
		queue.started.connect(_on_started)
		queue.finished.connect(_on_finished)
	_redraw()


func _ready() -> void:
	layer = LAYER
	name = "CommsPanel"
	_canvas = CommsCanvas.new()
	_canvas.name = "CommsCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.panel = self
	add_child(_canvas)
	DebugConsole.registry.register_provider(&"dialog", ConsoleVars.new({
		&"showing": {"get": is_showing, "doc": "A comms line is on screen"},
		&"line": {"get": func() -> String: return String(queue.current.id) if is_showing() else "none", "doc": "The id of the line showing"},
		&"speaker": {"get": func() -> String: return callsign() if is_showing() else "none", "doc": "The callsign of who is speaking"},
		&"text": {"get": func() -> String: return queue.current.text if is_showing() else "", "doc": "The subtitle showing"},
		&"queued": {"get": func() -> int: return queue.queued_count() if queue != null else 0, "doc": "Lines waiting their turn"},
		&"remaining_s": {"get": func() -> float: return queue.remaining_s() if queue != null else 0.0, "unit": "s",
				"doc": "Time left on the line showing"},
		&"lines_shown": {"get": func() -> int: return lines_shown, "doc": "Lines started so far in this mission"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	_unbind()


## A line is on screen.
func is_showing() -> bool:
	return queue != null and queue.current != null


## The callsign of the speaker showing ("" when nothing shows or the book does not know them).
func callsign() -> String:
	var speaker: DialogBook.Speaker = _speaker()
	return speaker.callsign if speaker != null else ""


## Draws the plate on `canvas`: the callsign in the faction's colour over the wrapped line. Called from the canvas's `_draw`.
func paint(canvas: Control) -> void:
	if not is_showing():
		return
	var layout: CommsLayout = CommsLayout.compute(canvas.size)
	var font: Font = HudPainter.font()
	var text: String = queue.current.text
	var width: float = layout.text_width()
	var text_height: float = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, layout.text_px).y
	var plate: Rect2 = layout.plate(text_height)
	var color: Color = _color()
	var name_text: String = callsign()
	canvas.draw_rect(plate, PLATE_COLOR, true)
	canvas.draw_rect(Rect2(plate.position, Vector2(maxf(3.0 * layout.scale, 2.0), plate.size.y)), color, true)
	var left: float = plate.position.x + layout.pad_px
	var callsign_at := Vector2(left, plate.position.y + layout.pad_px + float(layout.callsign_px))
	_text(canvas, font, name_text, callsign_at, layout.callsign_px, color)
	var text_at := Vector2(left, plate.position.y + layout.pad_px + float(layout.callsign_px) * CommsLayout.CALLSIGN_ROW
			+ font.get_ascent(layout.text_px))
	canvas.draw_multiline_string(font, text_at + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, width, layout.text_px, -1, SHADOW_COLOR)
	canvas.draw_multiline_string(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, width, layout.text_px, -1, TEXT_COLOR)
	drawn_plate = plate
	drawn_callsign = name_text
	drawn_color = color
	drawn_text = text
	draws += 1


func _unbind() -> void:
	if queue != null:
		if queue.started.is_connected(_on_started):
			queue.started.disconnect(_on_started)
		if queue.finished.is_connected(_on_finished):
			queue.finished.disconnect(_on_finished)


func _on_started(_ticket: int, _line: DialogBook.Line) -> void:
	lines_shown += 1
	_play(&"radio_open")
	_redraw()


func _on_finished(_ticket: int, _line: DialogBook.Line, cut: bool) -> void:
	if not cut:
		_play(&"radio_close")
	_redraw()


# Nothing plays while the scene is going (a line cut at quit would outlive the audio's own clean-up and leak its stream).
func _play(sound: StringName) -> void:
	if audio != null and is_instance_valid(audio) and audio.is_inside_tree() and is_inside_tree():
		audio.play_ui(sound, SQUELCH_DB)


func _redraw() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _speaker() -> DialogBook.Speaker:
	if not is_showing() or book == null:
		return null
	return book.speaker_of(queue.current)


func _color() -> Color:
	var speaker: DialogBook.Speaker = _speaker()
	return CommsLayout.faction_color(speaker.faction, viewer_faction) if speaker != null else TEXT_COLOR


func _text(canvas: Control, font: Font, text: String, baseline: Vector2, size: int, color: Color) -> void:
	canvas.draw_string(font, baseline + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, SHADOW_COLOR)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


## The control the panel draws on, full window.
class CommsCanvas extends Control:
	var panel: CommsPanel = null

	func _draw() -> void:
		if panel != null:
			panel.paint(self)
