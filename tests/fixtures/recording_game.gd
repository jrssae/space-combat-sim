class_name RecordingGame
extends "res://src/autoload/game.gd"
## A `Game` for menu tests: it is never added to the tree (so it registers nothing on the console) and changes no scene. It
## records what the menus asked of it, and answers `play` with `refusal` ("" accepts).

var played: Array[Dictionary] = []
var restarts: int = 0
var menus_shown: int = 0
var refusal: String = ""
## What the loading screen handed over, and why a load failed.
var loaded: Array[PackedScene] = []
var failures: Array[String] = []


func play(request: Dictionary) -> String:
	played.append(request)
	return refusal


func restart() -> String:
	restarts += 1
	return refusal


func show_front_end() -> void:
	menus_shown += 1


func finish_loading(packed: PackedScene) -> void:
	loaded.append(packed)


func fail_loading(reason: String) -> void:
	failures.append(reason)
