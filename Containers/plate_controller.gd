class_name PlateController
extends Node

@onready var dirty_node: Node3D = $"../Dirty"
@onready var container: ItemContainer = $"../Container"

@export var is_dirty: bool = false

## Synced plate contents (item ids), replacing reparented child nodes so
## contents survive replication (a MultiplayerSpawner-tracked item would
## despawn on every client the instant it was reparented out of WorldContent).
## Server writes it via ItemContainer; every peer (server included) renders
## the cosmetic result via the setter below.
@export var contained_ids: Array[String] = []: set = _set_contained_ids


func _ready() -> void:
	if not dirty_node:
		push_error("Plate is missing its dirty_node")
	dirty_node.visible = is_dirty


func _process(_delta: float) -> void:
	if is_dirty:
		container.enabled = false
		dirty_node.visible = true
	else:
		container.enabled = true
		dirty_node.visible = false


func _set_contained_ids(value: Array[String]) -> void:
	contained_ids = value
	# Deferred: this can be written by the replicated spawn payload before
	# this node's own @onready vars (container) have resolved.
	_refresh_visuals.call_deferred()


func _refresh_visuals() -> void:
	if container:
		container.refresh_visuals(contained_ids)
