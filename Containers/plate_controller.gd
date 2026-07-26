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
	# Only rebuild when the contents actually changed. This property is
	# replicated in ALWAYS mode, so the synchronizer assigns it every network
	# tick on every peer that doesn't own the plate — and refresh_visuals()
	# frees and re-instantiates a scene per item each time. That was thousands
	# of throwaway nodes per run (and a log line from each one's NetPickable).
	if contained_ids == value:
		return
	contained_ids = value
	# Deferred: this can be written by the replicated spawn payload before
	# this node's own @onready vars (container) have resolved.
	_refresh_visuals.call_deferred()


func _refresh_visuals() -> void:
	if container:
		container.refresh_visuals(contained_ids)
