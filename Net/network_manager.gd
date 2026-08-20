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
## Godot's fixed peer id for the server.
const SERVER_PEER_ID := 1

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
	if not owns_world() or not is_instance_valid(node):
		return
	log_line("despawn_item: %s" % node.name)
	# Items that came from the ItemsSpawner are despawned on every peer
	# automatically when they leave the tree here. Items baked into a scene file
	# are unknown to the spawner, so their removal has to be broadcast
	# explicitly — otherwise every client keeps a ghost copy of an item the
	# server has consumed, which then blocks the station it was sitting in and
	# gets grabbed instead of the real item that replaced it.
	if is_online() and not _is_spawner_tracked(node):
		_despawn_static_item.rpc(node.get_path())
	node.queue_free()


# Items the ItemsSpawner replicates live under its spawn path; anything else was
# baked into the scene file and the spawner knows nothing about it.
func _is_spawner_tracked(node: Node) -> bool:
	return _content_root != null and _content_root.is_ancestor_of(node)


@rpc("authority", "call_remote", "reliable")
func _despawn_static_item(path: NodePath) -> void:
	var node := get_node_or_null(path)
	if node:
		log_line("despawn_static_item: freeing %s (the server consumed it)" % node.name)
		node.queue_free()


# MultiplayerSpawner custom spawn function: runs on every peer to build the node
# from the replicated payload.
func _spawn_item_from_data(data: Variant) -> Node:
	var scene: PackedScene = load(data["scene"])
	if not scene:
		SweetLogger.error("Could not load scene {0}", [str(data.get("scene"))])
		return null
	var inst := scene.instantiate()
	if inst is Node3D:
		inst.transform = data["xform"]
	if data.get("name", "") != "":
		inst.name = data["name"]
	for key in data.get("props", {}):
		inst.set(key, data["props"][key])
	return inst

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
		if np and np.net_held_by != NetPickable.NOT_HELD and np.net_held_by != sender:
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
func release_item_authority_from(item_path: NodePath, lin: Vector3, ang: Vector3, xform: Transform3D) -> void:
	if is_server():
		_do_release_item_authority(item_path, lin, ang, xform, multiplayer.get_unique_id())
	else:
		_release_item_authority_rpc.rpc_id(1, item_path, lin, ang, xform)


@rpc("any_peer", "reliable")
func _release_item_authority_rpc(item_path: NodePath, lin: Vector3, ang: Vector3, xform: Transform3D) -> void:
	if not is_server():
		return
	_do_release_item_authority(item_path, lin, ang, xform, multiplayer.get_remote_sender_id())


## Runs on the server. If released next to a station, the server snaps it in
## (server-authoritative placement).
func _do_release_item_authority(item_path: NodePath, lin: Vector3, ang: Vector3, xform: Transform3D, sender: int) -> void:
	log_line("release_item_authority: %s released by peer %d" % [str(item_path), sender])
	_set_item_authority.rpc(item_path, 1)
	var item := get_node_or_null(item_path)
	if item is RigidBody3D:
		# Adopt the releasing peer's own final transform rather than trusting our
		# copy's. That peer was the item's authority right up to this moment, and
		# its position updates travel on the synchronizer's separate, unordered
		# channel — this reliable RPC routinely overtakes them, leaving our copy
		# still sitting where the item was BEFORE the peer carried it away. The
		# snap decision below then reads that stale position and teleports the
		# item straight back into the station it was just picked up from.
		item.global_transform = xform
		item.freeze = false
		item.linear_velocity = lin
		item.angular_velocity = ang
	_try_snap_into_station.call_deferred(item)


# All station snap zones in the world (every XRToolsSnapZone under a node in the
# "station" group — some stations, e.g. Table, have more than one). Derived from
# the station body rather than from the "station_zone" group directly, so zones
# that are deliberately not server-placeable (the player's Hatch) stay out.
func _station_snap_zones() -> Array:
	var zones := []
	for station in get_tree().get_nodes_in_group("station"):
		for zone in station.find_children("*", "XRToolsSnapZone", true, false):
			if not zones.has(zone):
				zones.append(zone)
	return zones


# If the item is snapped into any station, drop it from that station.
func _release_from_snap_zones(item: Node) -> void:
	for zone in _station_snap_zones():
		if zone.picked_up_object == item:
			log_line("releasing %s from %s's snap zone (authority just granted elsewhere)" % [item.name, zone.get_parent().name])
			zone.drop_object()
		# Make the zone forget the item as well. These zones are snap_mode=RANGE,
		# so every frame they re-grab anything still listed in their grab area
		# that can be picked up — and Jolt does not emit body_exited when let_go()
		# switches the item's collision layer back out of the zone's mask, so the
		# entry goes stale and never clears. The station then snatches the item
		# straight back off the player who just took it, teleporting it home.
		# Bringing it near again re-adds it properly (a held item is on the layer
		# the zone watches), and releasing next to a station is handled
		# explicitly by _try_snap_into_station.
		if zone._object_in_grab_area.has(item):
			zone._object_in_grab_area.erase(item)


# Snap the item into the nearest empty station snap zone within grab range.
#
# Called deferred from _do_release_item_authority: XRToolsFunctionPickup's own
# "grab an item out of a snap zone" path calls zone.drop_object() BEFORE it
# calls pick_up() on the hand's behalf. drop_object()'s let_go() synchronously
# fires the pickable's `dropped` signal, which (via NetPickable) lands here —
# if this ran synchronously it would immediately re-snap the item into the
# very same zone it's still physically inside, stealing it away before the
# hand's own pick_up() call (later in the same call stack) ever runs. That
# leaves XRToolsFunctionPickup.picked_up_object pointing at an item whose
# _grab_driver actually belongs to the zone — a stale reference that crashes
# (null _grab_driver) the next time a controller button is pressed. Deferring
# lets the hand's pick_up() go first; the is_picked_up() check below is a
# second guard in case the item gets grabbed for real before this runs.
func _try_snap_into_station(item: Node) -> void:
	if not (item is Node3D):
		return
	if item.has_method("is_picked_up") and item.is_picked_up():
		var by: Node = null
		if item.has_method("get_picked_up_by"):
			by = item.get_picked_up_by()
		log_line("skipped snapping %s: already held by %s (grab-race guard)" % [item.name, str(by.get_path()) if by else "?"])
		return
	for zone in _station_snap_zones():
		if is_instance_valid(zone.picked_up_object):
			continue
		if zone.global_position.distance_to(item.global_position) <= zone.grab_distance:
			log_line("snapped %s into %s" % [item.name, zone.get_parent().name])
			zone.pick_up_object(item)
			return
	log_line("no station in range to snap %s into (or none empty)" % item.name)


# Server broadcasts an authority assignment so every peer agrees on who owns the
# item (set_multiplayer_authority is a local call and must run everywhere).
@rpc("authority", "call_local", "reliable")
func _set_item_authority(item_path: NodePath, peer: int) -> void:
	var item := get_node_or_null(item_path)
	if not item:
		return
	log_line("_set_item_authority: %s -> peer %d" % [item.name, peer])
	item.set_multiplayer_authority(peer)  # recursive: item + synchronizer + NetPickable
	# ...except an ItemContainer under it. Deciding what a plate absorbs stays a
	# server call, broadcast with an "authority" RPC — and Godot only lets a
	# node's current authority send those. Letting the recursion above hand the
	# container to whichever client is holding the plate made the client reject
	# the server's own everyone_absorb_item, so the food was absorbed on the
	# server only and stayed loose (and grabbable, at its old path) on the client.
	var container := Helper.find_first_child_of_type(item, ItemContainer)
	if container:
		container.set_multiplayer_authority(SERVER_PEER_ID)
	var np := item.get_node_or_null("NetPickable")
	if np:
		np.net_held_by = NetPickable.NOT_HELD if peer == SERVER_PEER_ID else peer
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
	if is_online():
		return
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
	SweetLogger.debug("->[]")
	var args := OS.get_cmdline_args()
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
	SweetLogger.info(line, [], "network_manager.gd", "log_line")
	if _log_file:
		_log_file.store_line(line)
		_log_file.flush()
