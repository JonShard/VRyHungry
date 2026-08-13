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
var _original_freeze_mode: RigidBody3D.FreezeMode

# Same idea for the pickable's authored `enabled` flag, which the non-authority
# branch of apply_held_state() clears while someone else is holding the item.
var _original_enabled: bool

# Whether the "our own hand still holds this" guard has already been logged for
# the current grab. apply_held_state() runs every network tick, so without this
# the guard message repeats for as long as you hold the item.
var _grab_race_logged := false


func _ready() -> void:
	_pickable = get_parent() as XRToolsPickable
	if not _pickable:
		push_error("NetPickable must be a child of an XRToolsPickable")
		return
	_original_freeze_mode = _pickable.freeze_mode
	_original_enabled = _pickable.enabled
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
		SweetLogger.debug("{0} net_held_by: {1} -> {2} (local state: {3}, authority={4})", [_pickable.name, old, value, _holder_desc(), get_multiplayer_authority()])
	apply_held_state()


## Puts the item in the right physics state for whether this peer currently
## owns it. Called locally after net_held_by changes, and directly by
## NetworkManager._set_item_authority right after an authority handoff.
##
## IMPORTANT: this runs on every network tick, not just on a real change.
## net_held_by is replicated in ALWAYS mode, so the synchronizer assigns it every
## tick on non-authority peers — unchanged value included — and that assignment
## lands in _set_net_held_by(), which calls this. So every branch here has to be
## idempotent and silent when there is nothing to do: otherwise each item logs a
## line and rewrites four physics properties every tick on every peer that
## doesn't own it.
func apply_held_state() -> void:
	if not _pickable:
		return
	if not NetworkManager.is_online() or (is_inside_tree() and is_multiplayer_authority()) :
		_grab_race_logged = false
		# We own this item's simulation (offline, loose+server, or currently
		# holding it). If it's not actively in our own hand right now, make
		# sure it isn't still left frozen/collision-less from a previous
		# non-authority period (e.g. right after regaining authority when a
		# client released it) — while actually held, XRToolsPickable's own
		# pick_up()/let_go() already manage these fields, so leave those be.
		if not _pickable.is_picked_up():
			var changed := _pickable.freeze_mode != _original_freeze_mode \
				or _pickable.collision_mask != _pickable.original_collision_mask
			if changed:
				if NetworkManager.is_online():
					SweetLogger.debug("{0}: reclaiming ownership, restoring freeze_mode {1}->{2} collision_mask {3}->{4}", [_pickable.name, _pickable.freeze_mode, _original_freeze_mode, _pickable.collision_mask, _pickable.original_collision_mask])
				_pickable.freeze_mode = _original_freeze_mode
				_pickable.collision_mask = _pickable.original_collision_mask
		# Unlike freeze/collision (which XRToolsPickable manages itself while
		# held), `enabled` is only ever written by the non-authority branch
		# below, so it must be restored here or it stays false forever: once a
		# client grabbed this item, every other peer set enabled=false, and
		# regaining authority left it that way. On the server that silently
		# broke everything downstream — hands couldn't pick the item up again,
		# and a station snap zone would "snap" it (emitting has_picked_up, so
		# e.g. a plate still got marked dirty) while pick_up() bailed out on
		# the disabled item, leaving the zone holding an item with no grab
		# driver that then fell out of the station.
		if _pickable.enabled != _original_enabled:
			if NetworkManager.is_online():
				SweetLogger.debug("{0}: reclaiming ownership, restoring enabled {1}->{2}", [_pickable.name, _pickable.enabled, _original_enabled])
			_pickable.enabled = _original_enabled
		return
	# A net_held_by/position sync update can race ahead of the
	# authority-handoff RPC that's about to confirm a grab we just made
	# optimistically (they travel on different channels with no ordering
	# guarantee). Don't let a stale sync value yank an item out of our own
	# hand mid-grab — only an explicit force_release_item rejection, or
	# actually losing authority for real, should end a grab we initiated.
	if _pickable.is_picked_up() and _pickable.get_picked_up_by() is XRToolsFunctionPickup:
		# Log once per grab, not once per tick.
		if NetworkManager.is_online() and not _grab_race_logged:
			_grab_race_logged = true
			SweetLogger.debug("{0}: ignoring non-authority sync (net_held_by={1}) — still actively held by our own hand (grab-race guard)", [_pickable.name, net_held_by])
		return
	_grab_race_logged = false
	# Someone else owns it: stop simulating locally, just follow the sync.
	if _pickable.is_picked_up():
		if NetworkManager.is_online():
			# Jon's note: When we get this warning, it usually mean a client-side snapzone is not disabled, and is fighting the server over the item.
			SweetLogger.warning("{0}: was held by {1} on this peer, but authority now says peer {2} owns it — force-dropping", [_pickable.name, _holder_desc(), net_held_by])
		_pickable.drop()
	# Bail out when we're already in the follow-the-sync state. Without this the
	# writes below (and the line logged with them) repeated every tick for every
	# item on every non-authority peer — 90% of the log, plus four redundant
	# physics-property writes per item per tick. The comparison also means we
	# still re-apply if something else perturbs the state (e.g. let_go()
	# restoring the collision mask after a force-drop).
	var want_enabled := (net_held_by == 0)
	if _pickable.freeze \
			and _pickable.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC \
			and _pickable.collision_mask == 0 \
			and _pickable.enabled == want_enabled:
		return
	# if NetworkManager.is_online(): # This was spamming that Knife was frozen every frame.
	# 	print("%s: freezing (non-authority, owner=peer %d)" % [_pickable.name, net_held_by])
	_pickable.freeze = true
	_pickable.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_pickable.collision_mask = 0
	_pickable.enabled = want_enabled


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
			SweetLogger.debug("{0} picked up by {1} (not a hand) — no authority request", [_pickable.name, _holder_desc()])
		return
	if NetworkManager.is_online():
		SweetLogger.debug("{0} grabbed by hand (authority was peer {1}), requesting authority", [_pickable.name, net_held_by])
	NetworkManager.request_item_authority_from(_pickable.get_path())


func _on_dropped(_p) -> void:
	# Only forward if we're actually still the authority — a drop caused by
	# apply_held_state() losing authority (see above) must not re-report.
	if not is_multiplayer_authority():
		if NetworkManager.is_online():
			SweetLogger.debug("{0} dropped locally, but we aren't its authority (peer {1} is) — not reporting", [_pickable.name, net_held_by])
		return
	if NetworkManager.is_online():
		SweetLogger.debug("{0} dropped, reporting release to server (lin={1} ang={2})", [_pickable.name, _pickable.linear_velocity, _pickable.angular_velocity])
	# Send our own final transform too: we were the authority until now, and the
	# server's copy may not have received our last position sync yet.
	NetworkManager.release_item_authority_from(
		_pickable.get_path(), _pickable.linear_velocity, _pickable.angular_velocity,
		_pickable.global_transform
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
		return "zone(%s)" % (str(station.name) if station else str(by.get_path()))
	return "other(%s: %s)" % [by.get_class(), by.get_path()]
