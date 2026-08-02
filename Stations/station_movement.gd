extends Node

@export var snap_grid_size: float = 0.6

@export var move_handle: XRToolsPickable
@export var move_ghost: Area3D
@export var station: StaticBody3D

var move_handle_rigid: RigidBody3D
var original_collision_layer: int = 0
var original_y_pos: float = 0.0
var original_station_transform: Transform3D = Transform3D.IDENTITY
var moving: bool = false
var ghost_materials: Array[StandardMaterial3D] = []

const GHOST_COLOR_VALID: Color = Color(0, 1, 0, 0.35)
const GHOST_COLOR_INVALID: Color = Color(1, 0, 0, 0.35)


func set_move_handle_enabled(enabled: bool) -> void:
	move_handle.visible = enabled
	move_handle.enabled = enabled
	if enabled:
		move_handle.drop()


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	set_move_handle_enabled(new_state == GameManager.GameState.BUILDING)


func _ready() -> void:
	if not station:
		push_error("StationMovement is missing referece to station")
	if not move_handle:
		push_error("StationMovement is missing reference to move_handle")
	if not move_ghost:
		push_error("StationMovement is missing reference to move_ghost")

	move_handle_rigid = move_handle as RigidBody3D
	original_collision_layer = station.collision_layer
	original_y_pos = move_handle.transform.origin.y
	original_station_transform = station.global_transform
	move_handle.picked_up.connect(_handle_pickup)
	move_handle.dropped.connect(_handle_drop)

	move_ghost.monitoring = true
	move_ghost.visible = false
	_cache_ghost_materials()
	_set_ghost_color(GHOST_COLOR_VALID)
	set_move_handle_enabled(false)
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
	moving = true
	move_ghost.visible = true
	station.visible = false
	station.collision_layer = 0
	original_station_transform = station.global_transform
	move_ghost.global_transform = original_station_transform


func _handle_drop(_by: Node) -> void:
	print("StationMovement handle drop")
	moving = false
	move_ghost.visible = false
	station.visible = true
	station.collision_layer = original_collision_layer
	if _is_move_position_valid():
		station.global_transform = move_ghost.global_transform
	else:
		station.global_transform = original_station_transform
	move_handle.global_position = station.global_position + Vector3(0, original_y_pos, 0)
	move_handle.rotation = station.rotation


func _process(_delta: float) -> void:
	if not moving:
		return

	var target_transform: Transform3D = move_handle.global_transform
	target_transform.origin.x = snappedf(target_transform.origin.x, snap_grid_size)
	target_transform.origin.z = snappedf(target_transform.origin.z, snap_grid_size)
	target_transform.origin.y = original_station_transform.origin.y
	var target_yaw: float = snappedf(move_handle.global_rotation_degrees.y, 90)
	target_transform.basis = Basis(Vector3.UP, deg_to_rad(target_yaw))

	move_ghost.global_transform = target_transform
	if _is_move_position_valid():
		_set_ghost_color(GHOST_COLOR_VALID)
	else:
		_set_ghost_color(GHOST_COLOR_INVALID)


func _is_move_position_valid() -> bool:
	for body in move_ghost.get_overlapping_bodies():
		print("Overlapping body: ", body)
		if body == move_handle:
			continue
		if body == station:
			continue
		return false

	for area in move_ghost.get_overlapping_areas():
		print("Overlapping area: ", area)
		if area == move_ghost:
			continue
		return false

	return true
