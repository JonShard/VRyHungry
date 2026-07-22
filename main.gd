extends Node3D

const RECIPE_MANAGER = preload("res://RecipeManager.gd")
const GAME_MANAGER = preload("res://GameManager.gd")

var xr_interface :XRInterface

func _ready():
	RECIPE_MANAGER.print_all_recipes()

	GAME_MANAGER.meals_in_play.append("hamburger")
	
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR started :)")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
	else:
		print("OpenXR failed to start. Check your headset...")
