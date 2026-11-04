# Render measured fixtures in Godot. These are instrumented demonstrations,
# not screenshots of the normal gameplay HUD or gameplay FPS benchmarks.
extends SceneTree

const C := Color("0c1b27")
const TEXT := Color("e6eff5")
const MUTED := Color("9ab1c1")
const ACCENT := Color("52d8b5")
const ORANGE := Color("ffbe72")
var data: Dictionary
var ui: Control

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_size = Vector2i(1280,520)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	data = JSON.parse_string(FileAccess.get_file_as_string("res://docs/case-study/measurements.json"))
	for kind in ["streaming","meshing","concurrency","persistence"]:
		ui = Control.new()
		root.add_child(ui)
		_rect(Vector2.ZERO,Vector2(1280,520),C)
		call("_"+kind)
		for tick in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var output: String = "res://docs/case-study/"+str(kind)+".png"
		var status := root.get_texture().get_image().save_png(output)
		print("CAPTURE ",kind," status=",status)
		ui.queue_free()
		await process_frame
	await process_frame
	quit()

func _rect(at: Vector2, dimensions: Vector2, color: Color) -> void:
	var node := ColorRect.new()
	node.position = at
	node.size = dimensions
	node.color = color
	ui.add_child(node)

func _label(value: String, at: Vector2, size: int=22, color: Color=TEXT) -> void:
	var node := Label.new()
	node.text = value
	node.position = at
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	ui.add_child(node)

func _header(title: String, subtitle: String) -> void:
	_label(title,Vector2(36,15),30)
	_label(subtitle,Vector2(36,57),18,MUTED)
	_rect(Vector2(36,96),Vector2(590,330),Color("142b3a"))
	_rect(Vector2(654,96),Vector2(590,330),Color("142b3a"))

func _viewport(x: int, target: Vector3, relative_camera: Vector3) -> Node3D:
	var container := SubViewportContainer.new()
	container.position = Vector2(x,145)
	container.size = Vector2(566,267)
	container.stretch = true
	ui.add_child(container)
	var view := SubViewport.new()
	view.size = Vector2i(566,267)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(view)
	var scene := Node3D.new()
	view.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("142b3a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	scene.add_child(env)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = target+relative_camera
	camera.look_at(target)
	camera.fov = 44
	camera.make_current()
	return scene

func _arrays(chunk: Chunk, voxels: PackedInt32Array, naive: bool=false) -> Array:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var colors: Array[Color] = []
	if naive:
		for axis in range(3):
			var u := (axis+1)%3
			var v := (axis+2)%3
			for boundary in [-1,15]:
				for j in range(16):
					for k in range(16):
						var x := [0,0,0]
						x[axis] = boundary
						x[u] = j
						x[v] = k
						var du := [0,0,0]
						var dv := [0,0,0]
						du[u] = 1
						dv[v] = 1
						chunk.add_quad(vertices,normals,uvs,colors,x,du,dv,axis,-VoxelBlocks.STONE if boundary == -1 else VoxelBlocks.STONE)
	else:
		for axis in range(3):
			chunk._greedy_axis_snap(axis,voxels,{},vertices,normals,uvs,colors)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(colors)
	return arrays

func _show_mesh(scene: Node3D, arrays: Array, wire: bool=false) -> void:
	var instance := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	instance.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/voxel_atlas.gdshader")
	material.set_shader_parameter("atlas_texture",load("res://textures/terrain_1.png"))
	material.set_shader_parameter("atlas_grid",Vector2(16,16))
	instance.material_override = material
	scene.add_child(instance)
	if wire:
		var lines := ImmediateMesh.new()
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0,vertices.size(),3):
			for edge in [[0,1],[1,2],[2,0]]:
				lines.surface_add_vertex(vertices[i+edge[0]]-normals[i+edge[0]]*0.015)
				lines.surface_add_vertex(vertices[i+edge[1]]-normals[i+edge[1]]*0.015)
		lines.surface_end()
		var line_instance := MeshInstance3D.new()
		line_instance.mesh = lines
		line_instance.material_override = _flat(Color("1b2930"))
		scene.add_child(line_instance)

func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func _streaming() -> void:
	_header("Bound the amount of new work each tick","Actual scheduler requests, visualized as cubes. Radius 4, unload buffer 2; no terrain-generation timing.")
	var samples: Array = data.streaming.samples
	for i in range(2):
		var sample: Dictionary = samples[1] if i == 0 else samples[-1]
		var x := 48 if i == 0 else 666
		_label("Tick %d  |  %d loaded  |  %d waiting" % [sample.frame,sample.loaded,sample.load_queue],Vector2(x,108),21)
		var center_y: float = data.streaming.move_from[1] if data.streaming.coordinate_mode == "xyz_sphere" else (VoxelConstants.NUM_Y_CHUNKS-1)/2.0
		var center := Vector3(0,center_y,0) if i == 0 else Vector3(8,center_y,0)
		var scene := _viewport(x,center,Vector3(10,8,11))
		var environment: WorldEnvironment = scene.get_child(0)
		environment.environment.ambient_light_energy = 0.45
		var light := DirectionalLight3D.new()
		light.rotation = Vector3(-0.6,-0.8,0)
		scene.add_child(light)
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE*0.72
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = sample.coords.size()
		for j in range(sample.coords.size()):
			var coord: Array = sample.coords[j]
			var position := Vector3(coord[0],coord[1],coord[2])
			multi.set_instance_transform(j,Transform3D(Basis.IDENTITY,position))
			var distance_sq := position.distance_squared_to(center) if data.streaming.coordinate_mode == "xyz_sphere" else Vector2(position.x-center.x,position.z-center.z).length_squared()
			multi.set_instance_color(j,ORANGE if distance_sq>16 else ACCENT)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		var material := _flat(Color.WHITE)
		material.vertex_color_use_as_albedo = true
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		instance.material_override = material
		scene.add_child(instance)
	_label("Observed limits: 1 spawn and 2 unload attempts per tick",Vector2(36,442),25,ACCENT)
	_label("620 manual ticks. Player moves eight chunks at tick 301. Orange cubes remain inside the unload buffer.",Vector2(36,485),18,MUTED)

func _meshing() -> void:
	_header("Merge matching faces into larger rectangles","Same isolated 16 x 16 x 16 stone chunk. Wire overlay reveals triangles; neighbors are treated as air.")
	var chunk := Chunk.new()
	var voxels := PackedInt32Array()
	voxels.resize(4096)
	voxels.fill(VoxelBlocks.STONE)
	for i in range(2):
		var x := 48 if i == 0 else 666
		_label("Exposed unit faces: 1,536 quads" if i == 0 else "Greedy output: 6 quads",Vector2(x,108),22)
		var scene := _viewport(x,Vector3(8,8,8),Vector3(28,22,31))
		_show_mesh(scene,_arrays(chunk,voxels,i == 0),true)
	_label("3,072 triangles  ->  12 triangles in this flat-face fixture",Vector2(36,442),25,ACCENT)
	_label("Procedural terrain sample: %d exposed faces -> %d greedy quads. Reductions depend on the surface." % [data.meshing.terrain.exposed_unit_faces,data.meshing.terrain.greedy_quads],Vector2(36,485),18,MUTED)
	chunk.free()

func _concurrency() -> void:
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/case-study/snapshot-isolation.json"))
	assert(snapshot.failed == 0)
	_header("Keep worker inputs stable and reject stale results","Two controlled checks: a real worker held by a semaphore, and injected completions into the real apply method.")
	_label("Worker input isolation",Vector2(58,112),24)
	_label("Live values change after dispatch",Vector2(58,152),19,MUTED)
	var rows := ["Own voxel array","Neighbor voxel array","Saved edit dictionary"]
	for i in range(3):
		_label(rows[i],Vector2(58,213+i*55),23)
		_label("UNCHANGED",Vector2(420,213+i*55),21,ACCENT)
	_label("Completion order check",Vector2(676,112),24)
	_label("Three edits produce one queued rebuild",Vector2(676,152),19,MUTED)
	_label("Request revision 0",Vector2(676,216),23)
	_label("REJECTED",Vector2(1060,216),21,ORANGE)
	_label("Current revision 3",Vector2(676,274),23)
	_label("APPLIED",Vector2(1060,274),21,ACCENT)
	_label("Duplicate dispatch: refused",Vector2(676,351),19,MUTED)
	_label("Snapshot regression: %d / %d checks pass after explicit copies" % [snapshot.checks.size()-int(snapshot.failed),snapshot.checks.size()],Vector2(36,442),25,ACCENT)
	_label("Revision rejection and snapshot isolation are separate protections. These checks do not prove all thread interleavings.",Vector2(36,485),18,MUTED)

func _persistence() -> void:
	var coord_data: Array = data.persistence.chunk_coord
	var coord := Vector3i(coord_data[0],coord_data[1],coord_data[2])
	_header("Regenerate the base terrain and replay only edits","Three stone edits in procedural chunk %s. Outlines mark changed blocks in both views." % [coord])
	var full := FileAccess.open("/private/tmp/megalophobia-case-study/full_chunk.dat",FileAccess.READ)
	var edited: PackedInt32Array = full.get_var()
	full.close()
	var store = load("res://docs/case-study/storage_fixture.gd").new()
	var delta: Dictionary = store._load_from_disk(coord)
	var chunk := Chunk.new()
	var restored := chunk._generate_voxels_pure(coord,TerrainGenerator.new())
	for index in delta:
		restored[index] = delta[index]
	assert(restored == edited)
	for i in range(2):
		var x := 48 if i == 0 else 666
		_label("Edited terrain" if i == 0 else "Regenerated terrain + saved edits",Vector2(x,108),22)
		var scene := _viewport(x,Vector3(8,7,8),Vector3(19,20,-22))
		_show_mesh(scene,_arrays(chunk,edited if i == 0 else restored))
		for position in data.persistence.edit_local_positions:
			var marker := MeshInstance3D.new()
			var lines := ImmediateMesh.new()
			lines.surface_begin(Mesh.PRIMITIVE_LINES)
			var corners := [Vector3(-0.54,-0.54,-0.54),Vector3(0.54,-0.54,-0.54),Vector3(0.54,-0.54,0.54),Vector3(-0.54,-0.54,0.54),Vector3(-0.54,0.54,-0.54),Vector3(0.54,0.54,-0.54),Vector3(0.54,0.54,0.54),Vector3(-0.54,0.54,0.54)]
			for edge in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
				lines.surface_add_vertex(corners[edge[0]])
				lines.surface_add_vertex(corners[edge[1]])
			lines.surface_end()
			marker.mesh = lines
			marker.position = Vector3(position[0]+0.5,position[1]+0.5,position[2]+0.5)
			var material := _flat(ACCENT)
			material.no_depth_test = true
			marker.material_override = material
			scene.add_child(marker)
	_label("%d bytes of saved edits  |  %d bytes for the full chunk" % [data.persistence.delta_file_bytes,data.persistence.full_chunk_variant_bytes],Vector2(36,442),25,ACCENT)
	_label("Same Variant serialization format. Helpers tested in temporary files; normal debug gameplay disables disk saving.",Vector2(36,485),18,MUTED)
	chunk.free()
