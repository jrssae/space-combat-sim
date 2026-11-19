class_name JoypadDevices
extends RefCounted
## The gamepads Godot sees, for `Joypads` (M8-T22). A seam: tests subclass it to plug pads in and out without hardware.


func ids() -> Array[int]:
	return Input.get_connected_joypads()


func pad_name(id: int) -> String:
	return Input.get_joy_name(id)


func guid(id: int) -> String:
	return Input.get_joy_guid(id)


## True when Godot has a button mapping for the pad (SDL's database, or one it built for an Xbox-style pad).
func known(id: int) -> bool:
	return Input.is_joy_known(id)
