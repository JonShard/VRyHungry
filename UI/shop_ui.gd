class_name ShopUI
extends Panel

@onready var money_label: Label = $Money

var controller: XRController3D = null
var other_controller: XRController3D = null
const INPUT_TOGGLE_COOLDOWN := 0.15

var enabled: bool = false: set = _set_enabled

var _last_toggle_time := 0.0
var viewport: XRToolsViewport2DIn3D

func _ready() -> void:
	detect_hand_from_xr_ancestor()

	if controller:
		controller.button_pressed.connect(_on_controller_button_pressed)
	if other_controller:
		other_controller.button_pressed.connect(_on_other_controller_button_pressed)
	Signals.station_bought.connect(_on_station_bought)
	viewport = get_parent().get_parent() as XRToolsViewport2DIn3D
	if not viewport:
		push_error("Shop UI could not find XRToolsViewport2DIn3D grand parent")
	enabled = false
	
	
func _process(_delta: float) -> void:
	money_label.text = str(GameManager.money) + "$"


func toggle_shop():
	if GameManager.game_state == GameManager.GameState.BUILDING:
		SweetLogger.debug("toggle shop", [], "shop_ui.gd", "toggle_shop")
		enabled = !enabled
		SweetLogger.debug("_process: money={0} label text={1}", [GameManager.money, money_label.text], "shop_ui.gd", "toggle_shop")



func _set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if viewport:
		viewport.enabled = value

	_set_poke_enabled_for_controller(other_controller, value)



func _set_poke_enabled_for_controller(controller_node: XRController3D, value: bool) -> void:
	if not controller_node:
		return

	var poke_node = Helper.find_first_child_of_type(controller_node, XRToolsPoke)
	if poke_node:
		SweetLogger.debug("_set_poke_enabled_for_controller: {0} poke enabled: {1}", [poke_node.get_path(), value], "shop_ui.gd", "_set_poke_enabled_for_controller")
		poke_node.enabled = value
		poke_node.visible = value
	else:
		SweetLogger.debug("_set_poke_enabled_for_controller: {0} poke not found", [controller_node.name], "shop_ui.gd", "_set_poke_enabled_for_controller")

# For some reason, this is called every frame the button is down. So we need our own timer.
func _on_controller_button_pressed(button_name: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_toggle_time < INPUT_TOGGLE_COOLDOWN:
		return
	
	_last_toggle_time = now
	if button_name == "ax_button":
		toggle_shop()


func _on_other_controller_button_pressed(button_name: String) -> void:
	# If user opens menu on other hand. Close this one.
	if enabled and button_name == "ax_button":
		enabled = false


func _on_station_bought(_instance) -> void:
	enabled = false
	money_label.text = str(GameManager.money) + "$"
	SweetLogger.debug("_on_station_bought: new money: {0}", [GameManager.money], "shop_ui.gd", "_on_station_bought")


func detect_hand_from_xr_ancestor() -> void:
	controller = XRHelpers.get_xr_controller(self)
	if not controller:
		push_error("Shop UI could not find XRController3D ancestor")
		return

	var left_controller := XRHelpers.get_left_controller(self)
	var right_controller := XRHelpers.get_right_controller(self)

	if controller == left_controller:
		other_controller = right_controller
	elif controller == right_controller:
		other_controller = left_controller
	SweetLogger.debug("detected hand: {0}", [controller.get_tracker_hand()], "shop_ui.gd", "detect_hand_from_xr_ancestor")
