@tool
extends Node3D

const CHUNK = preload("res://scenes/chunk.tscn")
const PLAYER = preload("res://scenes/player.tscn")

var chunks: Dictionary = {}
var player: CharacterBody3D = null
var terrain_generator := TerrainGenerator.new()

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
	
	# Spawn the player in
	spawn_player(8, 8)


func spawn_player(spawn_x: int, spawn_z: int) -> void:
	player = PLAYER.instantiate()
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
