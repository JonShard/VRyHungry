extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	SweetLogger.debug("stations: {0}", [get_stations()], "testworldLoad.gd", "_ready")
	SweetLogger.debug("items: {0}", [get_items()], "testworldLoad.gd", "_ready")



func get_node_data(node):
	#		{"scene": "res://Stations/Hob.tscn", "name": "Hob",
	#		"xform": Transform3D(Basis(), Vector3(0.29336345, 0.8981018, -1.484)), "props": {}},
	var data = {}
	data["scene"] = node.scene_file_path
	data["name"] = node.name
	data["xform"] = node.transform
	data["props"] = {}
	var scrip = node.get_script()
	if scrip:
		for i in scrip.get_script_property_list():
			if i.usage & PROPERTY_USAGE_STORAGE:
				data["props"][i["name"]] = node.get(i["name"])
	return data


func get_stations() -> Array[Dictionary]:
	var Stations = ResourceLoader.list_directory("res://Stations/")

	var Stations2 = []
	for i in Stations:
		Stations2.append("res://Stations/" + i)
	Stations = Stations2
	
	var Stations_nodes = []
	for i in get_tree().root.find_children("*", "StaticBody3D", true, false):
			if i.scene_file_path in Stations:
				Stations_nodes.append(i)

	var data: Array[Dictionary] = []
	for i in Stations_nodes:
		data.append(get_node_data(i))
	return data
	
	
func get_items() -> Array[Dictionary]:
	var Items = ResourceLoader.list_directory("res://Items/")

	var Items2 = []
	for i in Items:
		Items2.append("res://Items/" + i)
	Items = Items2
	
	var Items_nodes = []
	for i in get_tree().root.find_children("*", "XRToolsPickable", true, false):
			if i.scene_file_path in Items:
				Items_nodes.append(i)
	
	var data: Array[Dictionary] = []
	for i in Items_nodes:
		data.append(get_node_data(i))
	return data
