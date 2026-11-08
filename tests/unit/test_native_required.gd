extends GutTest
## The native library is required (M4-T37, Q57 and Q67): `NativeLib` names every class the game needs, says which are
## missing, and the game refuses to start without them with a clear message and exit code 1. The start is checked in a
## fresh headless process, told to require a class no library has (`--native-require=`), since this process has the
## library loaded.

const FAKE_CLASS: StringName = &"ScsNoSuchClass"


func test_every_required_class_is_registered_in_this_build() -> void:
	assert_gt(NativeLib.REQUIRED.size(), 5, "the list names the library's classes")
	assert_eq(NativeLib.missing(), PackedStringArray(), "this build registers every one of them")
	assert_eq(NativeLib.refusal(), "", "so nothing refuses")


func test_a_missing_class_is_named_with_how_to_build_the_library() -> void:
	var classes: Array[StringName] = [SimCore.NATIVE_CLASS, FAKE_CLASS]
	assert_eq(NativeLib.missing(classes), PackedStringArray([String(FAKE_CLASS)]), "only the missing class is named")
	var why: String = NativeLib.refusal(classes)
	assert_string_contains(why, String(FAKE_CLASS))
	assert_string_contains(why, "scripts/build_native.sh")
	assert_string_contains(why, "bin/libscs_native.so")
	assert_string_contains(why, "rustup", "names what the build needs")
	assert_string_contains(why, "--import", "and the import that registers the library")


func test_the_game_refuses_to_start_without_a_required_class() -> void:
	await get_tree().process_frame  # OS.execute blocks; one idle frame keeps the runner's output in order
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--",
			"--native-require=" + String(FAKE_CLASS), "--console-exec=wait 120; quit"])
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(output)
	assert_eq(code, 1, "the game exits with 1 (%s)" % text.right(400))
	assert_string_contains(text, NativeLib.refusal([FAKE_CLASS]), "and prints why")
