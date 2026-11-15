extends GutTest
## The impact flash (M4-T08, M4-T36): flashes of one colour share their quad and material (making them per hit stalled a windowed
## tick by about 7 ms), the fade stays per flash, and a hit is one node: the sparks are the particle pool's hit burst.


func test_flashes_of_one_colour_share_their_quad_and_material() -> void:
	var a: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	var b: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 2)
	add_child_autofree(a)
	add_child_autofree(b)
	assert_same(a.mesh, b.mesh, "one quad mesh for the colour")
	assert_same((a.mesh as QuadMesh).material, (b.mesh as QuadMesh).material, "one glow material")


func test_another_colour_gets_its_own_tint() -> void:
	var blue: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	var red: ImpactFlash = ImpactFlash.create(Color(3.0, 0.6, 0.3), 1)
	add_child_autofree(blue)
	add_child_autofree(red)
	var glow := (red.mesh as QuadMesh).material as StandardMaterial3D
	assert_eq(glow.albedo_color, Color(3.0, 0.6, 0.3))
	assert_eq(glow.emission, Color(3.0, 0.6, 0.3))
	assert_eq(glow.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED)
	assert_ne((red.mesh as QuadMesh).material, (blue.mesh as QuadMesh).material)


func test_the_fade_stays_per_flash() -> void:
	var a: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	var b: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	add_child_autofree(a)
	add_child_autofree(b)
	a.advance(ImpactFlash.FLASH_S * 0.5)
	assert_gt(a.transparency, 0.0, "the older flash has faded")
	assert_eq(b.transparency, 0.0, "the new one has not")


func test_a_hit_is_one_node() -> void:
	var a: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	add_child_autofree(a)
	assert_eq(a.get_child_count(true), 0, "the flash quad alone; no mesh sparks (M4-T36)")
	assert_false(a.is_processing(), "animated by the hit flashes pass")


func test_warming_makes_every_weapon_colour_and_a_first_flash_builds_nothing() -> void:
	var colours: Array[Color] = WeaponSpec.known_bolt_colors()
	var from_files: Array[Color] = []
	for file: String in DirAccess.get_files_at(WeaponSpec.WEAPON_DIR):
		if file.ends_with(".tres"):
			var spec := load("%s/%s" % [WeaponSpec.WEAPON_DIR, file]) as WeaponSpec
			if spec != null and not from_files.has(spec.bolt_color):
				from_files.append(spec.bolt_color)
	assert_gt(from_files.size(), 5, "the station grid's and the ships' weapons have their own colours")
	assert_eq(colours.size(), from_files.size(), "every spec's colour is known")
	ImpactFlash.reset_shared()
	ImpactFlash.warm(colours)
	for color: Color in from_files:
		assert_true(ImpactFlash.is_warm(color), "the quad of %s is made" % color)
	var built: int = ImpactFlash.built_count
	for color: Color in from_files:
		add_child_autofree(ImpactFlash.create(color))
	assert_eq(ImpactFlash.built_count, built, "a first flash of any colour builds no node")
