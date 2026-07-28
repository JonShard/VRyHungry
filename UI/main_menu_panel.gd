extends Control

## The 2D UI rendered inside the main menu's world-space viewport
## (XRToolsViewport2DIn3D). Lets the player pick John's scene, host a
## multiplayer game, or join one by IP, driving scene switches + NetworkManager
## directly.

const JON_SCENE := "res://Scenes/JonScene.tscn"
const MULTIPLAYER_SCENE := "res://Scenes/multiPlayer.tscn"
const SETTINGS_PATH := "user://vryhungry_settings.cfg"

var _ip := "127.0.0.1"

@onready var _root_view: Control = %RootView
@onready var _join_view: Control = %JoinView
@onready var _ip_label: Label = %IPLabel
@onready var _status: Label = %Status
@onready var _keypad: GridContainer = %Keypad
@onready var _john_btn: Button = %JohnButton
@onready var _host_btn: Button = %HostButton
@onready var _join_menu_btn: Button = %JoinMenuButton
@onready var _join_btn: Button = %JoinButton
@onready var _back_btn: Button = %BackButton


func _ready() -> void:
	if _bypass_menu_for_cmdline():
		return
	for child in _keypad.get_children():
		if child is Button:
			child.pressed.connect(_on_key.bind(child.text))
	_john_btn.pressed.connect(_on_john_pressed)
	_host_btn.pressed.connect(_on_host_pressed)
	_join_menu_btn.pressed.connect(_show_join_view)
	_join_btn.pressed.connect(_on_join_pressed)
	_back_btn.pressed.connect(_show_root_view)
	_load_ip()
	_show_root_view()
	_refresh_ip()
	# Show why we're back here, if the last session ended unexpectedly
	# (dropped connection, failed join). Pulled rather than pushed, since
	# NetworkManager may have set this before this panel even existed.
	var status := NetworkManager.take_status()
	if not status.is_empty():
		set_status(status)


## --server / --join <ip> on the command line skip straight to the multiplayer
## scene, same as the previously headless-tested main.tscn flow.
func _bypass_menu_for_cmdline() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		NetworkManager.request_host()
		get_tree().change_scene_to_file.call_deferred(MULTIPLAYER_SCENE)
		return true
	if args.has("--join"):
		var idx := args.find("--join")
		var addr := "127.0.0.1"
		if idx + 1 < args.size():
			addr = args[idx + 1]
		NetworkManager.request_join(addr)
		get_tree().change_scene_to_file.call_deferred(MULTIPLAYER_SCENE)
		return true
	return false


func _show_root_view() -> void:
	_root_view.visible = true
	_join_view.visible = false


func _show_join_view() -> void:
	_root_view.visible = false
	_join_view.visible = true
	set_status("Enter host IP, then Join")


func _on_key(key: String) -> void:
	match key:
		"DEL":
			_ip = _ip.substr(0, max(0, _ip.length() - 1))
		_:
			if _ip.length() < 21:
				_ip += key
	_refresh_ip()


func _refresh_ip() -> void:
	_ip_label.text = _ip if not _ip.is_empty() else "_"


func _on_john_pressed() -> void:
	NetworkManager.leave()
	get_tree().change_scene_to_file.call_deferred(JON_SCENE)


func _on_host_pressed() -> void:
	NetworkManager.request_host()
	get_tree().change_scene_to_file.call_deferred("res://Scenes/JonScene.tscn")


func _on_join_pressed() -> void:
	if _ip.is_empty():
		set_status("Enter an IP first")
		return
	_save_ip()
	NetworkManager.request_join(_ip)
	get_tree().change_scene_to_file.call_deferred(MULTIPLAYER_SCENE)


## Remembers the last IP the player tried to join, so the keypad starts
## pre-filled next time instead of always defaulting to 127.0.0.1.
func _load_ip() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_ip = cfg.get_value("network", "last_ip", _ip)


func _save_ip() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("network", "last_ip", _ip)
	cfg.save(SETTINGS_PATH)


## Called by network_manager (e.g. on connection_failed after a bounce back to
## this menu) to show feedback.
func set_status(text: String) -> void:
	if _status:
		_status.text = text
