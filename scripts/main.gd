extends Node2D

const IsoCamera := preload("res://scripts/iso_camera.gd")
const IsoBuilding3DLayer := preload("res://scripts/iso_building_3d_layer.gd")
const IsoBuildingPreview3DLayer := preload("res://scripts/iso_building_preview_3d_layer.gd")
const IsoCamera3D := preload("res://scripts/iso_camera_3d.gd")
const IsoForest3DLayer := preload("res://scripts/iso_forest_3d_layer.gd")
const IsoMountain3DLayer := preload("res://scripts/iso_mountain_3d_layer.gd")
const IsoRoad3DLayer := preload("res://scripts/iso_road_3d_layer.gd")
const IsoTerrain3DLayer := preload("res://scripts/iso_terrain_3d_layer.gd")
const IsoUnit3DLayer := preload("res://scripts/iso_unit_3d_layer.gd")
const IsoWorld := preload("res://scripts/iso_world.gd")
const MapInputController := preload("res://scripts/map_input_controller.gd")

const BASE_VIEWPORT_SIZE := Vector2(1280, 720)
const HUD_MAX_WIDTH := 460.0
const HUD_MARGIN := 16.0
const UI_FONT_SIZE := 18
const UI_SMALL_FONT_SIZE := 16
const START_CAMERA_ZOOM := 2.0
const DEFAULT_TREE_DENSITY_PERCENT := 64
const DEFAULT_TREE_SIZE_PERCENT := 100
const RUNTIME_CONFIG_PATH := "res://config/runtime.cfg"
const START_SCREEN_BACKGROUND_PATH := "res://assets/start_screen_background.png"
const INTRO_MUSIC_PATH := "res://assets/audio/music/intro_dystopian_nightmare.mp3"
const GAME_MUSIC_PATH := "res://assets/audio/music/empty_orbit_signal.mp3"
const MUSIC_CROSSFADE_SECONDS := 1.5
const SUN_ROTATION_DEGREES := Vector3(-73.0, -28.0, 0.0)
const SUN_LIGHT_COLOR := Color8(255, 242, 216)
const SUN_LIGHT_ENERGY := 1.12
const AMBIENT_LIGHT_COLOR := Color8(64, 72, 67)
const AMBIENT_LIGHT_ENERGY := 0.56

enum AppState { MAIN_MENU, SANDBOX_SETUP, IN_GAME }

var app_state: AppState = AppState.MAIN_MENU
var world: IsoWorld
var camera: IsoCamera
var camera_3d: IsoCamera3D
var terrain_3d_layer: IsoTerrain3DLayer
var forest_3d_layer: IsoForest3DLayer
var mountain_3d_layer: IsoMountain3DLayer
var road_3d_layer: IsoRoad3DLayer
var building_3d_layer: IsoBuilding3DLayer
var building_preview_3d_layer: IsoBuildingPreview3DLayer
var unit_3d_layer: IsoUnit3DLayer
var sun_light: DirectionalLight3D
var world_environment: WorldEnvironment
var input_controller: MapInputController
var background: CanvasLayer
var background_fill: ColorRect
var main_menu_background: TextureRect
var music_player: AudioStreamPlayer
var music_fade_player: AudioStreamPlayer
var ui: CanvasLayer
var ui_root: Control
var main_menu_root: Control
var sandbox_root: Control
var game_hud_root: Control
var status_label: Label
var objective_label: Label
var colony_label: Label
var viewport_label: Label
var performance_label: Label
var hud_panel: PanelContainer
var resource_bar_panel: PanelContainer
var hq_metal_value_label: Label
var sharon_panel: PanelContainer
var game_title_label: Label
var construction_panel: PanelContainer
var selected_building_panel: PanelContainer
var selected_building_title_label: Label
var selected_building_stats_label: Label
var selected_building_actions_row: HBoxContainer
var build_drilling_machine_button: Button
var build_hauler_button: Button
var dev_tools_row: HBoxContainer
var road_tool_button: Button
var oxygen_extractor_button: Button
var living_quarters_button: Button
var machine_park_button: Button
var milling_plant_button: Button
var hq_button: Button
var tool_buttons: Array[Button] = []
var paths_spin_box: SpinBox
var path_width_spin_box: SpinBox
var clearing_noise_spin_box: SpinBox
var min_build_spin_box: SpinBox
var max_build_spin_box: SpinBox
var tree_density_spin_box: SpinBox
var tree_size_spin_box: SpinBox
var is_dev_mode: bool = false
var admin_panel_visible: bool = false
var music_enabled: bool = true
var music_volume_db: float = -10.0
var _camera_initialized: bool = false
var _layout_queued: bool = false
var _performance_update_elapsed: float = 0.0
var _music_tween: Tween


func _ready() -> void:
	get_window().size_changed.connect(_queue_responsive_layout)
	_load_runtime_config()
	_build_background()
	_build_music_player()
	_build_ui()
	_start_music()
	_show_main_menu()
	_apply_responsive_layout()


func _exit_tree() -> void:
	if _music_tween != null:
		_music_tween.kill()
	if music_player != null:
		music_player.stop()
	if music_fade_player != null:
		music_fade_player.stop()


func _process(delta: float) -> void:
	if app_state != AppState.IN_GAME or performance_label == null:
		return

	_sync_terrain_3d_camera()
	_sync_building_3d_preview()
	_sync_unit_3d_layer()

	_performance_update_elapsed += delta
	if _performance_update_elapsed < 0.25:
		return

	_performance_update_elapsed = 0.0
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = 0.0 if fps <= 0.0 else 1000.0 / fps
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var object_count: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var diagnostics: String = ""
	if world != null and input_controller != null:
		diagnostics = "\n%s\nInput: %dus  calls:%d" % [
			_format_render_diagnostics(world.get_render_diagnostics()),
			input_controller.last_conversion_usec,
			input_controller.conversion_calls,
		]
	performance_label.text = "FPS: %d  Frame: %.1f ms  Draw calls: %d  Objects: %d%s" % [
		int(fps),
		frame_ms,
		draw_calls,
		object_count,
		diagnostics,
	]


func _build_background() -> void:
	background = CanvasLayer.new()
	background.name = "Background"
	background.layer = -100
	add_child(background)

	background_fill = ColorRect.new()
	background_fill.name = "ViewportFill"
	background_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_fill.color = Color8(11, 13, 12)
	background_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(background_fill)


func _build_music_player() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = "Master"
	add_child(music_player)

	music_fade_player = AudioStreamPlayer.new()
	music_fade_player.name = "MusicFadePlayer"
	music_fade_player.bus = "Master"
	add_child(music_fade_player)

	if not music_enabled:
		return

	music_player.stream = _load_looping_music(INTRO_MUSIC_PATH)
	music_player.volume_db = music_volume_db
	music_fade_player.volume_linear = 0.0


func _start_music() -> void:
	if not music_enabled or music_player == null or music_player.stream == null or music_player.playing:
		return
	music_player.play()


func _load_looping_music(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("Missing music: %s" % path)
		return null
	var music_stream := load(path) as AudioStream
	if music_stream == null:
		push_warning("Could not load music: %s" % path)
		return null
	if music_stream is AudioStreamMP3:
		(music_stream as AudioStreamMP3).loop = true
	return music_stream


func _crossfade_music_to(path: String) -> void:
	if not music_enabled or music_player == null or music_fade_player == null:
		return
	if music_player.stream != null and music_player.stream.resource_path == path and music_player.playing:
		return

	var next_stream := _load_looping_music(path)
	if next_stream == null:
		return
	if _music_tween != null:
		_music_tween.kill()

	var outgoing_player := music_player
	var incoming_player := music_fade_player
	incoming_player.stop()
	incoming_player.stream = next_stream
	incoming_player.volume_linear = 0.0
	incoming_player.play()
	music_player = incoming_player
	music_fade_player = outgoing_player

	var target_volume_linear := db_to_linear(music_volume_db)
	_music_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_music_tween.tween_property(outgoing_player, "volume_linear", 0.0, MUSIC_CROSSFADE_SECONDS)
	_music_tween.parallel().tween_property(incoming_player, "volume_linear", target_volume_linear, MUSIC_CROSSFADE_SECONDS)
	_music_tween.chain().tween_callback(Callable(outgoing_player, "stop"))


func _load_runtime_config() -> void:
	var config := ConfigFile.new()
	var err := config.load(RUNTIME_CONFIG_PATH)
	if err != OK:
		music_enabled = true
		music_volume_db = -10.0
		return
	music_enabled = bool(config.get_value("audio", "music_enabled", true))
	music_volume_db = float(config.get_value("audio", "music_volume_db", -10.0))


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "Ui"
	add_child(ui)

	ui_root = Control.new()
	ui_root.name = "UiRoot"
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.theme = _build_ui_theme()
	ui.add_child(ui_root)

	_build_main_menu()
	_build_sandbox_setup()
	_build_game_hud()


func _build_ui_theme() -> Theme:
	var theme := Theme.new()
	for type_name in ["Label", "Button", "SpinBox", "LineEdit", "PanelContainer"]:
		theme.set_font_size("font_size", type_name, UI_FONT_SIZE)
	theme.set_font_size("font_size", "TabBar", UI_SMALL_FONT_SIZE)
	return theme


func _build_main_menu() -> void:
	main_menu_root = Control.new()
	main_menu_root.name = "MainMenu"
	main_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(main_menu_root)

	main_menu_background = TextureRect.new()
	main_menu_background.name = "StartScreenBackground"
	main_menu_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_menu_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_menu_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main_menu_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(START_SCREEN_BACKGROUND_PATH):
		main_menu_background.texture = load(START_SCREEN_BACKGROUND_PATH) as Texture2D
	else:
		push_warning("Missing start screen background: %s" % START_SCREEN_BACKGROUND_PATH)
	main_menu_root.add_child(main_menu_background)

	var readability_scrim := ColorRect.new()
	readability_scrim.name = "ReadabilityScrim"
	readability_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readability_scrim.color = Color(0.0, 0.0, 0.0, 0.18)
	readability_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_menu_root.add_child(readability_scrim)

	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "MainMenuPanel"
	panel.add_theme_constant_override("separation", 12)
	panel.custom_minimum_size = Vector2(360, 220)
	main_menu_root.add_child(panel)

	var title: Label = Label.new()
	title.text = "OUTPOST ALPHA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Remote colony survival sandbox"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subtitle)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	panel.add_child(spacer)

	var sandbox_button: Button = Button.new()
	sandbox_button.text = "Sandbox"
	sandbox_button.custom_minimum_size = Vector2(260, 42)
	sandbox_button.pressed.connect(_start_sandbox.bind(false))
	panel.add_child(sandbox_button)

	var dev_button: Button = Button.new()
	dev_button.text = "Dev Mode"
	dev_button.custom_minimum_size = Vector2(260, 42)
	dev_button.pressed.connect(_start_sandbox.bind(true))
	panel.add_child(dev_button)

	var quit_button: Button = Button.new()
	quit_button.text = "Quit to OS"
	quit_button.custom_minimum_size = Vector2(260, 42)
	quit_button.pressed.connect(_quit_to_os)
	panel.add_child(quit_button)


func _draw_main_menu_background(scene: Control) -> void:
	var size: Vector2 = scene.size
	if size.x <= 0 or size.y <= 0:
		return

	scene.draw_rect(Rect2(Vector2.ZERO, size), Color8(9, 11, 10), true)
	var horizon_y: float = size.y * 0.62
	var ground: PackedVector2Array = PackedVector2Array([
		Vector2(0, horizon_y),
		Vector2(size.x, horizon_y * 0.88),
		Vector2(size.x, size.y),
		Vector2(0, size.y),
	])
	scene.draw_colored_polygon(ground, Color8(30, 40, 30))

	for i in range(18):
		var x: float = fmod(float(i * 173), size.x + 220.0) - 110.0
		var y: float = horizon_y + float((i * 47) % int(maxf(size.y - horizon_y, 1.0)))
		var color: Color = Color8(85, 44, 106, 150) if i % 3 != 0 else Color8(42, 142, 148, 120)
		_draw_menu_crystal(scene, Vector2(x, y), 0.7 + float(i % 4) * 0.25, color)

	var base_origin: Vector2 = Vector2(size.x * 0.58, size.y * 0.48)
	_draw_menu_outpost(scene, base_origin, 2.4)
	_draw_menu_outpost(scene, base_origin + Vector2(-170, 82), 1.55)
	_draw_menu_beam(scene, base_origin + Vector2(72, -38), size)

	for i in range(10):
		var star: Vector2 = Vector2(fmod(float(i * 251), size.x), fmod(float(i * 83), horizon_y * 0.8))
		scene.draw_circle(star, 1.5, Color8(80, 130, 126, 80))


func _draw_menu_outpost(scene: Control, origin: Vector2, scale: float) -> void:
	var base: PackedVector2Array = PackedVector2Array([
		origin + Vector2(0, -18) * scale,
		origin + Vector2(58, 6) * scale,
		origin + Vector2(0, 34) * scale,
		origin + Vector2(-58, 6) * scale,
	])
	scene.draw_colored_polygon(base, Color8(50, 55, 53))
	scene.draw_polyline(base + PackedVector2Array([base[0]]), Color8(13, 15, 14), 2.0)
	scene.draw_rect(Rect2(origin + Vector2(-18, -32) * scale, Vector2(36, 32) * scale), Color8(72, 76, 73), true)
	scene.draw_rect(Rect2(origin + Vector2(-18, -32) * scale, Vector2(36, 32) * scale), Color8(14, 15, 14), false, 2.0)
	scene.draw_line(origin + Vector2(-22, -14) * scale, origin + Vector2(22, -14) * scale, Color8(236, 143, 34), 2.0 * scale)
	scene.draw_circle(origin + Vector2(22, -24) * scale, 4.0 * scale, Color8(244, 156, 42))


func _draw_menu_crystal(scene: Control, origin: Vector2, scale: float, color: Color) -> void:
	var offsets: Array[Vector2] = [Vector2(-9, 6), Vector2(0, 0), Vector2(9, 7)]
	for offset: Vector2 in offsets:
		var top: Vector2 = origin + offset * scale + Vector2(0, -18) * scale
		var left: Vector2 = origin + offset * scale + Vector2(-5, 2) * scale
		var right: Vector2 = origin + offset * scale + Vector2(5, 2) * scale
		var bottom: Vector2 = origin + offset * scale + Vector2(0, 10) * scale
		scene.draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), color)


func _draw_menu_beam(scene: Control, origin: Vector2, size: Vector2) -> void:
	var beam: PackedVector2Array = PackedVector2Array([
		origin + Vector2(-10, 0),
		origin + Vector2(10, 0),
		Vector2(origin.x + 42, 0),
		Vector2(origin.x - 42, 0),
	])
	scene.draw_colored_polygon(beam, Color8(45, 185, 205, 42))
	scene.draw_line(origin, Vector2(origin.x, 0), Color8(94, 226, 238, 90), 2.0)


func _build_sandbox_setup() -> void:
	sandbox_root = Control.new()
	sandbox_root.name = "SandboxSetup"
	sandbox_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sandbox_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(sandbox_root)

	var dim: ColorRect = ColorRect.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color8(8, 10, 9, 220)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	sandbox_root.add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "SandboxPanel"
	panel.custom_minimum_size = Vector2(620, 520)
	sandbox_root.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title: Label = Label.new()
	title.text = "SANDBOX ADMIN"
	box.add_child(title)

	var hint: Label = Label.new()
	hint.text = "World-generation controls. Toggle this panel with ` / §."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size = Vector2(560, 330)
	box.add_child(tabs)

	var world_tab: VBoxContainer = VBoxContainer.new()
	world_tab.name = "World"
	world_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(world_tab)

	paths_spin_box = _add_admin_spin_box(world_tab, "Paths", 1, 12, 3)
	path_width_spin_box = _add_admin_spin_box(world_tab, "Path width", 1, 16, 8)
	clearing_noise_spin_box = _add_admin_spin_box(world_tab, "Clear noise", 0, 100, 45)
	min_build_spin_box = _add_admin_spin_box(world_tab, "Build min", 4, 46, 25)
	max_build_spin_box = _add_admin_spin_box(world_tab, "Build max", 4, 47, 40)

	var visuals_tab: VBoxContainer = VBoxContainer.new()
	visuals_tab.name = "Visuals"
	visuals_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(visuals_tab)

	tree_density_spin_box = _add_admin_spin_box(visuals_tab, "Tree density %", 0, 100, DEFAULT_TREE_DENSITY_PERCENT)
	tree_density_spin_box.value_changed.connect(_on_forest_visual_settings_changed)
	tree_size_spin_box = _add_admin_spin_box(visuals_tab, "Tree size %", 25, 250, DEFAULT_TREE_SIZE_PERCENT)
	tree_size_spin_box.value_changed.connect(_on_forest_visual_settings_changed)

	var raids_tab: VBoxContainer = VBoxContainer.new()
	raids_tab.name = "Raids"
	raids_tab.add_child(_placeholder_label("Raid rules will live here."))
	tabs.add_child(raids_tab)

	var loot_tab: VBoxContainer = VBoxContainer.new()
	loot_tab.name = "Loot"
	loot_tab.add_child(_placeholder_label("Loot and salvage tuning will live here."))
	tabs.add_child(loot_tab)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	var back_button: Button = Button.new()
	back_button.text = "Close"
	back_button.pressed.connect(_set_admin_panel_visible.bind(false))
	buttons.add_child(back_button)

	var start_button: Button = Button.new()
	start_button.text = "Regenerate World"
	start_button.pressed.connect(_regenerate_current_world)
	buttons.add_child(start_button)


func _placeholder_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_game_hud() -> void:
	game_hud_root = Control.new()
	game_hud_root.name = "GameHud"
	game_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(game_hud_root)

	hud_panel = PanelContainer.new()
	hud_panel.name = "StatusPanel"
	hud_panel.custom_minimum_size = Vector2(440, 300)
	game_hud_root.add_child(hud_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	hud_panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	game_title_label = Label.new()
	game_title_label.text = "OUTPOST ALPHA - SANDBOX"
	box.add_child(game_title_label)

	status_label = Label.new()
	status_label.text = ""
	box.add_child(status_label)

	objective_label = Label.new()
	objective_label.text = ""
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective_label)

	colony_label = Label.new()
	colony_label.text = ""
	colony_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(colony_label)

	var roles_row: HBoxContainer = HBoxContainer.new()
	roles_row.add_theme_constant_override("separation", 6)
	box.add_child(roles_row)
	_add_role_button(roles_row, "Digger -", "digger", -1)
	_add_role_button(roles_row, "Digger +", "digger", 1)
	_add_role_button(roles_row, "Inf -", "infantry", -1)
	_add_role_button(roles_row, "Inf +", "infantry", 1)

	viewport_label = Label.new()
	viewport_label.text = ""
	box.add_child(viewport_label)

	performance_label = Label.new()
	performance_label.text = "FPS: --  Frame: -- ms"
	performance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(performance_label)

	var help: Label = Label.new()
	help.text = "Pan: WASD / arrows / middle mouse  |  Rotate: Alt + middle mouse  |  Zoom: mouse wheel  |  Grid: G  |  Admin: ` / §"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)

	_build_construction_menu()
	_build_resource_bar()
	_build_selected_building_panel()


func _build_resource_bar() -> void:
	resource_bar_panel = PanelContainer.new()
	resource_bar_panel.name = "ResourceBar"
	resource_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_bar_panel.custom_minimum_size = Vector2(210, 44)
	game_hud_root.add_child(resource_bar_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 8)
	resource_bar_panel.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var label: Label = Label.new()
	label.text = "METAL"
	row.add_child(label)

	hq_metal_value_label = Label.new()
	hq_metal_value_label.text = "0"
	hq_metal_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hq_metal_value_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(hq_metal_value_label)


func _build_construction_menu() -> void:
	construction_panel = PanelContainer.new()
	construction_panel.name = "ConstructionPanel"
	construction_panel.custom_minimum_size = Vector2(700, 64)
	game_hud_root.add_child(construction_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	construction_panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var build_row: HBoxContainer = HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 8)
	box.add_child(build_row)

	oxygen_extractor_button = _add_tool_button(build_row, "Oxygen 40", "building:oxygen_extractor")
	living_quarters_button = _add_tool_button(build_row, "Living", "building:living_quarters")
	machine_park_button = _add_tool_button(build_row, "Machines 60", "building:machine_park")
	milling_plant_button = _add_tool_button(build_row, "Milling 40", "building:milling_plant")
	hq_button = _add_tool_button(build_row, "HQ", "building:hq")
	road_tool_button = _add_tool_button(build_row, "Road", "road")

	dev_tools_row = HBoxContainer.new()
	dev_tools_row.add_theme_constant_override("separation", 8)
	box.add_child(dev_tools_row)

	_add_tool_button(dev_tools_row, "Basalt", "terrain:0")
	_add_tool_button(dev_tools_row, "Scrub", "terrain:1")
	_add_tool_button(dev_tools_row, "Crystal", "terrain:2")
	_add_tool_button(dev_tools_row, "Ore", "terrain:3")
	_add_tool_button(dev_tools_row, "Vent", "terrain:4")
	_add_tool_button(dev_tools_row, "Mountain", "terrain:5")

	_build_sharon_briefing()


func _build_selected_building_panel() -> void:
	selected_building_panel = PanelContainer.new()
	selected_building_panel.name = "SelectedBuildingPanel"
	selected_building_panel.visible = false
	selected_building_panel.custom_minimum_size = Vector2(340, 180)
	game_hud_root.add_child(selected_building_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	selected_building_panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	selected_building_title_label = Label.new()
	selected_building_title_label.text = "BUILDING"
	box.add_child(selected_building_title_label)

	selected_building_stats_label = Label.new()
	selected_building_stats_label.text = ""
	selected_building_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(selected_building_stats_label)

	selected_building_actions_row = HBoxContainer.new()
	selected_building_actions_row.add_theme_constant_override("separation", 8)
	box.add_child(selected_building_actions_row)

	build_drilling_machine_button = Button.new()
	build_drilling_machine_button.text = "Drill -50 metal"
	build_drilling_machine_button.custom_minimum_size = Vector2(130, 32)
	build_drilling_machine_button.pressed.connect(_build_vehicle_from_selected.bind("drilling_machine"))
	selected_building_actions_row.add_child(build_drilling_machine_button)

	build_hauler_button = Button.new()
	build_hauler_button.text = "Hauler -35 metal"
	build_hauler_button.custom_minimum_size = Vector2(130, 32)
	build_hauler_button.pressed.connect(_build_vehicle_from_selected.bind("hauler"))
	selected_building_actions_row.add_child(build_hauler_button)


func _build_sharon_briefing() -> void:
	sharon_panel = PanelContainer.new()
	sharon_panel.name = "SharonBriefing"
	sharon_panel.visible = false
	sharon_panel.custom_minimum_size = Vector2(460, 220)
	game_hud_root.add_child(sharon_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	sharon_panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var speaker: Label = Label.new()
	speaker.text = "SHARON // MISSION CONTROL"
	box.add_child(speaker)

	var message: Label = Label.new()
	message.text = "You made planetfall. Good. This colony is now our best chance to keep humanity alive.\n\nYour reserve oxygen will last only a few days. Build an Oxygen Extractor first. One module can support up to 5 colonists."
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(button_row)

	var dismiss_button: Button = Button.new()
	dismiss_button.text = "Begin"
	dismiss_button.custom_minimum_size = Vector2(96, 34)
	dismiss_button.pressed.connect(_dismiss_sharon_briefing)
	button_row.add_child(dismiss_button)


func _add_tool_button(parent: HBoxContainer, label_text: String, tool_id: String) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.set_meta("tool_id", tool_id)
	button.custom_minimum_size = Vector2(92, 32)
	button.pressed.connect(_select_build_tool.bind(tool_id))
	parent.add_child(button)
	tool_buttons.append(button)
	return button


func _add_role_button(parent: HBoxContainer, label_text: String, role: String, delta: int) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(74, 28)
	button.pressed.connect(_change_role_assignment.bind(role, delta))
	parent.add_child(button)
	return button


func _add_admin_spin_box(parent: VBoxContainer, label_text: String, min_value: int, max_value: int, current_value: int) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)

	var spin_box: SpinBox = SpinBox.new()
	spin_box.min_value = min_value
	spin_box.max_value = max_value
	spin_box.step = 1
	spin_box.value = current_value
	spin_box.custom_minimum_size = Vector2(180, 34)
	spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin_box)

	return spin_box


func _show_main_menu() -> void:
	app_state = AppState.MAIN_MENU
	_crossfade_music_to(INTRO_MUSIC_PATH)
	admin_panel_visible = false
	main_menu_root.visible = true
	sandbox_root.visible = false
	game_hud_root.visible = false
	_set_sharon_briefing_visible(false)
	_sync_debug_hud_visibility()
	_set_world_active(false)
	_queue_responsive_layout()


func _show_sandbox_setup() -> void:
	_set_admin_panel_visible(true)


func _start_sandbox(next_dev_mode: bool = false) -> void:
	app_state = AppState.IN_GAME
	_crossfade_music_to(GAME_MUSIC_PATH)
	is_dev_mode = next_dev_mode
	admin_panel_visible = false
	main_menu_root.visible = false
	sandbox_root.visible = false
	game_hud_root.visible = true
	_ensure_world()
	world.configure_mode(is_dev_mode, is_dev_mode)
	_apply_sandbox_settings_to_world()
	_set_world_active(true)
	_place_initial_camera(true)
	_sync_game_mode_ui()
	_sync_construction_button_state()
	_select_build_tool("none")
	_on_world_tile_changed(world.selected_tile, "Ready")
	_sync_resource_bar()
	_set_sharon_briefing_visible(not is_dev_mode)
	_sync_debug_hud_visibility()
	_queue_responsive_layout()


func _quit_to_os() -> void:
	get_tree().quit()


func _ensure_world() -> void:
	if world != null:
		return

	world = IsoWorld.new()
	world.name = "IsoWorld"
	world.configure_mode(is_dev_mode, is_dev_mode)
	add_child(world)
	world.tile_changed.connect(_on_world_tile_changed)
	world.colony_changed.connect(_on_colony_changed)
	world.paint_tool_changed.connect(_sync_tool_buttons)
	world.building_selection_changed.connect(_on_building_selection_changed)
	world.road_tiles_changed.connect(_on_world_road_tiles_changed)
	world.buildings_changed.connect(_on_world_buildings_changed)
	world.terrain_changed.connect(_on_world_terrain_changed)

	_build_world_lighting()

	terrain_3d_layer = IsoTerrain3DLayer.new()
	terrain_3d_layer.name = "Terrain3DLayer"
	add_child(terrain_3d_layer)
	terrain_3d_layer.set_map_data(world.map_data)

	forest_3d_layer = IsoForest3DLayer.new()
	forest_3d_layer.name = "Forest3DLayer"
	add_child(forest_3d_layer)
	forest_3d_layer.set_map_data(world.map_data)
	_apply_forest_visual_settings()

	mountain_3d_layer = IsoMountain3DLayer.new()
	mountain_3d_layer.name = "Mountain3DLayer"
	add_child(mountain_3d_layer)
	mountain_3d_layer.set_map_data(world.map_data)

	road_3d_layer = IsoRoad3DLayer.new()
	road_3d_layer.name = "Road3DLayer"
	add_child(road_3d_layer)
	road_3d_layer.set_map_data(world.map_data)

	building_3d_layer = IsoBuilding3DLayer.new()
	building_3d_layer.name = "Building3DLayer"
	add_child(building_3d_layer)
	building_3d_layer.set_building_catalog(world.building_catalog)
	building_3d_layer.set_colony_state(world.colony_state)

	building_preview_3d_layer = IsoBuildingPreview3DLayer.new()
	building_preview_3d_layer.name = "BuildingPreview3DLayer"
	add_child(building_preview_3d_layer)
	building_preview_3d_layer.set_building_catalog(world.building_catalog)

	unit_3d_layer = IsoUnit3DLayer.new()
	unit_3d_layer.name = "Unit3DLayer"
	add_child(unit_3d_layer)
	unit_3d_layer.set_unit_state(world.unit_state)

	camera_3d = IsoCamera3D.new()
	add_child(camera_3d)

	world.terrain_layer.visible = false
	world.road_layer.visible = false
	world.building_layer.set_hidden_building_types(["hq"])
	world.grid_layer.visible = false

	camera = IsoCamera.new()
	camera.name = "IsoCamera"
	camera.enabled = true
	camera.set_external_pan_enabled(true)
	camera.pan_dragged.connect(_on_camera_pan_dragged)
	camera.view_rotation_dragged.connect(_on_camera_view_rotation_dragged)
	add_child(camera)

	input_controller = MapInputController.new()
	input_controller.name = "MapInputController"
	input_controller.configure(world, camera, camera_3d)
	add_child(input_controller)
	world.unit_layer.set_map_position_projector(Callable(input_controller, "map_position_to_viewport"))


func _set_world_active(active: bool) -> void:
	if background != null:
		background.visible = not active
	if world != null:
		world.visible = active
		world.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if camera != null:
		camera.enabled = active
		camera.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if camera_3d != null:
		camera_3d.current = active
		camera_3d.visible = active
	if terrain_3d_layer != null:
		terrain_3d_layer.visible = active
	if forest_3d_layer != null:
		forest_3d_layer.visible = active
	if mountain_3d_layer != null:
		mountain_3d_layer.visible = active
	if road_3d_layer != null:
		road_3d_layer.visible = active
	if building_3d_layer != null:
		building_3d_layer.visible = active
	if building_preview_3d_layer != null:
		building_preview_3d_layer.visible = active
		if not active:
			building_preview_3d_layer.clear_preview()
	if unit_3d_layer != null:
		unit_3d_layer.visible = active
	if sun_light != null:
		sun_light.visible = active
	if world_environment != null:
		world_environment.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if input_controller != null:
		input_controller.set_active(active)


func _build_world_lighting() -> void:
	if world_environment == null:
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color8(8, 10, 9)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = AMBIENT_LIGHT_COLOR
		environment.ambient_light_energy = AMBIENT_LIGHT_ENERGY

		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		world_environment.environment = environment
		add_child(world_environment)

	if sun_light == null:
		sun_light = DirectionalLight3D.new()
		sun_light.name = "SunLight"
		sun_light.light_color = SUN_LIGHT_COLOR
		sun_light.light_energy = SUN_LIGHT_ENERGY
		sun_light.rotation_degrees = SUN_ROTATION_DEGREES
		sun_light.shadow_enabled = false
		add_child(sun_light)


func _apply_sandbox_settings_to_world() -> void:
	var min_build_radius: int = int(min_build_spin_box.value)
	var max_build_radius: int = int(max_build_spin_box.value)
	if min_build_radius > max_build_radius:
		max_build_radius = min_build_radius
		max_build_spin_box.value = max_build_radius

	world.regenerate(
		int(paths_spin_box.value),
		min_build_radius,
		max_build_radius,
		int(path_width_spin_box.value),
		int(clearing_noise_spin_box.value),
		is_dev_mode
	)
	if terrain_3d_layer != null:
		terrain_3d_layer.set_map_data(world.map_data)
	if forest_3d_layer != null:
		forest_3d_layer.set_map_data(world.map_data)
		_apply_forest_visual_settings()
	if mountain_3d_layer != null:
		mountain_3d_layer.set_map_data(world.map_data)
	if road_3d_layer != null:
		road_3d_layer.set_map_data(world.map_data)
	if building_3d_layer != null:
		building_3d_layer.set_building_catalog(world.building_catalog)
		building_3d_layer.set_colony_state(world.colony_state)
	if world.terrain_layer != null:
		world.terrain_layer.visible = false
	if world.road_layer != null:
		world.road_layer.visible = false
	if world.building_layer != null:
		world.building_layer.set_hidden_building_types(["hq"])
	if world.grid_layer != null:
		world.grid_layer.visible = false


func _regenerate_current_world() -> void:
	if app_state != AppState.IN_GAME:
		return
	_apply_sandbox_settings_to_world()
	_place_initial_camera(true)
	_on_world_tile_changed(world.selected_tile, "Ready")
	_sync_resource_bar()


func _set_admin_panel_visible(visible: bool) -> void:
	if app_state != AppState.IN_GAME:
		return
	admin_panel_visible = visible
	sandbox_root.visible = admin_panel_visible
	_sync_debug_hud_visibility()
	_queue_responsive_layout()


func _toggle_admin_panel() -> void:
	_set_admin_panel_visible(not admin_panel_visible)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and _is_admin_toggle_key(key):
			_toggle_admin_panel()
			get_viewport().set_input_as_handled()


func _is_admin_toggle_key(event: InputEventKey) -> bool:
	return event.unicode == 96 or event.unicode == 126 or event.unicode == 167


func _select_build_tool(tool_id: String) -> void:
	if world != null:
		world.set_paint_tool(tool_id)
	_sync_tool_buttons(tool_id)


func _sync_tool_buttons(tool_id: String) -> void:
	for button in tool_buttons:
		button.button_pressed = button.get_meta("tool_id", "") == tool_id


func _change_role_assignment(role: String, delta: int) -> void:
	if world == null:
		return
	if role == "digger":
		world.change_digger_operators(delta)
	elif role == "infantry":
		world.change_infantry(delta)


func _on_forest_visual_settings_changed(_value: float) -> void:
	_apply_forest_visual_settings()


func _apply_forest_visual_settings() -> void:
	if forest_3d_layer == null or tree_density_spin_box == null or tree_size_spin_box == null:
		return
	forest_3d_layer.set_visual_tuning(
		float(tree_size_spin_box.value) / 100.0,
		float(tree_density_spin_box.value) / 100.0
	)


func _sync_game_mode_ui() -> void:
	game_title_label.text = "OUTPOST ALPHA - DEV MODE" if is_dev_mode else "OUTPOST ALPHA - SANDBOX"
	dev_tools_row.visible = is_dev_mode
	construction_panel.custom_minimum_size = Vector2(860, 104) if is_dev_mode else Vector2(700, 64)
	_sync_debug_hud_visibility()


func _sync_debug_hud_visibility() -> void:
	if hud_panel == null:
		return
	hud_panel.visible = app_state == AppState.IN_GAME and (is_dev_mode or admin_panel_visible)


func _dismiss_sharon_briefing() -> void:
	_set_sharon_briefing_visible(false)


func _set_sharon_briefing_visible(visible: bool) -> void:
	if sharon_panel == null:
		return
	sharon_panel.visible = visible
	_queue_responsive_layout()


func _queue_responsive_layout() -> void:
	if _layout_queued:
		return

	_layout_queued = true
	call_deferred("_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_queued = false
	var viewport_size: Vector2 = Vector2(get_viewport_rect().size)
	_layout_main_menu(viewport_size)
	_layout_sandbox_setup(viewport_size)
	_layout_game_hud(viewport_size)
	_update_viewport_status(viewport_size)
	_sync_terrain_3d_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_queue_responsive_layout()


func _layout_main_menu(viewport_size: Vector2) -> void:
	var panel: Control = main_menu_root.get_node("MainMenuPanel") as Control
	panel.position = Vector2(72, maxf(80.0, viewport_size.y * 0.28))
	panel.size = Vector2(380, 240)


func _layout_sandbox_setup(viewport_size: Vector2) -> void:
	var panel: Control = sandbox_root.get_node("SandboxPanel") as Control
	var panel_size: Vector2 = Vector2(minf(660.0, viewport_size.x - 48.0), minf(560.0, viewport_size.y - 48.0))
	panel.position = (viewport_size - panel_size) * 0.5
	panel.size = panel_size


func _layout_game_hud(viewport_size: Vector2) -> void:
	game_hud_root.scale = Vector2.ONE

	var logical_size: Vector2 = viewport_size
	var panel_width: float = minf(HUD_MAX_WIDTH, logical_size.x - HUD_MARGIN * 2.0)
	hud_panel.position = Vector2(HUD_MARGIN, HUD_MARGIN)
	hud_panel.custom_minimum_size = Vector2(panel_width, 300)
	hud_panel.size = Vector2(panel_width, 300)

	if sharon_panel != null:
		var briefing_size: Vector2 = Vector2(minf(520.0, logical_size.x - HUD_MARGIN * 2.0), 240.0)
		sharon_panel.position = Vector2(
			logical_size.x - briefing_size.x - HUD_MARGIN,
			HUD_MARGIN
		)
		sharon_panel.size = briefing_size

	if selected_building_panel != null:
		var selected_size := Vector2(minf(380.0, logical_size.x - HUD_MARGIN * 2.0), 190.0)
		var selected_y := HUD_MARGIN
		if sharon_panel != null and sharon_panel.visible:
			selected_y = sharon_panel.position.y + sharon_panel.size.y + HUD_MARGIN
		selected_building_panel.position = Vector2(
			logical_size.x - selected_size.x - HUD_MARGIN,
			selected_y
		)
		selected_building_panel.size = selected_size

	if resource_bar_panel != null:
		var resource_size := Vector2(minf(260.0, logical_size.x - HUD_MARGIN * 2.0), 44.0)
		resource_bar_panel.position = Vector2(
			(logical_size.x - resource_size.x) * 0.5,
			HUD_MARGIN
		)
		resource_bar_panel.size = resource_size

	var construction_size: Vector2 = construction_panel.custom_minimum_size
	construction_size.x = minf(construction_size.x, logical_size.x - HUD_MARGIN * 2.0)
	construction_panel.position = Vector2(
		(logical_size.x - construction_size.x) * 0.5,
		logical_size.y - construction_size.y - HUD_MARGIN
	)
	construction_panel.size = construction_size


func _update_viewport_status(viewport_size: Vector2) -> void:
	if viewport_label == null:
		return

	var window_size: Vector2i = get_window().size
	viewport_label.text = "Window: %sx%s  Viewport: %sx%s  Zoom: %.2fx" % [
		window_size.x,
		window_size.y,
		int(viewport_size.x),
		int(viewport_size.y),
		camera.zoom.x if camera != null else 0.0,
	]


func force_responsive_layout_for_tests() -> void:
	_apply_responsive_layout()


func _place_initial_camera(force := false) -> void:
	if world == null or camera == null:
		return
	if _camera_initialized and not force:
		return

	var map_bounds: Rect2 = world.get_map_bounds()
	camera.position = map_bounds.get_center() + Vector2(0, 26)
	camera.set_zoom_level(START_CAMERA_ZOOM)
	_camera_initialized = true
	_sync_terrain_3d_camera()


func _sync_terrain_3d_camera() -> void:
	if camera_3d == null or camera == null:
		return
	camera_3d.sync_from_iso_camera(camera, Vector2(get_viewport_rect().size))


func _sync_building_3d_preview() -> void:
	if world == null or building_preview_3d_layer == null:
		return
	if not world.paint_tool.begins_with(world.PAINT_TOOL_BUILDING_PREFIX):
		building_preview_3d_layer.clear_preview()
		return
	if not world.map_data.is_inside(world.hovered_tile):
		building_preview_3d_layer.clear_preview()
		return

	var building_type: String = world.paint_tool.trim_prefix(world.PAINT_TOOL_BUILDING_PREFIX)
	if world.building_catalog.get_model_config(building_type).is_empty():
		building_preview_3d_layer.clear_preview()
		return

	var placement_feedback := world._get_placement_feedback()
	var valid := true
	for feedback in placement_feedback:
		if not bool(feedback.get("valid", false)):
			valid = false
			break
	building_preview_3d_layer.set_preview(building_type, world.hovered_tile, world.building_orientation, valid, placement_feedback)


func _sync_unit_3d_layer() -> void:
	if world == null or unit_3d_layer == null:
		return
	if unit_3d_layer.unit_state != world.unit_state:
		unit_3d_layer.set_unit_state(world.unit_state)
	else:
		unit_3d_layer.sync_units()
	if world.unit_layer != null:
		world.unit_layer.request_redraw("camera_projection")


func _on_camera_view_rotation_dragged(relative_pixels: float) -> void:
	if camera_3d == null:
		return
	camera_3d.rotate_view(relative_pixels)
	_sync_terrain_3d_camera()


func _on_camera_pan_dragged(relative_pixels: Vector2, previous_position: Vector2, current_position: Vector2) -> void:
	if camera == null:
		return
	if camera_3d == null or input_controller == null or not camera_3d.current or not camera_3d.visible:
		camera.position -= relative_pixels / camera.zoom.x
		return
	var previous_map_position := input_controller.viewport_to_map_position(previous_position)
	var current_map_position := input_controller.viewport_to_map_position(current_position)
	var map_delta := previous_map_position - current_map_position
	var next_camera_map_position := _iso_screen_to_map_position(camera.position) + map_delta
	camera.position = world.map_position_to_screen(next_camera_map_position)
	_sync_terrain_3d_camera()


func _iso_screen_to_map_position(screen_position: Vector2) -> Vector2:
	var map_x := (screen_position.y / 8.0 + screen_position.x / 16.0) * 0.5
	var map_y := (screen_position.y / 8.0 - screen_position.x / 16.0) * 0.5
	return Vector2(map_x, map_y)


func _on_world_tile_changed(tile: Vector2i, terrain_name: String) -> void:
	if status_label == null or world == null:
		return

	status_label.text = "Tile: %s,%s  Terrain: %s  Sprite tile: 32x16\n%s" % [
		tile.x,
		tile.y,
		terrain_name,
		world.get_generation_summary(),
	]


func _on_world_road_tiles_changed(tiles: Array) -> void:
	if road_3d_layer != null:
		road_3d_layer.notify_roads_changed(tiles)


func _on_world_terrain_changed() -> void:
	if world == null:
		return
	if terrain_3d_layer != null:
		terrain_3d_layer.set_map_data(world.map_data)
	if forest_3d_layer != null:
		forest_3d_layer.set_map_data(world.map_data)
		_apply_forest_visual_settings()
	if mountain_3d_layer != null:
		mountain_3d_layer.set_map_data(world.map_data)


func _on_world_buildings_changed() -> void:
	if building_3d_layer == null or world == null:
		return
	if building_3d_layer.building_catalog != world.building_catalog:
		building_3d_layer.set_building_catalog(world.building_catalog)
		if building_preview_3d_layer != null:
			building_preview_3d_layer.set_building_catalog(world.building_catalog)
	if building_3d_layer.colony_state != world.colony_state:
		building_3d_layer.set_colony_state(world.colony_state)
	else:
		building_3d_layer.refresh_buildings("buildings_changed")
	_sync_building_3d_preview()


func _on_colony_changed(summary_lines: Array[String]) -> void:
	if colony_label == null:
		return
	colony_label.text = "\n".join(summary_lines)
	if objective_label != null and world != null and world.colony_state != null:
		objective_label.text = "Objective: %s" % world.colony_state.get_primary_objective()
	_sync_resource_bar()
	_sync_construction_button_state()
	_sync_selected_building_panel()


func _sync_resource_bar() -> void:
	if hq_metal_value_label == null:
		return
	var stored_metal := 0
	if world != null and world.colony_state != null:
		stored_metal = world.colony_state.get_hq_stored_metal()
	hq_metal_value_label.text = str(stored_metal)


func _sync_construction_button_state() -> void:
	if world == null or world.colony_state == null:
		return
	if oxygen_extractor_button != null:
		oxygen_extractor_button.disabled = not world.colony_state.can_afford_building("oxygen_extractor")
	if machine_park_button != null:
		machine_park_button.disabled = not world.colony_state.can_afford_building("machine_park")
	if milling_plant_button != null:
		milling_plant_button.disabled = not world.colony_state.can_afford_building("milling_plant")
	if living_quarters_button != null:
		living_quarters_button.disabled = not world.colony_state.can_afford_building("living_quarters")
	if hq_button != null:
		hq_button.disabled = not world.colony_state.can_afford_building("hq")


func _on_building_selection_changed(_building: Dictionary) -> void:
	_sync_selected_building_panel()


func _sync_selected_building_panel() -> void:
	if selected_building_panel == null or world == null:
		return

	var building: Dictionary = world.get_selected_building()
	var was_visible := selected_building_panel.visible
	selected_building_panel.visible = not building.is_empty()
	if building.is_empty():
		if was_visible:
			_queue_responsive_layout()
		return

	var definition: Dictionary = world.colony_state.get_building_definition(building)
	var origin: Vector2i = building.get("origin", Vector2i.ZERO)
	var footprint: Vector2i = building.get("footprint", Vector2i.ONE)
	selected_building_title_label.text = str(definition.get("name", building.get("type", "Building"))).to_upper()
	selected_building_stats_label.text = "Health: %d / %d\nPower draw: %d\nOrigin: %s,%s  Footprint: %sx%s\nStored raw: %d  Stored metal: %d" % [
		int(building.get("health", 0)),
		int(building.get("max_health", 0)),
		int(building.get("power_usage", 0)),
		origin.x,
		origin.y,
		footprint.x,
		footprint.y,
		int(building.get("stored_raw", 0)),
		int(building.get("stored_metal", 0)),
	]

	var is_machine_park: bool = building.get("type", "") == "machine_park"
	selected_building_actions_row.visible = is_machine_park
	if is_machine_park:
		build_drilling_machine_button.disabled = not world.colony_state.can_afford_vehicle(building, "drilling_machine")
		build_hauler_button.disabled = not world.colony_state.can_afford_vehicle(building, "hauler")
	if not was_visible:
		_queue_responsive_layout()


func _build_vehicle_from_selected(unit_type: String) -> void:
	if world == null:
		return
	if world.request_build_vehicle(unit_type):
		_sync_unit_3d_layer()
		_sync_selected_building_panel()


func _format_render_diagnostics(diagnostics: Dictionary) -> String:
	var parts: Array[String] = []
	for layer_name in ["terrain", "roads", "buildings", "units", "grid", "overlay", "world"]:
		var layer: Dictionary = diagnostics.get(layer_name, {})
		if layer.is_empty():
			continue
		parts.append("%s d:%d r:%d c:%d us:%d bake:%d %s" % [
			layer_name.substr(0, 1).to_upper(),
			int(layer.get("draw_calls", 0)),
			int(layer.get("redraw_requests", 0)),
			int(layer.get("last_cells", 0)),
			int(layer.get("last_draw_usec", 0)),
			int(layer.get("last_bake_usec", 0)),
			str(layer.get("last_reason", "")),
		])
	return " | ".join(parts)
