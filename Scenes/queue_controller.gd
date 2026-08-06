extends Node3D

@export var queue_patience: float = 120

@export var progress_bar_3d: ProgressBar3D
@export var label_3d: Label3D


var _customers: Array[float] = [] # Temp. Array of their patience


func _ready() -> void:
	progress_bar_3d.override_fill_color(Color.YELLOW)
	progress_bar_3d.exponential = true
	Signals.request_customer_spawn.connect(_on_request_customer_spawn)
	Signals.consumed_customer.connect(on_consumed_customer)

func _on_request_customer_spawn() -> void:
	spawn_customer()


func on_consumed_customer() -> void:
	_customers.pop_front()


func spawn_customer()  -> void:
	_customers.append(queue_patience)


func _process(delta: float) -> void:
	# Process customers patience
	for i in range(0, _customers.size()):
		_customers[i] -= delta
		if _customers[i] <= 0:
			GameManager.game_over()

	# Try to assign customers to tables
	for customer in _customers:
		get_tree().call_group("table", "try_consume_customer") 


	# Update visuals
	if not _customers.is_empty():
		label_3d.text = "Customers in queue: " +  str(_customers.size())
		progress_bar_3d.set_progress(_customers.front() / queue_patience)
	else:
		progress_bar_3d.set_progress(0)
		label_3d.text = "No Customers"
		
