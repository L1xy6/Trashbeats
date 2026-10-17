class_name CoverScreen
extends Control
## 01 封面 — TrashBeats title screen with drifting pixel particles.

signal request_screen(idx: int)

func _ready() -> void:
	UIKit.full_rect(self)

	var center = VBoxContainer.new()
	UIKit.full_rect(center)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 18)
	add_child(center)

	var tag = UIKit.label("MTX · 音乐交互线上1组 · 2026", 13, UIKit.COL_MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(tag)

	var title = UIKit.label("TRASHBEATS", 64, UIKit.COL_NEON, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	var sub = UIKit.label("拾音 · 捡到一首歌", 26, UIKit.COL_NEON)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(sub)

	var pitch = UIKit.label("用捡来的垃圾当乐器，用 AI 辅助编曲。\n把环保行为，变成音乐创作的第一步。", 16, UIKit.COL_TEXT)
	pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(pitch)

	var start_btn = UIKit.button("▶ PRESS START · 开始寻宝", UIKit.COL_NEON, 18)
	start_btn.custom_minimum_size = Vector2(320, 52)
	var btn_wrap = CenterContainer.new()
	btn_wrap.add_child(start_btn)
	center.add_child(btn_wrap)
	start_btn.pressed.connect(func(): request_screen.emit(1))

	var hint = UIKit.label("← → 方向键切换页面", 12, UIKit.COL_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(hint)

	# blinking start button, like an arcade attract mode
	var blink = create_tween().set_loops()
	blink.tween_property(start_btn, "modulate:a", 0.35, 0.7)
	blink.tween_property(start_btn, "modulate:a", 1.0, 0.7)

	_spawn_particles()

func _spawn_particles() -> void:
	# floating pixel squares, mirroring coverFx in index.html
	for i in 44:
		var p = ColorRect.new()
		var size = 5.0 + randf() * 14.0
		p.custom_minimum_size = Vector2(size, size)
		p.size = Vector2(size, size)
		p.position = Vector2(randf() * 1280.0, randf() * 720.0)
		p.color = UIKit.COL_NEON
		p.color.a = 0.05 + randf() * 0.15
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)
		p.set_meta("base", p.position)
		_drift(p)

func _drift(p: ColorRect) -> void:
	if not is_instance_valid(p):
		return
	var base: Vector2 = p.get_meta("base")
	var tw = create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "position", base + Vector2(randf_range(-30, 30), randf_range(-20, 20)), randf_range(4.0, 9.0))
	tw.tween_callback(func(): _drift(p))

func on_enter() -> void:
	pass

func on_exit() -> void:
	pass
