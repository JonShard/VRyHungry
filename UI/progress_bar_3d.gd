extends Node3D
class_name ProgressBar3D

@export var y_billboard: bool = false
@export var exponential:bool = false

@onready var progress_bar: ProgressBar = $Sprite3D/SubViewport/ProgressBar
@onready var sprite_3d: Sprite3D = $Sprite3D


func _ready() -> void:
	Helper.check_reference(self, progress_bar, ProgressBar)
	if y_billboard:
		$Sprite3D.billboard = BaseMaterial3D.BillboardMode.BILLBOARD_FIXED_Y

func set_progress(value: float) -> void:
	if exponential:
		progress_bar.value = clamp(pow(value, 2.1), 0.0, 1.0) * 100
	else:
		progress_bar.value = clamp(value, 0.0, 1.0) * 100


func get_progress() -> float:
	return progress_bar.value


func set_bar_visible(value: bool) -> void:
	progress_bar.visible = value


func is_bar_visible() -> bool:
	return progress_bar != null and progress_bar.visible


func override_fill_color(color: Color) -> void:
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = color
	# Override the 'fill' StyleBox on the ProgressBar
	progress_bar.add_theme_stylebox_override("fill", style_box)
