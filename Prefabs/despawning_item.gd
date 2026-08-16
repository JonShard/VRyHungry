extends Node
class_name DespawningItem

@export var enabled: bool = true

@export var time_to_despawn: float = 8

# The minimum speed required to reset despawn timer.
@export var minimum_speed_square: float = 0.1


@onready var _pickable: XRToolsPickable = get_parent() as XRToolsPickable
@onready var _rigid: RigidBody3D = get_parent() as RigidBody3D


var _time_left: float = time_to_despawn

func _ready() -> void:
	if not _pickable:
			SweetLogger.error("{0} must be a grandchild of an XRToolsPickable", [name])
			return
	if not _rigid:
			SweetLogger.error("{0} must be a grandchild of a RigidBody3D", [name])
			return


func _process(delta: float) -> void:
	if not enabled:
		return

	# Despawning is a world decision, so only the owner of world logic runs the
	# clock. Every peer used to run its own copy: the countdown drifted between
	# them and the blink below toggled `visible` locally, so the same item was
	# shown on one peer and hidden on the other. Non-owners just follow the
	# server, which removes the item for everyone when its time is up.
	if not NetworkManager.owns_world():
		return

	# if we're held or moving, reset timer and return
	if  _pickable.get_picked_up_by() or _rigid.linear_velocity.length_squared() > pow(minimum_speed_square,2):
		_time_left = time_to_despawn
		_set_visible(true)
		return


	# Count down to zero and despawn
	_time_left -= delta
	if _time_left <= 0:
		SweetLogger.debug("Despawning {0}", [get_parent()])
		NetworkManager.despawn_item(get_parent())
		# Stop counting: despawn_item() only queues the free, so without this we
		# keep re-reporting the same item every frame until it actually goes.
		set_process(false)
		return

	# Make item blink in and out before despawning
	if _time_left < time_to_despawn / 2:
		_set_visible(int(_time_left * 5.0) % 2 == 0)


# `visible` is not a replicated property, so a blink driven only here would make
# the item flicker on the host and stay solid on clients. Until it is synced,
# only warn when there is nobody else to disagree with.
func _set_visible(value: bool) -> void:
	if NetworkManager.is_online():
		get_parent().visible = true
		return
	get_parent().visible = value
