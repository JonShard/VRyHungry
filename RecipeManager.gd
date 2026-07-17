class_name RecipeManager
extends Node

static var _recipes: Dictionary
static var _combining_map: Dictionary
static var _cooking_map: Dictionary
static var _scene_paths: Dictionary 
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
			if typeof(data) != TYPE_DICTIONARY:
				push_warning("RecipeManager: YAML addon parsed recipes.yaml but returned an unsupported structure")
			
			_recipes = data
			_build_scene_paths()
			_build_combining_map()
			_build_cooking_map()
			_loaded = true
			

static func get_combination_result(first_id: StringName, second_id: StringName) -> PackedScene:
	load_recipes()
	var result_id = _combining_map.get(_make_pair_key(first_id, second_id))
	if result_id == null:
		return null
	return get_item_scene(result_id)


static func get_cooking_result(ingredient_id: StringName) -> Dictionary:
	load_recipes()
	for cooked_id in _cooking_map.keys():
		var cook_def = _cooking_map[cooked_id]
		if cook_def["ingredient"] == ingredient_id:
			return {"cooked_id": cooked_id, "time": cook_def["time"]}
	return {}


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
				print("%s <- %s + %s" % [result_id, first, second])
			else:
				print("RecipeManager: invalid combining recipe for '%s'" % result_id)


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


# Reads strucure into _combining_map:
# combining:
#   hamburger:
#     - [cooked_burger, burger_buns]
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


# Reads structure into _cooking_map:
# cooking:
#   cooked_burger: 
#     ingredient: raw_burger
#     time: 3
static func _build_cooking_map() -> void:
	_cooking_map.clear()
	var cooking = _recipes.get("cooking", {})
	if typeof(cooking) != TYPE_DICTIONARY:
		return
	for cooked_id in cooking.keys():
		var cook_def = cooking[cooked_id]
		if typeof(cook_def) != TYPE_DICTIONARY:
			push_error("RecipeManager: cooking recipe for '%s' must be a dictionary" % cooked_id)
			continue
		var ingredient = cook_def.get("ingredient", "")
		if typeof(ingredient) != TYPE_STRING or str(ingredient).is_empty():
			push_error("RecipeManager: cooking recipe '%s' missing a valid 'ingredient' field" % cooked_id)
			continue
		var time_val = cook_def.get("time", null)
		if typeof(time_val) != TYPE_INT and typeof(time_val) != TYPE_FLOAT:
			push_error("RecipeManager: cooking recipe '%s' missing a valid 'time' field" % cooked_id)
			continue
		# store cooked item -> { ingredient: StringName, time: float }
		_cooking_map[StringName(cooked_id)] = {"ingredient": StringName(str(ingredient)), "time": float(time_val)}
	