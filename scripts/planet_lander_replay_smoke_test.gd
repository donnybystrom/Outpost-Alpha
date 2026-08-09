extends SceneTree

const IsoWorld := preload("res://scripts/iso_world.gd")


func _initialize() -> void:
	var world := IsoWorld.new()
	root.add_child(world)
	await process_frame

	if not world.complete_starting_lander_landing():
		_fail("Initial Planet Lander landing should complete.")
		return
	var initial_marine_count := _marine_count(world)
	if initial_marine_count != 3:
		_fail("Initial landing should deploy three marines.")
		return
	if not world.reset_starting_lander_for_replay():
		_fail("Planet Lander should reset to descending for replay.")
		return
	var replay_lander: Dictionary = world.colony_state.get_nearest_building_of_type("planet_lander_module", world.map_data.start_tile)
	if replay_lander.get("operational", true) or replay_lander.get("landing_state", "") != "descending":
		_fail("Replay should hide and deactivate the landed model during descent.")
		return
	if not world.complete_starting_lander_landing(false):
		_fail("Replayed Planet Lander landing should complete.")
		return
	if _marine_count(world) != initial_marine_count:
		_fail("Landing replay must not duplicate the deployed marines.")
		return

	print("lander_replay_ok marines=%d" % initial_marine_count)
	quit(0)


func _marine_count(world: IsoWorld) -> int:
	var count := 0
	for unit in world.unit_state.workers:
		if unit.get("role", "") == "space_marine":
			count += 1
	return count


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
