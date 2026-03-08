@tool
extends MeshInstance3D

@export var cube_size: float = 1.0
@export var width: int = 4
@export var height: int = 16
@export var depth: int = 4

@export var atlas_texture: Texture2D
@export var atlas_cols: int = 16
@export var atlas_rows: int = 16

# Prevent sampling neighboring tiles (tweak if needed)
@export var uv_inset_pixels: float = 0.5

# If true, we will create a StandardMaterial3D using the atlas texture.
# If false, we leave your existing material alone (recommended if you already set it in the editor).
@export var set_material_in_code: bool = false

var cube_mesh: ArrayMesh
var voxels: Array = []

const FACE_TOP := 0
const FACE_BOTTOM := 1
const FACE_SIDE := 2

const BLOCKS := {
	0: {"name": "Air", "solid": false, "tiles": {FACE_TOP: Vector2i(0, 15), FACE_BOTTOM: Vector2i(0, 15), FACE_SIDE: Vector2i(0, 15)}},
	1: {"name": "Grass", "solid": true, "tiles": {FACE_TOP: Vector2i(0, 0), FACE_BOTTOM: Vector2i(2, 0), FACE_SIDE: Vector2i(3, 0)}},
	2: {"name": "Dirt", "solid": true, "tiles": {FACE_TOP: Vector2i(2, 0), FACE_BOTTOM: Vector2i(2, 0), FACE_SIDE: Vector2i(2, 0)}}
}

func _ready() -> void:
	voxels = generate_voxels()
	voxels[2][15][2] = 0 # Just a random hole in the world lol
	generate_mesh(voxels)
	

	if set_material_in_code and atlas_texture:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = atlas_texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material_override = mat

func generate_mesh(voxels_in: Array) -> void:
	var faces: Array = []

	for x in range(voxels_in.size()):
		for y in range(voxels_in[x].size()):
			for z in range(voxels_in[x][y].size()):
				var block_id: int = voxels_in[x][y][z]
				if block_id == 0:
					continue

				var pos: Vector3 = Vector3(x, y, z) * cube_size

				# Only create faces that are exposed to air
				if x == 0 or voxels_in[x - 1][y][z] == 0:
					var t := block_tile_for_face(block_id, Vector3.LEFT)
					faces.append(create_face(Vector3.LEFT, pos, get_tile_uvs(t.x, t.y)))
				if x == voxels_in.size() - 1 or voxels_in[x + 1][y][z] == 0:
					var t := block_tile_for_face(block_id, Vector3.RIGHT)
					faces.append(create_face(Vector3.RIGHT, pos, get_tile_uvs(t.x, t.y)))
				if y == 0 or voxels_in[x][y - 1][z] == 0:
					var t := block_tile_for_face(block_id, Vector3.DOWN)
					faces.append(create_face(Vector3.DOWN, pos, get_tile_uvs(t.x, t.y)))
				if y == voxels_in[x].size() - 1 or voxels_in[x][y + 1][z] == 0:
					var t := block_tile_for_face(block_id, Vector3.UP)
					faces.append(create_face(Vector3.UP, pos, get_tile_uvs(t.x, t.y)))
				if z == 0 or voxels_in[x][y][z - 1] == 0:
					var t := block_tile_for_face(block_id, Vector3.FORWARD)
					faces.append(create_face(Vector3.FORWARD, pos, get_tile_uvs(t.x, t.y)))
				if z == voxels_in[x][y].size() - 1 or voxels_in[x][y][z + 1] == 0:
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
	self.mesh = cube_mesh

func generate_voxels() -> Array:
	var array: Array = []
	array.resize(width)

	for x in range(width):
		array[x] = []
		array[x].resize(height)
		for y in range(height):
			array[x][y] = []
			array[x][y].resize(depth)

	for x in range(width):
		for y in range(height):
			for z in range(depth):
				if y == height - 1:
					array[x][y][z] = 1
				else:
					array[x][y][z] = 2

	return array

func create_face(direction: Vector3, pos: Vector3, uv_coords: Array[Vector2]) -> Dictionary:
	var quad_vertices: Array[Vector3] = []
	var quad_normals: Array[Vector3] = []
	var quad_uvs: Array[Vector2] = oriented_uvs_for_face(direction, uv_coords)

	match direction:
		Vector3.UP:
			quad_vertices = [
				pos + Vector3(-0.5,  0.5, -0.5) * cube_size,
				pos + Vector3( 0.5,  0.5, -0.5) * cube_size,
				pos + Vector3( 0.5,  0.5,  0.5) * cube_size,
				pos + Vector3(-0.5,  0.5,  0.5) * cube_size
			]
		Vector3.DOWN:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5,  0.5) * cube_size,
				pos + Vector3( 0.5, -0.5,  0.5) * cube_size,
				pos + Vector3( 0.5, -0.5, -0.5) * cube_size,
				pos + Vector3(-0.5, -0.5, -0.5) * cube_size
			]
		Vector3.LEFT:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5, -0.5) * cube_size,
				pos + Vector3(-0.5,  0.5, -0.5) * cube_size,
				pos + Vector3(-0.5,  0.5,  0.5) * cube_size,
				pos + Vector3(-0.5, -0.5,  0.5) * cube_size
			]
		Vector3.RIGHT:
			quad_vertices = [
				pos + Vector3( 0.5, -0.5,  0.5) * cube_size,
				pos + Vector3( 0.5,  0.5,  0.5) * cube_size,
				pos + Vector3( 0.5,  0.5, -0.5) * cube_size,
				pos + Vector3( 0.5, -0.5, -0.5) * cube_size
			]
		Vector3.FORWARD:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5, -0.5) * cube_size,
				pos + Vector3( 0.5, -0.5, -0.5) * cube_size,
				pos + Vector3( 0.5,  0.5, -0.5) * cube_size,
				pos + Vector3(-0.5,  0.5, -0.5) * cube_size
			]
		Vector3.BACK:
			quad_vertices = [
				pos + Vector3(-0.5,  0.5,  0.5) * cube_size,
				pos + Vector3( 0.5,  0.5,  0.5) * cube_size,
				pos + Vector3( 0.5, -0.5,  0.5) * cube_size,
				pos + Vector3(-0.5, -0.5,  0.5) * cube_size
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
			return [base_uvs[1], base_uvs[0], base_uvs[3], base_uvs[2]] # horizontal flip
		Vector3.BACK:
			return [base_uvs[3], base_uvs[2], base_uvs[1], base_uvs[0]] # vertical flip
		Vector3.LEFT:
			# rotate 90
			return [base_uvs[1], base_uvs[2], base_uvs[3], base_uvs[0]]
		Vector3.RIGHT:
			# rotate 270
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
