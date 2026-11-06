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
