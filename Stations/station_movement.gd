extends Node3D

@export var snap_grid_size: float = 0.6
@onready var move_handle: XRToolsPickable = $MoveHandle

@onready var move_handle_rigid: RigidBody3D = $MoveHandle
@onready var station: StaticBody3D = $"../Station"

var original_collision_layer

func _ready() -> void:
	original_collision_layer = station.collision_layer


func _process(_delta: float) -> void:
	if move_handle.is_picked_up():
		station.collision_layer = 0
	else:
		station.collision_layer = original_collision_layer
	
	move_handle_rigid.linear_velocity = Vector3.ZERO
	move_handle_rigid.angular_velocity = Vector3.ZERO
	
	station.global_position.x = snappedf(move_handle.global_position.x, snap_grid_size)
	station.global_position.z = snappedf(move_handle.global_position.z, snap_grid_size)
	station.global_rotation_degrees.y = snappedf(move_handle.global_rotation_degrees.y, 90)
	
