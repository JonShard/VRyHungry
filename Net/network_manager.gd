extends Node

## Client-server session manager for VRyHungry (listen-server model).
##
## Registered as the "NetworkManager" autoload. Owns transport (ENet), tracks
## the session, and is the single place that reassigns multiplayer authority
## (only the server does so). The world scene (main.gd) registers its spawners
## here via [method register_world]; higher layers (players, items, stations)
## build on top of this in later phases.

const DEFAULT_PORT := 24565
const MAX_CLIENTS := 7

## Emitted on every peer (including the server for its own local player) when a
## player peer joins. On the server this fires for each remote peer; the server
## uses it to spawn that peer's player.
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal session_started(is_server: bool)
signal session_ended()
signal connection_failed()

# World hooks, registered by main.gd once the scene tree exists.
var _world: Node = null
var _players_spawner: MultiplayerSpawner = null
var _items_spawner: MultiplayerSpawner = null

var _log_file: FileAccess


func _ready() -> void:
	_open_log()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Public API ------------------------------------------------------------

## Start hosting. The host is peer 1 and also plays (listen server).
func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		log_line("HOST failed to create_server on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	log_line("HOST started on port %d (peer id %d)" % [port, multiplayer.get_unique_id()])
	session_started.emit(true)
	# The host's own local player joins immediately.
	_on_player_present(multiplayer.get_unique_id())
	return OK


## Join an existing host.
func join(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		log_line("JOIN failed to create_client %s:%d: %s" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	log_line("JOIN connecting to %s:%d ..." % [address, port])
	return OK


## Leave the session and tear down transport.
func leave() -> void:
	_go_offline()
	log_line("Session ended")
	session_ended.emit()


# Restore Godot's default OfflineMultiplayerPeer (rather than leaving the peer
# null), so is_multiplayer_authority()/get_unique_id() keep working while we are
# back in single-player / menu state.
func _go_offline() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


# --- Item spawning ---------------------------------------------------------

## Spawn a networked item. Server-only when online (replicates to all peers via
## the ItemsSpawner); works directly when offline. Returns the new node on the
## machine that owns spawning, else null.
func spawn_item(scene_path: String, xform: Transform3D) -> Node:
	if is_online() and not is_server():
		return null
	var data := {"scene": scene_path, "xform": xform}
	if is_online() and _items_spawner:
		return _items_spawner.spawn(data)
	# Offline: instantiate directly under the world.
	var inst := _spawn_item_from_data(data)
	if _world and inst:
		_world.add_child(inst)
	return inst


# MultiplayerSpawner custom spawn function: runs on every peer to build the node
# from the replicated payload.
func _spawn_item_from_data(data: Variant) -> Node:
	var scene: PackedScene = load(data["scene"])
	if not scene:
		push_error("spawn_item: could not load scene %s" % str(data.get("scene")))
		return null
	var inst := scene.instantiate()
	if inst is Node3D:
		inst.transform = data["xform"]
	return inst


# --- Item grab-authority transfer -----------------------------------------

## A client (or host) requests authority over an item it just grabbed. Runs on
## the server. If the item was snapped into a station, the station releases it
## so the grabber cleanly takes ownership.
@rpc("any_peer", "reliable")
func request_item_authority(item_path: NodePath) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Assign authority + held state first (disables the item on the server so its
	# snap zone won't re-grab it), then release it from any station.
	_set_item_authority.rpc(item_path, sender)
	var item := get_node_or_null(item_path)
	if item:
		_release_from_snap_zones(item)


## A player releases an item, forwarding its throw velocity so the server can
## resume simulating it. Runs on the server. If released next to a station, the
## server snaps it in (server-authoritative placement).
@rpc("any_peer", "reliable")
func release_item_authority(item_path: NodePath, lin: Vector3, ang: Vector3) -> void:
	if not is_server():
		return
	_set_item_authority.rpc(item_path, 1)
	var item := get_node_or_null(item_path)
	if item is RigidBody3D:
		item.freeze = false
		item.linear_velocity = lin
		item.angular_velocity = ang
	_try_snap_into_station(item)


# All station snap zones in the world (nodes in the "station" group).
func _station_snap_zones() -> Array:
	var zones := []
	for station in get_tree().get_nodes_in_group("station"):
		var zone = station.get_node_or_null("XRToolsSnapZone")
		if zone:
			zones.append(zone)
	return zones


# If the item is snapped into any station, drop it from that station.
func _release_from_snap_zones(item: Node) -> void:
	for zone in _station_snap_zones():
		if zone.picked_up_object == item:
			zone.drop_object()


# Snap the item into the nearest empty station snap zone within grab range.
func _try_snap_into_station(item: Node) -> void:
	if not (item is Node3D):
		return
	for zone in _station_snap_zones():
		if is_instance_valid(zone.picked_up_object):
			continue
		if zone.global_position.distance_to(item.global_position) <= zone.grab_distance:
			zone.pick_up_object(item)
			return


# Server broadcasts an authority assignment so every peer agrees on who owns the
# item (set_multiplayer_authority is a local call and must run everywhere).
@rpc("authority", "call_local", "reliable")
func _set_item_authority(item_path: NodePath, peer: int) -> void:
	var item := get_node_or_null(item_path)
	if not item:
		return
	item.set_multiplayer_authority(peer)  # recursive: item + synchronizer + NetPickable
	var np := item.get_node_or_null("NetPickable")
	if np:
		np.net_held_by = 0 if peer == 1 else peer
		np.apply_held_state()


func is_server() -> bool:
	return is_online() and multiplayer.is_server()


## True only when a real ENet session is active. Godot installs a default
## OfflineMultiplayerPeer, so a non-null peer alone does not mean "online".
func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer)


## True on the machine that owns authoritative world logic: the server when
## online, or the single player when offline. Station logic and spawning should
## only run where this is true, so state has one source of truth.
func owns_world() -> bool:
	return not is_online() or is_server()


# --- Station work-progress seam -------------------------------------------

## Reusable entry point for a client to contribute work to a station (e.g. a
## future chopping/gesture station). The client detects the gesture locally and
## calls this; the server validates and accumulates. Timer-driven stations like
## the Hob don't need it, but it is the drop-in seam for input-driven ones.
@rpc("any_peer", "reliable")
func submit_work(station_path: NodePath, amount: float) -> void:
	if not is_server():
		return
	var station := get_node_or_null(station_path)
	if station and station.has_method("add_work"):
		station.add_work(multiplayer.get_remote_sender_id(), amount)


## Called by main.gd once the world scene is ready, passing its spawners.
func register_world(world: Node, players_spawner: MultiplayerSpawner, items_spawner: MultiplayerSpawner) -> void:
	_world = world
	_players_spawner = players_spawner
	_items_spawner = items_spawner
	if _items_spawner:
		_items_spawner.spawn_function = _spawn_item_from_data
	log_line("World registered (players_spawner=%s items_spawner=%s)" % [str(players_spawner != null), str(items_spawner != null)])


## Called by main.gd after it has registered the world and connected its
## player_joined/left listeners. Kicks off any menu- or command-line-driven
## session so that session signals never fire before the world is listening.
func world_ready() -> void:
	consume_pending_session()


# --- Menu-driven session request -------------------------------------------

# Set by the main menu's Host/Join buttons before switching to the multiplayer
# scene; consumed once that scene's world is ready to listen for session
# signals (avoids a race between change_scene_to_file and connection callbacks).
var pending_action := ""
var pending_ip := ""

func request_host() -> void:
	pending_action = "host"

func request_join(ip: String) -> void:
	pending_action = "join"
	pending_ip = ip

func consume_pending_session() -> void:
	if pending_action == "host":
		pending_action = ""
		host()
	elif pending_action == "join":
		pending_action = ""
		join(pending_ip)
	else:
		_handle_cmdline()


# --- Session signal handlers ----------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	log_line("peer_connected: %d" % peer_id)
	# Only the server reacts by materialising that peer's player.
	if is_server():
		_on_player_present(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	log_line("peer_disconnected: %d" % peer_id)
	if is_server():
		_on_player_absent(peer_id)

func _on_connected_to_server() -> void:
	log_line("connected_to_server (my id=%d)" % multiplayer.get_unique_id())
	session_started.emit(false)

func _on_connection_failed() -> void:
	log_line("connection_failed")
	_go_offline()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	log_line("server_disconnected")
	_go_offline()
	session_ended.emit()


# Player materialise/dematerialise. Phase 2 wires these to the PlayersSpawner;
# for now they announce presence so the transport layer is independently testable.
func _on_player_present(peer_id: int) -> void:
	log_line("player_present: %d" % peer_id)
	player_joined.emit(peer_id)

func _on_player_absent(peer_id: int) -> void:
	log_line("player_absent: %d" % peer_id)
	player_left.emit(peer_id)


# --- Command-line driven test bootstrap -----------------------------------

func _handle_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		log_line("cmdline: --server")
		host()
	elif args.has("--join"):
		var idx := args.find("--join")
		var addr := "127.0.0.1"
		if idx + 1 < args.size():
			addr = args[idx + 1]
		log_line("cmdline: --join %s" % addr)
		join(addr)


# --- Logging ---------------------------------------------------------------

func _open_log() -> void:
	var dir := OS.get_environment("TEMP")
	if dir.is_empty():
		dir = OS.get_environment("TMPDIR")
	if dir.is_empty():
		dir = "user://"
	var path := dir.path_join("vryhungry_net_%d.log" % OS.get_process_id())
	_log_file = FileAccess.open(path, FileAccess.WRITE)
	log_line("=== NetworkManager log (pid %d) ===" % OS.get_process_id())

func log_line(s: String) -> void:
	var id := 0
	var p := multiplayer.multiplayer_peer
	if p != null and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		id = multiplayer.get_unique_id()
	var line := "[NET %d] %s" % [id, s]
	print(line)
	if _log_file:
		_log_file.store_line(line)
		_log_file.flush()
