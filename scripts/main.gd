extends Node2D

const IsoCamera := preload("res://scripts/iso_camera.gd")
const IsoWorld := preload("res://scripts/iso_world.gd")

const BASE_VIEWPORT_SIZE := Vector2(1280, 720)
const HUD_MAX_WIDTH := 420.0
const HUD_MARGIN := 16.0
const START_CAMERA_ZOOM := 2.0

var world: Node2D
var camera: IsoCamera
var hud: CanvasLayer
var background: CanvasLayer
var hud_root: Control
var status_label: Label
var viewport_label: Label
var hud_panel: PanelContainer
var _camera_initialized := false
var _layout_queued := false


func _ready() -> void:
	get_window().size_changed.connect(_queue_responsive_layout)

	world = IsoWorld.new()
	world.name = "IsoWorld"
	add_child(world)

	camera = IsoCamera.new()
	camera.name = "IsoCamera"
	camera.enabled = true
	add_child(camera)
	_place_initial_camera()

	_build_background()
	_build_hud()
	_apply_responsive_layout()
	world.tile_changed.connect(_on_world_tile_changed)
	_on_world_tile_changed(Vector2i.ZERO, "Ready")


func _build_background() -> void:
	background = CanvasLayer.new()
	background.name = "Background"
	background.layer = -100
	add_child(background)

	var fill := ColorRect.new()
	fill.name = "ViewportFill"
	fill.color = Color8(14, 16, 14)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(fill)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "Hud"
	add_child(hud)

	hud_root = Control.new()
	hud_root.name = "HudRoot"
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(hud_root)

	hud_panel = PanelContainer.new()
	hud_panel.name = "StatusPanel"
	hud_panel.custom_minimum_size = Vector2(360, 126)
	hud_root.add_child(hud_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	hud_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var title := Label.new()
	title.text = "OUTPOST ALPHA - ISO ENGINE"
	box.add_child(title)

	status_label = Label.new()
	status_label.text = ""
	box.add_child(status_label)

	viewport_label = Label.new()
	viewport_label.text = ""
	box.add_child(viewport_label)

	var help := Label.new()
	help.text = "Pan: WASD / arrows / middle mouse\nZoom: mouse wheel\nSelect tile: left click"
	box.add_child(help)


func _queue_responsive_layout() -> void:
	if _layout_queued:
		return

	_layout_queued = true
	call_deferred("_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_queued = false
	var viewport_size := Vector2(get_viewport_rect().size)
	_layout_hud(viewport_size)
	_update_viewport_status(viewport_size)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_queue_responsive_layout()


func _update_viewport_status(viewport_size: Vector2) -> void:
	if viewport_label == null:
		return

	var window_size := get_window().size
	viewport_label.text = "Window: %sx%s  Viewport: %sx%s  Zoom: %.2fx" % [
		window_size.x,
		window_size.y,
		int(viewport_size.x),
		int(viewport_size.y),
		camera.zoom.x,
	]


func force_responsive_layout_for_tests() -> void:
	_apply_responsive_layout()


func _place_initial_camera() -> void:
	if _camera_initialized:
		return

	var map_bounds: Rect2 = world.get_map_bounds()
	camera.position = map_bounds.get_center() + Vector2(0, 26)
	camera.set_zoom_level(START_CAMERA_ZOOM)
	_camera_initialized = true


func _layout_hud(viewport_size: Vector2) -> void:
	var scale_factor := clampf(minf(
		viewport_size.x / BASE_VIEWPORT_SIZE.x,
		viewport_size.y / BASE_VIEWPORT_SIZE.y
	), 0.85, 1.25)
	hud_root.scale = Vector2(scale_factor, scale_factor)

	var logical_size := viewport_size / scale_factor
	var panel_width := minf(HUD_MAX_WIDTH, logical_size.x - HUD_MARGIN * 2.0)
	hud_panel.position = Vector2(HUD_MARGIN, HUD_MARGIN)
	hud_panel.custom_minimum_size = Vector2(panel_width, 126)
	hud_panel.size = Vector2(panel_width, 126)


func _on_world_tile_changed(tile: Vector2i, terrain_name: String) -> void:
	status_label.text = "Tile: %s,%s  Terrain: %s  Sprite tile: 32x16" % [
		tile.x,
		tile.y,
		terrain_name,
	]
