class_name ConsoleTokenizer
extends RefCounted
## Console command syntax (architecture §6.4), pure:
## - whitespace separates tokens; "double quotes" group a token (`\"` and `\\` escape inside quotes);
## - `;` or a newline separates statements; empty statements are dropped;
## - `#` outside quotes starts a comment that runs to the end of the line.
## There is no other syntax: no variables, no expansion, no nesting.

## Why the last `split` failed, empty when it succeeded.
var error: String = ""


## Splits text into statements, each a list of tokens. On a syntax error returns [] and sets `error`.
func split(text: String) -> Array[PackedStringArray]:
	error = ""
	var statements: Array[PackedStringArray] = []
	var tokens := PackedStringArray()
	var current: String = ""
	var in_token: bool = false
	var in_quotes: bool = false
	var i: int = 0
	var n: int = text.length()
	while i < n:
		var c: String = text[i]
		if in_quotes:
			if c == "\\" and i + 1 < n and (text[i + 1] == "\"" or text[i + 1] == "\\"):
				current += text[i + 1]
				i += 2
				continue
			if c == "\"":
				in_quotes = false
			else:
				current += c
		elif c == "\"":
			in_quotes = true
			in_token = true
		elif c == ";" or c == "\n":
			if in_token:
				tokens.append(current)
			current = ""
			in_token = false
			if not tokens.is_empty():
				statements.append(tokens)
			tokens = PackedStringArray()
		elif c == "#":
			var newline: int = text.find("\n", i)
			i = n if newline == -1 else newline
			continue
		elif _is_space(c):
			if in_token:
				tokens.append(current)
			current = ""
			in_token = false
		else:
			current += c
			in_token = true
		i += 1
	if in_quotes:
		error = "unterminated quote"
		return []
	if in_token:
		tokens.append(current)
	if not tokens.is_empty():
		statements.append(tokens)
	return statements


## Lenient split of a partly typed line for Tab completion. Never fails. Returns:
## `head` (text before the statement being typed, e.g. "help; "), `words` (complete tokens of that statement),
## `current` (the token being typed, "" when the line ends in whitespace) and `comment` (true if the cursor is
## inside a comment, where nothing completes).
static func split_for_completion(text: String) -> Dictionary:
	var in_quotes: bool = false
	var statement_start: int = 0
	var i: int = 0
	while i < text.length():
		var c: String = text[i]
		if in_quotes:
			if c == "\\":
				i += 1  # skip the escaped character
			elif c == "\"":
				in_quotes = false
		elif c == "\"":
			in_quotes = true
		elif c == ";" or c == "\n":
			statement_start = i + 1
		elif c == "#":
			return {"head": text, "words": PackedStringArray(), "current": "", "comment": true}
		i += 1
	var head: String = text.substr(0, statement_start)
	var body: String = text.substr(statement_start)
	var ends_open: bool = body.is_empty() or _is_space(body[body.length() - 1])
	if in_quotes:
		ends_open = false
		body += "\""  # close it so the partial token survives the split
	var tokenizer := ConsoleTokenizer.new()
	var statements: Array[PackedStringArray] = tokenizer.split(body)
	var words := PackedStringArray()
	if not statements.is_empty():
		words = statements[0]
	var current: String = ""
	if not ends_open and not words.is_empty():
		current = words[words.size() - 1]
		words.remove_at(words.size() - 1)
	return {"head": head, "words": words, "current": current, "comment": false}


static func _is_space(c: String) -> bool:
	return c == " " or c == "\t" or c == "\r"
