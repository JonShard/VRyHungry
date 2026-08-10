class_name StationMovement
extends Node

@export var move_handle: XRToolsPickable
@export var move_ghost: Area3D
@export var station: StaticBody3D

var move_handle_rigid: RigidBody3D
var original_collision_layer: int = 0
var original_handle_y_pos: float = 0.0
var original_station_transform: Transform3D = Transform3D.IDENTITY
@export var moving: bool = false
var ghost_materials: Array[StandardMaterial3D] = []

# Ghost update throttling (clients send unreliable RPCs to server at this rate)
var ghost_send_interval: float = 0.1  # seconds (10 Hz)
var _ghost_send_accum: float = 0.0

const GHOST_COLOR_VALID: Color = Color(0, 1, 0, 0.35)
const GHOST_COLOR_INVALID: Color = Color(1, 0, 0, 0.35)


func set_move_handle_enabled(enabled: bool) -> void:
	print("StationMovement set_move_handle_enabled: ", enabled)
	move_handle.visible = enabled
	move_handle.enabled = enabled
	if enabled:
		move_handle.drop()


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	set_move_handle_enabled(new_state == GameManager.GameState.BUILDING)

func _on_station_bought(_instance: Node3D):
	print("StationMovement _on_station_bought")
	if GameManager.game_state == GameManager.GameState.BUILDING:
		set_move_handle_enabled(true)
		
func _ready() -> void:
	if not station:
		push_error("StationMovement is missing referece to station")
	if not move_handle:
		push_error("StationMovement is missing reference to move_handle")
	if not move_ghost:
		push_error("StationMovement is missing reference to move_ghost")

	move_handle_rigid = move_handle as RigidBody3D
	original_collision_layer = station.collision_layer
	original_handle_y_pos = move_handle.transform.origin.y
	original_station_transform = station.global_transform
	move_handle.picked_up.connect(_handle_pickup)
	move_handle.dropped.connect(_handle_drop)
	Signals.station_bought.connect(_on_station_bought)

	move_ghost.monitoring = true
	move_ghost.visible = false
	_cache_ghost_materials()
	_set_ghost_color(GHOST_COLOR_VALID)
	set_move_handle_enabled(GameManager.game_state == GameManager.GameState.BUILDING)
	Signals.game_state_changed.connect(_on_game_state_changed)


func _cache_ghost_materials() -> void:
	var combiner = move_ghost.get_node_or_null("CSGCombiner3D")
	if not combiner:
		return
	_collect_ghost_materials(combiner)


func _collect_ghost_materials(node: Node) -> void:
	if node is CSGCombiner3D:
		# Combiner nodes do not expose a material property to modify.
		for child in node.get_children():
			_collect_ghost_materials(child)
		return

	if node is CSGShape3D:
		var material = node.material
		if material and material is StandardMaterial3D:
			var instance = material.duplicate() as StandardMaterial3D
			instance.transparency = material.transparency
			instance.albedo_color = material.albedo_color
			node.material = instance
			ghost_materials.append(instance)

	for child in node.get_children():
		_collect_ghost_materials(child)


func _set_ghost_color(color: Color) -> void:
	for material in ghost_materials:
		material.albedo_color = color


func _handle_pickup(_by: Node) -> void:
	print("StationMovement handle pickup")
	if move_handle.get_picked_up_by() is XRToolsSnapZone:
		print("StationMovement handle pickup by snap zone, dropping and resetting position")
		move_handle.drop()
		move_handle.global_position = station.global_position + Vector3(0, original_handle_y_pos, 0)
		move_handle.rotation = station.rotation
		return
	
	moving = true
	station.collision_layer = 0
	original_station_transform = station.global_transform
	move_ghost.global_transform = original_station_transform
	if NetworkManager.is_online():
		# Ask the server to update visibility (reliable)
		server_update_visibility.rpc_id(1, true, false)
	else:
		# If not connected to server (single-player or test), apply locally
		move_ghost.visible = true
		station.visible = false


func _handle_drop(_by: Node) -> void:
	print("StationMovement handle drop")
	moving = false
	move_ghost.visible = false
	station.visible = true
	station.collision_layer = original_collision_layer

	var is_valid: bool = _is_move_position_valid()
	if NetworkManager.is_online():
		server_handle_drop.rpc_id(1, move_ghost.global_transform, is_valid)
	else:
		# If not connected to server (single-player or test), apply locally only when valid
		if is_valid:
			station.global_transform = move_ghost.global_transform
			move_handle.global_transform = move_ghost.global_transform.translated(Vector3(0, original_handle_y_pos, 0))
			print("StationMovement handle drop (local apply), station authority: ", station.get_multiplayer_authority(), " move_handle authority: ", move_handle.get_multiplayer_authority())
		else:
			station.global_transform = original_station_transform
			move_handle.global_transform = original_station_transform.translated(Vector3(0, original_handle_y_pos, 0))
			print("StationMovement handle drop (local reject), restoring original position")

func _process(_delta: float) -> void:
	if not moving:
		return

	# Update the ghost locally for instant feedback and send throttled unreliable RPCs to the server
	move_ghost.visible = true
	station.visible = false

	move_ghost.global_transform = Helper.get_snapped_transform(move_handle)
	move_ghost.global_transform.origin.y = original_station_transform.origin.y
	
	var ghost_color = GHOST_COLOR_VALID if _is_move_position_valid() else GHOST_COLOR_INVALID
	_set_ghost_color(ghost_color)

	# Throttle and send ghost transform updates to server so other clients see the preview
	_ghost_send_accum += _delta
	if _ghost_send_accum >= ghost_send_interval:
		_ghost_send_accum = 0.0
		# Unreliable RPC to the server to update the server-side ghost; server will replicate to clients
		# Use rpc_unreliable_id to avoid blocking traffic
		if NetworkManager.is_online():
			server_update_move_ghost_transform.rpc_id(1, move_ghost.global_transform, ghost_color)


func _is_move_position_valid() -> bool:
	for body in move_ghost.get_overlapping_bodies():
		print("Overlapping body: ", body)
		if body == move_handle:
			continue
		if body == station:
			continue
		# If body is a pickable that is held by a snapzone that is part of this station
		var pickable = body as XRToolsPickable
		if pickable and pickable is XRToolsPickable and Helper.is_node_decendant_of(pickable.get_picked_up_by(), get_parent()):
				continue
				
		return false

	for area in move_ghost.get_overlapping_areas():
		#print("Overlapping area: ", area)
		if area == move_ghost:
			continue
		return false

	return true


@rpc("any_peer", "call_remote", "reliable")
func server_handle_drop(new_transform: Transform3D, client_thinks_valid: bool):
	if not multiplayer.is_server():
		return
	if not (client_thinks_valid):
		# Reset state for everyone, including server
		var original_trans = original_station_transform # Make a copy to avoid server_update_station_transform setting it before move handle uses it
		server_update_station_transform.rpc(original_trans)
		server_update_move_ghost_transform.rpc(original_trans)
		server_update_handle_transform.rpc(original_trans.translated(Vector3(0, original_handle_y_pos, 0)))
		server_update_visibility.rpc(false, true)
		print("StationMovement server_handle_drop: transform rejected (invalid)")
		return

	server_update_station_transform.rpc(new_transform)
	server_update_move_ghost_transform.rpc(new_transform)
	server_update_handle_transform.rpc(new_transform.translated(Vector3(0, original_handle_y_pos, 0)))
	server_update_visibility.rpc(false, true)
	
	print("StationMovement server_handle_drop: transform applied")


@rpc("any_peer", "call_local", "reliable") # Server updates clients
func server_update_station_transform(new_transform: Transform3D) -> void:
	print("StationMovement server_update_station_transform")
	station.global_transform = new_transform
	original_station_transform = new_transform


@rpc("any_peer", "call_local", "reliable") # Server updates clients
func server_update_handle_transform(new_transform: Transform3D) -> void:
	print("StationMovement server_update_handle_transform")
	move_handle.global_transform = new_transform



@rpc("any_peer", "call_local", "reliable")
func server_update_visibility(ghost_visible: bool, station_visible: bool) -> void:
	print("StationMovement server_update_visibility")
	move_ghost.visible = ghost_visible
	station.visible = station_visible


@rpc("any_peer", "call_local", "unreliable")
func server_update_move_ghost_transform(new_transform: Transform3D, new_color: Color = Color.YELLOW) -> void:
	print("StationMovement server_update_move_ghost_transform")
	move_ghost.global_transform = new_transform
	_set_ghost_color(new_color)
