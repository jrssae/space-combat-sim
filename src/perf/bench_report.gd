class_name BenchReport
extends RefCounted
## The benchmark's written record (M4-T01): a run's and a sweep's `summary.json` and `summary.md`. Stage numbers are per tick
## in microseconds; means add up to the mean tick, so breakdowns use them, while medians and p99 are the budget's view. Only
## `machine` and `write` touch the system.

## Stages in the order a breakdown lists them; `tick` is their total.
const BREAKDOWN: Array[StringName] = [&"ai", &"flight", &"targeting", &"resolvers", &"late", &"physics", &"other"]
## Inside other stages, listed beside them (the stand-ins, M4-T07, inside flight).
const INSIDE: Array[StringName] = [&"scan", &"think", &"hit", &"ram", &"rebase", &"sync", &"standins"]
## Probe fields that count things rather than time them.
const COUNTS: Array[StringName] = [&"ships", &"bolts", &"pairs", &"stages_on", &"sync_on", &"fighters_near", &"fighters_far",
		&"capitals", &"turrets", &"interceptors", &"beams", &"missiles", &"mines", &"asteroids", &"launches", &"sides",
		&"tier_fighters", &"tier_capitals"]
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
		if field in COUNTS:
			continue
		# The tick, the engine's part and the remainder are timed in every tick; the stages only where their markers ran.
		var every_tick: bool = field in [&"tick", &"physics", &"sync"]
		stages[String(field)] = stage_stats(_floats(series[i], on, every_tick))
	# The rebase budget is on the whole tick that held a rebase; the shift's own cost is recorded beside it.
	var shifts := PackedFloat64Array()
	var rebase_ticks := PackedFloat64Array()
	var rebase_series: PackedInt64Array = series[PerfProbe.Field.REBASE]
	for i: int in rebase_series.size():
		if rebase_series[i] > 0:
			shifts.append(float(rebase_series[i]))
			rebase_ticks.append(float(series[PerfProbe.Field.TICK][i]))
	var ships: PackedInt64Array = series[PerfProbe.Field.SHIPS]
	var tick: Dictionary = stages["tick"]
	var lag_share: float = PerfStats.lag(float(meta.get("sim_s", 0.0)), float(meta.get("wall_s", 0.0)))
	var verdict: Dictionary = PerfStats.verdict(tick["median_us"], tick["p99_us"], PerfStats.max_value(rebase_ticks), lag_share)
	var failures: PackedStringArray = verdict["failures"]  # a packed array is a value: changed here, stored back below
	var aborted: String = String(meta.get("aborted", ""))
	if not aborted.is_empty():
		failures.append("aborted: " + aborted)
	var out: Dictionary = meta.duplicate()
	out["ticks"] = series[PerfProbe.Field.TICK].size()
	out["lag"] = lag_share
	out["stages"] = stages
	out["rebase"] = {"count": shifts.size(), "tick_max_us": PerfStats.max_value(rebase_ticks),
			"tick_median_us": PerfStats.median(rebase_ticks), "shift_max_us": PerfStats.max_value(shifts),
			"shift_median_us": PerfStats.median(shifts), "threshold_m": meta.get("rebase_threshold_m", 0.0)}
	out["sync_timed_share"] = PerfStats.mean(_floats(series[PerfProbe.Field.SYNC_ON], on, true))
	out["ships_min"] = _min_int(ships)
	out["ships_max"] = _max_int(ships)
	out["bolts_mean"] = PerfStats.mean(_floats(series[PerfProbe.Field.BOLTS], on, true))
	out["pairs_mean"] = PerfStats.mean(_floats(series[PerfProbe.Field.PAIRS], on, true))
	out["entities"] = entity_counts(series)
	out["verdict"] = {"pass": failures.is_empty(), "failures": Array(failures)}
	return out


## A run's summary as a short Markdown page.
static func run_markdown(s: Dictionary) -> String:
	var lines := PackedStringArray()
	var verdict: Dictionary = s.get("verdict", {})
	lines.append("# Bench %s, %d ships (seed %d)" % [s.get("layout", "?"), int(s.get("n", 0)), int(s.get("seed", 0))])
	lines.append("")
	lines.append("N counts the layout's ships; the player flies too, so %d ships were in play." % int(s.get("ships_max", 0)))
	lines.append("")
	lines.append("Verdict: **%s**%s" % ["pass" if bool(verdict.get("pass", false)) else "fail",
			("; " + "; ".join(PackedStringArray(verdict.get("failures", [])))) if not (verdict.get("failures", []) as Array).is_empty() else ""])
	lines.append("")
	var tick: Dictionary = (s.get("stages", {}) as Dictionary).get("tick", {})
	var rebase: Dictionary = s.get("rebase", {})
	lines.append("Tick: median %.2f ms, p99 %.2f ms, max %.2f ms over %d ticks; real time kept: %.2f %% behind; %d rebases (worst tick holding one %.2f ms, the shift alone at most %.2f ms); load %.0f ms; ships in play %d to %d; bolts %.0f on average" % [
			_ms(tick, "median_us"), _ms(tick, "p99_us"), _ms(tick, "max_us"), int(s.get("ticks", 0)), float(s.get("lag", 0.0)) * 100.0,
			int(rebase.get("count", 0)), float(rebase.get("tick_max_us", 0.0)) * 1e-3, float(rebase.get("shift_max_us", 0.0)) * 1e-3,
			float(s.get("load_ms", 0.0)), int(s.get("ships_min", 0)), int(s.get("ships_max", 0)), float(s.get("bolts_mean", 0.0))])
	if s.has("mix"):
		lines.append("")
		lines.append("Mix asked for: %s" % String(s.get("mix_line", "")))
	var entities: Dictionary = s.get("entities", {})
	if int(entities.get("capitals", 0)) > 0 or int(entities.get("asteroids", 0)) > 0:
		lines.append("")
		lines.append("Entities (mean per tick; launches in the window): %s" % entity_line(entities))
	var weapons: Dictionary = s.get("weapons", {})
	if not weapons.is_empty():
		lines.append("")
		lines.append("Weapons over the measured window (M4-T12): %d missiles launched, %d shot down, %d beam shots, %d mines set off; stand-in parts per tick: %s; missile steering %.1f us." % [
				int(weapons.get("missile_launches", 0)), int(weapons.get("missile_intercepts", 0)), int(weapons.get("beam_shots", 0)),
				int(weapons.get("detonations", 0)), _parts_line(weapons.get("parts_us", {}) as Dictionary),
				float(weapons.get("missile_steer_us", 0.0))])
		var tier: Dictionary = weapons.get("tier", {})
		if not tier.is_empty() and float(tier.get("fighter_rows", 0.0)) + float(tier.get("capital_rows", 0.0)) > 0.0:
			lines.append("")
			lines.append("The tier over the measured window (M4-T22): main-thread cost %.1f us a tick for %.0f fighter rows (%.3f us each: the integration, their rolls, the landing) and %.1f us for %.0f capital rows (%.2f us each: their rolls); %d fighter shots rolled, %d hits landed; %d far-capital hits landed." % [
					float(tier.get("fighters_us", 0.0)), float(tier.get("fighter_rows", 0.0)), float(tier.get("per_fighter_us", 0.0)),
					float(tier.get("capitals_us", 0.0)), float(tier.get("capital_rows", 0.0)), float(tier.get("per_capital_us", 0.0)),
					int(tier.get("shots", 0)), int(tier.get("hits", 0)), int(weapons.get("tier_capital_hits", 0))])
	lines.append("")
	lines.append_array(_breakdown_table(s.get("stages", {}) as Dictionary, float(s.get("sync_timed_share", 0.0))))
	var engine: Dictionary = s.get("engine_check", {})
	if not engine.is_empty():
		lines.append("")
		lines.append("Engine check (worst tick of each second against the probe's worst of each 60 ticks, medians): the engine's %.2f ms, the probe's %.2f ms; they should agree within noise." % [
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
static func _breakdown_table(stages: Dictionary, sync_share: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var tick: Dictionary = stages.get("tick", {})
	var total: float = maxf(float(tick.get("mean_us", 0.0)), 1e-9)
	lines.append("| stage | mean ms | share | median ms | p99 ms |")
	lines.append("|---|---|---|---|---|")
	for name: StringName in BREAKDOWN + INSIDE:
		var st: Dictionary = stages.get(String(name), {})
		var label: String = _label(name, sync_share)
		lines.append("| %s | %.3f | %.1f %% | %.3f | %.3f |" % [label, _ms(st, "mean_us"), 100.0 * float(st.get("mean_us", 0.0)) / total,
				_ms(st, "median_us"), _ms(st, "p99_us")])
	lines.append("| **tick** | %.3f | 100 %% | %.3f | %.3f |" % [_ms(tick, "mean_us"), _ms(tick, "median_us"), _ms(tick, "p99_us")])
	return lines


## What a run held per entity type (M4-T07): each count's mean per tick, rounded, and the launches summed over the window.
static func entity_counts(series: Array[PackedInt64Array]) -> Dictionary:
	var out: Dictionary = {}
	for field: StringName in PerfProbe.ENTITY_FIELDS:
		var values: PackedInt64Array = series[PerfProbe.FIELD_NAMES.find(field)]
		var total: int = 0
		for v: int in values:
			total += v
		if field == &"launches":
			out[String(field)] = total
		else:
			out[String(field)] = roundi(float(total) / float(values.size())) if not values.is_empty() else 0
	return out


## The entity counts as one line, in `PerfProbe.ENTITY_FIELDS` order.
static func _parts_line(parts: Dictionary) -> String:
	var out := PackedStringArray()
	for key: String in parts:
		out.append("%s %.0f us" % [key.replace("_", " "), float(parts[key])])
	return ", ".join(out)


static func entity_line(entities: Dictionary) -> String:
	var parts := PackedStringArray()
	for field: StringName in PerfProbe.ENTITY_FIELDS:
		parts.append("%s %d" % [String(field).replace("_", " "), int(entities.get(String(field), 0))])
	return ", ".join(parts)


## A sweep's summary from its runs' summaries: per layout and ship count the runs, their verdicts and the medians over runs,
## each layout's max N and whether it stopped, and the headline.
## `expected_runs` (0: whatever was found) counts a missing run, one that crashed or was killed, as a failure.
static func sweep_summary(runs: Array[Dictionary], meta: Dictionary = {}, expected_runs: int = 0) -> Dictionary:
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
			# A dead run's placeholder (`missing`) and a run with no file at all both count as failed, and neither has a tick.
			var list: Array[Dictionary] = []
			var dead: int = 0
			for run: Dictionary in by_n[n]:
				if bool(run.get("missing", false)):
					dead += 1
				else:
					list.append(run)
			var passes: Array = []
			for run: Dictionary in list:
				passes.append(bool((run.get("verdict", {}) as Dictionary).get("pass", false)))
			var missing: int = dead + maxi(0, expected_runs - list.size() - dead)
			for i: int in missing:
				passes.append(false)
			results[n] = passes
			counts.append(_count_entry(n, list, passes, missing))
		var best: int = PerfStats.max_n(results)
		max_by_layout[StringName(layout)] = best
		layouts[layout] = {"max_n": best, "stopped": PerfStats.should_stop(ns, results), "counts": counts}
	var out: Dictionary = meta.duplicate()
	out["expected_runs"] = expected_runs
	out["layouts"] = layouts
	out["headline_max_n"] = PerfStats.headline(max_by_layout)
	return out


# One ship count of a sweep: its runs' verdicts and the medians over them.
static func _count_entry(n: int, runs: Array[Dictionary], passes: Array, missing: int) -> Dictionary:
	var medians := PackedFloat64Array()
	var p99s := PackedFloat64Array()
	var lags := PackedFloat64Array()
	var loads := PackedFloat64Array()
	var rebase_worst: float = 0.0
	var shift_worst: float = 0.0
	var failures: Array = []
	var stage_means: Dictionary = {}
	for run: Dictionary in runs:
		var stages: Dictionary = run.get("stages", {})
		var tick: Dictionary = stages.get("tick", {})
		medians.append(float(tick.get("median_us", 0.0)))
		p99s.append(float(tick.get("p99_us", 0.0)))
		lags.append(float(run.get("lag", 0.0)))
		loads.append(float(run.get("load_ms", 0.0)))
		rebase_worst = maxf(rebase_worst, float((run.get("rebase", {}) as Dictionary).get("tick_max_us", 0.0)))
		shift_worst = maxf(shift_worst, float((run.get("rebase", {}) as Dictionary).get("shift_max_us", 0.0)))
		failures.append_array((run.get("verdict", {}) as Dictionary).get("failures", []))
		for name: StringName in [&"tick"] + BREAKDOWN + INSIDE:
			# A packed array is a value: take it, add to it, store it back.
			var means: PackedFloat64Array = stage_means.get(String(name), PackedFloat64Array())
			means.append(float((stages.get(String(name), {}) as Dictionary).get("mean_us", 0.0)))
			stage_means[String(name)] = means
	var breakdown: Dictionary = {}
	for key: String in stage_means:
		breakdown[key] = PerfStats.median(stage_means[key] as PackedFloat64Array)
	var entities: Dictionary = {}
	for field: StringName in PerfProbe.ENTITY_FIELDS:
		var values := PackedFloat64Array()
		for run: Dictionary in runs:
			values.append(float((run.get("entities", {}) as Dictionary).get(String(field), 0)))
		entities[String(field)] = roundi(PerfStats.median(values))
	var run_medians: Array = Array(medians)
	return {
		"n": n,
		"runs": passes.size(),
		"missing": missing,
		"passes": passes.count(true),
		"pass": PerfStats.count_passes(passes),
		"tick_median_us": PerfStats.median(medians),
		"tick_p99_us": PerfStats.median(p99s),
		"tick_median_spread_us": [PerfStats.percentile(medians, 0.0), PerfStats.percentile(medians, 1.0)],
		"run_tick_medians_us": run_medians,
		"lag": PerfStats.median(lags),
		"rebase_tick_max_us": rebase_worst,
		"rebase_shift_max_us": shift_worst,
		"load_ms": PerfStats.median(loads),
		"stage_means_us": breakdown,
		"entities": entities,
		"failures": failures,
	}


## A sweep's summary as Markdown: the max N per layout, every ship count measured, and the stage breakdown at 50 and 100.
static func sweep_markdown(s: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("# Bench sweep %s" % s.get("label", ""))
	lines.append("")
	lines.append("Headline max N (battle's when it was measured, M4-T07; else the lower of furball and spread): **%d**" % int(s.get("headline_max_n", 0)))
	lines.append("")
	var layouts: Dictionary = s.get("layouts", {})
	for layout: String in layouts:
		var entry: Dictionary = layouts[layout]
		lines.append("## %s: max N %d%s" % [layout, int(entry.get("max_n", 0)), " (stopped after two failing counts)" if bool(entry.get("stopped", false)) else ""])
		lines.append("")
		lines.append("| N | runs passed | tick median ms (runs) | p99 ms | behind real time | worst rebase tick ms | worst shift ms | load s |")
		lines.append("|---|---|---|---|---|---|---|---|")
		for c: Dictionary in entry.get("counts", []):
			var run_medians := PackedStringArray()
			for us: Variant in c.get("run_tick_medians_us", []):
				run_medians.append("%.2f" % (float(us) * 1e-3))
			var verdict_text: String = ("pass" if bool(c["pass"]) else "fail") + (" (%d missing)" % int(c["missing"]) if int(c.get("missing", 0)) > 0 else "")
			lines.append("| %d | %d/%d %s | %.2f (%s) | %.2f | %.2f %% | %.2f | %.2f | %.1f |" % [int(c["n"]), int(c["passes"]), int(c["runs"]),
					verdict_text, float(c["tick_median_us"]) * 1e-3, ", ".join(run_medians), float(c["tick_p99_us"]) * 1e-3,
					float(c["lag"]) * 100.0, float(c["rebase_tick_max_us"]) * 1e-3, float(c["rebase_shift_max_us"]) * 1e-3, float(c["load_ms"]) * 1e-3])
		lines.append("")
		var with_entities: bool = false
		for c: Dictionary in entry.get("counts", []):
			with_entities = with_entities or int((c.get("entities", {}) as Dictionary).get("capitals", 0)) > 0
		if with_entities:
			lines.append("Entities per ship count (median over runs of each run's mean per tick; launches per window):")
			lines.append("")
			var header := PackedStringArray(["N"])
			var rule := PackedStringArray(["---"])
			for field: StringName in PerfProbe.ENTITY_FIELDS:
				header.append(String(field).replace("_", " "))
				rule.append("---")
			lines.append("| " + " | ".join(header) + " |")
			lines.append("| " + " | ".join(rule) + " |")
			for c: Dictionary in entry.get("counts", []):
				var row := PackedStringArray([str(int(c["n"]))])
				for field: StringName in PerfProbe.ENTITY_FIELDS:
					row.append(str(int((c.get("entities", {}) as Dictionary).get(String(field), 0))))
				lines.append("| " + " | ".join(row) + " |")
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
		var label: String = _label(name, -1.0)
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
		"godot_binary": "%s (%s, %s)" % [OS.get_executable_path(), "editor build" if OS.has_feature("editor") else "export template",
				"debug" if OS.is_debug_build() else "release"],
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


# A stage's name in a table: inside stages in brackets, the remainder named as unaccounted, the sync marked as a lower bound
# when some ticks ran back to back (its share of timed ticks, -1 when unknown).
static func _label(name: StringName, sync_share: float) -> String:
	if name == &"other":
		return "other (unaccounted)"
	if name == &"sync":
		return "(sync, lower bound)" if sync_share < 0.0 else "(sync, timed in %.0f %% of ticks%s)" % [sync_share * 100.0,
				"" if sync_share > 0.999 else ": a lower bound"]
	return "(%s)" % name if name in INSIDE else String(name)


static func _machine_line(m: Dictionary) -> String:
	return "%s, %d logical cores (allowed %s), %s, Godot %s, %s, %s, load %s" % [m.get("cpu", "?"), int(m.get("logical_cores", 0)),
			m.get("cpus_allowed", "?"), m.get("os", "?"), m.get("godot", "?"), m.get("godot_binary", "?"), m.get("display", "?"),
			m.get("load_average", "?")]


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
