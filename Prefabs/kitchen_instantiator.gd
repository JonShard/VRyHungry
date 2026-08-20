extends Node3D

@export var kitchen_scene: PackedScene
@export var hob_scene: PackedScene


func _ready() -> void:
	Helper.check_reference(self, kitchen_scene, PackedScene)

	SweetLogger.debug("->[]")

	if NetworkManager.owns_world():
		SweetLogger.debug("Initializing on server")
		# Later we will do procedural generation here.
		# For now we just load a scene.
		NetworkManager.call_deferred("spawn_item", kitchen_scene.resource_path, transform)
