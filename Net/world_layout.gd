class_name WorldLayout

## Data-driven description of what's in the multiplayer world. The server (or
## the single machine, when offline) spawns every entry through
## NetworkManager.spawn_item() instead of baking these into the scene file, so
## a joining client receives them from the server rather than assuming its own
## copy of the scene matches. Swapping the contents of these two functions is
## the only change needed for a future varying/procedural layout.
##
## Positions below are transcribed verbatim from the previous baked layout in
## Scenes/multiPlayer.tscn so the starting world is unchanged.

static func get_stations() -> Array[Dictionary]:
	return [
		{"scene": "res://Stations/Hob.tscn", "name": "Hob",
			"xform": Transform3D(Basis(), Vector3(0.29336345, 0.8981018, -1.484)), "props": {}},
		{"scene": "res://Stations/BurgerBunsDispenser.tscn", "name": "BurgerBunsDispenser",
			"xform": Transform3D(Basis(), Vector3(-1.832131, 0.40028095, -1.4813508)), "props": {}},
		{"scene": "res://Stations/sink.tscn", "name": "Sink",
			"xform": Transform3D(Basis(), Vector3(1.3140475, 0.9061539, -1.4941733)), "props": {}},
		{"scene": "res://Stations/dirt_station.tscn", "name": "DirtStation",
			"xform": Transform3D(Basis(), Vector3(2.0864775, 0.8981018, -1.244947)), "props": {}},
		{"scene": "res://Stations/Counter.tscn", "name": "Counter",
			"xform": Transform3D(Basis(), Vector3(-0.7124918, 0.90304357, -1.4886917)), "props": {}},
		{"scene": "res://Stations/Counter.tscn", "name": "Counter2",
			"xform": Transform3D(Vector3(-4.371139e-08, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, -4.371139e-08), Vector3(-1.7648025, 0.90304357, -0.4458799)), "props": {}},
		{"scene": "res://Stations/Counter.tscn", "name": "Counter3",
			"xform": Transform3D(Vector3(-4.371139e-08, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, -4.371139e-08), Vector3(-1.7648025, 0.90304357, 0.55367994)), "props": {}},
		{"scene": "res://Stations/Counter.tscn", "name": "Counter4",
			"xform": Transform3D(Vector3(-4.371139e-08, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, -4.371139e-08), Vector3(-1.7648025, 0.90304357, 1.5539298)), "props": {}},
		{"scene": "res://Stations/table.tscn", "name": "Table",
			"xform": Transform3D(Basis(), Vector3(1.633146, 0.9030438, 1.1343781)),
			"props": {
				"initial_thinking_time": 8.0,
				"initial_primary_time": 40.0,
				"initial_friend_time": 3.0,
				"initial_eating_time": 3.0,
			}},
	]


static func get_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []

	items.append(_item("res://Items/BurgerBuns.tscn", "BurgerBuns", Vector3(-1.8162017, 1.6081157, -1.4714175)))
	items.append(_item("res://Items/BurgerBuns.tscn", "BurgerBuns2", Vector3(-1.3596323, 1.4110342, -0.22482127)))

	items.append(_item("res://Containers/plate.tscn", "Plate", Vector3(-1.5717233, 1.5454081, 1.5373346)))
	items.append(_item("res://Containers/plate.tscn", "Plate2", Vector3(-1.5730225, 1.499024, 0.59790254)))
	items.append(_item("res://Containers/plate.tscn", "Plate3", Vector3(-1.5818124, 1.499024, -0.4634577)))

	items.append(_item("res://Items/burger.tscn", "burger", Vector3(0.6888188, 1.4195822, -1.7110313)))
	items.append(_item("res://Items/burger.tscn", "burger2", Vector3(0.6931299, 1.5300478, -1.71225)))
	items.append(_item("res://Items/burger.tscn", "burger3", Vector3(0.69027674, 1.4969791, -1.7210286)))
	items.append(_item("res://Items/burger.tscn", "burger4", Vector3(0.69134104, 1.4543622, -1.7210286)))

	items.append(_item("res://Items/hamburger.tscn", "Hamburger", Vector3(-1.9352558, 1.623975, 1.2447833)))
	items.append(_item("res://Items/hamburger.tscn", "Hamburger2", Vector3(-1.9857153, 1.5329368, 0.9472374)))
	items.append(_item("res://Items/hamburger.tscn", "Hamburger3", Vector3(-1.7201865, 1.5329367, 0.14773655)))

	items.append(_item("res://Items/cooked_burger.tscn", "CookedBurger", Vector3(-0.30671906, 1.4131018, -1.0928738)))
	items.append(_item("res://Items/cooked_burger.tscn", "CookedBurger2", Vector3(-0.30671906, 1.4496142, -1.0928738)))
	items.append(_item("res://Items/cooked_burger.tscn", "CookedBurger3", Vector3(-1.3344773, 1.4398065, -0.7096845)))
	items.append(_item("res://Items/cooked_burger.tscn", "CookedBurger4", Vector3(-0.30671906, 1.525444, -1.0928738)))

	items.append(_item("res://Items/PickupCube.tscn", "PickableObject", Vector3(0.6225724, 1.4792972, -1.0473135)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject2", Vector3(0.6359743, 1.4639391, -1.1673055)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject3", Vector3(0.5142721, 1.4792972, -1.0473135)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject4", Vector3(0.5276739, 1.4639391, -1.1673055)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject5", Vector3(0.73287535, 1.4792972, -1.0473135)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject6", Vector3(0.7462772, 1.4639391, -1.1673055)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject7", Vector3(-1.3556751, 1.4792972, 0.28881657)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject8", Vector3(-1.3422732, 1.4639391, 0.16882455)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject9", Vector3(-1.4639754, 1.4792972, 0.28881657)))
	items.append(_item("res://Items/PickupCube.tscn", "PickableObject10", Vector3(-1.4505737, 1.4639391, 0.16882455)))

	return items


static func _item(scene: String, name: String, pos: Vector3) -> Dictionary:
	return {"scene": scene, "name": name, "xform": Transform3D(Basis(), pos), "props": {}}
