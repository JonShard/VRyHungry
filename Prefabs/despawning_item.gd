extends Node
class_name DespawningItem

@export var time_to_despawn: float = 8

# The minimum speed required to reset despawn timer.
@export var minimum_speed_square: float = 0.1


@onready var _pickable: XRToolsPickable = get_parent() as XRToolsPickable
@onready var _rigid: RigidBody3D = get_parent() as RigidBody3D


var _time_left: float = time_to_despawn

func _ready() -> void:
	if not _pickable:
			push_error("DespawningItem must be a grand child of an XRToolsPickable.")
			return
	if not _rigid:
			push_error("DespawningItem must be a grand child of an RigidBody3D.")
			return
		

func _process(delta: float) -> void:
	print("SpeedSquare: ", _rigid.linear_velocity.length_squared())
	# if we're held or moving, reset timer and return
	if  _pickable.get_picked_up_by() or _rigid.linear_velocity.length_squared() > pow(minimum_speed_square,2):
		_time_left = time_to_despawn
		get_parent().visible = true
		print("DespawningItem resetting timer: ", get_parent())
		return
	

	# Count down to zero and despawn
	_time_left -= delta
	if _time_left <= 0:
		print("DespawningItem despawning!" , get_parent())
		NetworkManager.despawn_item(get_parent())

	# Make item blink in and out before despawning
	if _time_left < time_to_despawn / 2:
		get_parent().visible = int(_time_left * 5.0) %2 == 0
