extends GutTest
## The five settings groups (M5-T45): every menu entry sits in exactly one, in the order the start screen lists them.

var schema := SettingsSchema.new()


func test_the_groups_come_in_order() -> void:
	var ids: Array[StringName] = []
	for group: Dictionary in SettingsSchema.GROUPS:
		ids.append(group["id"])
	assert_eq(ids, [&"gameplay", &"controls", &"camera_hud", &"video", &"audio"] as Array[StringName])
	assert_eq(SettingsSchema.GROUPS[2]["title"], "Camera & HUD")


func test_every_menu_entry_is_in_exactly_one_group() -> void:
	for key: StringName in schema.menu_keys():
		var holders: int = 0
		for group: Dictionary in SettingsSchema.GROUPS:
			if (group["categories"] as Array).has(schema.category_of(key)):
				holders += 1
		assert_eq(holders, 1, "%s (%s) is in one group" % [key, schema.category_of(key)])


func test_every_category_is_in_one_group_and_no_group_names_an_unknown_one() -> void:
	for category: StringName in SettingsSchema.CATEGORIES:
		assert_ne(SettingsSchema.group_of_category(category), &"", "%s falls in a group" % category)
	for group: Dictionary in SettingsSchema.GROUPS:
		for category: StringName in group["categories"]:
			assert_true(SettingsSchema.CATEGORIES.has(category), "%s is a category" % category)


func test_the_mapping_follows_the_design() -> void:
	assert_eq(SettingsSchema.categories_of_group(&"gameplay"), [&"game", &"flight"] as Array[StringName])
	assert_eq(SettingsSchema.categories_of_group(&"controls"), [&"controls"] as Array[StringName])
	assert_eq(SettingsSchema.categories_of_group(&"camera_hud"), [&"camera", &"hud"] as Array[StringName])
	assert_eq(SettingsSchema.categories_of_group(&"video"), [&"graphics"] as Array[StringName])
	assert_eq(SettingsSchema.categories_of_group(&"audio"), [&"audio"] as Array[StringName])
	assert_true(SettingsSchema.categories_of_group(&"nope").is_empty())


func test_the_groups_together_list_every_menu_key_once() -> void:
	var seen: Array[StringName] = []
	for group: Dictionary in SettingsSchema.GROUPS:
		seen.append_array(SettingsMenuModel.new(null, SettingsSchema.categories_of_group(group["id"])).visible_keys())
	seen.sort()
	var all: Array[StringName] = schema.menu_keys()
	all.sort()
	assert_eq(seen, all)
