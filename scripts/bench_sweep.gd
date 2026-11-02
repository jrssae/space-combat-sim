extends SceneTree
## Summarises a benchmark sweep (M4-T01, run by scripts/bench.sh after every ship count): reads every run's summary.json under
## `<dir>/runs/`, decides each layout's max N and whether its sweep stops (`PerfStats`), and writes `<dir>/summary.json` and
## `<dir>/summary.md`. Prints one `[bench-sweep]` line per ship count, layout and headline for the shell to read.
##
## Arguments after `--`: <dir> (a res:// or absolute path) [key=value ...] (recorded in the summary: commit, date, label).


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
	var summary: Dictionary = BenchReport.sweep_summary(runs, meta)
	var problem: String = BenchReport.write(dir, summary, BenchReport.sweep_markdown(summary))
	if not problem.is_empty():
		printerr("bench_sweep.gd: %s" % problem)
		quit(1)
		return
	var layouts: Dictionary = summary["layouts"]
	for layout: String in layouts:
		var entry: Dictionary = layouts[layout]
		for c: Dictionary in entry["counts"]:
			print("[bench-sweep] %s %d %s %d/%d tick median %.2f ms" % [layout, int(c["n"]), "pass" if bool(c["pass"]) else "fail",
					int(c["passes"]), int(c["runs"]), float(c["tick_median_us"]) * 1e-3])
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
