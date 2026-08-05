extends Node


func _ready() -> void:
	$"..".visible = false
	
	# Listen for the game over signal from GameManager
	Signals.game_state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.GAME_OVER:
		$"..".visible = true
	else:
		$"..".visible = false
