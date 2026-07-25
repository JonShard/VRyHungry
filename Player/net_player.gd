extends Node3D

## Networked representation of one connected player. The owning peer's local
## XR rig (found via the "local_xr_origin" group) drives Head/LeftHand/
## RightHand each frame; the MultiplayerSynchronizer replicates those
## transforms so every other peer sees a matching avatar.

@onready var _head: Node3D = $Head
@onready var _left_hand: Node3D = $LeftHand
@onready var _right_hand: Node3D = $RightHand

var _local_camera: Node3D
var _local_left_hand: Node3D
var _local_right_hand: Node3D


func _enter_tree() -> void:
	# MultiplayerSynchronizer resolves authority when this node enters the
	# tree, so authority must be set here rather than in _ready(), or the
	# first synced frames go the wrong direction.
	set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	if is_multiplayer_authority():
		var origin := get_tree().get_first_node_in_group("local_xr_origin")
		if origin:
			_local_camera = origin.get_node_or_null("XRCamera3D")
			_local_left_hand = origin.get_node_or_null("XRControllerLeftHand")
			_local_right_hand = origin.get_node_or_null("XRControllerRightHand")
			# Every peer's rig is baked at the same spot in the scene; spread
			# joiners out along X by peer id so they don't start stacked on
			# top of each other (host/peer 1 keeps the original spot).
			var peer_id := str(name).to_int()
			origin.position += Vector3((peer_id - 1) * 1.5, 0, 0)
		# Don't render your own floating head/hands from the inside.
		_head.visible = false
		_left_hand.visible = false
		_right_hand.visible = false
	else:
		set_process(false)


func _process(_delta: float) -> void:
	if _local_camera:
		_head.global_transform = _local_camera.global_transform
	if _local_left_hand:
		_left_hand.global_transform = _local_left_hand.global_transform
	if _local_right_hand:
		_right_hand.global_transform = _local_right_hand.global_transform
