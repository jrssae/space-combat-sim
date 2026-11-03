extends GutTest
## The impact flash's resources (M4-T08): a flash made new materials and a new quad for every hit, and in a window creating them
## stalled the tick by about 7 ms on four hits in ten (the windowed hit spike of AC6). Flashes of one colour now share them, so a
## hit makes only nodes. The look is unchanged: the same material settings, the fade per instance.


func _flash_quad(flash: ImpactFlash) -> QuadMesh:
	return (flash.get_node("Flash") as MeshInstance3D).mesh as QuadMesh


func _spark_material(flash: ImpactFlash) -> Material:
	return (flash.get_node("Spark0") as MeshInstance3D).material_override


func test_flashes_of_one_colour_share_their_quad_and_materials() -> void:
	var a: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	var b: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 2)
	add_child_autofree(a)
	add_child_autofree(b)
	assert_same(_flash_quad(a), _flash_quad(b), "one quad mesh for the colour")
	assert_same(_flash_quad(a).material, _flash_quad(b).material, "one glow material")
	assert_same(_spark_material(a), _spark_material(b), "one spark material")


func test_another_colour_gets_its_own_tint() -> void:
	var blue: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	var red: ImpactFlash = ImpactFlash.create(Color(3.0, 0.6, 0.3), 1)
	add_child_autofree(blue)
	add_child_autofree(red)
	var glow := _flash_quad(red).material as StandardMaterial3D
	assert_eq(glow.albedo_color, Color(3.0, 0.6, 0.3))
	assert_eq(glow.emission, Color(3.0, 0.6, 0.3))
	assert_eq(glow.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED)
	assert_eq((_spark_material(red) as StandardMaterial3D).albedo_color, Color(3.0, 0.6, 0.3))
	assert_ne(_flash_quad(red).material, _flash_quad(blue).material)


func test_the_fade_stays_per_flash() -> void:
	var a: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	var b: ImpactFlash = ImpactFlash.create(Color(0.9, 1.5, 3.0), 1)
	add_child_autofree(a)
	add_child_autofree(b)
	a.advance(ImpactFlash.FLASH_S * 0.5)
	var flash_a := a.get_node("Flash") as MeshInstance3D
	var flash_b := b.get_node("Flash") as MeshInstance3D
	assert_gt(flash_a.transparency, 0.0, "the older flash has faded")
	assert_eq(flash_b.transparency, 0.0, "the new one has not")
