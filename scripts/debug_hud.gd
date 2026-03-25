extends CanvasLayer
class_name DebugHUD

var _world: Node = null
var _label: RichTextLabel = null


func initialize(world_node: Node) -> void:
	_world = world_node


func _ready() -> void:
	visible = OS.is_debug_build()
	layer = 10

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(8, 8)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(280, 0)
	_label.add_theme_font_size_override("normal_font_size", 13)
	margin.add_child(_label)


func _process(_delta: float) -> void:
	if not visible or _world == null:
		return

	var player = _world.player
	var pos: Vector3 = player.global_position if player else Vector3.ZERO
	var chunk_coord: Vector2i = player.get_player_chunk_coord() if player else Vector2i.ZERO

	var load_q := 0
	var unload_q := 0
	if _world._streamer:
		load_q = _world._streamer._load_queue.size()
		unload_q = _world._streamer._unload_queue.size()

	var saves_str := (
		"[color=red]off (debug)[/color]" if OS.is_debug_build()
		else "[color=green]on[/color]"
	)

	_label.text = (
		"[color=yellow]-- debug --[/color]\n"
		+ "fps         %d\n" % Engine.get_frames_per_second()
		+ "pos         x=%.1f  y=%.1f  z=%.1f\n" % [pos.x, pos.y, pos.z]
		+ "chunk       %d, %d\n" % [chunk_coord.x, chunk_coord.y]
		+ "loaded      %d\n" % _world.chunks.size()
		+ "load queue  %d   unload  %d\n" % [load_q, unload_q]
		+ "rebuilding  %d   in-flight  %d/%d\n" % [_world._rebuilding_chunks.size(), _world._in_flight_count, _world.max_concurrent_rebuilds]
		+ "dirty       %d   priority  %d\n" % [_world._dirty_chunks.size(), _world._priority_chunks.size()]
		+ "disk saves  " + saves_str
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			visible = not visible
