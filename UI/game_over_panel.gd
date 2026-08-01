extends Control

@onready var _Restart_btn: Button = %Restart

func _ready() -> void:
	_Restart_btn.pressed.connect(_restart)
	
func _restart():
	GameManager._restart()
	get_tree().reload_current_scene()
	
