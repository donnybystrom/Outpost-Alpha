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
	await process_frame

	var world := root.get_node_or_null("IsoWorld")
	var camera := root.get_node_or_null("IsoCamera")
	if world == null or camera == null:
		push_error("Main scene did not create the expected world and camera nodes.")
		quit(1)
		return

	quit(0)
