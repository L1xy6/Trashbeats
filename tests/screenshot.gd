extends Node
## Screenshot fixture. Requires an isolated APPDATA directory containing
## trashbeats-capture and TRASHBEATS_CAPTURE_ONLY=1. Never uses real input.

func _ready() -> void:
	if OS.get_environment("TRASHBEATS_CAPTURE_ONLY") != "1" or "trashbeats-capture" not in OS.get_user_data_dir():
		printerr("Use a separate trashbeats-capture APPDATA directory for screenshots.")
		get_tree().quit(2)
		return
	seed(42)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("res://docs/images")
	await _capture("cover")
	main._go_to(1)
	await _capture("sound-library")
	main._go_to(3)
	var seq = main._screens[3]
	var pid = GameState.new_project("拾音练习 / Found sounds", 16)
	seq._open_project(pid)
	for t in 4:
		for step in seq.DEFAULT_PATTERNS[t].size():
			if seq.DEFAULT_PATTERNS[t][step] == 1:
				var cell = seq._cells[t][step]
				cell.set_note(true, false, 0)
				seq._sync_cell(cell, false)
	await _capture("sequencer")
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _capture(name: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var path = "res://docs/images/%s.png" % name
	var result = img.save_png(path)
	if result != OK:
		printerr("Screenshot failed: ", path)
		get_tree().quit(1)
	print("Screenshot saved: ", path)