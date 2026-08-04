class_name ShopUI
extends Panel

@onready var money_label: Label = $Money

var controller: XRController3D = null
const INPUT_TOGGLE_COOLDOWN := 0.15

var enabled: bool = false: set = _set_enabled

var _last_toggle_time := 0.0
var viewport: XRToolsViewport2DIn3D

func _ready() -> void:
	detect_hand_from_xr_ancestor()
	if controller:
		controller.button_pressed.connect(_on_tracker_button_pressed)
	viewport = get_parent().get_parent() as XRToolsViewport2DIn3D
	if not viewport:
		push_error("Shop UI could not find XRToolsViewport2DIn3D grand parent")
	enabled = false
	
	
func _process(_delta: float) -> void:
	money_label.text = str(GameManager.money) + "$"


func toggle_shop():
	if GameManager.game_state == GameManager.GameState.BUILDING:
		print("Shop UI toggle shop")
		enabled = !enabled


func _set_enabled(value: bool) -> void:
		enabled = value
		visible = value
		viewport.enabled = value


func _on_tracker_button_pressed(button_name: String) -> void:
	print("Shop _on_tracker_button_pressed, button: ", button_name)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_toggle_time < INPUT_TOGGLE_COOLDOWN:
		return
	
	_last_toggle_time = now
	if button_name == "ax_button":
		toggle_shop()


func detect_hand_from_xr_ancestor() -> void:
	var curr: Node = get_parent()
	# Climb up the tree until we find an XRNode3D/XRController3D or hit root
	while curr != null:
		if curr is XRController3D:
			controller = curr
			break
		curr = curr.get_parent()
	
	if not controller:
		push_error("Shop UI could not find XRController3D ancestor")
	else:
		print ("Shop UI detected hand: ", controller.get_tracker_hand())
