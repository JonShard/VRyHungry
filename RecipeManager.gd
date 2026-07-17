class_name RecipeManager
extends Node

static var _recipes: Dictionary = {}
static var _combining_map: Dictionary = {}
static var _scene_paths: Dictionary = {}
static var _loaded: bool = false

static func load_recipes() -> void:
	if _loaded:
		return

	var recipe_path := "res://recipes.yaml"
	if not FileAccess.file_exists(recipe_path):
		push_error("RecipeManager: recipes.yaml was not found at %s" % recipe_path)
		return

	var yaml_available := ClassDB.class_exists("YAML")
	if yaml_available:
		var result = ClassDB.class_call_static("YAML", "load_file", recipe_path)
		if result != null and not result.has_error():
			var data = result.get_data()
			if typeof(data) == TYPE_DICTIONARY:
				_recipes = data
				_build_scene_paths()
				_build_combining_map()
				_loaded = true
				return
			push_warning("RecipeManager: YAML addon parsed recipes.yaml but returned an unsupported structure; falling back to built-in parser")
		else:
			push_warning("RecipeManager: YAML addon failed to read %s; falling back to built-in parser: %s" % [recipe_path, result.get_error() if result != null else "unknown error"])

	var fallback_data = _load_recipes_with_fallback_parser(recipe_path)
	if typeof(fallback_data) != TYPE_DICTIONARY:
		push_error("RecipeManager: failed to parse recipes.yaml with both YAML addon and built-in fallback")
		return

	_recipes = fallback_data
	_build_scene_paths()
	_build_combining_map()
	_loaded = true

static func get_combination(first_id: StringName, second_id: StringName) -> PackedScene:
	load_recipes()
	var result_id = _combining_map.get(_make_pair_key(first_id, second_id))
	if result_id == null:
		return null
	return get_item_scene(result_id)

static func get_item_scene(item_id: StringName) -> PackedScene:
	load_recipes()
	var scene_path = _scene_paths.get(str(item_id), "")
	if typeof(scene_path) != TYPE_STRING or scene_path.is_empty():
		push_error("RecipeManager: no scene mapping found for item id '%s'" % item_id)
		return null

	var scene = ResourceLoader.load(scene_path)
	if not scene:
		push_error("RecipeManager: failed to load scene '%s' for item '%s'" % [scene_path, item_id])
		return null
	return scene as PackedScene

static func print_all_recipes() -> void:
	load_recipes()
	if not _loaded:
		print("RecipeManager: could not load recipes.yaml; no recipes printed.")
		return

	print("RecipeManager: Loaded recipes")

	var combining = _recipes.get("combining", {})
	if typeof(combining) != TYPE_DICTIONARY:
		print("RecipeManager: combining recipes are not available in recipes.yaml")
		return

	if combining.is_empty():
		print("RecipeManager: no combining recipes found")
		return

	for result_id in combining.keys():
		var recipe_entries = _get_recipe_entries(combining[result_id])
		if recipe_entries.is_empty():
			print("RecipeManager: invalid combining recipe for '%s'" % result_id)
			continue

		for recipe in recipe_entries:
			if typeof(recipe) == TYPE_ARRAY and recipe.size() == 2:
				var first = str(recipe[0])
				var second = str(recipe[1])
				print("%s + %s -> %s" % [first, second, result_id])
			else:
				print("RecipeManager: invalid combining recipe for '%s'" % result_id)

static func _load_recipes_with_fallback_parser(recipe_path: String) -> Dictionary:
	var file := FileAccess.open(recipe_path, FileAccess.READ)
	if file == null:
		push_error("RecipeManager: could not open %s: %s" % [recipe_path, FileAccess.get_open_error()])
		return {}

	var lines := file.get_as_text().split("\n")
	var result := {
		"items": {},
		"combining": {}
	}
	var current_section := ""
	var current_result_id := ""
	var current_item_id := ""
	var current_item_def: Dictionary = {}

	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"):
			continue

		var indent := line.length() - line.lstrip(" \t").length()
		if indent == 0:
			current_section = ""
			current_result_id = ""
			current_item_id = ""
			if trimmed == "items:":
				current_section = "items"
			elif trimmed == "combining:":
				current_section = "combining"
			continue

		if current_section == "items":
			if indent == 2 and trimmed.ends_with(":"):
				current_item_id = trimmed.trim_suffix(":")
				current_item_def = {}
				result["items"][current_item_id] = current_item_def
				continue

			if indent >= 4 and not current_item_id.is_empty():
				var parts := trimmed.split(":", true, 1)
				if parts.size() == 2:
					var key := parts[0].strip_edges()
					var value := parts[1].strip_edges()
					current_item_def[key] = value
			continue

		if current_section == "combining":
			if indent == 2 and trimmed.ends_with(":"):
				current_result_id = trimmed.trim_suffix(":")
				result["combining"][current_result_id] = []
				continue

			if trimmed.begins_with("- ") and not current_result_id.is_empty():
				var item_text := trimmed.substr(2).strip_edges()
				if item_text.begins_with("[") and item_text.ends_with("]"):
					var inner := item_text.substr(1, item_text.length() - 2).strip_edges()
					var parts := inner.split(",", false)
					var recipe := []
					for part in parts:
						recipe.append(part.strip_edges())
					result["combining"][current_result_id].append(recipe)
				else:
					result["combining"][current_result_id].append([item_text])

	return result

static func _build_scene_paths() -> void:
	_scene_paths.clear()
	var items = _recipes.get("items", {})
	if typeof(items) != TYPE_DICTIONARY:
		return
	for item_id in items.keys():
		var item_def = items[item_id]
		if typeof(item_def) != TYPE_DICTIONARY:
			continue
		var scene_path = item_def.get("scene", "")
		if typeof(scene_path) == TYPE_STRING and not scene_path.is_empty():
			_scene_paths[str(item_id)] = scene_path

static func _get_recipe_entries(recipe_value: Variant) -> Array:
	var recipes: Array = []
	if typeof(recipe_value) != TYPE_ARRAY:
		return recipes
	if recipe_value.is_empty():
		return recipes
	if typeof(recipe_value[0]) == TYPE_ARRAY:
		for recipe in recipe_value:
			if typeof(recipe) == TYPE_ARRAY and recipe.size() == 2:
				recipes.append(recipe)
	else:
		if recipe_value.size() == 2:
			recipes.append(recipe_value)
	return recipes

static func _build_combining_map() -> void:
	_combining_map.clear()
	var combining = _recipes.get("combining", {})
	for result_id in combining.keys():
		var recipe_entries = _get_recipe_entries(combining[result_id])
		if recipe_entries.is_empty():
			push_error("RecipeManager: combining recipe '%s' must contain at least one valid recipe" % result_id)
			continue
		for recipe in recipe_entries:
			var first = StringName(recipe[0])
			var second = StringName(recipe[1])
			var key = _make_pair_key(first, second)
			_combining_map[key] = result_id

static func _make_pair_key(first_id: StringName, second_id: StringName) -> StringName:
	if str(first_id) <= str(second_id):
		return StringName(str(first_id) + "|" + str(second_id))
	return StringName(str(second_id) + "|" + str(first_id))
