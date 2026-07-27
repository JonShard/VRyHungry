extends Node


func _ready() -> void:
	$"..".visible = false
	
	# Listen for the game over signal from GameManager
	Signals.game_over.connect(_on_game_over)

func _on_game_over() -> void:
	$"..".visible = true
