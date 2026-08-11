extends TileMapLayer

@export var tile_map: TileMapLayer

@export_enum("Small", "medeam", "large") var map_size: int 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	tile_map.clear()
	
	var mane_size = Vector2i(randi_range(16,20), randi_range(12,16))
	if map_size == 1:
		mane_size = Vector2i(randi_range(20,26), randi_range(12,18))
	if map_size == 2:
		mane_size = Vector2i(randi_range(26,32), randi_range(18,24))
		
	#mane_size = Vector2i(10, 10)
		
	var walls  = draw_room(mane_size)
	var next_room = Vector2i(randi_range(mane_size[0]/2,(mane_size[0]/3)*2), randi_range(mane_size[1]/2,(mane_size[1]/3)*2))

	var good = []
	for x in range(mane_size[0]):
		for y in range(mane_size[1]):
			if test_pos(Vector2i(x, y), next_room, walls, mane_size):
				#tile_map.set_cell(Vector2i(x,y), 0, Vector2i(1,4))
				good.append([x,y])

	if good.size()>0:
		for wall in draw_room(next_room, good.pick_random()):
			walls.append(wall)


	for i in range(8):
	
		next_room = Vector2i(randi_range(mane_size[0]/(3+i),mane_size[0]/(2+i)), randi_range(mane_size[1]/(3+i), mane_size[1]/(2+i)))
		good = []
		if next_room[0]>4 and next_room[1]>4:
			for x in range(mane_size[0]):
				for y in range(mane_size[1]):
					if test_pos(Vector2i(x, y), next_room, walls, mane_size):
						#tile_map.set_cell(Vector2i(x,y), 0, Vector2i(5,3))
						good.append([x,y])
						
			if good.size()>0:
				for wall in draw_room(next_room, good.pick_random()):
					walls.append(wall)

				
				
func overLap(pos1, len1, pos2, len2):
	#print("pos1: ", pos1, " len1: ", len1, " pos2: ", pos2, " len2: ", len2)
	if pos1 <= pos2 and pos1+len1 >= pos2: return true
	if pos2 <= pos1 and pos2+len2 >= pos1: return true
	return false
	
	
func overLapWall(wall, pos, size):
	var totle = 0
	var wall_tiles = []
	for i in range(wall["len"]):
		if wall["der"][1] == 0:wall_tiles.append(wall["pos"]+Vector2i(i,0))
		else:wall_tiles.append(wall["pos"]+Vector2i(0,i))
	
	for x in range(size[0]+1):
		for y in range(size[1]+1):
			if Vector2i(x+pos[0], y+pos[1]) in wall_tiles: totle+=1

	return totle

func test_pos(pos, size, walls, mane_size):
	
	if pos[0]+size[0] > mane_size[0]:return false
	if pos[1]+size[1] > mane_size[1]:return false
	
	var overlap = 0
	for wall in walls:
		overlap += overLapWall(wall, pos, size)
		if wall["der"][1] == 0:#horisontal wall
			if overLap(wall["pos"][0], wall["len"], pos[0], size[0]):
				if wall["pos"][1]+1 == pos[1]: return false
				if wall["pos"][1]+2 == pos[1]: return false
				if wall["pos"][1]-1 == pos[1]: return false
				if wall["pos"][1]-2 == pos[1]: return false
				
				if wall["pos"][1]+1 == pos[1]+size[1]: return false
				if wall["pos"][1]+2 == pos[1]+size[1]: return false
				if wall["pos"][1]-1 == pos[1]+size[1]: return false
				if wall["pos"][1]-2 == pos[1]+size[1]: return false
				
		
		else:#virtical wall
			if overLap(wall["pos"][1], wall["len"], pos[1], size[1]):
				if wall["pos"][0]+1 == pos[0]: return false
				if wall["pos"][0]+2 == pos[0]: return false
				if wall["pos"][0]-1 == pos[0]: return false
				if wall["pos"][0]-2 == pos[0]: return false
				
				if wall["pos"][0]+1 == pos[0]+size[0]: return false
				if wall["pos"][0]+2 == pos[0]+size[0]: return false
				if wall["pos"][0]-1 == pos[0]+size[0]: return false
				if wall["pos"][0]-2 == pos[0]+size[0]: return false

				#if pos[1]+size[1] > wall["len"]:return false

	if overlap < 3: return false


	return true


func get_next(size, walls):
	var offset = [-1,-1]
	
	walls.shuffle()
	SweetLogger.debug("get_next size: {0}", [size])
	
	for wall in walls:
		SweetLogger.debug("get_next wall: {0}", [wall])
		if wall["der"][1] == 0:
			SweetLogger.debug("get_next horizontal wall", [])
			if size[0]<wall["len"]-6:
				SweetLogger.debug("TileMapLayer get_next length 6 less can go anywhere", [])
				if wall["der"][0] == 1:offset[1] = wall["pos"][1]
				else: offset[1] = wall["pos"][1]-size[1]
				
				offset[0] = randi_range(0, wall["len"]-size[0])
				if offset[0]>wall["pos"][0] and offset[0]<wall["pos"][0]+3:offset[0]=wall["pos"][0]+3
				if size[0]+offset[0]>wall["pos"][0]+wall["len"]-3:offset[0] = wall["len"]-(3+size[0])
				
			elif size[0]<=wall["len"]-3:
				SweetLogger.debug("TileMapLayer get_next 3 less needs to be on a corner", [])
				if wall["der"][0] == 1:offset[1] = wall["pos"][1]
				else: offset[1] = wall["pos"][1]-size[1]
				
				if randi_range(0, 1):offset[0]=wall["pos"][0]+wall["len"]-size[0]
				else:offset[0] = wall["pos"][0]
		else:
			SweetLogger.debug("get_next vertical wall", [])
			if size[1]<wall["len"]-6:
				SweetLogger.debug("TileMapLayer get_next length 6 less can go anywhere", [])
				if wall["der"][1] == 1:offset[0] = wall["pos"][0]
				else: offset[0] = wall["pos"][0]-size[0]
				
				offset[1] = randi_range(0, wall["len"]-size[1])
				if offset[1]>wall["pos"][1] and offset[1]<wall["pos"][1]+3:offset[1]=wall["pos"][1]+3
				if size[1]+offset[1]>wall["len"]-3:offset[1] = wall["len"]-(3+size[1])
				
			elif size[1]<=wall["len"]-3:
				SweetLogger.debug("TileMapLayer get_next 3 less needs to be on a corner", [])
				if wall["der"][1] == 1:offset[0] = wall["pos"][0]
				else: offset[0] = wall["pos"][0]-size[0]
				SweetLogger.debug("get_next offset: {0}", [offset])
				
				if randi() % 2:offset[1]=wall["pos"][1]+wall["len"]-size[1]
				else:offset[1] = wall["pos"][1]
			
				
		if offset[0] != -1:break
	
	return offset


func draw_room(Size, offset=Vector2i(0, 0)):
	var walls = []
	offset = Vector2i(offset[0], offset[1])
	SweetLogger.debug("draw_room size: {0} offset: {1}", [Size, offset])
	
	for i in range(Size[0]):
		tile_map.set_cell(Vector2i(i+offset[0],offset[1]), 0, Vector2i(1,1))
	walls.append({"pos": offset, "der":Vector2i(1, 0), "len":Size[0]})
	
	for i in range(Size[0]):
		tile_map.set_cell(Vector2i(i+offset[0],Size[1]+offset[1]), 0, Vector2i(1,1))
	walls.append({"pos": Vector2i(offset[0],Size[1]+offset[1]), "der":Vector2i(-1, 0), "len":Size[0]})
	
	for i in range(Size[1]):
		tile_map.set_cell(Vector2i(offset[0],i+offset[1]), 0, Vector2i(2,1))
	walls.append({"pos": offset, "der":Vector2i(0, 1), "len":Size[1]})
		
	for i in range(Size[1]):
		tile_map.set_cell(Vector2i(Size[0]+offset[0],i+offset[1]), 0, Vector2i(2,1))
	walls.append({"pos": Vector2i(Size[0]+offset[0],offset[1]), "der":Vector2i(0, -1), "len":Size[1]})
	
	for x in range(Size[0]-1):
		for y in range(Size[1]-1):
			tile_map.erase_cell(Vector2i(x+1+offset[0],y+1+offset[1]))

		
		

	tile_map.set_cell(Vector2i(offset[0],offset[1]), 0, Vector2i(5,1))
	tile_map.set_cell(Vector2i(Size[0]+offset[0],offset[1]), 0, Vector2i(6,1))
	tile_map.set_cell(Vector2i(offset[0],Size[1]+offset[1]), 0, Vector2i(4,1))
	tile_map.set_cell(Vector2i(Size[0]+offset[0],Size[1]+offset[1]), 0, Vector2i(3,1))
	return walls
		


func set_room(tile_pos, size, pos):
	for x in size[0]:
		for y in size[1]:
			tile_map.set_cell(Vector2i(x+pos[0],y+pos[1]), 0, tile_pos)
			
		
		
