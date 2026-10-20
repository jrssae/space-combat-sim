extends GutTest
## ConsoleTokenizer syntax (architecture §6.4): whitespace, "double quotes", `;` between statements, `#` comments.

var tokenizer: ConsoleTokenizer


func before_each() -> void:
	tokenizer = ConsoleTokenizer.new()


func _split(text: String) -> Array:
	var out: Array = []
	for statement: PackedStringArray in tokenizer.split(text):
		out.append(Array(statement))
	return out


func test_whitespace_separates_tokens() -> void:
	assert_eq(_split("set  settings.stick_deadzone\t0.2"), [["set", "settings.stick_deadzone", "0.2"]])
	assert_eq(tokenizer.error, "")


func test_empty_and_blank_lines_have_no_statements() -> void:
	assert_eq(_split(""), [])
	assert_eq(_split("   \t "), [])
	assert_eq(_split(";;  ; "), [], "empty statements are dropped")


func test_double_quotes_group_a_token() -> void:
	assert_eq(_split("set targeting.selected \"NAV BRAVO\""), [["set", "targeting.selected", "NAV BRAVO"]])
	assert_eq(_split("echo \"\""), [["echo", ""]], "an empty quoted token is kept")
	assert_eq(_split("a\"b c\"d"), [["ab cd"]], "quotes join with adjacent text, shell-style")


func test_escapes_inside_quotes() -> void:
	assert_eq(_split("say \"a \\\"quoted\\\" word\""), [["say", "a \"quoted\" word"]])
	assert_eq(_split("say \"back\\\\slash\""), [["say", "back\\slash"]])
	assert_eq(_split("say \"keep \\n as is\""), [["say", "keep \\n as is"]], "only \\\" and \\\\ are escapes")


func test_semicolon_separates_statements() -> void:
	assert_eq(_split("help; set a.b 1;get a.b"), [["help"], ["set", "a.b", "1"], ["get", "a.b"]])


func test_semicolon_and_hash_inside_quotes_are_literal() -> void:
	assert_eq(_split("set x.y \"a;b # c\""), [["set", "x.y", "a;b # c"]])


func test_hash_starts_a_comment_to_end_of_line() -> void:
	assert_eq(_split("get ship.speed # how fast"), [["get", "ship.speed"]])
	assert_eq(_split("# only a comment"), [])
	assert_eq(_split("help # comment; quit"), [["help"]], "a ; inside a comment does not start a statement")
	assert_eq(_split("help # comment\nquit 1"), [["help"], ["quit", "1"]], "the comment ends at the newline")
	assert_eq(_split("a#b"), [["a"]], "# starts a comment even mid-word")


func test_newlines_separate_statements() -> void:
	assert_eq(_split("help\r\nstate\n\nquit"), [["help"], ["state"], ["quit"]])


func test_unterminated_quote_is_an_error() -> void:
	assert_eq(_split("set x.y \"open"), [])
	assert_eq(tokenizer.error, "unterminated quote")
	assert_eq(_split("help"), [["help"]], "the next split clears the error")
	assert_eq(tokenizer.error, "")


func test_join_tokens_round_trips() -> void:
	var tokens := PackedStringArray(["set", "targeting.selected", "NAV BRAVO", "", "a;b", "#x", "q\"uote", "b\\s"])
	var statements: Array[PackedStringArray] = tokenizer.split(ConsoleFormat.join_tokens(tokens))
	assert_eq(statements.size(), 1)
	assert_eq(Array(statements[0]), Array(tokens))


func test_split_for_completion_new_token() -> void:
	var split: Dictionary = ConsoleTokenizer.split_for_completion("set settings.camera_default ")
	assert_eq(Array(split["words"]), ["set", "settings.camera_default"])
	assert_eq(split["current"], "")
	assert_eq(split["head"], "")
	assert_false(split["comment"])


func test_split_for_completion_partial_token_after_semicolon() -> void:
	var split: Dictionary = ConsoleTokenizer.split_for_completion("help; get sett")
	assert_eq(split["head"], "help;")
	assert_eq(Array(split["words"]), ["get"])
	assert_eq(split["current"], "sett")


func test_split_for_completion_open_quote_and_comment() -> void:
	var split: Dictionary = ConsoleTokenizer.split_for_completion("set targeting.selected \"NAV B")
	assert_eq(split["current"], "NAV B", "an open quote still yields the partial token")
	assert_true(ConsoleTokenizer.split_for_completion("help # he")["comment"])
	assert_eq(ConsoleTokenizer.split_for_completion("")["current"], "")
