

function_pickup.gd:
	Add nil check in func _pick_up_object(target: Node3D)
	440: if target and target.has_method("pick_up"):
		target.pick_up(self)
