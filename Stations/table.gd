extends StaticBody3D

@export var initial_thinking_time: float = 8
@export var initial_primary_time: float = 3
@export var initial_friend_time: float = 3
@export var initial_eating_time: float = 3

@onready var label_3d: Label3D = $Label3D
@onready var label_3d_time: Label3D = $Label3DTime
@onready var snap_zone: XRToolsSnapZone = $XRToolsSnapZone

const lbl_thinking: String = "Thinking..."
const lbl_waiting_primary: String = "Waiting for food"
const lbl_gameover: String = "Game Over!"
const lbl_eating: String = "Eating..."

### Finite State Machine ####

enum TableState {
	EMPTY, 			 # Just finished eating or havent eaten yet
	THINKING,
	WAITING_PRIMARY, # Inital wait to be served
	WAITING_FRIEND,  # Waiting for friends food to arrive
	EATING
}
var _state = TableState.EMPTY # use _setState(), never set directly
var _state_time: float = 0.0


func _ready() -> void:
	if not label_3d:
		push_error("Table is missing reference to Label3D")
	if not label_3d_time:
		push_error("Table is missing reference to Label3DTime")
	if not snap_zone:
		push_error("Table is missing reference to XRToolsSnapZone")
	
	snap_zone.has_picked_up.connect(_on_object_picked_up)
	snap_zone.has_dropped.connect(_on_object_dropped)
	_setState(TableState.EMPTY)


func _on_object_picked_up(_item) -> void:
	print("Table: object picked up: ", _item)


func _on_object_dropped() -> void:
	print("Table: object dropped ")
	

func place_order() -> void:
	print("Table: place_order()")
	label_3d.text = "order!"


func _setState(newState: TableState) -> void:
	print("Table set _state: ", TableState.keys()[newState])

	if newState == TableState.EMPTY:
		label_3d.text = "empty"

	if newState == TableState.THINKING:
		_state_time = initial_eating_time
		label_3d.text = lbl_thinking
	
	if newState == TableState.WAITING_PRIMARY:
		_state_time = initial_primary_time
		label_3d.text = lbl_waiting_primary
	
	if newState == TableState.WAITING_FRIEND:
		_state_time = initial_friend_time
	
	if newState == TableState.EATING:
		_state_time = initial_eating_time
		label_3d.text = lbl_eating

	_state = newState
		

func _process(delta: float) -> void:
	# Wait for state to finish
	if _state_time > 0:
		_state_time -= delta
		label_3d_time.text = "%.1f" % _state_time
		return
	
	match _state:
		TableState.EMPTY:
			_setState(TableState.THINKING)
		
		TableState.THINKING:
			place_order()
			_setState(TableState.WAITING_PRIMARY)
		
		TableState.WAITING_PRIMARY:
			label_3d.text = lbl_gameover
		
		TableState.EATING:
			_setState(TableState.EMPTY)
		
