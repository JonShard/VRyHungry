extends Node3D

@export var kitchen_scene: PackedScene
@export var hob_scene: PackedScene


func _ready() -> void:

	if not kitchen_scene:
		push_error("StationSpawner missing kitchen_scene")
		
	print("Kitchen init")

	if NetworkManager.owns_world():
		print("Kitchen init is_server")
		# Later we will do procedural generation here.
		# For now we just load a scene.
		NetworkManager.call_deferred("spawn_item", kitchen_scene.resource_path, transform)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("satisfy_table_orders"):
		var trans: Transform3D = transform
		trans.origin += Vector3(-1.2, 0, 0)
		NetworkManager.call_deferred("spawn_item", hob_scene.resource_path, trans)
