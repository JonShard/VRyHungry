extends Node3D
class_name ProgressBar3D

@export var y_billboard: bool = false

@onready var progress_bar: ProgressBar = $Sprite3D/SubViewport/ProgressBar
@onready var sprite_3d: Sprite3D = $Sprite3D


func _ready() -> void:
	if not progress_bar:
		push_error("Progressbar3D missing reference to ProgressBar")
	if y_billboard:
		$Sprite3D.billboard = BaseMaterial3D.BillboardMode.BILLBOARD_FIXED_Y

func set_progress(value: float) -> void:
	progress_bar.value = clamp(value, 0.0, 1.0) * 100


func get_progress() -> float:
	return progress_bar.value


func set_bar_visible(value: bool) -> void:
	progress_bar.visible = value


func override_fill_color(color: Color) -> void:
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = color
	# Override the 'fill' StyleBox on the ProgressBar
	progress_bar.add_theme_stylebox_override("fill", style_box)
