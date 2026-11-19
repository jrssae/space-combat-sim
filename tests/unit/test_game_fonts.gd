extends GutTest
## The game's two fonts (M8-T21, D87, AC17): they load, cover what the UI prints, the project theme hands them to every control,
## and a changing number keeps its width (fixed digit slots).

const FrontEndTheme: Theme = preload("res://src/frontend/theme.tres")
## Everything the UI prints beyond ASCII: the HUD's degrees, the menus' separator, ellipsis and dash.
const EXTRA: String = "°·…—"


func _has_outline(font: Font, code: int) -> bool:
	return font.get_char_size(code, 32).x > 0.0


func test_both_fonts_load_under_their_names() -> void:
	assert_eq(GameFonts.title().get_font_name(), "Babylon5")
	assert_eq(GameFonts.body().get_font_name(), "Babylon5Credits")
	assert_same(GameFonts.body(), GameFonts.body(), "one shared resource")


func test_both_fonts_cover_ascii() -> void:
	for font: Font in [GameFonts.title(), GameFonts.body()]:
		var missing: String = ""
		for code: int in range(0x20, 0x7F):
			if not font.has_char(code) or not _has_outline(font, code):
				missing += char(code)
		assert_eq(missing, "", "%s draws every ASCII character" % font.get_font_name())


func test_the_body_font_covers_the_symbols_the_ui_prints() -> void:
	for i: int in EXTRA.length():
		assert_true(GameFonts.body().has_char(EXTRA.unicode_at(i)), "Babylon5Credits has %s" % EXTRA[i])
		assert_true(_has_outline(GameFonts.body(), EXTRA.unicode_at(i)), "%s has a width" % EXTRA[i])


func test_the_fonts_have_their_own_lowercase() -> void:
	for font: Font in [GameFonts.title(), GameFonts.body()]:
		assert_ne(font.get_char_size("a".unicode_at(0), 64).x, font.get_char_size("A".unicode_at(0), 64).x,
				"%s: a is not A again" % font.get_font_name())


# --- the theme ----------------------------------------------------------------------------------------------------------


func test_the_project_theme_is_the_games() -> void:
	assert_eq(String(ProjectSettings.get_setting("gui/theme/custom")), GameFonts.THEME_PATH)
	assert_eq(String(ProjectSettings.get_setting("gui/theme/custom_font", "")), "", "the theme names the font, nothing else does")
	var theme: Theme = ThemeDB.get_project_theme()
	assert_same(theme, load(GameFonts.THEME_PATH), "the engine's project theme is that file")
	assert_eq(theme.default_font.resource_path, GameFonts.BODY_PATH, "the Fonts autoload filled it in")
	for variation: StringName in GameFonts.TITLE_VARIATIONS:
		assert_eq(theme.get_type_variation_base(variation), &"Label", "%s is a label" % variation)
		assert_eq(theme.get_font(&"font", variation).resource_path, GameFonts.TITLE_PATH, "%s is in Babylon5" % variation)


func test_the_themes_file_names_no_font_so_a_fresh_checkout_imports_cleanly() -> void:
	# The engine loads the project theme before the first import; a font file named there cannot be loaded yet (CI saw
	# "Parse Error: referenced non-existent resource").
	var text: String = FileAccess.get_file_as_string(GameFonts.THEME_PATH)
	assert_false(text.contains("ext_resource"), "nothing to load with it")
	assert_false(text.contains(".ttf"))
	assert_string_contains(FileAccess.get_file_as_string("res://project.godot"), "[autoload]\n\nFonts=\"*res://src/autoload/fonts.gd\"",
			"and the fonts go in first thing at start")


func test_installing_again_changes_nothing() -> void:
	var theme: Theme = ThemeDB.get_project_theme()
	var body: Font = theme.default_font
	GameFonts.install()
	assert_same(theme.default_font, body)
	assert_same(theme.get_font(&"font", &"Title"), GameFonts.title())


func test_any_control_gets_the_body_font_and_a_title_the_title_font() -> void:
	var label := Label.new()
	var button := Button.new()
	var rich := RichTextLabel.new()
	var title := Label.new()
	title.theme_type_variation = &"Title"
	for control: Control in [label, button, rich, title]:
		add_child_autofree(control)
	assert_eq(label.get_theme_font(&"font").resource_path, GameFonts.BODY_PATH)
	assert_eq(button.get_theme_font(&"font").resource_path, GameFonts.BODY_PATH)
	assert_eq(rich.get_theme_font(&"normal_font").resource_path, GameFonts.BODY_PATH)
	assert_eq(label.get_theme_default_font().resource_path, GameFonts.BODY_PATH, "what code that draws on a control gets")
	assert_eq(title.get_theme_font(&"font").resource_path, GameFonts.TITLE_PATH)


func test_the_menus_theme_keeps_its_sizes_and_takes_the_fonts() -> void:
	var frame := Control.new()
	frame.theme = FrontEndTheme
	add_child_autofree(frame)
	var sizes: Dictionary = {&"Title": 34, &"Headline": 24, &"Heading": 18}
	for variation: StringName in sizes:
		var label := Label.new()
		label.theme_type_variation = variation
		frame.add_child(label)
		assert_eq(label.get_theme_font(&"font").resource_path, GameFonts.TITLE_PATH, "%s under the menus' theme" % variation)
		assert_eq(label.get_theme_font_size(&"font_size"), int(sizes[variation]))
	var body := Label.new()
	frame.add_child(body)
	assert_eq(body.get_theme_font(&"font").resource_path, GameFonts.BODY_PATH)
	assert_eq(body.get_theme_font_size(&"font_size"), 22)


# --- digit slots --------------------------------------------------------------------------------------------------------


func test_a_text_is_cut_where_digits_start_and_stop() -> void:
	assert_eq(GameFonts.pieces_of("HULL"), PackedStringArray(["HULL"]))
	assert_eq(GameFonts.pieces_of(""), PackedStringArray([""]))
	assert_eq(GameFonts.pieces_of("42"), PackedStringArray(["", "42"]))
	assert_eq(GameFonts.pieces_of("8.07 km  +61 m/s"), PackedStringArray(["", "8", ".", "07", " km  +", "61", " m/s"]))
	assert_eq(GameFonts.pieces_of("ALPHA 2"), PackedStringArray(["ALPHA ", "2"]))


func test_the_fonts_digits_are_not_one_width() -> void:
	var font: Font = GameFonts.body()
	assert_lt(font.get_char_size("1".unicode_at(0), 32).x, font.get_char_size("0".unicode_at(0), 32).x * 0.75,
			"the reason for the slots: 1 is far narrower than 0")


func test_a_number_keeps_its_width_whatever_its_digits() -> void:
	var font: Font = GameFonts.body()
	for px: int in [13, 18, 36]:
		var width: float = GameFonts.line_width(font, "111 m/s", px)
		for text: String in ["888 m/s", "104 m/s", "970 m/s"]:
			assert_almost_eq(GameFonts.line_width(font, text, px), width, 0.01, "%s at %d px" % [text, px])
		assert_almost_eq(GameFonts.line_width(font, "1111 m/s", px) - width, GameFonts.digit_slot(font, px), 0.01, "a digit more is a slot more")


func test_a_slot_is_as_wide_as_a_zero() -> void:
	var font: Font = GameFonts.body()
	assert_almost_eq(GameFonts.digit_slot(font, 20), font.get_char_size("0".unicode_at(0), 20).x, 0.001)
	assert_almost_eq(GameFonts.line_width(font, "1", 20), GameFonts.digit_slot(font, 20), 0.001)


func test_a_text_without_digits_is_as_wide_as_the_font_makes_it() -> void:
	var font: Font = GameFonts.body()
	assert_almost_eq(GameFonts.line_width(font, "NO TARGET", 20), font.get_string_size("NO TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x, 0.001)
	assert_eq(GameFonts.line_width(font, "", 20), 0.0)
