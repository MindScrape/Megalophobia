# Deterministic evidence fixtures. Run from the project root with:
# Godot --headless --path . --script docs/case-study/measure.gd
extends SceneTree

const OUTPUT := "res://docs/case-study/measurements.json"
const CHUNK_SCENE := preload("res://scenes/chunk.tscn")
const OBSERVED := preload("res://docs/case-study/observed_chunk.gd")
const STORE_FIXTURE := preload("res://docs/case-study/storage_fixture.gd")
const OFFSETS := [Vector3i(1,0,0),Vector3i(-1,0,0),Vector3i(0,1,0),Vector3i(0,-1,0),Vector3i(0,0,1),Vector3i(0,0,-1)]

class FixturePlayer extends CharacterBody3D:
	var coord := Vector3i(0, mini(5,VoxelConstants.NUM_Y_CHUNKS-1), 0)
	var vertical_chunks := FileAccess.get_file_as_string("res://scripts/player.gd").contains("func get_player_chunk_coord() -> Vector3i:")
	func get_player_chunk_coord():
		return coord if vertical_chunks else Vector2i(coord.x,coord.z)

class SchedulerWorld extends Node:
	var player := FixturePlayer.new()
	var chunks: Dictionary = {}
	var spawn_attempts := 0
	var unload_attempts := 0
	func spawn_chunk(coord: Vector3i) -> void:
		spawn_attempts += 1
		chunks[coord] = true
	func mark_chunk_for_mesh(_coord: Vector3i) -> void:
		pass
	func unload_chunk(coord: Vector3i) -> void:
		unload_attempts += 1
		chunks.erase(coord)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("/private/tmp/megalophobia-case-study")
	var results := {
		"godot": Engine.get_version_info().string,
		"cpu": OS.get_processor_name(),
		"debug_build": OS.is_debug_build(),
		"scope": "Controlled fixtures against the current working tree; not a gameplay FPS benchmark.",
	}
	results["streaming"] = _streaming()
	print("Measured streaming scheduler")
	results["meshing"] = _meshing()
	print("Measured greedy meshing")
	results["persistence"] = _persistence()
	print("Measured storage round trip")
	results["concurrency"] = await _concurrency()
	print("Measured revision guard")
	var a := PackedInt32Array([1])
	var b := a
	b[0] = 9
	results["packed_array_assignment_probe"] = {"original_after_alias_write": a[0]}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t") + "\n")
	file.close()
	print("CASE_STUDY_RESULTS " + JSON.stringify(results))
	await process_frame
	quit()

func _streaming() -> Dictionary:
	var world := SchedulerWorld.new()
	var streamer := ChunkStreamer.new()
	streamer.render_distance = 4
	streamer.initialize(world)
	var samples: Array = []
	var maximum_spawns := 0
	var maximum_unloads := 0
	for frame in range(620):
		if frame == 300:
			world.player.coord.x = 8
		world.spawn_attempts = 0
		world.unload_attempts = 0
		streamer._process(1.0 / 60.0)
		maximum_spawns = maxi(maximum_spawns, world.spawn_attempts)
		maximum_unloads = maxi(maximum_unloads, world.unload_attempts)
		assert(world.spawn_attempts <= 1)
		assert(world.unload_attempts <= 2)
		if frame in [0, 63, 256, 299, 300, 363, 619]:
			var coords: Array = []
			for coord in world.chunks:
				coords.append([coord.x, coord.y, coord.z])
			samples.append({"frame":frame + 1,"loaded":world.chunks.size(),"load_queue":streamer._load_queue.size(),"unload_queue":streamer._unload_queue.size(),"coords":coords})
	var result := {"radius_chunks":4,"unload_buffer":2,"frames":620,"move_at_frame":301,"move_from":[0,world.player.coord.y,0],"move_to":[8,world.player.coord.y,0],"coordinate_mode":"xyz_sphere" if world.player.vertical_chunks else "xz_columns","max_spawn_attempts_per_tick":maximum_spawns,"max_unload_attempts_per_tick":maximum_unloads,"samples":samples,"scope":"Scheduler methods called manually; fake world records requests without generating terrain or meshes."}
	streamer.free()
	world.player.free()
	world.free()
	return result

func _mesh_arrays(chunk: Chunk, data: PackedInt32Array) -> Dictionary:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var colors: Array[Color] = []
	for axis in range(3):
		chunk._greedy_axis_snap(axis, data, {}, vertices, normals, uvs, colors)
	return {"triangles":vertices.size() / 3,"quads":vertices.size() / 6}

func _exposed_faces(chunk: Chunk, data: PackedInt32Array) -> int:
	var count := 0
	for y in range(16):
		for z in range(16):
			for x in range(16):
				if data[chunk._voxel_index(x,y,z)] == VoxelBlocks.AIR:
					continue
				for offset in OFFSETS:
					var p: Vector3i = Vector3i(x,y,z) + offset
					if p.x < 0 or p.y < 0 or p.z < 0 or p.x >= 16 or p.y >= 16 or p.z >= 16 or data[chunk._voxel_index(p.x,p.y,p.z)] == VoxelBlocks.AIR:
						count += 1
	return count

func _meshing() -> Dictionary:
	var chunk := Chunk.new()
	var solid := PackedInt32Array()
	solid.resize(4096)
	solid.fill(VoxelBlocks.STONE)
	var solid_mesh := _mesh_arrays(chunk, solid)
	assert(solid_mesh.quads == 6)
	var generator := TerrainGenerator.new()
	var sample_coord := Vector3i(-1,floori(generator.get_surface_height(-8,8)/16.0),0)
	var terrain := chunk._generate_voxels_pure(sample_coord, generator)
	var terrain_mesh := _mesh_arrays(chunk, terrain)
	var samples: Array[float] = []
	for i in range(33):
		var before := Time.get_ticks_usec()
		_mesh_arrays(chunk, terrain)
		var milliseconds := (Time.get_ticks_usec() - before) / 1000.0
		if i >= 3:
			samples.append(milliseconds)
	samples.sort()
	var result := {"solid":{"blocks":4096,"exposed_unit_faces":_exposed_faces(chunk,solid),"greedy_quads":solid_mesh.quads,"greedy_triangles":solid_mesh.triangles},"terrain":{"chunk_coord":[sample_coord.x,sample_coord.y,sample_coord.z],"exposed_unit_faces":_exposed_faces(chunk,terrain),"greedy_quads":terrain_mesh.quads,"greedy_triangles":terrain_mesh.triangles,"runs":30,"warmup_runs":3,"greedy_cpu_median_ms":(samples[14]+samples[15])/2.0,"greedy_cpu_p95_ms":samples[28],"scope":"Only the three greedy axis passes and their output arrays; excludes generation, ArrayMesh upload, collision, and rendering. Missing neighbors treated as air."}}
	chunk.free()
	return result

func _persistence() -> Dictionary:
	var chunk := Chunk.new()
	var generator := TerrainGenerator.new()
	var coord := Vector3i(0,floori(generator.get_surface_height(5,8)/16.0),0)
	var original := chunk._generate_voxels_pure(coord,generator)
	var edited := original.duplicate()
	var store = STORE_FIXTURE.new()
	var edits: Array = []
	for x in [5,8,11]:
		var z := 8
		var surface_y := generator.get_surface_height(x,z) - coord.y*16
		assert(surface_y >= 0 and surface_y < 16)
		var index := chunk._voxel_index(x,surface_y,z)
		edited[index] = VoxelBlocks.STONE
		store.record_edit(coord,index,VoxelBlocks.STONE)
		edits.append([x,surface_y,z])
	# Explicitly exercise helpers: normal debug flush intentionally does not write.
	store._save_to_disk(coord,store.get_delta(coord))
	var fresh_store = STORE_FIXTURE.new()
	var loaded_delta: Dictionary = fresh_store._load_from_disk(coord)
	var regenerated := chunk._generate_voxels_pure(coord,generator)
	for index in loaded_delta:
		regenerated[index] = loaded_delta[index]
	assert(regenerated == edited)
	var delta_file := FileAccess.open(store._get_path(coord),FileAccess.READ)
	var delta_bytes := delta_file.get_length()
	delta_file.close()
	var full_path := "/private/tmp/megalophobia-case-study/full_chunk.dat"
	var full_file := FileAccess.open(full_path,FileAccess.WRITE)
	full_file.store_var(edited)
	full_file.close()
	full_file = FileAccess.open(full_path,FileAccess.READ)
	var full_bytes := full_file.get_length()
	full_file.close()
	var result := {"edits":loaded_delta.size(),"edit_local_positions":edits,"chunk_coord":[coord.x,coord.y,coord.z],"delta_file_bytes":delta_bytes,"full_chunk_variant_bytes":full_bytes,"identical_after_regeneration_and_replay":regenerated == edited,"scope":"Three-edit fixture; real storage helpers invoked directly with temporary paths. Debug gameplay disk saving remains disabled."}
	chunk.free()
	return result

func _concurrency() -> Dictionary:
	var world = load("res://scripts/world.gd").new()
	world.player = FixturePlayer.new()
	world.chunk_store = ChunkStore.new()
	var chunk = CHUNK_SCENE.instantiate()
	chunk.set_script(OBSERVED)
	chunk.initialize(Vector3i.ZERO,world,TerrainGenerator.new())
	chunk.voxels.resize(4096)
	chunk.voxels.fill(VoxelBlocks.STONE)
	world.chunks[Vector3i.ZERO] = chunk
	root.add_child(chunk)
	await process_frame
	# Represent an active request without relying on nondeterministic worker timing.
	world._rebuilding_chunks[Vector3i.ZERO] = true
	var duplicate_accepted: bool = world._dispatch_priority(Vector3i.ZERO,chunk)
	assert(not duplicate_accepted)
	for x in [5,8,11]:
		world.set_block(Vector3i.ZERO,Vector3i(x,15,8),VoxelBlocks.AIR)
	var queued_requests: int = world._priority_chunks.size()
	assert(queued_requests == 1)
	var sentinel := ArrayMesh.new()
	var stale := ArrayMesh.new()
	var fresh := ArrayMesh.new()
	chunk.cube_mesh = sentinel
	chunk._apply_mesh_data(stale,null,Callable(),PackedInt32Array(),0)
	assert(chunk.cube_mesh == sentinel)
	chunk._apply_mesh_data(fresh,null,Callable(),PackedInt32Array(),3)
	assert(chunk.cube_mesh == fresh)
	assert(chunk.observations[0].rejected)
	assert(not chunk.observations[1].rejected)
	var result := {"edits_while_request_marked_active":3,"coalesced_queue_entries":queued_requests,"duplicate_dispatch_accepted":duplicate_accepted,"observations":chunk.observations.duplicate(true),"final_revision":chunk._voxel_revision,"scope":"Deterministic completion injection into the real apply method. Active-task map seeded to exercise the duplicate-dispatch guard; no worker scheduling or general race-safety claim."}
	root.remove_child(chunk)
	chunk.free()
	world.chunks.clear()
	world.player.free()
	world.free()
	return result
