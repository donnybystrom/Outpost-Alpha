extends Node2D

const IsoCamera := preload("res://scripts/iso_camera.gd")
const IsoWorld := preload("res://scripts/iso_world.gd")
const MapInputController := preload("res://scripts/map_input_controller.gd")

const BASE_VIEWPORT_SIZE := Vector2(1280, 720)
const HUD_MAX_WIDTH := 460.0
const HUD_MARGIN := 16.0
const START_CAMERA_ZOOM := 2.0

enum AppState { MAIN_MENU, SANDBOX_SETUP, IN_GAME }

var app_state: AppState = AppState.MAIN_MENU
var world: IsoWorld
var camera: IsoCamera
var input_controller: MapInputController
var background: CanvasLayer
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
var sharon_panel: PanelContainer
var game_title_label: Label
var construction_panel: PanelContainer
var dev_tools_row: HBoxContainer
var road_tool_button: Button
var oxygen_extractor_button: Button
var living_quarters_button: Button
var machine_park_button: Button
var milling_plant_button: Button
var tool_buttons: Array[Button] = []
var paths_spin_box: SpinBox
var path_width_spin_box: SpinBox
var clearing_noise_spin_box: SpinBox
var min_build_spin_box: SpinBox
var max_build_spin_box: SpinBox
var is_dev_mode: bool = false
var admin_panel_visible: bool = false
var _camera_initialized: bool = false
var _layout_queued: bool = false
var _performance_update_elapsed: float = 0.0


func _ready() -> void:
	get_window().size_changed.connect(_queue_responsive_layout)
	_build_background()
	_build_ui()
	_show_main_menu()
	_apply_responsive_layout()


func _process(delta: float) -> void:
	if app_state != AppState.IN_GAME or performance_label == null:
		return

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

	var fill: ColorRect = ColorRect.new()
	fill.name = "ViewportFill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = Color8(11, 13, 12)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(fill)


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "Ui"
	add_child(ui)

	ui_root = Control.new()
	ui_root.name = "UiRoot"
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(ui_root)

	_build_main_menu()
	_build_sandbox_setup()
	_build_game_hud()


func _build_main_menu() -> void:
	main_menu_root = Control.new()
	main_menu_root.name = "MainMenu"
	main_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(main_menu_root)

	var scene: Control = Control.new()
	scene.name = "MenuScene"
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene.draw.connect(_draw_main_menu_background.bind(scene))
	main_menu_root.add_child(scene)

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
	panel.custom_minimum_size = Vector2(520, 430)
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
	tabs.custom_minimum_size = Vector2(480, 250)
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
	help.text = "Pan: WASD / arrows / middle mouse  |  Zoom: mouse wheel  |  Grid: G  |  Admin: ` / §"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)

	_build_construction_menu()


func _build_construction_menu() -> void:
	construction_panel = PanelContainer.new()
	construction_panel.name = "ConstructionPanel"
	construction_panel.custom_minimum_size = Vector2(660, 64)
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

	oxygen_extractor_button = _add_tool_button(build_row, "Oxygen", "building:oxygen_extractor")
	living_quarters_button = _add_tool_button(build_row, "Living", "building:living_quarters")
	machine_park_button = _add_tool_button(build_row, "Machines", "building:machine_park")
	milling_plant_button = _add_tool_button(build_row, "Milling", "building:milling_plant")
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
	label.custom_minimum_size = Vector2(116, 0)
	row.add_child(label)

	var spin_box: SpinBox = SpinBox.new()
	spin_box.min_value = min_value
	spin_box.max_value = max_value
	spin_box.step = 1
	spin_box.value = current_value
	spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin_box)

	return spin_box


func _show_main_menu() -> void:
	app_state = AppState.MAIN_MENU
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
	_select_build_tool("none")
	_on_world_tile_changed(world.selected_tile, "Ready")
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

	camera = IsoCamera.new()
	camera.name = "IsoCamera"
	camera.enabled = true
	add_child(camera)

	input_controller = MapInputController.new()
	input_controller.name = "MapInputController"
	input_controller.configure(world, camera)
	add_child(input_controller)


func _set_world_active(active: bool) -> void:
	if world != null:
		world.visible = active
		world.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if camera != null:
		camera.enabled = active
		camera.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if input_controller != null:
		input_controller.set_active(active)


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


func _regenerate_current_world() -> void:
	if app_state != AppState.IN_GAME:
		return
	_apply_sandbox_settings_to_world()
	_place_initial_camera(true)
	_on_world_tile_changed(world.selected_tile, "Ready")


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


func _sync_game_mode_ui() -> void:
	game_title_label.text = "OUTPOST ALPHA - DEV MODE" if is_dev_mode else "OUTPOST ALPHA - SANDBOX"
	dev_tools_row.visible = is_dev_mode
	construction_panel.custom_minimum_size = Vector2(760, 104) if is_dev_mode else Vector2(600, 64)
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_queue_responsive_layout()


func _layout_main_menu(viewport_size: Vector2) -> void:
	var panel: Control = main_menu_root.get_node("MainMenuPanel") as Control
	panel.position = Vector2(72, maxf(80.0, viewport_size.y * 0.28))
	panel.size = Vector2(380, 240)


func _layout_sandbox_setup(viewport_size: Vector2) -> void:
	var panel: Control = sandbox_root.get_node("SandboxPanel") as Control
	var panel_size: Vector2 = Vector2(minf(560.0, viewport_size.x - 48.0), minf(460.0, viewport_size.y - 48.0))
	panel.position = (viewport_size - panel_size) * 0.5
	panel.size = panel_size


func _layout_game_hud(viewport_size: Vector2) -> void:
	var scale_factor: float = clampf(minf(
		viewport_size.x / BASE_VIEWPORT_SIZE.x,
		viewport_size.y / BASE_VIEWPORT_SIZE.y
	), 0.85, 1.25)
	game_hud_root.scale = Vector2(scale_factor, scale_factor)

	var logical_size: Vector2 = viewport_size / scale_factor
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


func _on_world_tile_changed(tile: Vector2i, terrain_name: String) -> void:
	if status_label == null or world == null:
		return

	status_label.text = "Tile: %s,%s  Terrain: %s  Sprite tile: 32x16\n%s" % [
		tile.x,
		tile.y,
		terrain_name,
		world.get_generation_summary(),
	]


func _on_colony_changed(summary_lines: Array[String]) -> void:
	if colony_label == null:
		return
	colony_label.text = "\n".join(summary_lines)
	if objective_label != null and world != null and world.colony_state != null:
		objective_label.text = "Objective: %s" % world.colony_state.get_primary_objective()


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
