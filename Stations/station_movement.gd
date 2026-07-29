extends Node3D

@onready var move_handle: XRToolsPickable = $MoveHandle
@onready var move_handle_rigid: RigidBody3D = $MoveHandle

@onready var hob: StaticBody3D = $".."

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	move_handle_rigid.linear_velocity = Vector3.ZERO
	move_handle_rigid.angular_velocity = Vector3.ZERO
	hob.global_position.x = move_handle.global_position.x
	hob.global_position.z = move_handle.global_position.z
