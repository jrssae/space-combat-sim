extends SceneTree
## Summarises a benchmark sweep (M4-T01, run by scripts/bench.sh): decides each layout's max N from the runs' summaries and
## writes `<dir>/summary.json` and `summary.md`, with one `[bench-sweep]` line per verdict for the shell.
## Arguments after `--`: <dir> [runs=<n>] [key=value ...]; with `runs`, each missing run counts as a failure.
## `BenchReport` is loaded at run time: a `-s` script compiles before the autoloads it reaches exist.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("bench_sweep.gd: give the sweep's directory after --")
		quit(2)
		return
	var dir: String = args[0]
	var meta: Dictionary = {"label": dir.get_file()}
	for i: int in range(1, args.size()):
		var pair: PackedStringArray = args[i].split("=", true, 1)
		if pair.size() == 2:
			meta[pair[0]] = pair[1]
	var runs: Array[Dictionary] = _read_runs(dir.path_join("runs"))
	if not runs.is_empty():
		meta["machine"] = runs[0].get("machine", {})
	var report: GDScript = load("res://src/perf/bench_report.gd") as GDScript
	var summary: Dictionary = report.call("sweep_summary", runs, meta, int(meta.get("runs", "0")))
	var problem: String = report.call("write", dir, summary, report.call("sweep_markdown", summary))
	if not problem.is_empty():
		printerr("bench_sweep.gd: %s" % problem)
		quit(1)
		return
	var layouts: Dictionary = summary["layouts"]
	for layout: String in layouts:
		var entry: Dictionary = layouts[layout]
		for c: Dictionary in entry["counts"]:
			print("[bench-sweep] %s %d %s %d/%d tick median %.2f ms%s" % [layout, int(c["n"]), "pass" if bool(c["pass"]) else "fail",
					int(c["passes"]), int(c["runs"]), float(c["tick_median_us"]) * 1e-3,
					", %d missing" % int(c["missing"]) if int(c["missing"]) > 0 else ""])
		print("[bench-sweep] %s max_n %d%s" % [layout, int(entry["max_n"]), " stop" if bool(entry["stopped"]) else ""])
	print("[bench-sweep] headline %d (%d runs)" % [int(summary["headline_max_n"]), runs.size()])
	quit(0)


func _read_runs(runs_dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var absolute: String = ProjectSettings.globalize_path(runs_dir)
	var listing := DirAccess.open(absolute)
	if listing == null:
		return out
	var names: PackedStringArray = listing.get_directories()
	names.sort()
	for run_name: String in names:
		var path: String = absolute.path_join(run_name).path_join("summary.json")
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			out.append(parsed as Dictionary)
	return out
