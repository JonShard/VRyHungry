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
var _content_root: Node = null

var _log_file: FileAccess

## Reason the session ended, shown by the menu on the next _ready() (see
## take_status). Avoids depending on a live signal connection to a panel that
## doesn't exist yet at the moment the session actually ends.
var last_status := ""


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
	unregister_world()


# --- Item spawning ---------------------------------------------------------

## Spawn a networked item. Server-only when online (replicates to all peers via
## the ItemsSpawner, including late joiners); works directly when offline.
## node_name gives the spawned node a deterministic, identical name on every
## peer (needed for NodePath-based RPCs to resolve it); props are applied to
## the instance before it enters the tree, so exported vars land correctly.
## Returns the new node on the machine that owns spawning, else null.
func spawn_item(scene_path: String, xform: Transform3D, node_name: String = "", props: Dictionary = {}) -> Node:
	if is_online() and not is_server():
		return null
	var data := {"scene": scene_path, "xform": xform, "name": node_name, "props": props}
	var via := "spawner" if (is_online() and _items_spawner) else "offline"
	log_line("spawn_item: %s (name=%s, via=%s)" % [scene_path.get_file(), node_name, via])
	if is_online() and _items_spawner:
		return _items_spawner.spawn(data)
	# Offline: instantiate directly under the registered content root, or (for
	# scenes that never call register_world, e.g. the offline menu/dev scenes)
	# the current scene, so this keeps working without every offline scene
	# needing to opt in.
	var inst := _spawn_item_from_data(data)
	if inst:
		var parent: Node = _content_root if _content_root else get_tree().current_scene
		if parent:
			parent.add_child(inst)
	return inst


## Despawn a server-spawned item. MultiplayerSpawner broadcasts a despawn to
## every peer when a tracked node exits the tree on the authority, so this is
## the single seam for destroying spawned items (works offline too).
func despawn_item(node: Node) -> void:
	if owns_world() and is_instance_valid(node):
		log_line("despawn_item: %s" % node.name)
		node.queue_free()


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
	if data.get("name", "") != "":
		inst.name = data["name"]
	for key in data.get("props", {}):
		inst.set(key, data["props"][key])
	if not owns_world():
		_gate_station(inst)
	return inst


# Stations run their own logic and auto-grab (XRToolsSnapZone with
# snap_mode=RANGE) identically on every peer by default, which would let each
# peer independently grab/simulate the same shared object. Disable both on
# every peer except the one that owns world logic; the server-authoritative
# item-authority RPCs are what let clients still grab a server-held item by
# hand. Runs before the node enters the tree, so its own _ready() sees the
# final (disabled) state.
func _gate_station(node: Node) -> void:
	if not (node is StaticBody3D):
		return
	for child in node.get_children():
		if child is XRToolsSnapZone:
			child.enabled = false
			child.set_process(false)
	node.set_process(false)
	log_line("gated station (non-owner peer): %s" % node.name)


# --- Item grab-authority transfer -----------------------------------------

## Called by NetPickable when this peer grabs an item by hand. Godot rejects
## rpc_id() targeting your own peer id ("RPC on yourself is not allowed"), so
## when we ARE the server this runs the logic directly instead of round-
## tripping an RPC to ourselves — otherwise every host-side grab/drop was
## silently failing to run its server-side half (no denial checks, and
## crucially no auto-snap-into-station on release).
func request_item_authority_from(item_path: NodePath) -> void:
	if is_server():
		_grant_or_reject_item_authority(item_path, multiplayer.get_unique_id())
	else:
		_request_item_authority_rpc.rpc_id(1, item_path)


@rpc("any_peer", "reliable")
func _request_item_authority_rpc(item_path: NodePath) -> void:
	if not is_server():
		return
	_grant_or_reject_item_authority(item_path, multiplayer.get_remote_sender_id())


## Runs on the server (called directly if the requester IS the server, or via
## the RPC above otherwise). If the item was snapped into a station, the
## station releases it so the grabber cleanly takes ownership.
func _grant_or_reject_item_authority(item_path: NodePath, sender: int) -> void:
	var item := get_node_or_null(item_path)
	if item:
		var np := item.get_node_or_null("NetPickable")
		if np and np.net_held_by != 0 and np.net_held_by != sender:
			# Already legitimately held by a different live peer: reject the
			# requester's optimistic client-side grab instead of stealing it.
			log_line("request_item_authority: DENIED %s to peer %d (already held by %d)" % [item.name, sender, np.net_held_by])
			_force_release_item_to(sender, item_path)
			return
	log_line("request_item_authority: granting %s to peer %d" % [str(item.name) if item else str(item_path), sender])
	# Assign authority + held state first (disables the item on the server so its
	# snap zone won't re-grab it), then release it from any station.
	_set_item_authority.rpc(item_path, sender)
	if item:
		_release_from_snap_zones(item)


## Called by NetPickable when this peer releases an item, forwarding its throw
## velocity so the server can resume simulating it. Same self-RPC issue as
## above: runs directly if we're the server.
func release_item_authority_from(item_path: NodePath, lin: Vector3, ang: Vector3) -> void:
	if is_server():
		_do_release_item_authority(item_path, lin, ang, multiplayer.get_unique_id())
	else:
		_release_item_authority_rpc.rpc_id(1, item_path, lin, ang)


@rpc("any_peer", "reliable")
func _release_item_authority_rpc(item_path: NodePath, lin: Vector3, ang: Vector3) -> void:
	if not is_server():
		return
	_do_release_item_authority(item_path, lin, ang, multiplayer.get_remote_sender_id())


## Runs on the server. If released next to a station, the server snaps it in
## (server-authoritative placement).
func _do_release_item_authority(item_path: NodePath, lin: Vector3, ang: Vector3, sender: int) -> void:
	log_line("release_item_authority: %s released by peer %d" % [str(item_path), sender])
	_set_item_authority.rpc(item_path, 1)
	var item := get_node_or_null(item_path)
	if item is RigidBody3D:
		item.freeze = false
		item.linear_velocity = lin
		item.angular_velocity = ang
	_try_snap_into_station(item)


# All station snap zones in the world (every XRToolsSnapZone child of a node in
# the "station" group — some stations, e.g. Table, have more than one).
func _station_snap_zones() -> Array:
	var zones := []
	for station in get_tree().get_nodes_in_group("station"):
		for child in station.get_children():
			if child is XRToolsSnapZone:
				zones.append(child)
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
			log_line("snapped %s into %s" % [item.name, zone.get_parent().name])
			zone.pick_up_object(item)
			return


# Server broadcasts an authority assignment so every peer agrees on who owns the
# item (set_multiplayer_authority is a local call and must run everywhere).
@rpc("authority", "call_local", "reliable")
func _set_item_authority(item_path: NodePath, peer: int) -> void:
	var item := get_node_or_null(item_path)
	if not item:
		return
	log_line("_set_item_authority: %s -> peer %d" % [item.name, peer])
	item.set_multiplayer_authority(peer)  # recursive: item + synchronizer + NetPickable
	var np := item.get_node_or_null("NetPickable")
	if np:
		np.net_held_by = 0 if peer == 1 else peer
		np.apply_held_state()


## Rejects peer's optimistic grab (the item was already legitimately held by
## someone else). Same self-RPC concern: if the rejected peer is the server
## itself, apply it directly rather than rpc_id-ing ourselves.
func _force_release_item_to(peer: int, item_path: NodePath) -> void:
	if peer == 1:
		_do_force_release(item_path)
	else:
		force_release_item.rpc_id(peer, item_path)


@rpc("authority", "reliable")
func force_release_item(item_path: NodePath) -> void:
	_do_force_release(item_path)


func _do_force_release(item_path: NodePath) -> void:
	log_line("force_release_item: dropping %s (server rejected our grab)" % str(item_path))
	var item := get_node_or_null(item_path)
	if item and item.has_method("drop"):
		item.drop()


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
		log_line("submit_work: peer %d contributed %.2f to %s" % [multiplayer.get_remote_sender_id(), amount, station.name])
		station.add_work(multiplayer.get_remote_sender_id(), amount)


## Called by the world scene once it's ready, passing its spawners. Must run
## before world_ready()/host()/join() on every peer so the custom spawn
## function is installed before any spawn packet can arrive.
func register_world(world: Node, players_spawner: MultiplayerSpawner, items_spawner: MultiplayerSpawner) -> void:
	_world = world
	_players_spawner = players_spawner
	_items_spawner = items_spawner
	_content_root = items_spawner.get_node(items_spawner.spawn_path) if items_spawner else world
	if _items_spawner:
		_items_spawner.spawn_function = _spawn_item_from_data
	log_line("World registered (players_spawner=%s items_spawner=%s)" % [str(players_spawner != null), str(items_spawner != null)])


## Called when the world scene goes away (disconnect, leaving the session) so
## the autoload doesn't hold stale/freed references across a scene reload.
func unregister_world() -> void:
	_world = null
	_content_root = null
	_players_spawner = null
	_items_spawner = null


## Returns the reason the last session ended (if any) and clears it. The menu
## pulls this on its own _ready() rather than depending on a live signal
## connection to a panel that doesn't exist yet when the session ends.
func take_status() -> String:
	var s := last_status
	last_status = ""
	return s


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
	last_status = "Could not connect"
	connection_failed.emit()

func _on_server_disconnected() -> void:
	log_line("server_disconnected")
	_go_offline()
	last_status = "Host disconnected"
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
