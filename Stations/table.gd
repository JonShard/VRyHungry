class_name Table
extends StaticBody3D

@export var thinking_duration: float = 3.0
@export var ordering_duration: float = 50.0
@export var primary_duration: float = 70.0
@export var friend_duration: float = 12.0
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
	IDLE,			 # Don't update table. incorrect GameState
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
## so both the server (via _set_state) and clients (via incoming sync) show
## the same text. Use _set_state(), never assign _state directly.
var _state: TableState = TableState.EMPTY
var _state_time: float = 0.0
var _state_duration: float = 0.0 # set in _set_state_time
var _original_orders: Array[String] = []
var _unsatisfied_orders: Array[String] = []
var _players_count: int = 0


func place_order() -> void:
	SweetLogger.debug("place_order()")
	var new_orders: Array[String] = _unsatisfied_orders.duplicate()
	# for _i in range(0, randi_range(1, 2)):
	# 	new_orders.append(GameManager.get_random_meal())
	# for _i in range(0, randi_range(0, 1)):
	# 	new_orders.append(GameManager.get_random_side())
	new_orders.append(GameManager.get_random_meal())
	_unsatisfied_orders = new_orders
	_original_orders = _unsatisfied_orders.duplicate()


func absorb_items():
	SweetLogger.debug("absorb_items()")
	for snap_zone_node in snap_zones:
		var held_object = snap_zone_node.picked_up_object
		if not held_object:
			continue

		_absorb_item_if_correct(held_object)
		
		
func satisfyAllOrders() -> void:
	SweetLogger.debug("satisfyAllOrders()")
	_unsatisfied_orders.clear()
	_original_orders.clear()
	clearAllFood()
	_set_state(TableState.EMPTY)


func clearAllFood() -> void:
	SweetLogger.debug("clearAllFood()")
	for zone in snap_zones:
		var held_object = zone.picked_up_object
		if not held_object:
			continue

		var plate: PlateController = _get_plate_controller_from_item(held_object)
		var food_item: FoodItem = Helper.find_food_item(held_object)
		if plate:
			plate.container.clear()
			plate.is_dirty = true

		# Side or other food item directly on table
		elif food_item and food_item.type == FoodItem.Type.SIDE:
			zone.drop_object()
			NetworkManager.despawn_item(held_object)


# Group called from Queue when trying to assign customers to tables
func try_consume_customer() -> bool:
	if _state == TableState.EMPTY:
		SweetLogger.debug("try_consume_customer, consumed a customer")
		_state_end(TableState.EMPTY)
		return true
	return false


func _ready() -> void:
	if not label_3d:
		push_error("Table is missing reference to Label3D")
	if not label_3d_time:
		push_error("Table is missing reference to Label3DTime")
	if not progress_bar or progress_bar is not ProgressBar3D:
		push_error("Table missing reference to progressbar, or wrong type:", progress_bar)
	progress_bar.y_billboard = true
	progress_bar.exponential = true
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
	set_process(true)
	_set_state(TableState.EMPTY)


func _on_object_picked_up(_item) -> void:
	SweetLogger.debug("object picked up: {0}", [_item])
	if _state == TableState.EATING:
		return
	_absorb_item_if_correct(_item)


func _on_object_dropped(_item) -> void:
	SweetLogger.debug("object dropped, item: {0}", [_item])
	# If then player picks up a food_item (side) the table has already registerd, unregister
	var food_item: FoodItem = Helper.find_food_item(_item)
	if food_item and food_item.type == FoodItem.Type.SIDE:
		var original_count = _original_orders.count(food_item.id)
		var unsatisfied_count = _unsatisfied_orders.count(food_item.id)
		if original_count > unsatisfied_count:
			_unsatisfied_orders.append(food_item.id)


# original 		: burger cube, cube
# unsatisfied 	: burger cube
# table			: 

# There is no on_stay signal, we have to track player with bool
func _on_player_enter(_body):
	_players_count += 1
	SweetLogger.debug("_on_player_enter() players_count: {0}", [_players_count])


func _on_player_exit(_body):
	_players_count -= 1
	SweetLogger.debug("_on_player_exit() players_count: {0}", [_players_count])


func _place_order_if_player():
	if _state != TableState.ORDERING:
		return
	if _players_count > 0:
		place_order()
		_set_state(TableState.WAITING_PRIMARY)


# func _get_plate_controller_from_item(_item: Node) -> PlateController:
# 	return _item.get_children().filter(func(c): return c is PlateController).front() as PlateController


func _get_plate_controller_from_item(_item: Node) -> PlateController:
	if not _item:
		SweetLogger.debug("_item is null")
		return null

	for child in _item.get_children():
		if child is PlateController:
			SweetLogger.debug("found child")
			return child
	
	SweetLogger.debug("no match")
	return null


func _absorb_item_if_correct(_item: Node) -> void:
	SweetLogger.debug("_absorb_item_if_correct, item: {0}", [_item])
	if not _item:
		return
	if not (_state == TableState.WAITING_PRIMARY or _state == TableState.WAITING_FRIEND):
		return

	# Plate: Get plate controller in child of _item (hopefully a plate XRpickable)
	var plate_controller = _get_plate_controller_from_item(_item)
	SweetLogger.debug("_absorb_item_if_correct plate_controller ref: {0}", [plate_controller])
	_item.print_tree_pretty()
	
	if plate_controller:
		# Absorm items from the plate we want
		for food_item: FoodItem in plate_controller.container.contained_items: # TOOD: handle registering the meal again when a side is added to the plate
			if food_item.id in _unsatisfied_orders and not food_item.is_absorbed:
				SweetLogger.debug("_absorb_item_if_correct held a plate with FoodItem that is in unsatisfied orders, removing it")
				(plate_controller.get_parent() as XRToolsPickable).get_picked_up_by().enabled = false # Lock meal that is deliverd
				_unsatisfied_orders.erase(food_item.id)
				food_item.is_absorbed = true
				_update_state_from_orders()
		return
	
	# Side pickable item, no container
	var food_item: FoodItem = Helper.find_food_item(_item)
	if food_item and food_item.type == FoodItem.Type.SIDE:
		SweetLogger.debug("_absorb_item_if_correct held a side that is in unsatisfied orders, removing it")
		# Do not lock snap zone here. Problem if table want many meals, but to many sides have filled up slots, so can't place plates.
		_unsatisfied_orders.erase(food_item.id)
		_update_state_from_orders()
		return

	SweetLogger.debug("absorb_item_if_correct() held object is not a Plate or Side")


func _update_state_from_orders():
	SweetLogger.debug("_update_state_from_orders: unsatisfied_orders: {0}", [_unsatisfied_orders])
	if _unsatisfied_orders.size() > 0 and _state != TableState.EATING:
		_set_state(TableState.WAITING_FRIEND)

	# Table has everything it wants. Start eating
	elif _unsatisfied_orders.is_empty() and _state != TableState.EATING:
		_set_state(TableState.EATING)


func _collect_money_from_food():
	for snap_zone_node in snap_zones:
		var held_object = snap_zone_node.picked_up_object
		if not held_object:
			continue

		var plate: PlateController = _get_plate_controller_from_item(held_object)
		var food_item: FoodItem = Helper.find_food_item(held_object)
		if plate:
			for fi: FoodItem in plate.get_food_items():
				GameManager.set_money(GameManager.money + fi.sell_value)
		elif food_item:
			GameManager.set_money(GameManager.money + food_item.sell_value)

	SweetLogger.debug("_collect_money_from_food(), money: {0}", [GameManager.money])


func _set_snap_zones_enabled(value: bool) -> void:
	for zone in snap_zones:
		zone.enabled = value


## Server-only state transition: sets the new state's timer and assigns
## _state (whose setter refreshes the display on every peer).
func _set_state(newState: TableState) -> void:
	SweetLogger.debug("State START: {0}", [TableState.keys()[newState]], "table.gd", "_set_state")

	match newState:
		TableState.IDLE:
			_state_time = 0.0
			_state_duration = 0.0
			_state = newState
			customers.visible = false
		TableState.EMPTY:
			customers.visible = false
			_state = newState
		TableState.THINKING:
			_state_time = thinking_duration
			_state_duration = thinking_duration # Can't be done in _set_state(), will set duration inside timer
			_state = newState
		TableState.ORDERING:
			_state_time = ordering_duration
			_state_duration = ordering_duration
			_state = newState
		TableState.WAITING_PRIMARY:
			_state_time = primary_duration
			_state_duration = primary_duration
			_state = newState
			# Absorm meals that were already in the table when the state starts
			for zone in snap_zones:
				_absorb_item_if_correct(zone.picked_up_object)
		TableState.WAITING_FRIEND:
			_state_time = friend_duration
			_state_duration = friend_duration
			_state = newState
		TableState.EATING:
			_state_time = eating_duration
			_state_duration = eating_duration
			_collect_money_from_food()
			_set_snap_zones_enabled(false)
			audio_player.stream = money_sound
			audio_player.play()
			_state = newState


# When state timer is finished, do this stuff before moving to next state
func _state_end(oldState: TableState):
	SweetLogger.debug("State END: {0}", [TableState.keys()[oldState]], "table.gd", "_state_end")
	match oldState:
		TableState.EMPTY:
			customers.visible = true
			_set_state(TableState.THINKING)

		TableState.THINKING:
			_set_state(TableState.ORDERING)

		TableState.EATING:
			clearAllFood()
			_set_snap_zones_enabled(true)
			_set_state(TableState.EMPTY)

		TableState.ORDERING, TableState.WAITING_PRIMARY, TableState.WAITING_FRIEND:
			label_3d.text = lbl_gameover
			GameManager.game_over()


## Pure presentation, driven off the current (locally authoritative or
## synced-from-server) state. Runs on every peer.
func _refresh_display() -> void:
	# _state, _state_time and _unsatisfied_orders are replicated with spawn=true,
	# and MultiplayerSpawner applies a spawn payload BEFORE the node enters the
	# tree — so these setters fire while the @onready children below are still
	# null. Bail out until _ready() has resolved them; _ready() calls back in
	# once it has, so nothing that arrived early is lost.
	if not progress_bar or not label_3d or not label_3d_time:
		push_error("Table missing progress bar or label")
		return
	match _state:
		TableState.IDLE:
			progress_bar.set_bar_visible(false)
			label_3d.text = ""
			label_3d_time.text = ""
		TableState.EMPTY:
			progress_bar.set_bar_visible(false)
			label_3d.text = ""
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


func _process(delta: float) -> void:
	_refresh_display()
	if GameManager.game_state == GameManager.GameState.GAME_OVER:
		return
	_place_order_if_player()
	
	# If build mode, set, exit loop, be idle
	if GameManager.game_state == GameManager.GameState.BUILDING and not _state == TableState.IDLE:
		_set_state(TableState.IDLE)
		return
	# Game running, reenter loop
	elif GameManager.game_state == GameManager.GameState.RUNNING and _state == TableState.IDLE:
		_set_state(TableState.EMPTY)
		return
	# Still idle, do nothing
	elif  _state == TableState.IDLE:
		return

	# No counting down if wer're empty
	if _state == TableState.EMPTY:
		return	

	# Wait for state to finish
	if _state_time > 0.0:
		_state_time = max(0.0, _state_time - delta)
		return
	if GameManager.game_state == GameManager.GameState.GAME_OVER:
		return

	_state_end(_state)
