class_name ConsoleCompleter
extends RefCounted
## Tab completion over a ConsoleRegistry (architecture §6.4), pure. The first token completes command names; later
## tokens complete by argument kind: provider paths (`settings.` first, then the keys, narrowed by the argument's
## PathFilter), bool and enum values, the values of the key named in `set <path> <value>`, and anything an
## argument's `suggest` Callable offers. Returns whole candidate lines, sorted, so a UI can cycle through them.

var _registry: ConsoleRegistry


func _init(registry: ConsoleRegistry) -> void:
	_registry = registry


func complete(partial: String) -> PackedStringArray:
	var split: Dictionary = ConsoleTokenizer.split_for_completion(partial)
	if split["comment"]:
		return PackedStringArray()
	var words: PackedStringArray = split["words"]
	var current: String = split["current"]
	var candidates := PackedStringArray()
	if words.is_empty():
		for command_name: StringName in _registry.command_names():
			candidates.append(String(command_name))
	else:
		var command: ConsoleCommand = _registry.get_command(StringName(words[0].to_lower()))
		if command == null:
			return PackedStringArray()
		var arg_tokens: PackedStringArray = words.slice(1)
		var arg: ConsoleArg = command.arg_for_token(arg_tokens, arg_tokens.size())
		if arg == null:
			return PackedStringArray()
		candidates = _arg_candidates(command, arg, arg_tokens, current)

	var matches := PackedStringArray()
	var needle: String = current.to_lower()
	for candidate: String in candidates:
		if candidate.to_lower().begins_with(needle) and not matches.has(candidate):
			matches.append(candidate)
	matches.sort()

	var head: String = split["head"]
	if not head.is_empty() and not head.ends_with(" "):
		head += " "
	var lead: String = ConsoleFormat.join_tokens(words)
	if not lead.is_empty():
		lead += " "
	var out := PackedStringArray()
	for candidate: String in matches:
		# A provider prefix ("settings.") continues into its keys; anything else is a finished token.
		var tail: String = "" if candidate.ends_with(".") else " "
		out.append(head + lead + ConsoleFormat.quote_token(candidate) + tail)
	return out


func _arg_candidates(command: ConsoleCommand, arg: ConsoleArg, arg_tokens: PackedStringArray,
		current: String) -> PackedStringArray:
	if arg.suggest.is_valid():
		var suggested: Variant = arg.suggest.call()
		return PackedStringArray(suggested) if suggested is PackedStringArray or suggested is Array \
				else PackedStringArray()
	match arg.kind:
		ConsoleArg.Kind.BOOL:
			return PackedStringArray(["on", "off"])
		ConsoleArg.Kind.ENUM:
			return arg.choice_list()
		ConsoleArg.Kind.PATH:
			return _path_candidates(arg.path_filter, current)
	if arg.value_of >= 0:
		var path_arg_index: int = arg.value_of
		var path_token: int = _first_token_of(command, arg_tokens, path_arg_index)
		if path_token >= 0 and path_token < arg_tokens.size():
			return _value_candidates(arg_tokens[path_token])
	return PackedStringArray()


func _path_candidates(filter: ConsoleArg.PathFilter, current: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dot: int = current.find(".")
	if dot == -1:
		for provider_name: StringName in _registry.provider_names():
			if not _registry.provider_keys(provider_name, filter).is_empty():
				out.append(String(provider_name) + ".")
		return out
	var provider_name := StringName(current.substr(0, dot))
	for key: StringName in _registry.provider_keys(provider_name, filter):
		out.append("%s.%s" % [provider_name, key])
	return out


func _value_candidates(path: String) -> PackedStringArray:
	var resolved: Dictionary = _registry.resolve(path)
	if not resolved["ok"]:
		return PackedStringArray()
	var provider: ConsoleStateProvider = resolved["provider"]
	var value_arg: ConsoleArg = provider.value_arg(resolved["key"])
	if value_arg == null:
		return PackedStringArray()
	match value_arg.kind:
		ConsoleArg.Kind.BOOL:
			return PackedStringArray(["on", "off"])
		ConsoleArg.Kind.ENUM:
			return value_arg.choice_list()
	return PackedStringArray()


# Index of the first token that belongs to argument `arg_index`, or -1.
func _first_token_of(command: ConsoleCommand, arg_tokens: PackedStringArray, arg_index: int) -> int:
	var position: int = 0
	for i: int in command.args.size():
		if i == arg_index:
			return position
		var arg: ConsoleArg = command.args[i]
		position += 3 if arg.kind == ConsoleArg.Kind.VEC3 and not (position < arg_tokens.size()
				and arg_tokens[position].contains(",")) else 1
	return -1
