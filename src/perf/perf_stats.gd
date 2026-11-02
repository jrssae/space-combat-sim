class_name PerfStats
extends RefCounted
## The statistics behind the many-ships benchmark (M4-T01, `docs/milestones/m4-performance-and-scale.md`, "The budget").
## Pure: medians and percentiles of a run's ticks, the budget verdict of one run, and the max-N search over a sweep.
##
## A run passes when its tick median and p99 are inside budget, no rebase tick is longer than one 60 Hz frame and the
## simulation kept up with the wall clock. A ship count passes on two runs of three; a layout's max N is the largest passing
## count in its sweep, and a sweep stops after two failing counts in a row. The headline is the lower of furball and spread.

## Simulation tick budget, microseconds: median and p99 over the measured window.
const TICK_MEDIAN_BUDGET_US: float = 8000.0
const TICK_P99_BUDGET_US: float = 12000.0
## No rebase tick may be longer than one physics frame at 60 Hz.
const REBASE_BUDGET_US: float = 1.0e6 / 60.0
## The share of wall time the simulation may fall behind over a run.
const LAG_BUDGET: float = 0.01
## Layouts that set the headline; the others are recorded.
const HEADLINE_LAYOUTS: Array[StringName] = [&"furball", &"spread"]


## The middle value (the mean of the two middle ones for an even count); 0 for no samples.
static func median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var mid: int = sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) * 0.5


## The nearest-rank percentile for `share` in 0..1: the smallest sample with at least that share of the samples at or below
## it. 0 for no samples.
static func percentile(values: PackedFloat64Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var rank: int = ceili(clampf(share, 0.0, 1.0) * float(sorted.size()) - 1e-9)
	return sorted[clampi(rank - 1, 0, sorted.size() - 1)]


static func mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for v: float in values:
		sum += v
	return sum / float(values.size())


static func max_value(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var best: float = -INF
	for v: float in values:
		best = maxf(best, v)
	return best


## How far the simulation fell behind the wall clock: the share of `wall_s` that `sim_s` did not cover (0 when it kept up).
static func lag(sim_s: float, wall_s: float) -> float:
	if wall_s <= 0.0:
		return 0.0
	return maxf(0.0, 1.0 - sim_s / wall_s)


## One run against the budget: `{"pass": bool, "failures": PackedStringArray}`, one line per budget it broke.
static func verdict(tick_median_us: float, tick_p99_us: float, rebase_max_us: float, lag_share: float) -> Dictionary:
	var failures := PackedStringArray()
	if tick_median_us > TICK_MEDIAN_BUDGET_US:
		failures.append("tick median %.2f ms over %.1f ms" % [tick_median_us * 1e-3, TICK_MEDIAN_BUDGET_US * 1e-3])
	if tick_p99_us > TICK_P99_BUDGET_US:
		failures.append("tick p99 %.2f ms over %.1f ms" % [tick_p99_us * 1e-3, TICK_P99_BUDGET_US * 1e-3])
	if rebase_max_us > REBASE_BUDGET_US + 1e-6:
		failures.append("a rebase tick took %.2f ms, over one frame (%.1f ms)" % [rebase_max_us * 1e-3, REBASE_BUDGET_US * 1e-3])
	if lag_share >= LAG_BUDGET:
		failures.append("real time not kept: %.2f %% behind the wall clock (budget under %.0f %%)" % [lag_share * 100.0,
				LAG_BUDGET * 100.0])
	return {"pass": failures.is_empty(), "failures": failures}


## The cost of B against A from blocks run alternately in one process, A first and last (A, B, A, ..., B, A): the median over
## the B blocks of the mean of the two neighbouring A medians minus the B median. A steady drift of the machine cancels out.
## 0 unless there is exactly one more A block than B blocks.
static func paired_difference(a_block_medians: PackedFloat64Array, b_block_medians: PackedFloat64Array) -> float:
	if b_block_medians.is_empty() or a_block_medians.size() != b_block_medians.size() + 1:
		return 0.0
	var differences := PackedFloat64Array()
	for i: int in b_block_medians.size():
		differences.append((a_block_medians[i] + a_block_medians[i + 1]) * 0.5 - b_block_medians[i])
	return median(differences)


## Passing runs a ship count needs: two of three (rounded up for other counts).
static func runs_needed(runs: int) -> int:
	return maxi(1, ceili(float(runs) * 2.0 / 3.0 - 1e-9))


## Whether a ship count passes, from its runs' verdicts.
static func count_passes(run_passes: Array) -> bool:
	if run_passes.is_empty():
		return false
	var passed: int = 0
	for p: Variant in run_passes:
		passed += 1 if bool(p) else 0
	return passed >= runs_needed(run_passes.size())


## The largest passing ship count of a sweep (`{n: [run passes]}`), 0 when none passes.
static func max_n(results: Dictionary) -> int:
	var best: int = 0
	for n: Variant in results:
		if count_passes(results[n] as Array):
			best = maxi(best, int(n))
	return best


## Whether a sweep that has measured `ns_in_order` (ascending, as run) should stop: its last two ship counts both failed.
static func should_stop(ns_in_order: Array, results: Dictionary) -> bool:
	if ns_in_order.size() < 2:
		return false
	for n: Variant in ns_in_order.slice(ns_in_order.size() - 2):
		if count_passes(results.get(n, []) as Array):
			return false
	return true


## The milestone's headline number: the lowest max N over `HEADLINE_LAYOUTS` (`{layout: max N}`); 0 if one is missing.
static func headline(max_by_layout: Dictionary) -> int:
	var lowest: int = -1
	for layout: StringName in HEADLINE_LAYOUTS:
		if not max_by_layout.has(layout):
			return 0
		var n: int = int(max_by_layout[layout])
		lowest = n if lowest < 0 else mini(lowest, n)
	return maxi(lowest, 0)
