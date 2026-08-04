extends SceneTree


func _initialize() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Could not load main scene.")
		quit(1)
		return

	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	root._start_sandbox(false)
	await process_frame

	var camera := root.get_node("IsoCamera") as Camera2D
	var hud_panel := root.get_node("Ui/UiRoot/GameHud/StatusPanel") as Control
	var initial_zoom := camera.zoom

	get_root().size = Vector2i(1920, 720)
	await process_frame
	var wide_viewport_size := get_root().get_visible_rect().size
	var wide_zoom := camera.zoom
	var wide_panel_position := hud_panel.position

	get_root().size = Vector2i(900, 900)
	await process_frame
	var square_viewport_size := get_root().get_visible_rect().size
	var square_zoom := camera.zoom
	var square_panel_position := hud_panel.position

	if not initial_zoom.is_equal_approx(wide_zoom) or not initial_zoom.is_equal_approx(square_zoom):
		push_error("Window resize changed camera zoom.")
		quit(1)
		return

	if wide_viewport_size.x <= square_viewport_size.x:
		push_error("Wider viewport did not expose a wider visible area.")
		quit(1)
		return

	if wide_panel_position != square_panel_position:
		push_error("HUD panel lost its anchored margin across resize.")
		quit(1)
		return

	print("initial_zoom=", initial_zoom, " wide=", wide_viewport_size, " square=", square_viewport_size)
	quit(0)
