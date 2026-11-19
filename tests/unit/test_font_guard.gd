extends GutTest
## No font but the game's two (M8-T21, D87, AC17): nothing under `src/` or `data/`, no scene, theme or project setting loads or
## builds another one. The debug console alone keeps a fixed-width system font (its log is columns of commands and values).

const ROOTS: Array[String] = ["res://src", "res://data"]
const EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "cfg", "json"]
## The files that may name a font, and what each may name.
const ALLOWED: Dictionary = {
	"res://src/console/console_ui.tscn": ["SystemFont", "font_names"],
	"res://src/ui/game_fonts.gd": ["babylon5.ttf", "babylon5_credits.ttf"],
}
## What makes or loads a font. A font file's name is checked apart (`FONT_FILE`).
const FORBIDDEN: Array[String] = ["SystemFont", "FontFile", "FontVariation", "font_names", "fallback_font", "theme_override_fonts",
		"custom_font"]
const FONT_FILE: String = "\\.(ttf|otf|woff2?|fnt)\\b"


# Every source and scene file under `dir`.
func _files(dir: String, into: PackedStringArray) -> void:
	for name: String in DirAccess.get_files_at(dir):
		if EXTENSIONS.has(name.get_extension()):
			into.append(dir.path_join(name))
	for sub: String in DirAccess.get_directories_at(dir):
		_files(dir.path_join(sub), into)


# What in `text` names a font the file at `path` may not: one entry per line, as `path:line: word`.
func _offences(path: String, text: String) -> PackedStringArray:
	var allowed: Array = ALLOWED.get(path, [])
	var font_file := RegEx.create_from_string(FONT_FILE)
	var found := PackedStringArray()
	var lines: PackedStringArray = text.split("\n")
	for i: int in lines.size():
		var line: String = lines[i]
		for word: String in FORBIDDEN:
			if line.contains(word) and not allowed.has(word):
				found.append("%s:%d: %s" % [path, i + 1, word])
		for hit: RegExMatch in font_file.search_all(line):
			var named: bool = false
			for name: Variant in allowed:
				named = named or line.contains(String(name))
			if not named:
				found.append("%s:%d: %s" % [path, i + 1, hit.get_string()])
		if line.contains("add_theme_font_override") and not line.contains("GameFonts."):
			found.append("%s:%d: a font override that is not from GameFonts" % [path, i + 1])
	return found


func test_the_scan_sees_every_way_to_bring_a_font_in() -> void:
	for line: String in ["var f := SystemFont.new()", "var f := FontFile.new()", "font_names = PackedStringArray(\"Mono\")",
			"label.add_theme_font_override(&\"font\", ThemeDB.fallback_font)", "theme_override_fonts/font = SubResource(\"x\")",
			"var f: Font = load(\"res://assets/fonts/other.ttf\")", "[ext_resource type=\"FontFile\" path=\"res://a.otf\" id=\"1\"]",
			"label.add_theme_font_override(&\"font\", some_font)"]:
		assert_false(_offences("res://src/hud/x.gd", line).is_empty(), "caught: %s" % line)
	assert_true(_offences("res://src/hud/x.gd", "label.add_theme_font_override(&\"font\", GameFonts.title())").is_empty())
	assert_true(_offences("res://src/hud/x.gd", "var font: Font = GameFonts.body()\n\tdraw_string(font, at, text)").is_empty())
	assert_true(_offences("res://src/console/console_ui.tscn", "[sub_resource type=\"SystemFont\" id=\"SystemFont_mono\"]").is_empty(),
			"the console keeps its fixed-width font")
	assert_false(_offences("res://src/console/console_ui.tscn", "[ext_resource type=\"FontFile\" path=\"res://a.ttf\"]").is_empty(),
			"but no font file")


func test_no_source_or_scene_brings_in_another_font() -> void:
	var files := PackedStringArray()
	for root: String in ROOTS:
		_files(root, files)
	assert_gt(files.size(), 300, "the walk found the sources")
	var found := PackedStringArray()
	for path: String in files:
		found.append_array(_offences(path, FileAccess.get_file_as_string(path)))
	assert_eq(found, PackedStringArray(), "every font is one of the game's two")


func test_the_only_font_files_in_the_game_are_the_two() -> void:
	var fonts := PackedStringArray()
	for name: String in DirAccess.get_files_at("res://assets/fonts"):
		if not name.ends_with(".import"):
			fonts.append(name)
	fonts.sort()
	assert_eq(fonts, PackedStringArray(["babylon5.ttf", "babylon5_credits.ttf"]))
	assert_eq(GameFonts.TITLE_PATH, "res://assets/fonts/babylon5.ttf")
	assert_eq(GameFonts.BODY_PATH, "res://assets/fonts/babylon5_credits.ttf")


func test_the_project_names_no_font_of_its_own() -> void:
	var text: String = FileAccess.get_file_as_string("res://project.godot")
	assert_string_contains(text, "theme/custom=\"%s\"" % GameFonts.THEME_PATH)
	assert_false(text.contains("custom_font"), "the theme is the one place the default font is named")
