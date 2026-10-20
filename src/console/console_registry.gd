class_name ConsoleRegistry
extends RefCounted
## The console's command and state tables (architecture §6.4), pure: no scene tree, no Input, no files.
## Subsystems register commands and providers in `_ready` with themselves as owner and call
## `unregister_owner(self)` in `_exit_tree`; owners are held weakly and freed owners are pruned on every access,
## so a node that forgets to unregister still disappears from the console. The console never imports a subsystem.
##
## Paths are `provider.key`, resolved against whitelisted providers only; there is no reflection.
## `execute` runs statements synchronously and stops at a `wait` (handing back what it did not run) or a `quit`;
## the DebugConsole node owns the queue that turns those into frame delays and exit codes.

## Statements one `execute` call may run, counting ones injected by `exec` (stops runaway recursive scripts).
const MAX_STATEMENTS_PER_EXECUTE: int = 10000

var _commands: Dictionary = {}  # StringName -> {"command": ConsoleCommand, "handler": Callable, "owner": WeakRef}
var _providers: Dictionary = {}  # StringName -> {"provider": ConsoleStateProvider, "owner": WeakRef}


## Adds (or replaces) a command. `owner` null means "never pruned" (the console's own commands).
func register_command(command: ConsoleCommand, handler: Callable, owner: Object = null) -> void:
	_commands[command.name] = {"command": command, "handler": handler, "owner": _weak(owner)}


## Adds (or replaces) a state provider under `name` (lower_snake, no dots).
func register_provider(provider_name: StringName, provider: ConsoleStateProvider, owner: Object = null) -> void:
	assert(not String(provider_name).contains("."), "provider names cannot contain '.'")
	_providers[provider_name] = {"provider": provider, "owner": _weak(owner)}


## Drops every command and provider `owner` registered.
func unregister_owner(owner: Object) -> void:
	for table: Dictionary in [_commands, _providers]:
		for entry_name: StringName in table.keys():
			var ref: WeakRef = table[entry_name]["owner"]
			if ref != null and ref.get_ref() == owner:
				table.erase(entry_name)
	_prune()


func unregister_command(command_name: StringName) -> void:
	_commands.erase(command_name)


func unregister_provider(provider_name: StringName) -> void:
	_providers.erase(provider_name)


func has_command(command_name: StringName) -> bool:
	_prune()
	return _commands.has(command_name)


func get_command(command_name: StringName) -> ConsoleCommand:
	_prune()
	return _commands[command_name]["command"] if _commands.has(command_name) else null


func command_names() -> Array[StringName]:
	_prune()
	return _sorted(_commands.keys())


func has_provider(provider_name: StringName) -> bool:
	_prune()
	return _providers.has(provider_name)


func get_provider(provider_name: StringName) -> ConsoleStateProvider:
	_prune()
	return _providers[provider_name]["provider"] if _providers.has(provider_name) else null


func provider_names() -> Array[StringName]:
	_prune()
	return _sorted(_providers.keys())


## Keys of a provider that pass `filter` (empty if the provider does not exist).
func provider_keys(provider_name: StringName, filter := ConsoleArg.PathFilter.ANY) -> Array[StringName]:
	var out: Array[StringName] = []
	var provider: ConsoleStateProvider = get_provider(provider_name)
	if provider == null:
		return out
	for key: StringName in provider.keys():
		if _passes(provider, key, filter):
			out.append(key)
	return out


## Splits and checks a path. Returns {"ok", "provider": ConsoleStateProvider, "provider_name", "key", "error"}.
func resolve(path: String) -> Dictionary:
	var text: String = path.strip_edges()
	var dot: int = text.find(".")
	var provider_name := StringName(text if dot == -1 else text.substr(0, dot))
	var provider: ConsoleStateProvider = get_provider(provider_name)
	if provider == null:
		var names := PackedStringArray()
		for known: StringName in provider_names():
			names.append(String(known))
		return _unresolved("unknown provider '%s'%s" % [provider_name,
				ConsoleFormat.did_you_mean(String(provider_name), names)])
	if dot == -1 or dot == text.length() - 1:
		return _unresolved("'%s' is a provider, not a path: use %s.<key> (or 'state %s')" % [provider_name,
				provider_name, provider_name])
	var key := StringName(text.substr(dot + 1))
	if not provider.has_key(key):
		var paths := PackedStringArray()
		for known: StringName in provider.keys():
			paths.append("%s.%s" % [provider_name, known])
		return _unresolved("unknown key '%s'%s" % [text, ConsoleFormat.did_you_mean(text, paths)])
	return {"ok": true, "provider": provider, "provider_name": provider_name, "key": key, "error": ""}


## "path = value unit" for a path, or the reason it cannot be read.
func format_path(path: String) -> String:
	var resolved: Dictionary = resolve(path)
	if not resolved["ok"]:
		return "%s: %s" % [path, resolved["error"]]
	var provider: ConsoleStateProvider = resolved["provider"]
	var key: StringName = resolved["key"]
	return ConsoleFormat.key_value(path.strip_edges(), provider.read(key), provider.unit(key))


## Reads a path. Returns {"ok", "value", "error"}.
func read(path: String) -> Dictionary:
	var resolved: Dictionary = resolve(path)
	if not resolved["ok"]:
		return {"ok": false, "value": null, "error": resolved["error"]}
	var provider: ConsoleStateProvider = resolved["provider"]
	return {"ok": true, "value": provider.read(resolved["key"]), "error": ""}


## `state <provider>` lines: every `path = value unit`, `*` on modified keys.
func describe_provider(provider_name: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var provider: ConsoleStateProvider = get_provider(provider_name)
	if provider == null:
		return out
	for key: StringName in provider.keys():
		out.append(ConsoleFormat.key_value("%s.%s" % [provider_name, key], provider.read(key), provider.unit(key),
				provider.is_modified(key)))
	return out


## Type-checked write of a typed value (validated against the key's ConsoleArg).
func write(path: String, value: Variant) -> ConsoleResult:
	var resolved: Dictionary = resolve(path)
	if not resolved["ok"]:
		return ConsoleResult.failure(resolved["error"])
	var provider: ConsoleStateProvider = resolved["provider"]
	var key: StringName = resolved["key"]
	var value_arg: ConsoleArg = provider.value_arg(key)
	if value_arg == null:
		return ConsoleResult.failure("%s is read-only" % path)
	var checked: Dictionary = value_arg.validate(value, path)
	if not checked["ok"]:
		return ConsoleResult.failure(checked["error"])
	return _apply(provider, key, path, checked["value"])


## Type-checked write from console text ("0.2", "on", "cockpit", "1 2 3").
func write_text(path: String, text: String) -> ConsoleResult:
	var resolved: Dictionary = resolve(path)
	if not resolved["ok"]:
		return ConsoleResult.failure(resolved["error"])
	var provider: ConsoleStateProvider = resolved["provider"]
	var key: StringName = resolved["key"]
	var value_arg: ConsoleArg = provider.value_arg(key)
	if value_arg == null:
		return ConsoleResult.failure("%s is read-only" % path)
	var parsed: Dictionary = value_arg.parse_text(text, path)
	if not parsed["ok"]:
		return ConsoleResult.failure(parsed["error"])
	return _apply(provider, key, path, parsed["value"])


## Flips a writable bool, or sets it when `state` is a bool.
func toggle(path: String, state: Variant = null) -> ConsoleResult:
	var current: Dictionary = read(path)
	if not current["ok"]:
		return ConsoleResult.failure(current["error"])
	if typeof(current["value"]) != TYPE_BOOL:
		return ConsoleResult.failure("%s is not a bool" % path)
	var target: bool = not bool(current["value"]) if state == null else bool(state)
	return write(path, target)


func reset(path: String) -> ConsoleResult:
	var resolved: Dictionary = resolve(path)
	if not resolved["ok"]:
		return ConsoleResult.failure(resolved["error"])
	var provider: ConsoleStateProvider = resolved["provider"]
	var key: StringName = resolved["key"]
	if not provider.can_reset(key):
		return ConsoleResult.failure("%s has no default" % path)
	var refused: String = provider.reset(key)
	if not refused.is_empty():
		return ConsoleResult.failure(_qualify(path, key, refused))
	return ConsoleResult.line(ConsoleFormat.key_value(path, provider.read(key), provider.unit(key)))


## `help` lines: every command with its usage and summary, or one command's details.
func help(command_name: StringName = &"") -> PackedStringArray:
	if command_name != &"":
		var command: ConsoleCommand = get_command(command_name)
		if command == null:
			return PackedStringArray([_unknown_command(command_name)])
		return command.help_lines()
	var rows: Array[PackedStringArray] = []
	var width: int = 0
	for known: StringName in command_names():
		var command: ConsoleCommand = get_command(known)
		var usage: String = command.usage()
		width = maxi(width, usage.length())
		rows.append(PackedStringArray([usage, command.summary]))
	var out := PackedStringArray(["commands (help <command> for details; paths are provider.key, see 'state'):"])
	for row: PackedStringArray in rows:
		out.append("  %s  %s" % [row[0].rpad(width), row[1]])
	return out


func complete(partial: String) -> PackedStringArray:
	return ConsoleCompleter.new(self).complete(partial)


## Runs every statement of a line. Stops after a `quit`, at a `wait` (the result's `remaining` holds the
## statements not run yet), or at the first error when `stop_on_error` is set. `exec` statements run inline.
func execute(line: String, stop_on_error: bool = false) -> Array[ConsoleResult]:
	var tokenizer := ConsoleTokenizer.new()
	var statements: Array[PackedStringArray] = tokenizer.split(line)
	if not tokenizer.error.is_empty():
		var failed := ConsoleResult.failure(tokenizer.error)
		failed.command_text = line.strip_edges()
		var only: Array[ConsoleResult] = [failed]
		return only
	return execute_statements(statements, stop_on_error)


func execute_statements(statements: Array[PackedStringArray], stop_on_error: bool = false) -> Array[ConsoleResult]:
	var results: Array[ConsoleResult] = []
	var queue: Array[PackedStringArray] = statements.duplicate()
	var budget: int = MAX_STATEMENTS_PER_EXECUTE
	while not queue.is_empty():
		budget -= 1
		if budget < 0:
			results.append(ConsoleResult.failure("too many commands in one go (recursive exec?)"))
			break
		var tokens: PackedStringArray = queue.pop_front()
		var result: ConsoleResult = execute_tokens(tokens)
		results.append(result)
		if not result.inject.is_empty():
			var merged: Array[PackedStringArray] = result.inject.duplicate()
			merged.append_array(queue)
			queue = merged
		if result.quit_code >= 0 or (stop_on_error and not result.ok):
			break
		if result.wait_frames > 0:
			result.remaining = queue
			break
	return results


## Runs one statement: looks the command up, parses and checks its arguments, calls the handler.
func execute_tokens(tokens: PackedStringArray) -> ConsoleResult:
	if tokens.is_empty():
		return ConsoleResult.success()
	var command_name := StringName(tokens[0].to_lower())
	var result: ConsoleResult
	_prune()
	var entry: Dictionary = _commands.get(command_name, {})
	if entry.is_empty() or not (entry["handler"] as Callable).is_valid():
		_commands.erase(command_name)
		result = ConsoleResult.failure(_unknown_command(command_name))
	else:
		var command: ConsoleCommand = entry["command"]
		var parsed: Dictionary = command.parse_args(tokens.slice(1))
		var problem: String = "" if parsed["ok"] else String(parsed["error"])
		if problem.is_empty():
			problem = _check_paths(command, parsed["values"])
		if problem.is_empty():
			var handler: Callable = entry["handler"]
			result = ConsoleResult.from_value(handler.call(parsed["values"]))
		else:
			result = ConsoleResult.failure(problem)
	result.command_text = ConsoleFormat.join_tokens(tokens)
	return result


func _check_paths(command: ConsoleCommand, values: Dictionary) -> String:
	for arg: ConsoleArg in command.args:
		if arg.kind != ConsoleArg.Kind.PATH or values.get(arg.name) == null:
			continue
		var path: String = values[arg.name]
		var resolved: Dictionary = resolve(path)
		if not resolved["ok"]:
			return resolved["error"]
		if not _passes(resolved["provider"], resolved["key"], arg.path_filter):
			match arg.path_filter:
				ConsoleArg.PathFilter.WRITABLE:
					return "%s is read-only" % path
				ConsoleArg.PathFilter.WRITABLE_BOOL:
					return "%s is not a writable bool" % path
				ConsoleArg.PathFilter.RESETTABLE:
					return "%s has no default" % path
	return ""


func _passes(provider: ConsoleStateProvider, key: StringName, filter: ConsoleArg.PathFilter) -> bool:
	match filter:
		ConsoleArg.PathFilter.WRITABLE:
			return provider.is_writable(key)
		ConsoleArg.PathFilter.WRITABLE_BOOL:
			var value_arg: ConsoleArg = provider.value_arg(key)
			return value_arg != null and value_arg.kind == ConsoleArg.Kind.BOOL
		ConsoleArg.PathFilter.RESETTABLE:
			return provider.can_reset(key)
	return true


func _apply(provider: ConsoleStateProvider, key: StringName, path: String, value: Variant) -> ConsoleResult:
	var refused: String = provider.write(key, value)
	if not refused.is_empty():
		return ConsoleResult.failure(_qualify(path, key, refused))
	return ConsoleResult.line(ConsoleFormat.key_value(path, provider.read(key), provider.unit(key)))


# A provider's refusal, phrased with the full path: "stick_deadzone must be ..." -> "settings.stick_deadzone must ...",
# "engines are offline" -> "ship.thrust: engines are offline".
static func _qualify(path: String, key: StringName, message: String) -> String:
	if message.begins_with(path):
		return message
	if message.begins_with(String(key) + " "):
		return path + message.substr(String(key).length())
	return "%s: %s" % [path, message]


func _unknown_command(command_name: StringName) -> String:
	var names := PackedStringArray()
	for known: StringName in command_names():
		names.append(String(known))
	return "unknown command '%s'%s; type 'help' for a list" % [command_name,
			ConsoleFormat.did_you_mean(String(command_name), names)]


func _prune() -> void:
	for table: Dictionary in [_commands, _providers]:
		for entry_name: StringName in table.keys():
			var ref: WeakRef = table[entry_name]["owner"]
			if ref != null and ref.get_ref() == null:
				table.erase(entry_name)


static func _weak(owner: Object) -> WeakRef:
	if owner == null:
		return null
	return weakref(owner) as WeakRef


static func _unresolved(message: String) -> Dictionary:
	return {"ok": false, "provider": null, "provider_name": &"", "key": &"", "error": message}


static func _sorted(names: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for item: Variant in names:
		out.append(StringName(item))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
