extends Node
## F11 toggles fullscreen (input action "toggle_fullscreen"). Borderless fullscreen so macOS Spaces stay snappy.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var win := get_window()
		var full := win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		win.mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
