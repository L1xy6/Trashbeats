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
	for step in [0, 4, 8, 12]:
		seq._cells[0][step].set_note(true, false, 0)
		seq._sync_cell(seq._cells[0][step], false)
	for step in [4, 12]:
		seq._cells[1][step].set_note(true, false, 0)
		seq._sync_cell(seq._cells[1][step], false)
	await _capture("sequencer")
	# This fixture records the audio engine directly; keep UI auto-stop counters
	# out of the two independent demo takes.
	Audio.step_changed.disconnect(seq._on_step)
	var before: PackedFloat32Array = await _record_loop(4.0)
	seq._ai_continue()
	await _capture("continuation")
	var after: PackedFloat32Array = await _record_loop(4.0)
	before.append_array(after)
	DirAccess.make_dir_recursive_absolute("res://docs/audio")
	if not Audio.write_wav("res://docs/audio/quickstart-before-after.wav", before):
		printerr("Audio demo export failed")
		get_tree().quit(1)
		return
	print("Audio demo saved: 4 seconds of seeds, 4 seconds after continuation")
	Audio._player.stop()
	Audio._playback = null
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
func _record_loop(seconds: float) -> PackedFloat32Array:
	Audio.stop()
	Audio._voices.clear()
	Audio.bpm = 120.0
	Audio.start_recording()
	Audio.start()
	Audio._next_step_pos = Audio._sample_counter
	var count := int(seconds * Audio.MIX_RATE)
	while Audio._rec_buffer.size() < count:
		await get_tree().process_frame
	Audio.stop()
	return Audio.stop_recording().slice(0, count)
