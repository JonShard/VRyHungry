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
	# LeftHand/RightHand are the full godot-xr-tools glove scenes, whose root
	# node carries hand.gd (XRToolsHand). That script sets top_level = true
	# and every physics frame does global_transform = get_parent().
	# global_transform * offset — i.e. it actively repositions itself to
	# track a live XRController3D parent. Here the parent is just this
	# NetPlayer node, not a controller, so left running it fights (and mostly
	# wins, since it runs every physics tick regardless of our own _process)
	# against both the local authority's transform copy below and the
	# replicated values on other peers — the exact "hands stuck near origin,
	# only occasionally correct" symptom. Disable it everywhere; nothing else
	# in that script matters here since _controller is always null without a
	# real controller ancestor (grip/trigger animation already no-ops).
	_left_hand.set_physics_process(false)
	_right_hand.set_physics_process(false)

	if is_multiplayer_authority():
		var origin := get_tree().get_first_node_in_group("local_xr_origin")
		if origin:
			_local_camera = origin.get_node_or_null("XRCamera3D")
			_local_left_hand = origin.get_node_or_null("XRControllerLeftHand")
			_local_right_hand = origin.get_node_or_null("XRControllerRightHand")
			# Every peer's rig is baked at the same spot in the scene; spread
			# joiners out along X so they don't start stacked on top of each
			# other. Peer ids from ENet are large effectively-random 32-bit
			# numbers, so this must be bounded, AND kept well within the
			# floor's actual footprint (15x15, so ~7.5 units from center) —
			# a previous version used up to 12 units and could place a
			# joining player off the edge of the floor.
			var peer_id := str(name).to_int()
			if peer_id != 1:
				var slot := absi(peer_id) % 4
				origin.position += Vector3((slot - 1.5) * 1.2, 0, 0)
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
