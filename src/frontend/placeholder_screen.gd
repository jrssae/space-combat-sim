class_name PlaceholderScreen
extends MenuScreen
## A page that is not built yet (architecture §18, D57): Settings and Controls open this inside the frame until M5-T03 and
## M5-T04 replace it through `MenuScreens`.


func setup_placeholder(page_title: String, note: String) -> void:
	title = page_title
	var label := Label.new()
	label.text = note
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	add_back_option()
