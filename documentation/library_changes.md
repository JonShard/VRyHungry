

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


viewport_2d_in_3d.tscn:
	Removed the baked ViewportTexture sub-resource (no viewport_path set, genuinely
	invalid) that was the default material on the Screen mesh. The script always
	builds and swaps in its own material at _ready(), so the baked one only
	existed to be briefly invalid before being discarded, printing a spurious
	"Viewport Texture must be set to use it" error on every instance (MainMenuPanel3D
	at boot, the player's shop_menu_3d on avatar spawn).
	Removed:
		[sub_resource type="ViewportTexture" id="ViewportTexture_ufe4n"]

		[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_fvml0"]
		transparency = 1
		cull_mode = 2
		albedo_texture = SubResource("ViewportTexture_ufe4n")
		texture_filter = 1
	And the reference to it on the Screen node:
		surface_material_override/0 = SubResource("StandardMaterial3D_fvml0")
