extends Node

@export var snap_grid_size: float = 0.6

@export var move_handle: XRToolsPickable
@export var move_ghost: Area3D
@export var station: StaticBody3D

var move_handle_rigid: RigidBody3D
var original_collision_layer
var original_y_pos: float

# TODO: Reject placing station in occupied spot.
# TODO: Make ghost version of station that is displayed instead of model.
# TODO: public toggle to disable handle in build mode.
# TODO: If game exits build mode, drop the handle before  disabling it.


func _ready() -> void:
	if not station:
		push_error("StationMovement is missing referece to station")
		
	move_handle_rigid = move_handle as RigidBody3D
	original_collision_layer = station.collision_layer
	original_y_pos = move_handle.transform.origin.y
	move_handle.picked_up.connect(_handle_pickup)
	move_handle.dropped.connect(_handle_drop)


func _handle_pickup(_by):
	print("StationMovement handle pickup")
	station.collision_layer = 0	
		
		
func _handle_drop(_by):
	print("StationMovement handle drop")
	station.collision_layer = original_collision_layer
	move_handle.global_position = station.global_position + Vector3(0, original_y_pos, 0)
	move_handle.rotation = station.rotation


func _process(_delta: float) -> void:
	station.global_position.x = snappedf(move_handle.global_position.x, snap_grid_size)
	station.global_position.z = snappedf(move_handle.global_position.z, snap_grid_size)
	station.global_rotation_degrees.y = snappedf(move_handle.global_rotation_degrees.y, 90)
	
