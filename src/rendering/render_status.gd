class_name RenderStatus
extends Node
## What the renderer did last frame, for the console and the measuring scripts (architecture §7.4, §6.4; M4-T31 replaced the old
## renderer's status node with this one).
##
## Main (M1-T15) adds one RenderStatus outside `World`. Console: provider `render`: `renderer` (`forward_plus`, or `headless` when
## there is no display: import, CI, GUT), `fps`, `frame_ms`, `draw_calls`, `triangles`, `vram_mb`, `far_dots` (ships drawn as
## dots, M4-T11), `gpu` and `gpu_ms`.

const RENDERER_HEADLESS: StringName = &"headless"


## The rendering method drawing the game, or `headless` when nothing is drawn.
static func renderer() -> StringName:
	if DisplayServer.get_name() == "headless":
		return RENDERER_HEADLESS
	return StringName(RenderingServer.get_current_rendering_method())


func _ready() -> void:
	DebugConsole.registry.register_provider(&"render", ConsoleVars.new({
		&"renderer": {"get": renderer, "doc": "The rendering method: forward_plus, or headless when nothing is drawn"},
		&"fps": {"get": func() -> float: return Engine.get_frames_per_second(), "doc": "Frames per second"},
		&"frame_ms": {"get": _frame_ms, "unit": "ms", "doc": "Mean frame time over the last second"},
		&"draw_calls": {"get": func() -> int: return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				"doc": "Draw calls in the last frame"},
		&"triangles": {"get": func() -> int: return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				"doc": "Triangles drawn in the last frame"},
		&"vram_mb": {"get": func() -> float: return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6,
				"unit": "MB", "doc": "Video memory the renderer holds, MB"},
		&"far_dots": {"get": LodSwitcher.far_dot_count, "doc": "Ships in play drawn as far dots, past settings.far_ship_dot_m (M4-T11)"},
		&"gpu": {"get": _gpu_name, "doc": "Video adapter name"},
		&"gpu_ms": {"get": _gpu_ms, "doc": "Last frame's GPU time, ms (0 on the first read: measuring starts then)"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


static func _frame_ms() -> float:
	var fps: float = Engine.get_frames_per_second()
	return 1000.0 / fps if fps > 0.0 else 0.0


func _gpu_ms() -> float:
	var viewport: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	return RenderingServer.viewport_get_measured_render_time_gpu(viewport)


static func _gpu_name() -> String:
	var adapter: String = RenderingServer.get_video_adapter_name()
	return adapter if not adapter.is_empty() else "none"
