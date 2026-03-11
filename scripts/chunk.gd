@tool
class_name Chunk
extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var chunk_coord: Vector2i = Vector2i.ZERO
var world: Node = null
var cube_mesh: ArrayMesh
var voxels: PackedInt32Array

const CUBE_SIZE: float = VoxelConstants.CUBE_SIZE
const WIDTH: int = VoxelConstants.CHUNK_WIDTH
const HEIGHT: int = VoxelConstants.CHUNK_HEIGHT
const DEPTH: int = VoxelConstants.CHUNK_DEPTH

@export var atlas_texture: Texture2D
const atlas_cols: int = VoxelConstants.CUBE_ATLAS_COLS
const atlas_rows: int = VoxelConstants.CUBE_ATLAS_ROWS

# Prevent sampling neighboring tiles (tweak if needed)
@export var uv_inset_pixels: float = 0.5

# Renders the texture onto the 3D Mesh from the script
@export var set_material_in_code: bool = true

const FACE_TOP := 0
const FACE_BOTTOM := 1
const FACE_SIDE := 2

const BLOCKS := {
	VoxelBlocks.AIR: {"name": "Air", "solid": false, "tiles": {FACE_TOP: Vector2i(0, 15), FACE_BOTTOM: Vector2i(0, 15), FACE_SIDE: Vector2i(0, 15)}},
	VoxelBlocks.GRASS: {"name": "Grass", "solid": true, "tiles": {FACE_TOP: Vector2i(0, 0), FACE_BOTTOM: Vector2i(2, 0), FACE_SIDE: Vector2i(3, 0)}},
	VoxelBlocks.DIRT: {"name": "Dirt", "solid": true, "tiles": {FACE_TOP: Vector2i(2, 0), FACE_BOTTOM: Vector2i(2, 0), FACE_SIDE: Vector2i(2, 0)}}
}

func initialize(coord: Vector2i, surrounding_world: Node) -> void:
	chunk_coord = coord
	world = surrounding_world


func _ready() -> void:
	print("Generating chunk at coord: %s" % chunk_coord)
	if voxels.is_empty():
		generate_voxels()
	generate_mesh()
	# We need to have this in the ready function of the chunk if we want to render the textures
	if set_material_in_code and atlas_texture:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = atlas_texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mesh_instance.material_override = mat


func _voxel_index(x: int, y: int, z: int) -> int:
	return x + WIDTH * (z + DEPTH * y)


func get_voxel(x:int,y:int,z:int) -> int:
	return voxels[_voxel_index(x,y,z)]


func set_voxel(x:int,y:int,z:int,val:int) -> void:
	voxels[_voxel_index(x,y,z)] = val


func get_voxel_safe(x:int, y:int, z:int) -> int:
	# Y outside chunk = air
	if y < 0 or y >= HEIGHT:
		return VoxelBlocks.AIR
	# inside this chunk
	if x >= 0 and x < WIDTH and z >= 0 and z < DEPTH:
		return get_voxel(x,y,z)
	# Currently previewing a single chunk, so no world exists...
	if not world:
		return VoxelBlocks.AIR
	# determine neighboring chunk
	var neighbor_coord := chunk_coord
	if x < 0:
		neighbor_coord.x -= 1
	elif x >= WIDTH:
		neighbor_coord.x += 1

	if z < 0:
		neighbor_coord.y -= 1
	elif z >= DEPTH:
		neighbor_coord.y += 1

	var neighbor = world.get_chunk(neighbor_coord)
	if neighbor == null:
		return VoxelBlocks.AIR
	var nx = posmod(x, WIDTH)
	var nz = posmod(z, DEPTH)
	return neighbor.get_voxel(nx, y, nz)


func generate_mesh() -> void:
	var faces: Array = []

	for x in range(WIDTH):
		for y in range(HEIGHT):
			for z in range(DEPTH):
				var block_id: int = get_voxel(x,y,z)
				if block_id == VoxelBlocks.AIR:
					continue

				var pos: Vector3 = Vector3(x, y, z) * CUBE_SIZE

				# Only create faces that are exposed to air
				if get_voxel_safe(x - 1, y, z) == VoxelBlocks.AIR:
					var t := block_tile_for_face(block_id, Vector3.LEFT)
					faces.append(create_face(Vector3.LEFT, pos, get_tile_uvs(t.x, t.y)))
				if get_voxel_safe(x + 1, y, z) == VoxelBlocks.AIR:
					var t := block_tile_for_face(block_id, Vector3.RIGHT)
					faces.append(create_face(Vector3.RIGHT, pos, get_tile_uvs(t.x, t.y)))
				if get_voxel_safe(x, y - 1, z) == VoxelBlocks.AIR:
					var t := block_tile_for_face(block_id, Vector3.DOWN)
					faces.append(create_face(Vector3.DOWN, pos, get_tile_uvs(t.x, t.y)))
				if get_voxel_safe(x, y + 1, z) == VoxelBlocks.AIR:
					var t := block_tile_for_face(block_id, Vector3.UP)
					faces.append(create_face(Vector3.UP, pos, get_tile_uvs(t.x, t.y)))
				if get_voxel_safe(x, y, z - 1) == VoxelBlocks.AIR:
					var t := block_tile_for_face(block_id, Vector3.FORWARD)
					faces.append(create_face(Vector3.FORWARD, pos, get_tile_uvs(t.x, t.y)))
				if get_voxel_safe(x, y, z + 1) == VoxelBlocks.AIR:
					var t := block_tile_for_face(block_id, Vector3.BACK)
					faces.append(create_face(Vector3.BACK, pos, get_tile_uvs(t.x, t.y)))

	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []

	for face in faces:
		vertices.append_array(face["vertices"])
		normals.append_array(face["normals"])
		uvs.append_array(face["uvs"])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs)

	cube_mesh = ArrayMesh.new()
	cube_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = cube_mesh


func generate_voxels() -> void:
	voxels = PackedInt32Array()
	voxels.resize(WIDTH * HEIGHT * DEPTH)

	for x in range(WIDTH):
		for y in range(HEIGHT):
			for z in range(DEPTH):
				# Eventually, height = noise(world_x, world_z)
				# var world_x = chunk_coord.x * WIDTH + x
				# var world_z = chunk_coord.y * DEPTH + z
				if y == HEIGHT - 1:
					set_voxel(x, y, z, VoxelBlocks.GRASS)
				else:
					set_voxel(x, y, z, VoxelBlocks.DIRT)


func create_face(direction: Vector3, pos: Vector3, uv_coords: Array[Vector2]) -> Dictionary:
	var quad_vertices: Array[Vector3] = []
	var quad_normals: Array[Vector3] = []
	var quad_uvs: Array[Vector2] = oriented_uvs_for_face(direction, uv_coords)

	match direction:
		Vector3.UP:
			quad_vertices = [
				pos + Vector3(-0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3(-0.5,  0.5,  0.5) * CUBE_SIZE
			]
		Vector3.DOWN:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5, -0.5) * CUBE_SIZE,
				pos + Vector3(-0.5, -0.5, -0.5) * CUBE_SIZE
			]
		Vector3.LEFT:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5, -0.5) * CUBE_SIZE,
				pos + Vector3(-0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3(-0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3(-0.5, -0.5,  0.5) * CUBE_SIZE
			]
		Vector3.RIGHT:
			quad_vertices = [
				pos + Vector3( 0.5, -0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5, -0.5) * CUBE_SIZE
			]
		Vector3.FORWARD:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3(-0.5,  0.5, -0.5) * CUBE_SIZE
			]
		Vector3.BACK:
			quad_vertices = [
				pos + Vector3(-0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5,  0.5) * CUBE_SIZE,
				pos + Vector3(-0.5, -0.5,  0.5) * CUBE_SIZE
			]
		_:
			return {"vertices": [], "normals": [], "uvs": []}

	quad_normals.resize(4)
	quad_normals.fill(direction)

	return {
		"vertices": [
			quad_vertices[0], quad_vertices[1], quad_vertices[2],
			quad_vertices[0], quad_vertices[2], quad_vertices[3],
		],
		"normals": [
			quad_normals[0], quad_normals[1], quad_normals[2],
			quad_normals[0], quad_normals[2], quad_normals[3],
		],
		"uvs": [
			quad_uvs[0], quad_uvs[1], quad_uvs[2],
			quad_uvs[0], quad_uvs[2], quad_uvs[3],
		]
	}


func oriented_uvs_for_face(face_dir: Vector3, base_uvs: Array[Vector2]) -> Array[Vector2]:
	# base_uvs is [BL, BR, TR, TL] or whatever you decided—just be consistent.
	# Your current get_tile_uvs returns: [ (u0,v1), (u1,v1), (u1,v0), (u0,v0) ]
	# which corresponds to: [BL, BR, TR, TL] in UV space (Godot's V grows downward in many setups).
	#
	# We’ll rotate/flip so that "up" on the texture points toward +Y for all side faces.

	match face_dir:
		Vector3.FORWARD:
			# Often needs a flip to keep consistent with BACK
			return [base_uvs[1], base_uvs[0], base_uvs[3], base_uvs[2]]
		Vector3.BACK:
			return [base_uvs[3], base_uvs[2], base_uvs[1], base_uvs[0]]
		Vector3.LEFT:
			# rotate 90
			return [base_uvs[1], base_uvs[2], base_uvs[3], base_uvs[0]]
		Vector3.RIGHT:
			# rotate 270
			# TODO: There is a bug where this face is vertically mirrored
			return [base_uvs[1], base_uvs[2], base_uvs[3], base_uvs[0]]
		Vector3.UP:
			# optional: depends on how you want top oriented
			return base_uvs
		Vector3.DOWN:
			# optional: flip to make bottom not mirrored
			return [base_uvs[3], base_uvs[2], base_uvs[1], base_uvs[0]]
		_:
			return base_uvs


func block_tile_for_face(block_id: int, face_dir: Vector3) -> Vector2i:
	var block = BLOCKS.get(block_id, BLOCKS[0])
	var tiles = block["tiles"]

	if face_dir == Vector3.UP:
		return tiles[FACE_TOP]
	elif face_dir == Vector3.DOWN:
		return tiles[FACE_BOTTOM]
	else:
		return tiles[FACE_SIDE]


func get_tile_uvs(tile_x: int, tile_y: int) -> Array[Vector2]:
	# Each tile in UV space
	var tile_u := 1.0 / float(atlas_cols)
	var tile_v := 1.0 / float(atlas_rows)

	# Optional: flip Y if your atlas indexing starts at top-left
	# If your tiles appear vertically flipped/wrong row, uncomment:
	# tile_y = (atlas_rows - 1) - tile_y

	var u0 := float(tile_x) * tile_u
	var v0 := float(tile_y) * tile_v
	var u1 := u0 + tile_u
	var v1 := v0 + tile_v

	# Inset by a small amount (in pixels) to avoid bleeding
	if atlas_texture and uv_inset_pixels > 0.0:
		var tex_w := float(atlas_texture.get_width())
		var tex_h := float(atlas_texture.get_height())
		var inset_u := uv_inset_pixels / tex_w
		var inset_v := uv_inset_pixels / tex_h
		u0 += inset_u
		u1 -= inset_u
		v0 += inset_v
		v1 -= inset_v

	# Quad UV order must match your vertex order.
	# Here we map the quad corners consistently.
	return [
		Vector2(u0, v1),
		Vector2(u1, v1),
		Vector2(u1, v0),
		Vector2(u0, v0),
	]
