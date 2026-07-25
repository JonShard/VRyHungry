extends Node3D

## World script for the multiplayer scene. Consumes the host/join request set
## by the main menu, spawns the world's stations/items on whichever machine
## owns the world (server, or the local player when offline), spawns/despawns
## a player avatar per connected peer, and returns to the menu if the session
## ends.
##
## The world's actual content (stations, items) is NOT baked into this scene —
## it's spawned at runtime from Net/world_layout.gd via NetworkManager, so a
## joining client receives it from the server (MultiplayerSpawner replays
## existing spawns to late joiners) instead of relying on its own local copy
## matching.

const PLAYER_SCENE := preload("res://Player/net_player.tscn")

var xr_interface: XRInterface
var _populated := false


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true

	NetworkManager.register_world(self, $PlayersSpawner, $ItemsSpawner)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.session_started.connect(_on_session_started)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Offline (single player / dev run): owns_world() is already true, so
	# populate immediately. Online host case is handled by session_started.
	_populate_world_if_owner()

	NetworkManager.world_ready()


func _exit_tree() -> void:
	NetworkManager.unregister_world()


func _on_session_started(_is_server: bool) -> void:
	_populate_world_if_owner()


## Spawns the world's stations/items exactly once, on the machine that owns
## world logic (server or offline). Safe to call multiple times/entry points.
func _populate_world_if_owner() -> void:
	if not NetworkManager.owns_world() or _populated:
		return
	_populated = true
	GameManager.meals_in_play = ["hamburger"]
	for d in WorldLayout.get_stations():
		NetworkManager.spawn_item(d["scene"], d["xform"], d["name"], d["props"])
	for d in WorldLayout.get_items():
		NetworkManager.spawn_item(d["scene"], d["xform"], d["name"], d["props"])


## Only the server (or the single offline machine) materialises player
## avatars; MultiplayerSpawner replicates the result to everyone else,
## including late joiners.
func _on_player_joined(peer_id: int) -> void:
	if not NetworkManager.owns_world() or $Players.has_node(str(peer_id)):
		return
	var p := PLAYER_SCENE.instantiate()
	p.name = str(peer_id)
	$Players.add_child(p, true)


func _on_player_left(peer_id: int) -> void:
	if not NetworkManager.owns_world():
		return
	var p := $Players.get_node_or_null(str(peer_id))
	if p:
		p.queue_free()


func _on_session_ended() -> void:
	get_tree().change_scene_to_file("res://Scenes/mainMenu.tscn")


func _on_connection_failed() -> void:
	get_tree().change_scene_to_file("res://Scenes/mainMenu.tscn")
