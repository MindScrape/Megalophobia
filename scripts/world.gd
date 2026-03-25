extends Node3D

const CHUNK = preload("res://scenes/chunk.tscn")
const PLAYER = preload("res://scenes/player.tscn")
const CHUNK_STREAMER = preload("res://scripts/chunk_streamer.gd")
const CHUNK_STORE = preload("res://scripts/chunk_store.gd")
const DEBUG_HUD = preload("res://scripts/debug_hud.gd")

var chunk_store: ChunkStore = null							# I/O storage for chunk load/save and player edit persistence
var _streamer: ChunkStreamer = null
var chunks: Dictionary[Vector2i, Chunk] = {}				# (chunk-coord -> Chunk) All chunks currently in the game world, keyed by their chunk coordinates (Vector2i)
var _dirty_chunks: Dictionary[Vector2i, Chunk] = {}			# (chunk-coord -> Chunk) Background seam-repair rebuilds
var _priority_chunks: Dictionary[Vector2i, Chunk] = {}		# (chunk-coord -> Chunk) Player block edits — dispatched before background rebuilds and immediately on rebuild completion
var _rebuilding_chunks: Dictionary[Vector2i, bool] = {}		# (chunk-coord -> bool)  Chunks with an active worker — prevents double-dispatch of the same coord
var _in_flight_count: int = 0								# Background workers only — priority tasks bypass this count intentionally
var player: CharacterBody3D = null
var terrain_generator := TerrainGenerator.new()

@export var rebuild_interval: float = 0.01
@export var max_concurrent_rebuilds: int = 8	# Hard cap on the number of background threads for rebuilding the chunks

func _ready() -> void:
	chunk_store = CHUNK_STORE.new()
	print("Spawning World")
	print("Chunk dimensions (x=%d, y=%d, z=%d)" % [
		VoxelConstants.CHUNK_SIZE.x,
		VoxelConstants.CHUNK_SIZE.y,
		VoxelConstants.CHUNK_SIZE.z,
	])

	# Start the dirty-chunk rebuild timer
	var timer := Timer.new()
	timer.wait_time = rebuild_interval
	timer.autostart = true
	timer.timeout.connect(_rebuild_dirty_chunks)
	add_child(timer)

	# Spawn player first so the streamer has a valid position on its first _process tick
	spawn_player(0, 0)

	# Start the chunk streamer — loads/unloads chunks around the player each frame
	_streamer = CHUNK_STREAMER.new()
	_streamer.initialize(self)
	add_child(_streamer)

	var hud := DEBUG_HUD.new()
	hud.initialize(self)
	add_child(hud)


func spawn_player(spawn_x: int, spawn_z: int) -> void:
	print("Spawning player at (%d, %d)" % [spawn_x, spawn_z])
	player = PLAYER.instantiate()
	player.initialize(self)
	add_child(player)
	var surface_y = terrain_generator.get_surface_height(spawn_x, spawn_z)
	player.global_position = Vector3(spawn_x, surface_y + 3, spawn_z)


func spawn_chunk(coord: Vector2i) -> void:
	if chunks.has(coord):
		return
	var chunk_instance: Chunk = CHUNK.instantiate()
	chunk_instance.initialize(coord, self, terrain_generator)
	if chunk_store.has_data(coord):
		chunk_instance._pending_delta = chunk_store.get_delta(coord)
	var world_x := coord.x * VoxelConstants.CHUNK_SIZE.x
	var world_z := coord.y * VoxelConstants.CHUNK_SIZE.z
	chunk_instance.position = Vector3(world_x, 0, world_z)

	chunks[coord] = chunk_instance
	add_child(chunk_instance)


# Trigger async mesh generation for a freshly spawned chunk, and dirty its
# neighbors so seams caused by the new chunk's voxels are removed.
func mark_chunk_for_mesh(coord: Vector2i) -> void:
	var chunk := get_chunk(coord)
	if chunk == null:
		return
	if _rebuilding_chunks.has(coord) or _in_flight_count >= max_concurrent_rebuilds:
		_dirty_chunks[coord] = chunk
		return
	_rebuilding_chunks[coord] = true
	_in_flight_count += 1
	chunk.generate_mesh_async(func():
		_on_chunk_rebuilt(coord)
		_dirty_neighbor_chunks(coord)
	)


# Dispatch a background (seam-repair) rebuild through WorkerThreadPool.
# Returns false if the coord is already rebuilding or the concurrent cap is reached.
func _try_dispatch(coord: Vector2i, chunk: Chunk) -> bool:
	if _rebuilding_chunks.has(coord):
		return false
	if _in_flight_count >= max_concurrent_rebuilds:
		return false
	_rebuilding_chunks[coord] = true
	_in_flight_count += 1
	chunk.generate_mesh_async(func(): _on_chunk_rebuilt(coord))
	return true


# Dispatch a player-edit rebuild via WorkerThreadPool with high_priority=true.
# Bypasses the concurrent rebuild cap so player edits are never queued behind background work.
# Rate-limited naturally by _rebuilding_chunks — the same coord can't be double-dispatched.
# Returns false only if the coord is already rebuilding.
func _dispatch_priority(coord: Vector2i, chunk: Chunk) -> bool:
	if _rebuilding_chunks.has(coord):
		return false
	_rebuilding_chunks[coord] = true
	chunk.generate_mesh_async(func(): _on_priority_rebuilt(coord), true)
	return true


func unload_chunk(coord: Vector2i) -> void:
	if _rebuilding_chunks.has(coord):
		return  # worker thread still holds a ref; will retry on next player-chunk-change
	var chunk := get_chunk(coord)
	if chunk == null:
		return
	chunks.erase(coord)
	_dirty_chunks.erase(coord)
	_priority_chunks.erase(coord)
	chunk_store.flush(coord)
	chunk.queue_free()
	_dirty_neighbor_chunks(coord)  # neighbors now have exposed faces that need rebuilding


func _dirty_neighbor_chunks(coord: Vector2i) -> void:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor := get_chunk(coord + offset)
		if neighbor != null:
			_dirty_chunks[coord + offset] = neighbor


func set_block(chunk_coord: Vector2i, local_pos: Vector3i, block_id: int) -> void:
	var chunk = get_chunk(chunk_coord)
	if chunk == null:
		return
	chunk.set_voxel_safe(local_pos.x, local_pos.y, local_pos.z, block_id)
	chunk_store.record_edit(chunk_coord, chunk._voxel_index(local_pos.x, local_pos.y, local_pos.z), block_id)
	_priority_chunks[chunk_coord] = chunk

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
	var player_chunk = player.get_player_chunk_coord()

	# Priority pass: player block edits — dedicated OS thread, independent of WorkerThreadPool cap
	var priority_to_dispatch := _priority_chunks.duplicate()
	_priority_chunks.clear()
	for coord in priority_to_dispatch:
		if not _dispatch_priority(coord, priority_to_dispatch[coord]):
			_priority_chunks[coord] = priority_to_dispatch[coord]

	# Background pass: seam repairs, sorted nearest-first
	var to_dispatch := _dirty_chunks.duplicate()
	_dirty_chunks.clear()
	var coords := to_dispatch.keys()
	coords.sort_custom(func(a, b):
		return a.distance_squared_to(player_chunk) < b.distance_squared_to(player_chunk)
	)
	for coord in coords:
		if not _try_dispatch(coord, to_dispatch[coord]):
			_dirty_chunks[coord] = to_dispatch[coord]


func _on_chunk_rebuilt(coord: Vector2i) -> void:
	_rebuilding_chunks.erase(coord)
	_in_flight_count -= 1
	# Slot just opened — immediately dispatch any waiting priority edit for this coord
	if _priority_chunks.has(coord):
		var chunk: Chunk = _priority_chunks[coord]
		_priority_chunks.erase(coord)
		_dispatch_priority(coord, chunk)


func _on_priority_rebuilt(coord: Vector2i) -> void:
	_rebuilding_chunks.erase(coord)
	# If another edit landed while we were rebuilding, dispatch it immediately
	if _priority_chunks.has(coord):
		var chunk: Chunk = _priority_chunks[coord]
		_priority_chunks.erase(coord)
		_dispatch_priority(coord, chunk)


func world_to_chunk(pos: Vector3) -> Vector2i:
	var cx := floori(pos.x / VoxelConstants.CHUNK_SIZE.x)
	var cz := floori(pos.z / VoxelConstants.CHUNK_SIZE.z)
	return Vector2i(cx, cz)

func world_to_local(pos: Vector3) -> Vector3i:
	var lx := posmod(floori(pos.x), VoxelConstants.CHUNK_SIZE.x)
	var lz := posmod(floori(pos.z), VoxelConstants.CHUNK_SIZE.z)
	return Vector3i(lx, int(pos.y), lz)

func _exit_tree() -> void:
	chunk_store.flush_all()


func get_chunk(coord: Vector2i) -> Chunk:
	if chunks.has(coord):
		return chunks[coord]
	return null
