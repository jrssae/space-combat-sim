class_name FactionConsole
extends RefCounted
## The console side of the faction table (architecture §16.4): provider `factions` (`ids`, `relations`, `friendly_fire`)
## and the command `relation <a> <b> [friendly|neutral|hostile]` / `relation reset`. `Factions` is a static class with no
## node to own console entries, so `HitResolver` (which reads `settings.friendly_fire` each tick) registers these in
## `_ready`, owner = itself, like its own `combat` provider.
##
## Changes are for the session: they edit the in-memory table and never write `data/factions.json`. `relation reset`
## reloads the file. The HUD, target cycling and the resolver ask `Factions` every time, so they follow at once.

const RESET_WORD: String = "reset"


static func provider() -> ConsoleVars:
	return ConsoleVars.new({
		&"ids": {"get": ids, "doc": "Every faction id in data/factions.json"},
		&"relations": {"get": relations,
				"doc": "The listed pairs as `a b relation`; every other pair of listed factions is the file's default"},
		&"friendly_fire": {"get": friendly_fire, "type": TYPE_BOOL,
				"doc": "Mirror of settings.friendly_fire: bolts hurt any ship but their shooter"},
	})


static func command() -> ConsoleCommand:
	return ConsoleCommand.new(&"relation",
			"Show or set (this session only) how faction <a> regards faction <b>; `relation reset` reloads data/factions.json",
			[ConsoleArg.string_required(&"a").with_suggestions(_suggestions),
			ConsoleArg.string_optional(&"b").with_suggestions(_suggestions),
			ConsoleArg.enum_optional(&"relation", FactionTable.RELATION_NAMES)])


static func ids() -> Array:
	var out: Array = []
	for id: StringName in Factions.table().ids():
		out.append(String(id))
	return out


static func relations() -> Array:
	var out: Array = []
	for pair: Dictionary in Factions.table().listed_pairs():
		out.append("%s %s %s" % [pair["a"], pair["b"], FactionTable.relation_name(int(pair["relation"]))])
	return out


static func friendly_fire() -> bool:
	return bool(Settings.get_value(&"friendly_fire"))


## Handler of `relation`: `args` holds `a`, `b` (null if omitted) and `relation` (null if omitted).
static func run(args: Dictionary) -> ConsoleResult:
	var a: String = String(args[&"a"]).to_lower()
	if args[&"b"] == null:
		if a != RESET_WORD:
			return ConsoleResult.failure("relation needs a second faction: relation <a> <b> [%s], or relation %s" % [
					"|".join(PackedStringArray(FactionTable.RELATION_NAMES)), RESET_WORD])
		Factions.reset()
		return ConsoleResult.line("factions reloaded from %s" % Factions.TABLE_PATH)
	var b: String = String(args[&"b"]).to_lower()
	var table: FactionTable = Factions.table()
	for id: String in [a, b]:
		if not table.has(StringName(id)):
			return ConsoleResult.failure("unknown faction '%s' (known: %s)%s" % [id, ", ".join(PackedStringArray(table.ids())),
					ConsoleFormat.did_you_mean(id, PackedStringArray(table.ids()))])
	var before: Factions.Relation = table.relation(StringName(a), StringName(b))
	if args[&"relation"] == null:
		return ConsoleResult.line("%s vs %s: %s" % [a, b, FactionTable.relation_name(before)])
	var wanted: int = FactionTable.relation_from_name(args[&"relation"])
	var error: String = table.set_relation(StringName(a), StringName(b), wanted as Factions.Relation)
	if not error.is_empty():
		return ConsoleResult.failure(error)
	return ConsoleResult.line("%s vs %s: %s -> %s (this session)" % [a, b, FactionTable.relation_name(before),
			FactionTable.relation_name(wanted)])


# Tab completion: the listed ids, and `reset` for the first argument's sake.
static func _suggestions() -> PackedStringArray:
	var out := PackedStringArray()
	for id: StringName in Factions.table().ids():
		out.append(String(id))
	out.append(RESET_WORD)
	return out
