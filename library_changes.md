

function_pickup.gd:
	Add nil check in func _pick_up_object(target: Node3D)
	440: if target and target.has_method("pick_up"):
		target.pick_up(self)


Add (what) to singal dropped in snap_zone
	signal has_dropped(what)
	# Pickup Method: Drop the currently picked up object
	...
	func drop_object() -> void:
		if not is_instance_valid(picked_up_object):
			return

		# let go of this object
		has_dropped.emit(picked_up_object)
		picked_up_object.let_go(self, Vector3.ZERO, Vector3.ZERO)
		picked_up_object = null
		highlight_updated.emit(self, enabled)
