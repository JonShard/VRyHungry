class_name RecipeManager
extends Node

static var _recipes: Dictionary
static var _combining_map: Dictionary
static var _cooking_map: Dictionary
static var _chopping_map: Dictionary
static var _rolling_map: Dictionary
static var _augmenting_map: Dictionary
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
			_build_chopping_map()
			_build_rolling_map()
			_build_augmenting_map()
			_loaded = true
			

static func get_combination_result(first_id: StringName, second_id: StringName) -> PackedScene:
	load_recipes()
	var result_id = _combining_map.get(_make_pair_key(first_id, second_id))
	if result_id == null:
		return null
	return get_item_scene(result_id)


static func get_cooking_result(ingredient_id: StringName) -> String:
	load_recipes()
	for cooked_id in _cooking_map.keys():
		var cook_defs = _cooking_map[cooked_id]
		# cook_defs may be an Array of recipe dicts (new) or a single dict (backwards compat)
		if typeof(cook_defs) == TYPE_ARRAY:
			for cook_def in cook_defs:
				if cook_def["ingredient"] == ingredient_id:
					return cooked_id
		else:
			var cook_def = cook_defs
			if cook_def["ingredient"] == ingredient_id:
				return cooked_id
	return ""


static func get_cooking_time(ingredient_id: StringName) -> float:
	load_recipes()
	for cooked_id in _cooking_map.keys():
		var cook_defs = _cooking_map[cooked_id]
		if typeof(cook_defs) == TYPE_ARRAY:
			for cook_def in cook_defs:
				if cook_def["ingredient"] == ingredient_id:
					return cook_def["time"]
		else:
			var cook_def = cook_defs
			if cook_def["ingredient"] == ingredient_id:
				return cook_def["time"]
	return 0.0


static func get_chopping_result(ingredient_id: StringName) -> String:
	load_recipes()
	for chopped_id in _chopping_map.keys():
		var chop_def = _chopping_map[chopped_id]
		if chop_def["ingredient"] == ingredient_id:
			return chopped_id
	return ""


static func get_chopping_work(ingredient_id: StringName) -> float:
	load_recipes()
	for chopped_id in _chopping_map.keys():
		var chop_def = _chopping_map[chopped_id]
		if chop_def["ingredient"] == ingredient_id:
			return chop_def["work"]
	return 0.0


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
		SweetLogger.warning("could not load recipes.yaml; no recipes printed.", [])
		return

	if _combining_map.is_empty():
		SweetLogger.warning("no combining recipes found", [])
		return

	SweetLogger.info("#### RecipeManager: Loaded recipes ####", [])
	_print_combining_recipes()
	SweetLogger.info("", [])
	_print_cooking_recipes()
	SweetLogger.info("", [])
	_print_chopping_recipes()
	SweetLogger.info("", [])
	_print_rolling_recipes()
	SweetLogger.info("", [])
	_print_augmenting_recipes()

static func _print_combining_recipes() -> void:
	for pair_key in _combining_map.keys():
		var result_id = _combining_map[pair_key]
		var key_str = str(pair_key)
		var separator_index = key_str.find("|")
		if separator_index == -1:
			SweetLogger.warning("invalid combining map key '{0}'", [key_str])
			continue

		var first = key_str.substr(0, separator_index)
		var second = key_str.substr(separator_index + 1, key_str.length() - separator_index - 1)
		SweetLogger.info("  {0} <-combine-- {1} + {2}", [result_id, first, second])


static func _print_cooking_recipes() -> void:
	for cooked_id in _cooking_map.keys():
		var cook_defs = _cooking_map[cooked_id]
		if typeof(cook_defs) == TYPE_ARRAY:
			for cook_def in cook_defs:
				SweetLogger.info("  {0} <-cook-- {1} - time: {2}", [cooked_id, cook_def["ingredient"], cook_def["time"]], "RecipeManager.gd", "_print_cooking_recipes")
		else:
			var cook_def = cook_defs
			SweetLogger.info("  {0} <-cook-- {1} - time: {2}", [cooked_id, cook_def["ingredient"], cook_def["time"]], "RecipeManager.gd", "_print_cooking_recipes")


static func _print_chopping_recipes() -> void:
	for chopped_id in _chopping_map.keys():
		var chop_def = _chopping_map[chopped_id]
		SweetLogger.info("  {0} <-chop-- {1} - work: {2}", [chopped_id, chop_def["ingredient"], chop_def["work"]], "RecipeManager.gd", "_print_chopping_recipes")


static func _print_rolling_recipes() -> void:
	for rolled_id in _rolling_map.keys():
		var roll_def = _rolling_map[rolled_id]
		SweetLogger.info("  {0} <-roll-- {1} - work: {2}", [rolled_id, roll_def["ingredient"], roll_def["work"]], "RecipeManager.gd", "_print_rolling_recipes")


static func _print_augmenting_recipes() -> void:
	for target_id in _augmenting_map.keys():
		var augment_def = _augmenting_map[target_id]
		for ingredient_id in augment_def.keys():
			var attr_key = augment_def[ingredient_id]
			SweetLogger.info("  {0} <-augment-- {1} adds attribute '{2}'", [target_id, ingredient_id, attr_key])


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


static func _make_pair_key(first_id: StringName, second_id: StringName) -> StringName:
	if str(first_id) <= str(second_id):
		return StringName(str(first_id) + "|" + str(second_id))
	return StringName(str(second_id) + "|" + str(first_id))


# Reads structure into _cooking_map:
# cooking:
#   cooked_burger: 
#     ingredient: raw_burger
#     time: 3
# or allowing multiple recipes for the same cooked item:
#   charcoal:
#     - ingredient: cube
#       time: 1
#     - ingredient: some_other
#       time: 2
static func _build_cooking_map() -> void:
	_cooking_map.clear()
	var cooking = _recipes.get("cooking", {})
	if typeof(cooking) != TYPE_DICTIONARY:
		return
	for cooked_id in cooking.keys():
		var cook_val = cooking[cooked_id]
		var entries: Array = []
		if typeof(cook_val) == TYPE_ARRAY:
			for entry in cook_val:
				if typeof(entry) != TYPE_DICTIONARY:
					push_error("RecipeManager: cooking recipe for '%s' contains a non-dictionary entry" % cooked_id)
					continue
				entries.append(entry)
		elif typeof(cook_val) == TYPE_DICTIONARY:
			entries.append(cook_val)
		else:
			push_error("RecipeManager: cooking recipe for '%s' must be a dictionary or array of dictionaries" % cooked_id)
			continue

		var parsed_entries: Array = []
		for cook_def in entries:
			var ingredient = cook_def.get("ingredient", "")
			if typeof(ingredient) != TYPE_STRING or str(ingredient).is_empty():
				push_error("RecipeManager: cooking recipe '%s' missing a valid 'ingredient' field" % cooked_id)
				continue
			var time_val = cook_def.get("time", null)
			if typeof(time_val) != TYPE_INT and typeof(time_val) != TYPE_FLOAT:
				push_error("RecipeManager: cooking recipe '%s' missing a valid 'time' field" % cooked_id)
				continue
			parsed_entries.append({"ingredient": StringName(str(ingredient)), "time": float(time_val)})

		if not parsed_entries.is_empty():
			_cooking_map[StringName(cooked_id)] = parsed_entries
	

# Reads structure into _chopping_map:
# chopping:
#   chopped_onion: 
#     ingredient: onion
#     work: 2
static func _build_chopping_map() -> void:
	_chopping_map.clear()
	var chopping = _recipes.get("chopping", {})
	if typeof(chopping) != TYPE_DICTIONARY:
		return
	for chopped_id in chopping.keys():
		var chop_def = chopping[chopped_id]
		if typeof(chop_def) != TYPE_DICTIONARY:
			push_error("RecipeManager: chopping recipe for '%s' must be a dictionary" % chopped_id)
			continue
		var ingredient = chop_def.get("ingredient", "")
		if typeof(ingredient) != TYPE_STRING or str(ingredient).is_empty():
			push_error("RecipeManager: chopping recipe '%s' missing a valid 'ingredient' field" % chopped_id)
			continue
		var work_val = chop_def.get("work", null)
		if typeof(work_val) != TYPE_INT and typeof(work_val) != TYPE_FLOAT:
			push_error("RecipeManager: chopping recipe '%s' missing a valid 'work' field" % chopped_id)
			continue
		# store chopped item -> { ingredient: StringName, work: float }
		_chopping_map[StringName(chopped_id)] = {"ingredient": StringName(str(ingredient)), "work": float(work_val)}


# Reads structure into _rolling_map:
# rolling:
#   pie_base:
# 	  ingredient: dough
# 	  work: 80
static func _build_rolling_map() -> void:
	_rolling_map.clear()
	var rolling = _recipes.get("rolling", {})
	if typeof(rolling) != TYPE_DICTIONARY:
		return
	for rolled_id in rolling.keys():
		var roll_def = rolling[rolled_id]
		if typeof(roll_def) != TYPE_DICTIONARY:
			push_error("RecipeManager: rolling recipe for '%s' must be a dictionary" % rolled_id)
			continue
		var ingredient = roll_def.get("ingredient", "")
		if typeof(ingredient) != TYPE_STRING or str(ingredient).is_empty():
			push_error("RecipeManager: rolling recipe '%s' missing a valid 'ingredient' field" % rolled_id)
			continue
		var work_val = roll_def.get("work", null)
		if typeof(work_val) != TYPE_INT and typeof(work_val) != TYPE_FLOAT:
			push_error("RecipeManager: rolling recipe '%s' missing a valid 'work' field" % rolled_id)
			continue
		# store rolled item -> { ingredient: StringName, work: float }
		_rolling_map[StringName(rolled_id)] = {"ingredient": StringName(str(ingredient)), "work": float(work_val)}


# Reads structure into _augmenting_map:
# augmenting: # Process of adding an item onto another without changing it's type, but toggling attributes.
# 	cooked_burger:
# 		has_tomato: sliced_tomato
# 		has_cheese: cheese
static func _build_augmenting_map() -> void:
	_augmenting_map.clear()
	var augmenting = _recipes.get("augmenting", {})
	if typeof(augmenting) != TYPE_DICTIONARY:
		return
	for target_id in augmenting.keys():
		var augment_def = augmenting[target_id]
		if typeof(augment_def) != TYPE_DICTIONARY:
			push_error("RecipeManager: augmenting recipe for '%s' must be a dictionary" % target_id)
			continue
		var map: Dictionary = {}
		for attr_key in augment_def.keys():
			var ingredient = augment_def[attr_key]
			if typeof(ingredient) != TYPE_STRING or str(ingredient).is_empty():
				push_error("RecipeManager: augmenting recipe '%s' has invalid ingredient for '%s'" % [target_id, attr_key])
				continue
			# store ingredient -> attribute_key (e.g. sliced_tomato -> has_tomato)
			map[StringName(str(ingredient))] = StringName(str(attr_key))
		if not map.is_empty():
			_augmenting_map[StringName(target_id)] = map
	
	
