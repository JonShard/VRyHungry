extends Node3D

@export var kitchen_scene: PackedScene
@export var hob_scene: PackedScene


func _ready() -> void:

	if not kitchen_scene:
		SweetLogger.warning("{0} missing kitchen_scene reference", [name])

	SweetLogger.debug("->[]")

	if NetworkManager.owns_world():
		SweetLogger.debug("Initializing on server")
		# Later we will do procedural generation here.
		# For now we just load a scene.
		NetworkManager.call_deferred("spawn_item", kitchen_scene.resource_path, transform)
