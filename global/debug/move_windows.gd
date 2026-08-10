extends Node

func _ready() -> void:
	if OS.has_feature("editor"):
		# Force subwindows to be native OS windows instead of embedded viewports
		get_tree().root.gui_embed_subwindows = false
		get_tree().create_timer(0.05).timeout.connect(_position_window)

func _position_window() -> void:
	var is_server: bool = OS.get_cmdline_args().has("--server")
	var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	
	var window_width: int = screen_rect.size.x / 2
	var window_height: int = int(screen_rect.size.y * (2.0 / 3.0))
	
	DisplayServer.window_set_size(Vector2i(window_width - 10, window_height))
	
	var x_pos: int = screen_rect.position.x + window_width if is_server else screen_rect.position.x
	DisplayServer.window_set_position(Vector2i(x_pos, screen_rect.position.y))
