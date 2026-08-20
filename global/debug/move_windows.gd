extends Node

## Nudge down from the screen top so the window's title bar/menu stays visible.
const SERVER_Y_OFFSET := 45

func _ready() -> void:
	# Only the (non-VR) server window needs positioning; the VR instance's
	# window is left wherever the OS/editor puts it.
	if OS.has_feature("editor") and OS.get_cmdline_args().has("--server"):
		get_tree().root.gui_embed_subwindows = false
		get_tree().create_timer(0.05).timeout.connect(_position_window)

func _position_window() -> void:
	var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())

	@warning_ignore("integer_division")
	var window_width: int = screen_rect.size.x / 2
	var x_pos: int = screen_rect.position.x + window_width
	var y_pos: int = screen_rect.position.y + SERVER_Y_OFFSET
	DisplayServer.window_set_position(Vector2i(x_pos, y_pos))
