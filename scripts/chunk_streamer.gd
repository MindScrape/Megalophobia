extends Node
class_name ChunkStreamer

@export var render_distance: int = 10	# The radius (in chunks) around the player within which chunks should be loaded
@export var unload_buffer: int = 2		# Prevents chunks from loading when player steps past the boundary
@export var chunks_per_frame: int = 1	# Number of chunks allowed to spawn per frame to prevent lag spikes
@export var unloads_per_frame: int = 2	# Number of chunks allowed to unload per frame to prevent lag spikes

var _world: Node = null
var _last_player_chunk := Vector2i(999999, 999999)	# XZ only — Y levels are always fully loaded per column
var _load_queue: Array[Vector3i] = []
var _unload_queue: Array[Vector3i] = []

func initialize(world_node: Node) -> void:
	_world = world_node

func _process(_delta: float) -> void:
	if _world == null or _world.player == null:
		return

	var player_chunk: Vector2i = _world.player.get_player_chunk_coord()
	if player_chunk != _last_player_chunk:
		_last_player_chunk = player_chunk
		_rebuild_load_queue(player_chunk)
		_unload_distant_chunks(player_chunk)

	# Drain load queue: spawn up to chunks_per_frame new chunks per frame
	var spawned := 0
	while _load_queue.size() > 0 and spawned < chunks_per_frame:
		var coord: Vector3i = _load_queue.pop_front()
		if not _world.chunks.has(coord):
			_world.spawn_chunk(coord)
			_world.mark_chunk_for_mesh(coord)
		spawned += 1

	# Drain unload queue: free up to unloads_per_frame chunks per frame
	var unloaded := 0
	while _unload_queue.size() > 0 and unloaded < unloads_per_frame:
		var coord: Vector3i = _unload_queue.pop_front()
		if _world.chunks.has(coord):
			_world.unload_chunk(coord)
		unloaded += 1

func _rebuild_load_queue(player_chunk: Vector2i) -> void:
	_load_queue.clear()
	var r := render_distance
	for x in range(player_chunk.x - r, player_chunk.x + r + 1):
		for z in range(player_chunk.y - r, player_chunk.y + r + 1):
			var xz := Vector2i(x, z)
			if xz.distance_squared_to(player_chunk) > r * r:
				continue
			for cy in range(VoxelConstants.NUM_Y_CHUNKS):
				var coord := Vector3i(x, cy, z)
				if not _world.chunks.has(coord):
					_load_queue.append(coord)
	_load_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return Vector2i(a.x, a.z).distance_squared_to(player_chunk) \
			 < Vector2i(b.x, b.z).distance_squared_to(player_chunk)
	)

func _unload_distant_chunks(player_chunk: Vector2i) -> void:
	var unload_r_sq := (render_distance + unload_buffer) * (render_distance + unload_buffer)
	for coord in _world.chunks.keys():
		if Vector2i(coord.x, coord.z).distance_squared_to(player_chunk) > unload_r_sq:
			if not _unload_queue.has(coord):
				_unload_queue.append(coord)
