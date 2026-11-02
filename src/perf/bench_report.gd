class_name BenchReport
extends RefCounted
## The benchmark's written record (M4-T01): one run's `summary.json` and `summary.md` from the probe's recorded ticks, and a
## sweep's from its runs' summaries (`scripts/bench_sweep.gd`). Builds plain dictionaries and text; only `machine` and `write`
## touch the system.
##
## Stage numbers are per tick, in microseconds: the median and p99 of each stage over the ticks it was timed in, and its mean.
## Means add up (the stages split each tick), so the breakdown uses them; medians and p99 are the budget's view.

## Stages in the order a breakdown lists them; `tick` is their total.
const BREAKDOWN: Array[StringName] = [&"ai", &"flight", &"targeting", &"resolvers", &"late", &"physics", &"other"]
## Inside other stages, listed beside them.
const INSIDE: Array[StringName] = [&"scan", &"think", &"rebase", &"sync"]
## Ship counts whose stage breakdown the sweep summary lists (the milestone's AC2).
const BREAKDOWN_NS: Array[int] = [50, 100]


## Median, p99, mean and max of one stage's samples.
static func stage_stats(values: PackedFloat64Array) -> Dictionary:
	return {
		"median_us": PerfStats.median(values),
		"p99_us": PerfStats.percentile(values, 0.99),
		"mean_us": PerfStats.mean(values),
		"max_us": PerfStats.max_value(values),
	}


## One run's summary. `meta` holds what the runner knows (layout, n, seed, label, warmup_s, seconds, load_ms, wall_s,
## sim_s, rebase_threshold_m, sync_timed, engine checks, probe cost, aborted); `series` is the probe's recorded ticks.
static func run_summary(meta: Dictionary, series: Array[PackedInt64Array]) -> Dictionary:
	var on: PackedInt64Array = series[PerfProbe.Field.STAGES_ON]
	var stages: Dictionary = {}
	for i: int in PerfProbe.FIELD_NAMES.size():
		var field: StringName = PerfProbe.FIELD_NAMES[i]
		if field in [&"ships", &"bolts", &"pairs", &"stages_on"]:
			continue
		# The tick, the engine's part and the remainder are timed in every tick; the stages only where their markers ran.
		var every_tick: bool = field in [&"tick", &"physics", &"sync"]
		stages[String(field)] = stage_stats(_floats(series[i], on, every_tick))
	var rebases := PackedFloat64Array()
	for us: int in series[PerfProbe.Field.REBASE]:
		if us > 0:
			rebases.append(float(us))
	var ships: PackedInt64Array = series[PerfProbe.Field.SHIPS]
	var tick: Dictionary = stages["tick"]
	var lag_share: float = PerfStats.lag(float(meta.get("sim_s", 0.0)), float(meta.get("wall_s", 0.0)))
	var verdict: Dictionary = PerfStats.verdict(tick["median_us"], tick["p99_us"], PerfStats.max_value(rebases), lag_share)
	var aborted: String = String(meta.get("aborted", ""))
	if not aborted.is_empty():
		(verdict["failures"] as PackedStringArray).append("aborted: " + aborted)
		verdict["pass"] = false
	var out: Dictionary = meta.duplicate()
	out["ticks"] = series[PerfProbe.Field.TICK].size()
	out["lag"] = lag_share
	out["stages"] = stages
	out["rebase"] = {"count": rebases.size(), "max_us": PerfStats.max_value(rebases), "median_us": PerfStats.median(rebases),
			"threshold_m": meta.get("rebase_threshold_m", 0.0)}
	out["ships_min"] = _min_int(ships)
	out["ships_max"] = _max_int(ships)
	out["bolts_mean"] = PerfStats.mean(_floats(series[PerfProbe.Field.BOLTS], on, true))
	out["pairs_mean"] = PerfStats.mean(_floats(series[PerfProbe.Field.PAIRS], on, true))
	out["verdict"] = {"pass": verdict["pass"], "failures": Array(verdict["failures"] as PackedStringArray)}
	return out


## A run's summary as a short Markdown page.
static func run_markdown(s: Dictionary) -> String:
	var lines := PackedStringArray()
	var verdict: Dictionary = s.get("verdict", {})
	lines.append("# Bench %s, %d ships (seed %d)" % [s.get("layout", "?"), int(s.get("n", 0)), int(s.get("seed", 0))])
	lines.append("")
	lines.append("Verdict: **%s**%s" % ["pass" if bool(verdict.get("pass", false)) else "fail",
			("; " + "; ".join(PackedStringArray(verdict.get("failures", [])))) if not (verdict.get("failures", []) as Array).is_empty() else ""])
	lines.append("")
	var tick: Dictionary = (s.get("stages", {}) as Dictionary).get("tick", {})
	lines.append("Tick: median %.2f ms, p99 %.2f ms, max %.2f ms over %d ticks; real time kept: %.2f %% behind; rebases %d (worst %.2f ms); load %.0f ms; ships in play %d to %d; bolts %.0f on average" % [
			_ms(tick, "median_us"), _ms(tick, "p99_us"), _ms(tick, "max_us"), int(s.get("ticks", 0)), float(s.get("lag", 0.0)) * 100.0,
			int((s.get("rebase", {}) as Dictionary).get("count", 0)), float((s.get("rebase", {}) as Dictionary).get("max_us", 0.0)) * 1e-3,
			float(s.get("load_ms", 0.0)), int(s.get("ships_min", 0)), int(s.get("ships_max", 0)), float(s.get("bolts_mean", 0.0))])
	lines.append("")
	lines.append_array(_breakdown_table(s.get("stages", {}) as Dictionary))
	var engine: Dictionary = s.get("engine_check", {})
	if not engine.is_empty():
		lines.append("")
		lines.append("Engine check (worst tick of each second, median over the seconds): the engine's %.2f ms, the probe's %.2f ms." % [
				float(engine.get("engine_worst_us", 0.0)) * 1e-3, float(engine.get("probe_worst_us", 0.0)) * 1e-3])
	var probe: Dictionary = s.get("probe_cost", {})
	if not probe.is_empty():
		lines.append("")
		lines.append("Probe cost (stage timers on against off, %d and %d blocks): %+.0f us per tick on a median tick of %.0f us." % [
				int(probe.get("on_blocks", 0)), int(probe.get("off_blocks", 0)), float(probe.get("paired_us", 0.0)), float(probe.get("tick_median_us", 0.0))])
	lines.append("")
	lines.append("Machine: %s" % _machine_line(s.get("machine", {}) as Dictionary))
	return "\n".join(lines) + "\n"


## The stage table: mean (they add up to the mean tick), share, median and p99 of each stage.
static func _breakdown_table(stages: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var tick: Dictionary = stages.get("tick", {})
	var total: float = maxf(float(tick.get("mean_us", 0.0)), 1e-9)
	lines.append("| stage | mean ms | share | median ms | p99 ms |")
	lines.append("|---|---|---|---|---|")
	for name: StringName in BREAKDOWN + INSIDE:
		var st: Dictionary = stages.get(String(name), {})
		var label: String = String(name) if name in BREAKDOWN else "(%s, inside)" % name
		if name == &"other":
			label = "other (unaccounted)"
		lines.append("| %s | %.3f | %.1f %% | %.3f | %.3f |" % [label, _ms(st, "mean_us"), 100.0 * float(st.get("mean_us", 0.0)) / total,
				_ms(st, "median_us"), _ms(st, "p99_us")])
	lines.append("| **tick** | %.3f | 100 %% | %.3f | %.3f |" % [_ms(tick, "mean_us"), _ms(tick, "median_us"), _ms(tick, "p99_us")])
	return lines


## A sweep's summary from its runs' summaries: per layout and ship count the runs, their verdicts and the medians over runs,
## each layout's max N and whether it stopped, and the headline.
static func sweep_summary(runs: Array[Dictionary], meta: Dictionary = {}) -> Dictionary:
	var by_layout: Dictionary = {}
	for run: Dictionary in runs:
		var layout: String = String(run.get("layout", ""))
		var n: int = int(run.get("n", 0))
		if not by_layout.has(layout):
			by_layout[layout] = {}
		var by_n: Dictionary = by_layout[layout]
		if not by_n.has(n):
			by_n[n] = [] as Array[Dictionary]
		(by_n[n] as Array[Dictionary]).append(run)
	var layouts: Dictionary = {}
	var max_by_layout: Dictionary = {}
	for layout: String in by_layout:
		var by_n: Dictionary = by_layout[layout]
		var ns: Array = by_n.keys()
		ns.sort()
		var results: Dictionary = {}
		var counts: Array[Dictionary] = []
		for n: int in ns:
			var list: Array[Dictionary] = by_n[n]
			var passes: Array = []
			for run: Dictionary in list:
				passes.append(bool((run.get("verdict", {}) as Dictionary).get("pass", false)))
			results[n] = passes
			counts.append(_count_entry(n, list, passes))
		var best: int = PerfStats.max_n(results)
		max_by_layout[StringName(layout)] = best
		layouts[layout] = {"max_n": best, "stopped": PerfStats.should_stop(ns, results), "counts": counts}
	var out: Dictionary = meta.duplicate()
	out["layouts"] = layouts
	out["headline_max_n"] = PerfStats.headline(max_by_layout)
	return out


# One ship count of a sweep: its runs' verdicts and the medians over them.
static func _count_entry(n: int, runs: Array[Dictionary], passes: Array) -> Dictionary:
	var medians := PackedFloat64Array()
	var p99s := PackedFloat64Array()
	var lags := PackedFloat64Array()
	var loads := PackedFloat64Array()
	var rebase_worst: float = 0.0
	var failures: Array = []
	var stage_means: Dictionary = {}
	for run: Dictionary in runs:
		var stages: Dictionary = run.get("stages", {})
		var tick: Dictionary = stages.get("tick", {})
		medians.append(float(tick.get("median_us", 0.0)))
		p99s.append(float(tick.get("p99_us", 0.0)))
		lags.append(float(run.get("lag", 0.0)))
		loads.append(float(run.get("load_ms", 0.0)))
		rebase_worst = maxf(rebase_worst, float((run.get("rebase", {}) as Dictionary).get("max_us", 0.0)))
		failures.append_array((run.get("verdict", {}) as Dictionary).get("failures", []))
		for name: StringName in [&"tick"] + BREAKDOWN + INSIDE:
			if not stage_means.has(String(name)):
				stage_means[String(name)] = PackedFloat64Array()
			(stage_means[String(name)] as PackedFloat64Array).append(float((stages.get(String(name), {}) as Dictionary).get("mean_us", 0.0)))
	var breakdown: Dictionary = {}
	for key: String in stage_means:
		breakdown[key] = PerfStats.median(stage_means[key] as PackedFloat64Array)
	var run_medians: Array = Array(medians)
	return {
		"n": n,
		"runs": runs.size(),
		"passes": passes.count(true),
		"pass": PerfStats.count_passes(passes),
		"tick_median_us": PerfStats.median(medians),
		"tick_p99_us": PerfStats.median(p99s),
		"tick_median_spread_us": [PerfStats.percentile(medians, 0.0), PerfStats.percentile(medians, 1.0)],
		"run_tick_medians_us": run_medians,
		"lag": PerfStats.median(lags),
		"rebase_max_us": rebase_worst,
		"load_ms": PerfStats.median(loads),
		"stage_means_us": breakdown,
		"failures": failures,
	}


## A sweep's summary as Markdown: the max N per layout, every ship count measured, and the stage breakdown at 50 and 100.
static func sweep_markdown(s: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("# Bench sweep %s" % s.get("label", ""))
	lines.append("")
	lines.append("Headline max N (the lower of furball and spread): **%d**" % int(s.get("headline_max_n", 0)))
	lines.append("")
	var layouts: Dictionary = s.get("layouts", {})
	for layout: String in layouts:
		var entry: Dictionary = layouts[layout]
		lines.append("## %s: max N %d%s" % [layout, int(entry.get("max_n", 0)), " (stopped after two failing counts)" if bool(entry.get("stopped", false)) else ""])
		lines.append("")
		lines.append("| N | runs passed | tick median ms (runs) | p99 ms | behind real time | worst rebase ms | load s |")
		lines.append("|---|---|---|---|---|---|---|")
		for c: Dictionary in entry.get("counts", []):
			var run_medians := PackedStringArray()
			for us: Variant in c.get("run_tick_medians_us", []):
				run_medians.append("%.2f" % (float(us) * 1e-3))
			lines.append("| %d | %d/%d %s | %.2f (%s) | %.2f | %.2f %% | %.2f | %.1f |" % [int(c["n"]), int(c["passes"]), int(c["runs"]),
					"pass" if bool(c["pass"]) else "fail", float(c["tick_median_us"]) * 1e-3, ", ".join(run_medians), float(c["tick_p99_us"]) * 1e-3,
					float(c["lag"]) * 100.0, float(c["rebase_max_us"]) * 1e-3, float(c["load_ms"]) * 1e-3])
		lines.append("")
		for c: Dictionary in entry.get("counts", []):
			if int(c["n"]) in BREAKDOWN_NS:
				lines.append("Stage means at %d ships (median over runs), ms per tick:" % int(c["n"]))
				lines.append("")
				lines.append_array(_means_table(c.get("stage_means_us", {}) as Dictionary))
				lines.append("")
	if s.has("machine"):
		lines.append("Machine: %s" % _machine_line(s["machine"] as Dictionary))
	return "\n".join(lines) + "\n"


static func _means_table(means: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var total: float = maxf(float(means.get("tick", 0.0)), 1e-9)
	var header := PackedStringArray()
	var row := PackedStringArray()
	for name: StringName in BREAKDOWN + INSIDE + [&"tick"]:
		var label: String = "other (unaccounted)" if name == &"other" else ("(%s)" % name if name in INSIDE else String(name))
		header.append(label)
		var us: float = float(means.get(String(name), 0.0))
		row.append("%.2f (%.0f %%)" % [us * 1e-3, 100.0 * us / total] if name != &"tick" else "%.2f" % (us * 1e-3))
	lines.append("| " + " | ".join(header) + " |")
	var rule := PackedStringArray()
	for i: int in header.size():
		rule.append("---")
	lines.append("| " + " | ".join(rule) + " |")
	lines.append("| " + " | ".join(row) + " |")
	return lines


## What the numbers were measured on: CPU, the cores the process may use, OS, Godot build, display, load and memory.
static func machine() -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	var memory: Dictionary = OS.get_memory_info()
	return {
		"cpu": OS.get_processor_name(),
		"logical_cores": OS.get_processor_count(),
		"cpus_allowed": _proc_status_field("Cpus_allowed_list"),
		"os": "%s %s" % [OS.get_distribution_name(), OS.get_version()],
		"godot": "%s (%s)" % [String(version.get("string", "")), String(version.get("hash", "")).left(9)],
		"display": DisplayServer.get_name(),
		"load_average": _read_proc("/proc/loadavg").strip_edges(),
		"memory_gb": float(memory.get("physical", 0)) / 1073741824.0,
	}


## Writes `summary.json` and `summary.md` into `dir_path` (made if missing). Returns "" or what went wrong.
static func write(dir_path: String, summary: Dictionary, markdown: String) -> String:
	var absolute: String = ProjectSettings.globalize_path(dir_path)
	var made: Error = DirAccess.make_dir_recursive_absolute(absolute)
	if made != OK and not DirAccess.dir_exists_absolute(absolute):
		return "cannot make %s (%s)" % [absolute, error_string(made)]
	for pair: Array in [["summary.json", JSON.stringify(summary, "  ", false)], ["summary.md", markdown]]:
		var file := FileAccess.open(absolute.path_join(String(pair[0])), FileAccess.WRITE)
		if file == null:
			return "cannot write %s (%s)" % [absolute.path_join(String(pair[0])), error_string(FileAccess.get_open_error())]
		file.store_string(String(pair[1]))
		file.close()
	return ""


static func _machine_line(m: Dictionary) -> String:
	return "%s, %d logical cores (allowed %s), %s, Godot %s, %s, load %s" % [m.get("cpu", "?"), int(m.get("logical_cores", 0)),
			m.get("cpus_allowed", "?"), m.get("os", "?"), m.get("godot", "?"), m.get("display", "?"), m.get("load_average", "?")]


static func _proc_status_field(field: String) -> String:
	for line: String in _read_proc("/proc/self/status").split("\n"):
		if line.begins_with(field + ":"):
			return line.substr(field.length() + 1).strip_edges()
	return ""


# A /proc file's text (they report no size, so they are read line by line); "" where there is none.
static func _read_proc(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var lines := PackedStringArray()
	while lines.size() < 500:
		var line: String = file.get_line()
		if file.eof_reached() and line.is_empty():
			break
		lines.append(line)
	return "\n".join(lines)


# The samples as floats: every tick, or only the ticks whose stages were timed.
static func _floats(values: PackedInt64Array, stages_on: PackedInt64Array, every_tick: bool) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i: int in values.size():
		if every_tick or (i < stages_on.size() and stages_on[i] == 1):
			out.append(float(values[i]))
	return out


static func _ms(stats: Dictionary, key: String) -> float:
	return float(stats.get(key, 0.0)) * 1e-3


static func _min_int(values: PackedInt64Array) -> int:
	var best: int = 0
	for i: int in values.size():
		best = values[i] if i == 0 else mini(best, values[i])
	return best


static func _max_int(values: PackedInt64Array) -> int:
	var best: int = 0
	for v: int in values:
		best = maxi(best, v)
	return best
