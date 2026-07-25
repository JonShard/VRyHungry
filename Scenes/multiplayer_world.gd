extends Node3D

## World script for the multiplayer scene. Consumes the host/join request set
## by the main menu, and returns to the menu if the session ends.
##
## Connection-level only for now: no PlayersSpawner/ItemsSpawner here since the
## networked Player/NetPickable scenes aren't ported yet (out of scope for this
## change) — peers connect, but avatars/items don't sync.

var xr_interface: XRInterface


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true

	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.world_ready()


func _on_session_ended() -> void:
	get_tree().change_scene_to_file("res://Scenes/mainMenu.tscn")


func _on_connection_failed() -> void:
	get_tree().change_scene_to_file("res://Scenes/mainMenu.tscn")
