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

## Whether to spawn the full WorldLayout on the machine that owns the world.
## The real game scene wants this; focused debug scenes (test/) bake their own
## handful of stations and items instead and turn it off, so the thing under
## test isn't sharing the world with a second copy of the whole kitchen.
@export var populate_from_layout: bool = true

var xr_interface: XRInterface
var _populated := false

@export var items_spawner: MultiplayerSpawner
@export var players_spawner: MultiplayerSpawner


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true

	NetworkManager.register_world(self, players_spawner, items_spawner)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.session_started.connect(_on_session_started)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# world_ready() is what actually calls host()/join() (or the cmdline
	# equivalent). Populating before this point is wrong for EVERY case, not
	# just offline: is_online() is still false until host()/join() runs, so
	# owns_world() would read true for a joining client too, and it would
	# build its own local copy instead of receiving the server's via the
	# spawner. host() emits session_started synchronously, which populates
	# via _on_session_started below; the explicit call after world_ready()
	# only matters for the case where neither host() nor join() ran (no
	# pending session, no cmdline args) — running this scene directly offline.
	NetworkManager.world_ready()
	_populate_world_if_owner()

	get_tree().create_timer(3.0).timeout.connect(_log_world_state)


# Temporary-ish sanity check: confirms WorldContent actually ended up
# populated on this peer (whether by spawning it or by receiving it via
# replication), so a silent replication failure shows up in the net log
# instead of just an empty-looking world.
func _log_world_state() -> void:
	NetworkManager.log_line("World state: WorldContent=%d children, Players=%d children" % [$WorldContent.get_child_count(), $Players.get_child_count()])


func _exit_tree() -> void:
	NetworkManager.unregister_world()


func _on_session_started(_is_server: bool) -> void:
	_populate_world_if_owner()


## Spawns the world's stations/items exactly once, on the machine that owns
## world logic (server or offline). Safe to call multiple times/entry points.
func _populate_world_if_owner() -> void:
	if _populated or not populate_from_layout:
		return
	# WorldLayout reads the live scene tree to find what to replicate, so it
	# needs to be an instance sitting in that tree — its methods can't be called
	# on the class itself.
	var layout := WorldLayout.new()
	add_child(layout)
	var authored := layout.get_station_nodes()
	authored.append_array(layout.get_item_nodes())

	# The stations and items authored into the scene file are a *template*, not
	# the live world. Only the server turns them into real objects, spawned
	# through NetworkManager so they replicate. Every peer therefore drops its
	# own authored copies: the client would otherwise show its local originals
	# on top of the server's replicated ones, and the two sets would drift apart
	# because only the server's are synced.
	if not NetworkManager.owns_world():
		NetworkManager.log_line("Clearing %d authored nodes; the server's copies replace them" % authored.size())
		_remove_authored(authored)
		layout.queue_free()
		return

	_init_recipes()
	_populated = true
	var stations := layout.get_stations()
	var items := layout.get_items()
	layout.queue_free()
	_remove_authored(authored)
	NetworkManager.log_line("Populating world: %d stations, %d items" % [stations.size(), items.size()])
	# One frame between spawns - MultiplayerSpawner corrupts replication when
	# several nodes register for sync in the same frame (godotengine/godot#96914).
	for d in stations:
		NetworkManager.spawn_item(d["scene"], d["xform"], d["name"], d["props"])
		await get_tree().process_frame
	for d in items:
		NetworkManager.spawn_item(d["scene"], d["xform"], d["name"], d["props"])
		await get_tree().process_frame
	NetworkManager.log_line("World populated")


func _init_recipes():
	GameManager.set_meals_in_play(["hamburger"])
	GameManager.set_sides_in_play(["cube"])


# Free the authored template nodes. Done immediately rather than with
# queue_free() so the names are released before the replicated copies are
# spawned under the same ones.
func _remove_authored(nodes: Array[Node]) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()


## Only the server (or the single offline machine) materialises player
## avatars; MultiplayerSpawner replicates the result to everyone else,
## including late joiners.
func _on_player_joined(peer_id: int) -> void:
	if not NetworkManager.owns_world() or $Players.has_node(str(peer_id)):
		return
	var p := PLAYER_SCENE.instantiate()
	p.name = str(peer_id)
	$Players.add_child(p, true)
	NetworkManager.log_line("Spawned avatar for peer %d" % peer_id)


func _on_player_left(peer_id: int) -> void:
	if not NetworkManager.owns_world():
		return
	var p := $Players.get_node_or_null(str(peer_id))
	if p:
		p.queue_free()
		NetworkManager.log_line("Despawned avatar for peer %d" % peer_id)


func _on_session_ended() -> void:
	NetworkManager.log_line("Session ended, returning to main menu")
	get_tree().change_scene_to_file("res://scenes/mainMenu.tscn")


func _on_connection_failed() -> void:
	NetworkManager.log_line("Connection failed, returning to main menu")
	get_tree().change_scene_to_file("res://scenes/mainMenu.tscn")
