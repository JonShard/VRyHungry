extends StaticBody3D

const GAME_MANAGER = preload("res://GameManager.gd")

@export var initial_thinking_time: float = 6
@export var initial_primary_time: float = 60
@export var initial_friend_time: float = 10
@export var initial_eating_time: float = 4

@onready var label_3d: Label3D = $Label3D
@onready var label_3d_time: Label3D = $Label3DTime
@onready var snap_zones: Array[XRToolsSnapZone] = []

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
var _unsatisfied_orders: Array[String]

func _ready() -> void:
	if not label_3d:
		push_error("Table is missing reference to Label3D")
	if not label_3d_time:
		push_error("Table is missing reference to Label3DTime")

	# Get snap_zones for plates, store in array snap_zones
	for child in get_children():
		var snap_zone_node = child as XRToolsSnapZone
		if snap_zone_node:
			snap_zones.append(snap_zone_node)

	if snap_zones.is_empty():
		push_error("Table is missing XRToolsSnapZone children")
		return

	for snap_zone_node in snap_zones:
		snap_zone_node.has_picked_up.connect(_on_object_picked_up)
		snap_zone_node.has_dropped.connect(_on_object_dropped)
	_setState(TableState.EMPTY)


func _on_object_picked_up(_item) -> void:
	print("Table: object picked up: ", _item)
	_absorb_item_if_correct(_item)



func _on_object_dropped() -> void:
	print("Table: object dropped ")
	
	
func _get_plate_from_item(_item: Node) -> PlateController:
	return _item.get_children().filter(func(c): return c is PlateController).front() as PlateController


func _absorb_item_if_correct(_item: Node) -> void:
	# Get plate controller in childer of _item (hopefully a plate XRpickable)
	var plate = _get_plate_from_item(_item)
	if not plate:
		print("Table: held object is not a Plate")
		return 
	print("Table: held a Plate!")
	
	# Absorm items from the plate we want
	for food_item in plate.container.contained_items:
		print("Table: held a plate with FoodItem: ", food_item.id)
		if food_item.id in _unsatisfied_orders:
			print("Table: held FoodItem is in unsatisfied orders, removing it")
			_unsatisfied_orders.erase(food_item.id)
			GAME_MANAGER.money += food_item.sell_value
			_setState(TableState.WAITING_FRIEND)
			_update_order_text()
			
	# Table has everything it wants. Start eating
	if _unsatisfied_orders.is_empty():
		_setState(TableState.EATING)
	

func place_order() -> void:
	print("Table: place_order()")
	_unsatisfied_orders.append(GAME_MANAGER.get_random_meal())
	_unsatisfied_orders.append(GAME_MANAGER.get_random_meal())


func _update_order_text() -> void:
	label_3d.text = "%s\n%s" % [TableState.keys()[_state], "\n".join(_unsatisfied_orders)]


func _setState(newState: TableState) -> void:
	print("Table set _state: ", TableState.keys()[newState])

	if newState == TableState.EMPTY:
		label_3d.text = "empty"

	if newState == TableState.THINKING:
		_state_time = initial_eating_time
		label_3d.text = lbl_thinking
	
	if newState == TableState.WAITING_PRIMARY:
		_state_time = initial_primary_time
		_update_order_text()

	if newState == TableState.WAITING_FRIEND:
		_state_time = initial_friend_time
		_update_order_text()

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
	
	# When state timer is finished, do this stuff before moving to next state
	match _state:
		TableState.EMPTY:
			_setState(TableState.THINKING)
		
		TableState.THINKING:
			_setState(TableState.WAITING_PRIMARY)
			place_order()
			_update_order_text()

		
		TableState.WAITING_PRIMARY:
			label_3d.text = lbl_gameover
		
		TableState.WAITING_FRIEND:
			label_3d.text = lbl_gameover

		TableState.EATING:
			for snap_zone_node in snap_zones:
				var held_object = snap_zone_node.picked_up_object
				if not held_object:
					continue

				var plate = _get_plate_from_item(held_object)
				if plate:
					plate.container.clear()
					plate.is_dirty = true
			_setState(TableState.EMPTY)
		
