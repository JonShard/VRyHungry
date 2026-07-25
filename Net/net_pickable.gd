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

# This item's own baked freeze_mode (e.g. plate.tscn bakes KINEMATIC, not the
# RigidBody3D default of STATIC) — captured once so it can be restored when
# this peer regains ownership, instead of getting stuck on whatever
# apply_held_state() last forced it to while non-authority.
var _original_freeze_mode: int


func _ready() -> void:
	_pickable = get_parent() as XRToolsPickable
	if not _pickable:
		push_error("NetPickable must be a child of an XRToolsPickable")
		return
	_original_freeze_mode = _pickable.freeze_mode
	_pickable.picked_up.connect(_on_picked_up)
	_pickable.dropped.connect(_on_dropped)
	# Deferred: the pickable root captures its own original_collision_mask/
	# original_collision_layer via @onready, which runs AFTER this child's
	# _ready() but BEFORE the root's _ready() body. Calling apply_held_state
	# synchronously here would freeze/mask the item before that capture runs,
	# permanently corrupting the "restore on drop" values.
	apply_held_state.call_deferred()


func _set_net_held_by(value: int) -> void:
	var old := net_held_by
	net_held_by = value
	if old != value and NetworkManager.is_online():
		NetworkManager.log_line("%s net_held_by: %d -> %d (local state: %s, authority=%d)" % [
			_pickable.name, old, value, _holder_desc(), get_multiplayer_authority()
		])
	apply_held_state()


## Puts the item in the right physics state for whether this peer currently
## owns it. Called locally after net_held_by changes, and directly by
## NetworkManager._set_item_authority right after an authority handoff.
func apply_held_state() -> void:
	if not _pickable:
		return
	if not NetworkManager.is_online() or is_multiplayer_authority():
		# We own this item's simulation (offline, loose+server, or currently
		# holding it). If it's not actively in our own hand right now, make
		# sure it isn't still left frozen/collision-less from a previous
		# non-authority period (e.g. right after regaining authority when a
		# client released it) — while actually held, XRToolsPickable's own
		# pick_up()/let_go() already manage these fields, so leave those be.
		if not _pickable.is_picked_up():
			var changed := _pickable.freeze_mode != _original_freeze_mode \
				or _pickable.collision_mask != _pickable.original_collision_mask
			if changed and NetworkManager.is_online():
				NetworkManager.log_line(
					"%s: reclaiming ownership, restoring freeze_mode %d->%d collision_mask %d->%d" % [
						_pickable.name, _pickable.freeze_mode, _original_freeze_mode,
						_pickable.collision_mask, _pickable.original_collision_mask
					]
				)
			_pickable.freeze_mode = _original_freeze_mode
			_pickable.collision_mask = _pickable.original_collision_mask
		return
	# A net_held_by/position sync update can race ahead of the
	# authority-handoff RPC that's about to confirm a grab we just made
	# optimistically (they travel on different channels with no ordering
	# guarantee). Don't let a stale sync value yank an item out of our own
	# hand mid-grab — only an explicit force_release_item rejection, or
	# actually losing authority for real, should end a grab we initiated.
	if _pickable.is_picked_up() and _pickable.get_picked_up_by() is XRToolsFunctionPickup:
		if NetworkManager.is_online():
			NetworkManager.log_line(
				"%s: ignoring non-authority sync (net_held_by=%d) — still actively held by our own hand (grab-race guard)" % [
					_pickable.name, net_held_by
				]
			)
		return
	# Someone else owns it: stop simulating locally, just follow the sync.
	if _pickable.is_picked_up():
		if NetworkManager.is_online():
			NetworkManager.log_line(
				"%s: was held by %s on this peer, but authority now says peer %d owns it — force-dropping" % [
					_pickable.name, _holder_desc(), net_held_by
				]
			)
		_pickable.drop()
	if NetworkManager.is_online():
		NetworkManager.log_line("%s: freezing (non-authority, owner=peer %d)" % [_pickable.name, net_held_by])
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
		# e.g. a station snap zone grabbed it (server-side auto-snap, or the
		# addon's own "grab out of a snap zone" shortcut mid-cascade) — not a
		# player-initiated hand grab, so no authority request from here.
		if NetworkManager.is_online():
			NetworkManager.log_line("%s picked up by %s (not a hand) — no authority request" % [_pickable.name, _holder_desc()])
		return
	if NetworkManager.is_online():
		NetworkManager.log_line("%s grabbed by hand (authority was peer %d), requesting authority" % [_pickable.name, net_held_by])
	NetworkManager.request_item_authority_from(_pickable.get_path())


func _on_dropped(_p) -> void:
	# Only forward if we're actually still the authority — a drop caused by
	# apply_held_state() losing authority (see above) must not re-report.
	if not is_multiplayer_authority():
		if NetworkManager.is_online():
			NetworkManager.log_line("%s dropped locally, but we aren't its authority (peer %d is) — not reporting" % [_pickable.name, net_held_by])
		return
	if NetworkManager.is_online():
		NetworkManager.log_line("%s dropped, reporting release to server (lin=%s ang=%s)" % [
			_pickable.name, _pickable.linear_velocity, _pickable.angular_velocity
		])
	NetworkManager.release_item_authority_from(
		_pickable.get_path(), _pickable.linear_velocity, _pickable.angular_velocity
	)


## Human-readable description of what's currently holding this item on THIS
## peer, for diagnosing desyncs between a hand's own "what am I holding"
## bookkeeping and the item's actual grab state (see the snap-zone-grab race
## in NetworkManager._try_snap_into_station for a real example).
func _holder_desc() -> String:
	if not _pickable or not _pickable.is_picked_up():
		return "loose"
	var by := _pickable.get_picked_up_by()
	if not by:
		return "held(no grabber?)"
	if by is XRToolsFunctionPickup:
		return "hand(%s)" % by.get_path()
	if by is XRToolsSnapZone:
		var station := by.get_parent()
		return "zone(%s)" % (station.name if station else str(by.get_path()))
	return "other(%s: %s)" % [by.get_class(), by.get_path()]
