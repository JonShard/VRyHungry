class_name Table
extends StaticBody3D

const GAME_MANAGER = preload("res://GameManager.gd")

@export var thinking_duration: float = 5.0
@export var ordering_duration: float = 40.0
@export var primary_duration: float = 40.0
@export var friend_duration: float = 10.0
@export var eating_duration: float = 5.0
@export var money_sound: AudioStream 

@onready var label_3d: Label3D = $Label3D
@onready var label_3d_time: Label3D = $Label3DTime
@onready var snap_zones: Array[XRToolsSnapZone] = []
@onready var progress_bar: ProgressBar3D = $ProgressBar3D
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var customers: Node3D = $Customers
@onready var player_detect_area_3d: Area3D = $PlayerDetectArea3D

const lbl_thinking: String = "..."
const lbl_ordering: String = "!"
const lbl_gameover: String = "Game Over!"
const lbl_eating: String = "Eating..."

### Finite State Machine ####

enum TableState {
	EMPTY, 			 # Just finished eating or havent eaten yet
	THINKING,
	ORDERING,		 # Wating for player to take their order
	WAITING_PRIMARY, # Inital wait to be served
	WAITING_FRIEND,  # Waiting for friends food to arrive
	EATING
}

## State is server-authoritative and synced (see table.tscn's Sync node);
## state transitions only ever run where NetworkManager.owns_world() is true
## (the whole station's _process is gated off elsewhere for non-owners, see
## NetworkManager._gate_station). The setters below just refresh the display,
## so both the server (via _setState) and clients (via incoming sync) show
## the same text. Use _setState(), never assign _state directly.
var _state: TableState = TableState.EMPTY: set = _set_state
var _state_time: float = 0.0: set = _set_state_time
var _state_duration: float = 0.0 # set in _set_state_time
var _unsatisfied_orders: Array[String] = []: set = _set_unsatisfied_orders


func _ready() -> void:
	if not label_3d:
		push_error("Table is missing reference to Label3D")
	if not label_3d_time:
		push_error("Table is missing reference to Label3DTime")
	if not progress_bar or progress_bar is not ProgressBar3D:
		push_error("Table missing reference to progressbar, or wrong type:", progress_bar)
	progress_bar.y_billboard = true
	# Render whatever state already arrived from the server before we were in
	# the tree (see the guard in _refresh_display).
	_refresh_display.call_deferred()
	if not audio_player:
		push_error("Table is missing reference to AudioStreamPlayer3D")
		
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
	player_detect_area_3d.body_entered.connect(_on_player_detected)
	set_process(true)
	_setState(TableState.EMPTY)


func _on_object_picked_up(_item) -> void:
	print("Table: object picked up: ", _item)
	if _state == TableState.EATING:
		return
	_absorb_item_if_correct(_item)


func _on_object_dropped() -> void:
	print("Table: object dropped ")


func _on_player_detected(player):
	print("Table _on_player_detected(), ", player)
	if _state != TableState.ORDERING:
		return
		
	place_order()
	_set_state(TableState.WAITING_PRIMARY)

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
			if _unsatisfied_orders.size() > 0 and _state != TableState.EATING:
				_setState(TableState.WAITING_FRIEND)

			# Table has everything it wants. Start eating
			elif _unsatisfied_orders.is_empty() and _state != TableState.EATING:
				GAME_MANAGER.money += food_item.sell_value
				audio_player.stream = money_sound
				audio_player.play()
				_setState(TableState.EATING)



func place_order() -> void:
	print("Table: place_order()")
	var new_orders = _unsatisfied_orders.duplicate()
	new_orders.append(GAME_MANAGER.get_random_meal())
	new_orders.append(GAME_MANAGER.get_random_meal())
	_set_unsatisfied_orders(new_orders)


func satisfyAllOrders() -> void:
	print("Table: satisfyAllOrders()")
	_unsatisfied_orders.clear()
	clearAllPlates()
	_setState(TableState.EMPTY)


func clearAllPlates() -> void:
	print("Table: clearAllPlates()")
	for snap_zone_node in snap_zones:
		var held_object = snap_zone_node.picked_up_object
		if not held_object:
			continue

		var plate = _get_plate_from_item(held_object)
		if plate:
			plate.container.clear()
			plate.is_dirty = true


func _set_snap_zones_enabled(value: bool) -> void:
	for zone in snap_zones:
		zone.enabled = value


## Server-only state transition: sets the new state's timer and assigns
## _state (whose setter refreshes the display on every peer).
func _setState(newState: TableState) -> void:
	print("Table set _state: ", TableState.keys()[newState])

	match newState:
		TableState.EMPTY:
			_state_time = 5.0
			_state_duration = 5.0
			customers.visible = false
		TableState.THINKING:
			_state_time = thinking_duration
			_state_duration = thinking_duration # Can't be done in _set_state(), will set duration inside timer
		TableState.ORDERING:
			_state_time = ordering_duration
			_state_duration = ordering_duration
		TableState.WAITING_PRIMARY:
			_state_time = primary_duration
			_state_duration = primary_duration
		TableState.WAITING_FRIEND:
			_state_time = friend_duration
			_state_duration = friend_duration
		TableState.EATING:
			_state_time = eating_duration
			_state_duration = eating_duration
			_set_snap_zones_enabled(false)

	_state = newState


## Pure presentation, driven off the current (locally authoritative or
## synced-from-server) state. Runs on every peer.
func _refresh_display() -> void:
	# _state, _state_time and _unsatisfied_orders are replicated with spawn=true,
	# and MultiplayerSpawner applies a spawn payload BEFORE the node enters the
	# tree — so these setters fire while the @onready children below are still
	# null. Bail out until _ready() has resolved them; _ready() calls back in
	# once it has, so nothing that arrived early is lost.
	if not progress_bar or not label_3d or not label_3d_time:
		return
	match _state:
		TableState.EMPTY:
			progress_bar.set_bar_visible(false)
			label_3d.text = "empty"
		TableState.THINKING:
			progress_bar.set_bar_visible(false)
			label_3d.text = lbl_thinking
		TableState.ORDERING:
			progress_bar.set_bar_visible(true)
			progress_bar.override_fill_color(Color.RED if _state_time < 10 else Color.YELLOW)
			label_3d.text = lbl_ordering
		TableState.WAITING_PRIMARY:
			label_3d.text = "%s\n%s" % [TableState.keys()[_state], "\n".join(_unsatisfied_orders)]
			progress_bar.set_bar_visible(true)
			progress_bar.override_fill_color(Color.RED if _state_time < 10 else Color.YELLOW)
		TableState.WAITING_FRIEND:
			label_3d.text = "%s\n%s" % [TableState.keys()[_state], "\n".join(_unsatisfied_orders)]
			progress_bar.set_bar_visible(true)
			progress_bar.override_fill_color(Color.RED if _state_time < 5 else Color.YELLOW)
		TableState.EATING:
			label_3d.text = lbl_eating
			progress_bar.set_bar_visible(false)
	
	label_3d_time.text = "%.1f" % _state_time
	progress_bar.set_progress(clampf(float(_state_time) / _state_duration, 0.0, 1.0))


func _set_state(value: TableState) -> void:
	_state = value
	_refresh_display()


func _set_state_time(value: float) -> void:
	_state_time = value
	_refresh_display()


func _set_unsatisfied_orders(value: Array[String]) -> void:
	_unsatisfied_orders = value
	_refresh_display()


func _process(delta: float) -> void:
	# Wait for state to finish
	if _state_time > 0.0:
		_state_time = max(0.0, _state_time - delta)
		return
	
	if GAME_MANAGER.game_state == GAME_MANAGER.GameState.GAME_OVER:
		return

	# When state timer is finished, do this stuff before moving to next state
	match _state:
		TableState.EMPTY:
			print("Table State EMPTY finish")
			customers.visible = true
			_setState(TableState.THINKING)

		TableState.THINKING:
			print("Table State THINKING finish")
			_setState(TableState.ORDERING)

		TableState.ORDERING:
			print("Table State ORDERING finish")
			label_3d.text = lbl_gameover
			GAME_MANAGER.game_over()


		TableState.WAITING_PRIMARY:
			print("Table State WAITING_PRIMARY finish")
			label_3d.text = lbl_gameover
			GAME_MANAGER.game_over()

		TableState.WAITING_FRIEND:
			print("Table State WAITING_FRIEND finish")
			label_3d.text = lbl_gameover
			GAME_MANAGER.game_over()

		TableState.EATING:
			print("Table State EATING finish")
			clearAllPlates()
			_set_snap_zones_enabled(true)
			_setState(TableState.EMPTY)
