@tool
extends Node3D

const CHUNK = preload("res://scenes/chunk.tscn")
const PLAYER = preload("res://scenes/player.tscn")

var chunks: Dictionary[Vector2i, Chunk] = {}				# (chunk-coord -> Chunk) All chunks currently in the game world, keyed by their chunk coordinates (Vector2i)
var _dirty_chunks: Dictionary[Vector2i, Chunk] = {}			# (chunk-coord -> Chunk) A batch of chunks that the player has modified in realtime and need to be redrawn asynchronously
var _rebuilding_chunks: Dictionary[Vector2i, bool] = {}		# (chunk-coord -> bool)  A batch of chunks that we're actively redrawing asynchronously onto the player's screen
var player: CharacterBody3D = null
var terrain_generator := TerrainGenerator.new()

@export var rebuild_interval: float = 0.01

func _ready() -> void:
	print("Spawning World")
	var chunk_debug = "Spawning chunks with dimensions (x=%d, y=%d, z=%d)" % [
		VoxelConstants.CHUNK_SIZE.x,
		VoxelConstants.CHUNK_SIZE.y,
		VoxelConstants.CHUNK_SIZE.z
	]
	print(chunk_debug)
	spawn_world()

func spawn_world():
	# Pass 1: create chunks and voxel data
	for x in range(8):
		for z in range(8):
			var coord := Vector2i(x, z)
			spawn_chunk(coord)

	# Pass 2: build meshes after all chunks exist
	for chunk in chunks.values():
		print("Generating mesh at chunk: %s" % chunk.chunk_coord)
		chunk.generate_mesh()
	
	# Start the dirty-chunk rebuild timer
	var timer := Timer.new()
	timer.wait_time = rebuild_interval
	timer.autostart = true
	timer.timeout.connect(_rebuild_dirty_chunks)
	add_child(timer)

	# Spawn the player in
	spawn_player(8, 8)


func spawn_player(spawn_x: int, spawn_z: int) -> void:
	player = PLAYER.instantiate()
	player.initialize(self)
	add_child(player)
	var surface_y = terrain_generator.get_surface_height(spawn_x, spawn_z)
	player.global_position = Vector3(spawn_x, surface_y + 3, spawn_z)
	

func spawn_chunk(coord: Vector2i):
	if chunks.has(coord):
		return

	var chunk_instance: Chunk = CHUNK.instantiate()
	chunk_instance.initialize(coord, self, terrain_generator)
	var world_x := coord.x * VoxelConstants.CHUNK_SIZE.x
	var world_z := coord.y * VoxelConstants.CHUNK_SIZE.z
	chunk_instance.position = Vector3(world_x, 0, world_z)

	chunks[coord] = chunk_instance
	add_child(chunk_instance)

func set_block(chunk_coord: Vector2i, local_pos: Vector3i, block_id: int) -> void:
	var chunk = get_chunk(chunk_coord)
	if chunk == null:
		return
	chunk.set_voxel_safe(local_pos.x, local_pos.y, local_pos.z, block_id)
	_dirty_chunks[chunk_coord] = chunk

	var border_checks = [
		[Vector2i(1, 0),  local_pos.x == VoxelConstants.CHUNK_SIZE.x - 1],
		[Vector2i(-1, 0), local_pos.x == 0],
		[Vector2i(0, 1),  local_pos.z == VoxelConstants.CHUNK_SIZE.z - 1],
		[Vector2i(0, -1), local_pos.z == 0],
	]
	for check in border_checks:
		if check[1]:
			var neighbor = get_chunk(chunk_coord + check[0])
			if neighbor:
				_dirty_chunks[chunk_coord + check[0]] = neighbor


func _rebuild_dirty_chunks() -> void:
	var to_dispatch := _dirty_chunks.duplicate()
	_dirty_chunks.clear()
	for coord in to_dispatch:
		if _rebuilding_chunks.has(coord):
			# Worker still actively rebuilding the chunk. Re-queue for next tick
			_dirty_chunks[coord] = to_dispatch[coord]
			continue
		# Mark the current chunk as being actively rebuilt to prevent multiple workers from picking it up simultaneously
		_rebuilding_chunks[coord] = true
		var chunk: Chunk = to_dispatch[coord]
		chunk.generate_mesh_async(func(): _on_chunk_rebuilt(coord))

func _on_chunk_rebuilt(coord: Vector2i) -> void:
	_rebuilding_chunks.erase(coord)

func update_neighbors(coord):
	var dirs = [
		Vector2i(1,0),
		Vector2i(-1,0),
		Vector2i(0,1),
		Vector2i(0,-1)
	]
	for d in dirs:
		var neighbor = get_chunk(coord + d)
		if neighbor:
			neighbor.generate_mesh()

func world_to_chunk(pos: Vector3) -> Vector2i:
	var cx := floori(pos.x / VoxelConstants.CHUNK_SIZE.x)
	var cz := floori(pos.z / VoxelConstants.CHUNK_SIZE.z)
	return Vector2i(cx, cz)

func world_to_local(pos: Vector3) -> Vector3i:
	var lx := posmod(int(pos.x), VoxelConstants.CHUNK_SIZE.x)
	var lz := posmod(int(pos.z), VoxelConstants.CHUNK_SIZE.z)
	return Vector3i(lx, int(pos.y), lz)

func get_chunk(coord: Vector2i):
	if chunks.has(coord):
		return chunks[coord]
	return null
