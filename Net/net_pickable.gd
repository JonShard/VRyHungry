class_name NetPickable
extends MultiplayerSynchronizer

## Networked sync component for a pickable item. Added as a child literally
## named "NetPickable" (network_manager.gd's authority RPCs already expect
## this) of every net-synced pickable, replicating its transform and held
## state. Only the current multiplayer authority (the server while loose, or
## whichever peer is holding it) actually simulates physics for the item;
## every other peer freezes their local copy and just follows the synced
## transform.

## Nobody is holding the item, so it is loose and simulated by the server. Not
## the same as "the server holds it" — that would be the server's peer id.
const NOT_HELD := 0

## NOT_HELD, or the peer id currently holding it.
## Replicated at spawn and on change so a late joiner sees the current holder.
var net_held_by: int = NOT_HELD: set = _set_net_held_by

## Transform properties, kept apart from the rest of the replicated set because
## set_transform_owned() drops them while something else drives the item.
const TRANSFORM_PROPERTIES: Array[String] = [".:position", ".:quaternion"]

## False while something else drives this item's transform — e.g. it has been
## reparented into a container and is carried by its new parent. See set_transform_owned().
var transform_owned: bool = true: set = set_transform_owned

var _pickable: XRToolsPickable

# This item's own baked freeze_mode (e.g. plate.tscn bakes KINEMATIC, not the
# RigidBody3D default of STATIC) — captured once so it can be restored.
var _original_freeze_mode: RigidBody3D.FreezeMode

# Same idea for the pickable's authored `enabled` flag, which the non-authority
# branch of apply_held_state() clears while someone else is holding the item.
var _original_enabled: bool

## Intent set by external game logic (e.g. a station enabling/disabling a tool),
## independent of hold state. apply_held_state() is the sole writer of the
## pickable's actual `enabled` property, so this is how other systems express
## "should be enabled" without fighting that reconciliation every tick.
var grabbable: bool = true: set = set_grabbable

func _ready() -> void:
	_pickable = get_parent() as XRToolsPickable
	if not _pickable:
		SweetLogger.error("{0} must be a child of an XRToolsPickable", [name])
		return

	# Configure Multiplayer Synchronizer
	# This overwrites any changes made in the inspector.
	replication_config = SceneReplicationConfig.new()
	for property_path in TRANSFORM_PROPERTIES + [".:enabled", ".:visible"]:
		_add_always_property(property_path)
	# Unlike the properties above, this one is replicated at spawn too, so a
	# late joiner sees the current holder immediately.
	var held_by_path := NodePath("NetPickable:net_held_by")
	replication_config.add_property(held_by_path)
	replication_config.property_set_replication_mode(held_by_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	replication_config.property_set_spawn(held_by_path, true)

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


func _add_always_property(property_path: String) -> void:
	replication_config.add_property(property_path)
	replication_config.property_set_replication_mode(property_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	replication_config.property_set_spawn(property_path, false)


## Set false by whatever takes over driving this item's transform (e.g. an
## ItemContainer reparenting it onto a plate). Disables apply_held_state()
## Without this net_held_by tick and would keep restoring `enabled`, `freeze` and the
## collision mask.
func set_transform_owned(value: bool) -> void:
	if transform_owned == value:
		return
	transform_owned = value
	for property_path in TRANSFORM_PROPERTIES:
		if value:
			_add_always_property(property_path)
		else:
			replication_config.remove_property(property_path)
	# Ours again: re-derive the physics state we stopped maintaining.
	if value:
		apply_held_state()


## Set by external game logic (e.g. Counter._enable_tool/_disable_tool) to
## express whether this item should be usable right now, independent of hold
## state. Reapplies immediately so the change takes effect without waiting for
## the next net_held_by tick.
func set_grabbable(value: bool) -> void:
	if grabbable == value:
		return
	grabbable = value
	apply_held_state()


func _set_net_held_by(value: int) -> void:
	var old := net_held_by
	net_held_by = value
	if old != value and NetworkManager.is_online():
		SweetLogger.debug("{0} net_held_by: {1} -> {2} (local state: {3}, authority={4})", [_pickable.name, old, value, _holder_desc(), get_multiplayer_authority()])
	apply_held_state()


## Puts the item in the right physics state for whether this peer currently
## owns it. Called locally after net_held_by changes, and directly by
## NetworkManager._set_item_authority right after an authority handoff.
func apply_held_state() -> void:
	if not _pickable:
		return
	if not transform_owned: # We don't own it.
		return
	if not NetworkManager.is_online() or (is_inside_tree() and is_multiplayer_authority()) :
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
		var want_enabled_authority := _original_enabled and grabbable
		if _pickable.enabled != want_enabled_authority:
			if NetworkManager.is_online():
				SweetLogger.debug("{0}: reclaiming ownership, restoring enabled {1}->{2}", [_pickable.name, _pickable.enabled, want_enabled_authority])
			_pickable.enabled = want_enabled_authority
		return
	# A net_held_by/position sync update can race ahead of the
	# authority-handoff RPC that's about to confirm a grab we just made
	# optimistically (they travel on different channels with no ordering
	# guarantee). Don't let a stale sync value yank an item out of our own
	# hand mid-grab — only an explicit force_release_item rejection, or
	# actually losing authority for real, should end a grab we initiated.
	if _pickable.is_picked_up() and _pickable.get_picked_up_by() is XRToolsFunctionPickup:
		return
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
	var want_enabled := (net_held_by == NOT_HELD) and grabbable
	if _pickable.freeze \
			and _pickable.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC \
			and _pickable.collision_mask == 0 \
			and _pickable.enabled == want_enabled:
		return
	_pickable.freeze = true
	_pickable.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_pickable.collision_mask = 0
	_pickable.enabled = want_enabled


## Local hand grab (not a station snap zone, which is server-only): request
## authority immediately so the throw/drop can be reconciled, but let the grab
## happen instantly here rather than waiting on the round trip.
func _on_picked_up(_p) -> void:
	if not (_pickable.get_picked_up_by() is XRToolsFunctionPickup):
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
