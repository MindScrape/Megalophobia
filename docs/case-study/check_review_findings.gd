extends SceneTree

class FixturePlayer extends CharacterBody3D:
	func get_player_chunk_coord():
		var vertical := FileAccess.get_file_as_string("res://scripts/player.gd").contains("func get_player_chunk_coord() -> Vector3i:")
		return Vector3i(0,mini(5,VoxelConstants.NUM_Y_CHUNKS-1),0) if vertical else Vector2i.ZERO

class BusyWorld extends Node:
	var player := FixturePlayer.new()
	var chunks: Dictionary = {Vector3i(5,5,0):true}
	var busy := true
	func spawn_chunk(coord: Vector3i) -> void:
		chunks[coord] = true
	func mark_chunk_for_mesh(_coord: Vector3i) -> void:
		pass
	func unload_chunk(coord: Vector3i) -> void:
		if not busy:
			chunks.erase(coord)

func _initialize() -> void:
	var chunk := Chunk.new()
	var air := PackedInt32Array()
	air.resize(4096)
	var solid := air.duplicate()
	solid.fill(VoxelBlocks.STONE)
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var colors: Array[Color] = []
	chunk._greedy_axis_snap(0,air,{Vector3i.RIGHT:solid},vertices,normals,uvs,colors)
	var borrowed_faces := vertices.size() / 6
	print("Empty chunk emits neighbor-owned quads: ",borrowed_faces," (expected 0)")
	var world := BusyWorld.new()
	var streamer := ChunkStreamer.new()
	streamer.render_distance = 1
	streamer.initialize(world)
	streamer._process(1.0/60.0)
	world.busy = false
	for i in range(30):
		streamer._process(1.0/60.0)
	var not_retried := world.chunks.has(Vector3i(5,5,0)) and streamer._unload_queue.is_empty()
	print("Busy unload lost its retry while player stays still: ",not_retried)
	var findings := {"empty_chunk_emits_neighbor_owned_quads":borrowed_faces,"busy_unload_not_retried":not_retried}
	var file := FileAccess.open("res://docs/case-study/review-findings.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(findings,"\t")+"\n")
	file.close()
	streamer.free()
	world.player.free()
	world.free()
	chunk.free()
	quit()
