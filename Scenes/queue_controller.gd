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
	SweetLogger.debug("_rebuild_table_list complete: {0}", [_tables])


func _try_to_assign_customers() -> void:
	for customer in _customers:
		for table: Table in _tables:
			var result: bool = table.try_consume_customer()
			if result == true:
				_customers.pop_front()
				break


func _process(delta: float) -> void:
	# Process customers patience
	for i in range(0, _customers.size()):
		_customers[i] -= delta
		if _customers[i] <= 0:
			GameManager.game_over()

	_try_to_assign_customers()

	# Update visuals
	if not _customers.is_empty():
		label_3d.text = "Customers in queue: " +  str(_customers.size())
		progress_bar_3d.set_progress(_customers.front() / queue_patience)
	else:
		progress_bar_3d.set_progress(0)
		label_3d.text = "No Customers"
		
