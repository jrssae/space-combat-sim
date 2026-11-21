extends GutTest
## `docs/catalogue/ships.md` (M10-T61): rendered from the catalogue, and the committed page is in sync with it.


func test_the_committed_page_is_in_sync_with_the_catalogue_and_the_assets() -> void:
	var rows: Array[Dictionary] = ShipCatalogDoc.rows(ShipCatalog.data())
	for row: Dictionary in rows:
		assert_ne(row["size"], "?", "%s: its manifest is built (scripts/gen_assets.sh)" % row["id"])
	var fresh: String = ShipCatalogDoc.render(rows)
	var committed: String = FileAccess.get_file_as_string(ShipCatalogDoc.OUT_PATH)
	assert_eq(committed, fresh, "docs/catalogue/ships.md is stale: run scripts/gen_ship_catalog.sh")


func test_every_type_has_a_row() -> void:
	var page: String = FileAccess.get_file_as_string(ShipCatalogDoc.OUT_PATH)
	for id: StringName in ShipCatalog.data().ids():
		assert_string_contains(page, "| `%s` |" % id)


func test_render_puts_one_row_per_entry_in_both_tables() -> void:
	var rows: Array[Dictionary] = [{"id": "a", "faction": "narn", "role": "civilian", "size": "10.0 x 5.0 x 2.0", "hull": "900",
			"weapons": "none", "jump": "no", "fighters": "no", "spec": "res://a.tres", "pooled": "yes", "callsign": "BEE"}]
	var page: String = ShipCatalogDoc.render(rows)
	assert_string_contains(page, "| `a` | narn | civilian | 10.0 x 5.0 x 2.0 | 900 | none | no | no |")
	assert_string_contains(page, "| `a` | `res://a.tres` | - | yes | - | - | - | - | BEE |", "an empty flag reads -")
	assert_true(page.ends_with("\n"))
