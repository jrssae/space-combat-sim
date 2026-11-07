extends GutTest
## The weapon rows in a real battle (M4-T20, Q22): a seeded 30 s `battle` at 100 ships on the real main scene, once with the
## turrets, interceptors, beams, missiles and mines on the native rows: the hits the stand-ins' weapons land (bolts, beams
## and missiles shot by capitals), every hit of the battle, and the beams, launches, kills and detonations come out within
## 10 % of the GDScript stand-ins' battle, recorded before M4-T37 removed them (`tests/fixtures/parity/`). A battle on the main
## scene does not repeat exactly between runs (847 hits against 856, fix round 1's controls), so it is held to Q22's
## tolerance, not to equality. Skips, saying why, without the native library.

const NATIVE_CLASS: StringName = &"ScsWeaponRows"
const ROOT: String = "user://test_weapon_rows_battle"
const SECONDS: float = 30.0

var main: Main
var _hits: int = 0
var _capital_hits: int = 0


# A slow file (M4-T36, Q58): runs with GUT_SLOW=1 (the full run and CI), skipped in focused runs.
@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()
	Factions.reset()


const FIXTURE: String = "weapon_rows_battle"


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no weapon kernels to test")
	return true


# One seeded battle on a fresh main scene: [every hit, capitals' hits, beam shots, launches, missiles shot down, mines set off].
func _battle() -> Array:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	add_child(main)
	main.bench.report_root = ROOT
	for i: int in 2:
		await get_tree().physics_frame
	_hits = 0
	_capital_hits = 0
	var resolver := main.get_node("Combat/HitResolver") as HitResolver
	resolver.hit_resolved.connect(_on_hit)
	var label: String = "native"
	var result: ConsoleResult = DebugConsole.registry.execute("bench battle 100 %d warmup=0 seed=1 label=%s" % [SECONDS, label])[0]
	assert_true(result.ok, result.text())
	await wait_for_signal(main.bench.finished, 240.0, "the battle finishes")
	assert_eq(main.bench.standins.weapons_path(), &"native", "the weapons ran on the native rows")
	var summary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT.path_join(label).path_join("summary.json")))
	var weapons: Dictionary = summary.get("weapons", {})
	var out: Array = [_hits, _capital_hits, int(weapons.get("beam_shots", 0)), int(weapons.get("missile_launches", 0)),
			int(weapons.get("missile_intercepts", 0)), int(weapons.get("detonations", 0))]
	resolver.hit_resolved.disconnect(_on_hit)
	remove_child(main)
	main.queue_free()
	await get_tree().physics_frame
	return out


func _on_hit(info: HitInfo) -> void:
	_hits += 1
	var shooter := instance_from_id(info.shooter_id) as Node if is_instance_id_valid(info.shooter_id) else null
	if shooter is CapitalStandin:
		_capital_hits += 1


func test_a_seeded_battle_lands_the_same_hits_within_ten_percent_on_both_paths() -> void:
	if _skipped():
		return
	# The GDScript stand-ins' battle, recorded before M4-T37 removed them.
	var recorded: Variant = ParityFixture.stored(FIXTURE, "battle_100_seed_1")
	assert_not_null(recorded, "the GDScript stand-ins' battle was recorded")
	if recorded == null:
		return
	var gdscript: Array = []
	for count: Variant in recorded:
		gdscript.append(int(count))
	var native: Array = await _battle()
	var names: Array[String] = ["hits", "capitals' hits", "beam shots", "launches", "missiles shot down", "mines set off"]
	gut.p("battle 100, %d s, seed 1: GDScript %s, native %s" % [SECONDS, gdscript, native])
	assert_gt(int(gdscript[1]), 20, "the stand-ins' weapons landed hits: %s" % [gdscript])
	for i: int in names.size():
		var a: int = gdscript[i]
		var b: int = native[i]
		assert_lte(absi(a - b), maxi(1, ceili(0.1 * maxi(a, b))), "%s within 10 %%: %d against %d" % [names[i], a, b])
