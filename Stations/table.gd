class_name Table
extends SharedInventoryStation

@export var thinking_duration: float = 3.0
@export var ordering_duration: float = 50.0
@export var primary_duration: float = 70.0
@export var friend_duration: float = 12.0
@export var eating_duration: float = 5.0
@export var money_sound: AudioStream 

@export var label_3d: Label3D
@export var label_3d_time: Label3D
@export var snap_zones: Array[XRToolsSnapZone]
@export var progress_bar: ProgressBar3D
@export var audio_player: AudioStreamPlayer3D
@export var customers: Node3D
@export var player_detect_area_3d: Area3D

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


var _state: TableState = TableState.EMPTY
var _state_time: float = 0.0
var _state_duration: float = 0.0
var _original_orders: Array[String] = []
var _unsatisfied_orders: Array[String] = []
var _players_count: int = 0
var _is_leader: bool = true # Only the group leader orchestrates the state and shows its own visuals; see _on_group_changed().


func place_order() -> void:
	SweetLogger.debug("->[]")
	if not NetworkManager.owns_world():
		server_place_order.rpc_id(1)
		SweetLogger.debug("  []-> rpc")
		return
	var new_orders: Array[String] = _unsatisfied_orders.duplicate()
	# for _i in range(0, randi_range(1, 2)):
	# 	new_orders.append(GameManager.get_random_meal())
	# for _i in range(0, randi_range(0, 1)):
	# 	new_orders.append(GameManager.get_random_side())
	new_orders.append(GameManager.get_random_meal())
	_unsatisfied_orders = new_orders
	_original_orders = _unsatisfied_orders.duplicate()
	_set_state(TableState.WAITING_PRIMARY)
	SweetLogger.info("Placed order, orders: {0}", [_unsatisfied_orders])

@rpc("any_peer", "call_remote", "reliable")
func server_place_order() -> void:
	SweetLogger.debug("->[]")
	if NetworkManager.owns_world():
		place_order()


# Flattens items held across all of this table's snap zones
func get_exposed_food_items() -> Array[FoodItem]:
	var items: Array[FoodItem] = []
	for zone in snap_zones:
		var held_object = zone.picked_up_object
		if not held_object:
			continue
		var plate: PlateController = Helper.find_first_child_of_type(held_object, PlateController)
		if plate:
			items.append_array(plate.container.contained_items)
			continue
		var food_item: FoodItem = Helper.find_food_item(held_object)
		if food_item:
			items.append(food_item)
	return items


# Only the group leader orchestrates the FSM and shows its visuals
func _on_group_changed() -> void:
	_is_leader = is_group_leader()
	if label_3d:
		label_3d.visible = _is_leader
	if label_3d_time:
		label_3d_time.visible = _is_leader
	if progress_bar:
		progress_bar.set_bar_visible(_is_leader and progress_bar.is_bar_visible())


func satisfyAllOrders() -> void:
	SweetLogger.debug("->[]")
	_unsatisfied_orders.clear()
	_original_orders.clear()
	clearAllFood()
	_set_state(TableState.EMPTY)


func clearAllFood() -> void:
	SweetLogger.debug("->[]")
	for zone in snap_zones:
		var held_object = zone.picked_up_object
		if not held_object:
			continue

		var plate: PlateController = Helper.find_first_child_of_type(held_object, PlateController)
		var food_item: FoodItem = Helper.find_food_item(held_object)
		if plate:
			plate.container.clear()
			plate.enabled = true
			plate.is_dirty = true

		# Side or other food item directly on table
		elif food_item and food_item.type == FoodItem.Type.SIDE:
			zone.drop_object()
			NetworkManager.despawn_item(held_object)


# Group called from Queue when trying to assign customers to tables
func try_consume_customer() -> bool:
	if _state == TableState.EMPTY:
		SweetLogger.debug("Try consume customer, consumed a customer")
		_state_end(TableState.EMPTY)
		return true
	return false


func _enter_tree() -> void:
	super._enter_tree()
	var properties: Array[NodePath] = [".:_state_duration", ".:_state", ".:_state_time", ".:_unsatisfied_orders", "Customers:visible"]
	for property_path in properties:
		sync_config.add_property(property_path)
		sync_config.property_set_spawn(property_path, false)
		sync_config.property_set_replication_mode(property_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	SweetLogger.debug("sync_config properties: {0} | root_path: {1} | authority: {2} | peer: {3}", [sync_config.get_properties(), synchronizer.root_path, get_multiplayer_authority(), multiplayer.get_unique_id()])


func _ready() -> void:
	super.ready()
	Helper.check_reference(self, label_3d, Label3D)
	Helper.check_reference(self, label_3d_time, Label3D)
	Helper.check_reference(self, progress_bar, ProgressBar3D)
	progress_bar.y_billboard = true
	progress_bar.exponential = true
	Helper.check_reference(self, audio_player, AudioStreamPlayer3D)
		
	# Get snap_zones for plates, store in array snap_zones
	for child in get_children():
		var snap_zone_node = child as XRToolsSnapZone
		if snap_zone_node:
			snap_zones.append(snap_zone_node)

	if snap_zones.is_empty():
		SweetLogger.warning("{0} missing XRToolsSnapZone children", [name])
		return

	for snap_zone_node in snap_zones:
		snap_zone_node.has_picked_up.connect(_on_object_picked_up)
		snap_zone_node.has_dropped.connect(_on_object_dropped)
	_set_state(TableState.EMPTY)


func _on_object_picked_up(_item) -> void:
	SweetLogger.debug("Object picked up: {0}", [_item])
	if _state == TableState.EATING:
		return
	_absorb_item_if_correct(_item)


func _on_object_dropped(_item) -> void:
	SweetLogger.debug("Object dropped, item: {0}", [_item])
	# If then player picks up a food_item (side) the table has already registerd, unregister
	var food_item: FoodItem = Helper.find_food_item(_item)
	if food_item and food_item.type == FoodItem.Type.SIDE:
		var original_count = _original_orders.count(food_item.id)
		var unsatisfied_count = _unsatisfied_orders.count(food_item.id)
		if original_count > unsatisfied_count:
			_unsatisfied_orders.append(food_item.id)


# There is no on_stay signal, we have to track player with bool
func _on_player_enter(_body):
	_players_count += 1
	SweetLogger.debug("Player enter, players_count: {0}", [_players_count])
	if _is_leader and _state == TableState.ORDERING:
		place_order()


func _on_player_exit(_body):
	_players_count -= 1
	SweetLogger.debug("Player exit, players_count: {0}", [_players_count])


func _absorb_item_if_correct(_item: Node) -> void:
	SweetLogger.debug("Absorb item if correct, item: {0}", [_item])
	if not _item:
		return
	if not (_state == TableState.WAITING_PRIMARY or _state == TableState.WAITING_FRIEND):
		return

	# Plate: Get plate controller in child of _item (hopefully a plate XRpickable)
	var plate_controller: PlateController = Helper.find_first_child_of_type(_item, PlateController)
	SweetLogger.debug("Plate_controller ref: {0}", [plate_controller])
	
	if plate_controller:
		# Absorm items from the plate we want
		for food_item: FoodItem in plate_controller.container.contained_items: # TOOD: handle registering the meal again when a side is added to the plate
			if food_item.id in _unsatisfied_orders and not food_item.is_absorbed:
				SweetLogger.debug("Held a plate with FoodItem that is in unsatisfied orders, removing it")
				plate_controller.enabled = false # Lock plate
				_unsatisfied_orders.erase(food_item.id)
				food_item.is_absorbed = true
				_update_state_from_orders()
		return
	
	# Side pickable item, no container
	var food_item: FoodItem = Helper.find_food_item(_item)
	if food_item and food_item.type == FoodItem.Type.SIDE:
		SweetLogger.debug("Held a side that is in unsatisfied orders, removing it")
		# Do not lock snap zone here. Problem if table want many meals, but to many sides have filled up slots, so can't place plates.
		_unsatisfied_orders.erase(food_item.id)
		_update_state_from_orders()
		return

	SweetLogger.debug("Held object is not a Plate or Side")


func _update_state_from_orders():
	SweetLogger.debug("Unsatisfied_orders: {0}", [_unsatisfied_orders])
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

		var plate: PlateController = Helper.find_first_child_of_type(held_object, PlateController)
		var food_item: FoodItem = Helper.find_food_item(held_object)
		if plate:
			for fi: FoodItem in plate.get_food_items():
				GameManager.set_money(GameManager.money + fi.sell_value)
		elif food_item:
			GameManager.set_money(GameManager.money + food_item.sell_value)

	SweetLogger.debug("Money: {0}", [GameManager.money])


func _set_snap_zones_enabled(value: bool) -> void:
	# Enabling is the world owner's call only — a client's zones stay gated no
	# matter what state its copy of the FSM thinks it is in.
	var is_enabled := value and NetworkManager.owns_world()
	for zone in snap_zones:
		zone.enabled = is_enabled


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
			# Absorm meals that were already in the table when the state starts (We missed the pickup event)
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
			SweetLogger.info("Table satisfied, emitting signal")
			Signals.table_satisfied.emit(self)

		TableState.ORDERING, TableState.WAITING_PRIMARY, TableState.WAITING_FRIEND:
			SweetLogger.info("{0}: order timed out in state {1}, game over", [name, TableState.keys()[oldState]])
			label_3d.text = lbl_gameover
			GameManager.game_over()


func _refresh_display() -> void:
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
	super.process(delta)
	#SweetLogger.debug("State {0} time: {1} duration: {2} is_leader: {3}", [TableState.keys()[_state], _state_time, _state_duration, _is_leader])
	_refresh_display()
	if not _is_leader:
		return # Follower: the group leader orchestrates the FSM, we just mirror its synced state.

	if not NetworkManager.owns_world():
		# SweetLogger.debug("Not server, skipping state update")
		return

	if GameManager.game_state == GameManager.GameState.GAME_OVER:
		return
	
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
