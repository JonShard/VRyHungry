class_name QueueController
extends Node3D

@export var queue_patience: float = 120

@export var progress_bar_3d: ProgressBar3D
@export var label_3d: Label3D

var _customers: Array[float] = [] # Temp. Array of their patience
var _tables: Array[Node3D] = []


func _ready() -> void:
	progress_bar_3d.override_fill_color(Color.YELLOW)
	progress_bar_3d.exponential = true
	Signals.request_customer_spawn.connect(_on_request_customer_spawn)
	Signals.game_state_changed.connect(_on_game_state_changed)


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.RUNNING:
		_rebuild_table_list()


func _on_request_customer_spawn() -> void:
	spawn_customer()


func spawn_customer()  -> void:
	_customers.append(queue_patience)


func _rebuild_table_list() -> void:
	_tables.clear()
	_tables.append_array(get_tree().get_nodes_in_group("table"))
	SweetLogger.debug("Rebuild table list complete: {0}", [_tables])


func _try_to_assign_customers() -> void:
	for customer in _customers:
		for table: Table in _tables:
			var result: bool = table.try_consume_customer()
			if result == true:
				_customers.pop_front()
				break


func _update_clients_display() -> void:
	if not _customers.is_empty():
		everyone_set_queue_info.rpc("Customers in queue: " +  str(_customers.size()), _customers.front() / queue_patience)
	else:
		everyone_set_queue_info.rpc("No Customers", 0)

		
@rpc("authority", "call_local", "unreliable")
func everyone_set_queue_info(label_text: String, progress: float) -> void:
	label_3d.text = label_text
	progress_bar_3d.set_progress(progress)


func _process(delta: float) -> void:
	if not NetworkManager.owns_world():
		return
	# Process customers patience
	for i in range(0, _customers.size()):
		_customers[i] -= delta
		if _customers[i] <= 0:
			SweetLogger.info("Customer patience ran out, game over")
			GameManager.game_over()
	_try_to_assign_customers()
	_update_clients_display()