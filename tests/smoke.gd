extends Node
## Run through tests/run_smoke.ps1. It stages an isolated project and save folder.
## No external service, physical microphone, camera, or real user save is used.

var _failures := 0
var _checks := 0

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS  ", what)
	else:
		_failures += 1
		printerr("FAIL  ", what)

func _ready() -> void:
	var marker := OS.get_environment("TRASHBEATS_TEST_RUN_ID")
	if marker.is_empty() or not OS.get_user_data_dir().replace("\\", "/").ends_with("Trashbeats-SmokeTests/" + marker):
		printerr("Refusing unisolated smoke test. Use tests/run_smoke.ps1.")
		get_tree().quit(2)
		return
	if ProjectSettings.get_setting("audio/driver/enable_input", true):
		printerr("Refusing smoke test with audio input enabled.")
		get_tree().quit(2)
		return
	Audio.set_process(false)
	seed(20261017)
	_test_synthesis_and_sound_edit()
	_test_persistence()
	_test_transport()
	await _test_sequencer()
	await _test_missing_credentials()
	# Release the generator playback reference before quitting the headless driver.
	Audio._player.stop()
	Audio._playback = null
	await get_tree().process_frame
	print("SMOKE TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _test_synthesis_and_sound_edit() -> void:
	var buffers := [Synth.kick(44100), Synth.woodblock(44100), Synth.bell(44100), Synth.tom(44100)]
	for i in buffers.size():
		_check(buffers[i].size() > 1000, "preset %d produces an audio buffer" % i)
	_check(SoundEdit.process_hit(PackedFloat32Array()).is_empty(), "sound edit handles empty input")
	var source := PackedFloat32Array()
	source.resize(22050)
	for i in range(13230, 19845):
		source[i] = 0.7 * sin(float(i - 13230) * TAU * 440.0 / 22050.0) * exp(-float(i - 13230) / 1800.0)
	var edited := SoundEdit.process_hit(source, 22050)
	_check(edited.size() == 13230, "sound edit returns a 0.3-second hit at 44.1 kHz")
	var peak := 0.0
	var finite := true
	for sample in edited:
		finite = finite and is_finite(sample) and absf(sample) <= 1.0
		peak = maxf(peak, absf(sample))
	_check(finite and peak > 0.01, "sound edit returns finite, bounded, non-silent audio")
	_check(Audio.write_wav("user://samples/synthetic.wav", edited), "synthetic WAV export succeeds")
	var reloaded: PackedFloat32Array = Audio.read_wav("user://samples/synthetic.wav")
	_check(reloaded.size() == edited.size(), "WAV sample count survives export and import")
	var max_error := 0.0
	for i in reloaded.size():
		max_error = maxf(max_error, absf(reloaded[i] - edited[i]))
	_check(max_error < 0.0001, "WAV round trip stays within 16-bit PCM precision")

func _test_persistence() -> void:
	_check(GameState.list_projects().is_empty(), "fresh save does not create a phantom legacy arrangement")
	GameState.reset_progress()
	GameState.projects.clear()
	GameState._save_projects()
	var legacy := ConfigFile.new()
	legacy.load(GameState.SAVE_PATH)
	legacy.set_value("pat_t0", "s3_on", true)
	legacy.set_value("pat_t0", "s3_pitch", 2)
	legacy.save(GameState.SAVE_PATH)
	GameState._migrate_old_pattern()
	_check(GameState.projects.size() == 1 and GameState.projects[0].patterns.can[3].pitch == 2, "real legacy patterns still migrate with their notes")
	GameState._migrate_old_pattern()
	_check(GameState.projects.size() == 1 and GameState.load_patterns().is_empty(), "legacy migration runs once and clears old pattern sections")
	GameState.projects.clear()
	GameState._save_projects()
	GameState.mark_collected("can")
	GameState._load_state()
	_check(GameState.collected_count() == 1 and GameState.collected.can, "collection persists")
	var discovered: Dictionary = GameState.add_discovered("Test material", Color.GREEN, "Synthetic test fixture")
	var custom: Dictionary = GameState.add_custom_sound("Synthetic hit", "", "user://samples/synthetic.wav", Color.GREEN)
	_check(GameState.is_favorite(custom.id) and GameState.global_track_of(custom.id) >= 4, "custom sound joins the instrument library")
	GameState.mark_collected("glass")
	GameState.discovered.clear()
	GameState.custom_sounds.clear()
	GameState._load_discovered()
	GameState._load_custom()
	_check(not GameState.get_instrument(discovered.id).is_empty(), "collecting preserves discovered instruments on disk")
	_check(not GameState.get_instrument(custom.id).is_empty(), "collecting preserves custom sounds on disk")
	Audio.write_wav("user://samples/synthetic-second.wav", Synth.tom(44100))
	var second_custom: Dictionary = GameState.add_custom_sound("Second synthetic hit", "", "user://samples/synthetic-second.wav", Color.GREEN, GameState.next_custom_id())
	var a: String = GameState.new_project("First", 16)
	var b: String = GameState.new_project("Triplet", 12)
	var row := []
	row.resize(16)
	row[3] = {"on": true, "pitch": 5, "ai": false}
	GameState.save_project(a, ["can", "glass"], {"can": row}, 128.0)
	GameState.rename_project(a, "Saved groove")
	GameState._load_projects()
	var restored: Dictionary = GameState.load_project(a)
	_check(GameState.list_projects().size() == 2 and a != b, "multiple projects persist independently")
	_check(restored.name == "Saved groove" and restored.bpm == 128.0, "project name and BPM round trip")
	_check(restored.patterns.can[3].on and restored.patterns.can[3].pitch == 5, "notes persist by instrument ID")
	_check(GameState.load_project(b).get("steps") == 12 and restored.get("steps") == 16, "12-step and 16-step projects retain their grid sizes")
	GameState.delete_project(a)
	GameState._load_projects()
	_check(GameState.load_project(a).is_empty() and not GameState.load_project(b).is_empty(), "deleting one project preserves the other")
	GameState.remove_custom_sound(custom.id)
	GameState.custom_sounds.clear()
	GameState._load_custom()
	_check(GameState.get_instrument(custom.id).is_empty(), "deleted custom sound stays deleted after reload")
	_check(not GameState.get_instrument(second_custom.id).is_empty() and GameState.custom_sounds.size() == 1, "deleting a custom sound preserves exactly the remaining sound")

func _test_transport() -> void:
	Audio.stop()
	Audio.clear_pattern()
	Audio._voices.clear()
	# Fit two loops in the available buffer, so no wall-clock wait is required.
	var frame_budget: int = Audio._playback.get_frames_available()
	Audio.bpm = 44100.0 * 60.0 / (float(maxi(1, frame_budget / 32)) * 4.0)
	Audio.steps = 16
	Audio.set_cell(0, 0, {"pitch": 0, "vel": 1.0})
	var seen := []
	var positions := []
	var on_step := func(s: int):
		seen.append(s)
		positions.append(Audio._sample_counter)
	Audio.step_changed.connect(on_step)
	Audio.start_recording()
	Audio.start()
	Audio._next_step_pos = Audio._sample_counter
	Audio._process(0.0)
	Audio.stop()
	var recorded: PackedFloat32Array = Audio.stop_recording()
	Audio.step_changed.disconnect(on_step)
	_check(seen.size() >= 16, "sample-buffer advance runs a complete transport loop")
	var clock_ok := seen.size() > 1
	for i in seen.size():
		clock_ok = clock_ok and seen[i] == i % 16
		if i > 0:
			clock_ok = clock_ok and positions[i] - positions[i - 1] == Audio.samples_per_step()
	_check(clock_ok, "transport wraps and fires steps at exact sample offsets")
	_check(not Audio.playing and not Audio.is_recording() and recorded.size() > 1000, "transport and output recording stop cleanly")
	Audio.bpm = 120.0
	Audio.steps = 12
	_check(Audio.samples_per_step() == 7350, "12-step grid uses triplet subdivisions of four beats")
	Audio.steps = 16

func _grid_snapshot(seq: Control) -> Array:
	var result := []
	for row in seq._cells:
		var cells := []
		for cell in row:
			cells.append([cell.on, cell.ai, cell.pitch])
		result.append(cells)
	return result

func _test_sequencer() -> void:
	var seq: Control = load("res://scripts/screens/sequencer.gd").new()
	add_child(seq)
	var pid: String = GameState.new_project("Sequencer smoke", 16)
	seq._open_project(pid)
	_check(seq._cells.size() == 4 and seq._cells[0].size() == 16, "new project opens the current four-track editor")
	seq._clear_all()
	seq._ai_continue()
	var empty := _grid_snapshot(seq)
	var on_count := 0
	for row in seq._cells:
		for cell in row:
			on_count += int(cell.on)
	_check(on_count == 0, "local continuation refuses an empty grid")
	var cell = seq._cells[0][5]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(10, 10)
	click.pressed = true
	cell._gui_input(click)
	click.pressed = false
	cell._gui_input(click)
	_check(cell.on and Audio._patterns[0][5] != null, "click places a persistent note and updates the audio engine")
	for t in 4:
		seq._cells[t][0].set_note(true, false, t)
		seq._sync_cell(seq._cells[t][0], false)
	var before := _grid_snapshot(seq)
	seq._ai_continue()
	var generated := 0
	var seeds_preserved := true
	for t in 4:
		seeds_preserved = seeds_preserved and seq._cells[t][0].on and not seq._cells[t][0].ai and seq._cells[t][0].pitch == t
		for c in seq._cells[t]:
			generated += int(c.on and c.ai)
	_check(generated > 0 and seeds_preserved, "local continuation adds marked notes while preserving seeds")
	seq._undo_ai_continue()
	_check(_grid_snapshot(seq) == before and before != empty, "continuation undo restores the exact user grid")
	seq._save_current_patterns()
	var other: String = GameState.new_project("Other project", 12)
	seq._open_project(other)
	_check(seq._cells[0].size() == 12 and Audio._patterns[0][5] == null, "switching projects clears previous audio notes")
	seq._open_project(pid)
	_check(_grid_snapshot(seq) == before, "reopening a project restores its own notes")
	_check(seq._recorder == null, "opening sequencer does not start microphone capture")
	seq.queue_free()
	await get_tree().process_frame

func _test_missing_credentials() -> void:
	OS.unset_environment("TRASHBEATS_TIANQIN_APP_ID")
	OS.unset_environment("TRASHBEATS_TIANQIN_APP_KEY")
	var generator := MelodyGenerator.new()
	add_child(generator)
	var errors := []
	generator.error.connect(func(message: String): errors.append(message))
	_check(not MelodyGenerator.is_configured(), "online melody reports absent credentials")
	generator._current_task_id = "stale-test-task"
	await generator.generate("", "test", "user://must-not-exist.mp3")
	_check(errors.size() == 1 and errors[0] == MelodyGenerator.CONFIGURATION_ERROR, "missing credentials produce an actionable error immediately")
	_check(generator._current_task_id.is_empty() and generator._poll_timer.is_stopped(), "failed submission cannot resume a stale task")
	_check(not generator._busy and generator._http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED, "missing credentials never issue a network request")
	generator.start_polling("test", "user://must-not-exist.mp3")
	_check(generator._poll_timer.is_stopped() and not FileAccess.file_exists("user://must-not-exist.mp3"), "direct polling also refuses absent configuration")
	generator.queue_free()
	await get_tree().process_frame
