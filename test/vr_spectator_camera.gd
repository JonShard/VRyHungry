class_name VrSpectatorCamera
extends Node

# Debug tool: on a non-VR client, follows a connected VR client's head so you can spectate it.

@export var players_path: NodePath = ^"../Players"

@onready var _players: Node = get_node_or_null(players_path)
var _camera: Camera3D


func _ready() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		SweetLogger.debug("{0} disabled - this instance is the VR client", [name])
		return
	if not _players:
		SweetLogger.warning("{0} could not resolve players_path {1}", [name, players_path])
		return
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()


func _process(_delta: float) -> void:
	if not _camera:
		return
	var head := _find_remote_head()
	if head:
		_camera.global_transform = head.global_transform


# First connected player that isn't this local peer
func _find_remote_head() -> Node3D:
	var my_id := multiplayer.get_unique_id()
	for player in _players.get_children():
		if player.name == str(my_id):
			continue
		return player.get_node_or_null("Head")
	return null
