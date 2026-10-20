class_name ConsoleCommand
extends RefCounted
## A console command's declaration (architecture §6.4): name, one-line summary and typed arguments. The handler
## and owner are given to `ConsoleRegistry.register_command` alongside it.
##
## Handlers take one `Dictionary` (argument name -> typed value; omitted optional arguments hold their fallback)
## and return a ConsoleResult, a String / PackedStringArray of output lines, or null. Errors are
## `ConsoleResult.failure("...")`.

var name: StringName
var summary: String
var args: Array[ConsoleArg] = []


func _init(p_name: StringName, p_summary: String, p_args: Array[ConsoleArg] = []) -> void:
	name = p_name
	summary = p_summary
	args = p_args


## "set <path> <value>", "fps [on|off]".
func usage() -> String:
	var parts := PackedStringArray([String(name)])
	for arg: ConsoleArg in args:
		parts.append(arg.usage())
	return " ".join(parts)


func help_lines() -> PackedStringArray:
	return PackedStringArray(["usage: " + usage(), "  " + summary])


## The argument that the token at `index` (0 = first token after the command name) belongs to, or null.
func arg_for_token(tokens: PackedStringArray, index: int) -> ConsoleArg:
	var position: int = 0
	for arg: ConsoleArg in args:
		if arg.rest:
			return arg
		var span: int = 1
		if arg.kind == ConsoleArg.Kind.VEC3 and not (position < tokens.size() and tokens[position].contains(",")):
			span = 3  # three slots even while they are still being typed
		if index < position + span:
			return arg
		position += span
	return null


## Maps tokens to typed values. Returns {"ok": bool, "values": Dictionary, "error": String}.
## Does not check that PATH arguments name existing keys; the registry does that.
func parse_args(tokens: PackedStringArray) -> Dictionary:
	var values: Dictionary = {}
	var position: int = 0
	for arg: ConsoleArg in args:
		if position >= tokens.size():
			if not arg.optional:
				return _fail("missing %s (usage: %s)" % [arg.subject(), usage()])
			values[arg.name] = arg.fallback
			continue
		var span: int = arg.token_span(tokens, position)
		var text: String = " ".join(tokens.slice(position, position + span))
		if arg.kind == ConsoleArg.Kind.VEC3 and span < 3 and not tokens[position].contains(","):
			return _fail("%s expects three numbers (x y z), got '%s' (usage: %s)" % [arg.subject(), text, usage()])
		var parsed: Dictionary = arg.parse_text(text) if arg.kind != ConsoleArg.Kind.STRING else {"ok": true,
				"value": text if arg.rest else tokens[position], "error": ""}
		if not parsed["ok"]:
			return _fail("%s (usage: %s)" % [parsed["error"], usage()])
		values[arg.name] = parsed["value"]
		position += span
	if position < tokens.size():
		return _fail("too many arguments (usage: %s)" % usage())
	return {"ok": true, "values": values, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "values": {}, "error": message}
