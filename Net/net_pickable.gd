extends MultiplayerSynchronizer

## Networked sync component for a pickable item. Added as a child literally
## named "NetPickable" (network_manager.gd's authority RPCs already expect
## this) of every net-synced pickable, replicating its transform and held
## state. Only the current multiplayer authority (the server while loose, or
## whichever peer is holding it) actually simulates physics for the item;
## every other peer freezes their local copy and just follows the synced
## transform.

## 0 = loose/server-simulated; otherwise the peer id currently holding it.
## Replicated at spawn and on change so a late joiner sees the current holder.
var net_held_by: int = 0: set = _set_net_held_by

var _pickable: XRToolsPickable


func _ready() -> void:
	_pickable = get_parent() as XRToolsPickable
	if not _pickable:
		push_error("NetPickable must be a child of an XRToolsPickable")
		return
	_pickable.picked_up.connect(_on_picked_up)
	_pickable.dropped.connect(_on_dropped)
	# Deferred: the pickable root captures its own original_collision_mask/
	# original_collision_layer via @onready, which runs AFTER this child's
	# _ready() but BEFORE the root's _ready() body. Calling apply_held_state
	# synchronously here would freeze/mask the item before that capture runs,
	# permanently corrupting the "restore on drop" values.
	apply_held_state.call_deferred()


func _set_net_held_by(value: int) -> void:
	net_held_by = value
	apply_held_state()


## Puts the item in the right physics state for whether this peer currently
## owns it. Called locally after net_held_by changes, and directly by
## NetworkManager._set_item_authority right after an authority handoff.
func apply_held_state() -> void:
	if not _pickable:
		return
	if not NetworkManager.is_online() or is_multiplayer_authority():
		# We own this item's simulation (offline, loose+server, or currently
		# holding it): leave physics alone, XRToolsPickable manages the rest.
		return
	# Someone else owns it: stop simulating locally, just follow the sync.
	if _pickable.is_picked_up():
		_pickable.drop()
	_pickable.freeze = true
	_pickable.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_pickable.collision_mask = 0
	_pickable.enabled = (net_held_by == 0)


## Local hand grab (not a station snap zone, which is server-only): request
## authority immediately so the throw/drop can be reconciled, but let the grab
## happen instantly here rather than waiting on the round trip.
func _on_picked_up(_p) -> void:
	var by := _pickable.get_picked_up_by()
	if not (by is XRToolsFunctionPickup):
		return
	NetworkManager.request_item_authority.rpc_id(1, _pickable.get_path())


func _on_dropped(_p) -> void:
	# Only forward if we're actually still the authority — a drop caused by
	# apply_held_state() losing authority (see above) must not re-report.
	if not is_multiplayer_authority():
		return
	NetworkManager.release_item_authority.rpc_id(
		1, _pickable.get_path(), _pickable.linear_velocity, _pickable.angular_velocity
	)
