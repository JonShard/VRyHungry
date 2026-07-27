extends Control

@onready var _Restart_btn: Button = %Restart
const GAME_MANAGER = preload("res://GameManager.gd")


func _ready() -> void:
	_Restart_btn.pressed.connect(_restart)
	
func _restart():
	GAME_MANAGER._restart()
	get_tree().reload_current_scene()
	
