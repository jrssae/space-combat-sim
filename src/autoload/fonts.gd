extends Node
## Fonts autoload, the first one (M8-T21, D87): puts the game's two fonts into the project theme before any control exists.
## The fonts are not named in the theme's file: the engine loads that before a fresh checkout's first import, when no font
## file can be loaded yet, and would report the theme as broken.


func _init() -> void:
	GameFonts.install()
