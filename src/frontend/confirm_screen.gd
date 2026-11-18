class_name ConfirmScreen
extends MenuScreen
## A yes/no question as a small page of its own (M7-T31): the pause menu's "Quit to desktop?". The focus starts on No, so a
## stray double press of A never quits; No and B both step back, only Yes emits `confirmed`.

signal confirmed


func setup_confirm(question: String) -> void:
	title = question
	compact = true
	show_pad = false
	show_right = false
	add_back_option_named("No")
	add_option("Yes", func() -> void: confirmed.emit())


## "No": a Back button that reads as an answer. The frame plays the back sound.
func add_back_option_named(text: String) -> Button:
	return add_option(text, func() -> void: back_requested.emit(), true, false)
