extends SceneTree
## Writes `docs/catalogue/ships.md` from the ship catalogue (M10-T61, `ShipCatalogDoc`). Run through `scripts/gen_ship_catalog.sh`.


func _init() -> void:
	var data: ShipCatalogData = ShipCatalog.data()
	if not data.error.is_empty():
		printerr("gen_ship_catalog: %s" % data.error)
		quit(1)
		return
	var file := FileAccess.open(ShipCatalogDoc.OUT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("gen_ship_catalog: cannot write %s" % ShipCatalogDoc.OUT_PATH)
		quit(1)
		return
	file.store_string(ShipCatalogDoc.render(ShipCatalogDoc.rows(data)))
	file.close()
	print("gen_ship_catalog: wrote %s (%d hulls)" % [ShipCatalogDoc.OUT_PATH, data.ids().size()])
	quit(0)
