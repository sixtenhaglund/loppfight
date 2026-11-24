extends CanvasLayer
## LOPP FIGHT - all menus and the HUD. Everything is built in code with a "school paper" look:
## buttons are paper scraps with ink borders, panels are lined notebook paper, titles are in marker.

const MARKER := preload("res://assets/fonts/PermanentMarker-Regular.ttf")
const HAND := preload("res://assets/fonts/PatrickHand-Regular.ttf")
const INK := Color(0.12, 0.12, 0.18)
const PAPER := Color(0.97, 0.96, 0.91)
const HILITE := Color(1.0, 0.9, 0.42)     # yellow highlighter

var main
var root: Control
var screens := {}
var back_to := "menu"        # where "Back" in settings goes
var hud: Control
var msg: Label
var fps_label: Label
var hint: Label
var ghost := [100.0, 100.0]  # the lighter bar that drains after a hit
var buttons := {}            # buttons whose text changes (settings)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # menus must work while the game is paused
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_hud()
	_build_menu()
	_build_settings()
	_build_howto()
	_build_pause()
	_build_match_over()
	fps_label = Label.new()
	fps_label.add_theme_font_size_override("font_size", 20)
	_outline(fps_label, 4)
	fps_label.position = Vector2(10, 4)
	fps_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.add_child(fps_label)


# ================================================================ look
func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = HAND
	th.default_font_size = 30
	var normal := _box(PAPER, 3, Vector2(3, 4))
	var hover := _box(HILITE, 3, Vector2(3, 4))
	var pressed := _box(Color(0.86, 0.84, 0.78), 3, Vector2(1, 1))
	for type in ["Button"]:
		th.set_stylebox("normal", type, normal)
		th.set_stylebox("hover", type, hover)
		th.set_stylebox("pressed", type, pressed)
		th.set_stylebox("focus", type, StyleBoxEmpty.new())
		th.set_stylebox("disabled", type, normal)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			th.set_color(c, type, INK)
	th.set_color("font_color", "Label", INK)
	# volume slider: an ink line with a paper knob
	var line := StyleBoxFlat.new()
	line.bg_color = INK
	line.content_margin_top = 3
	line.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.45, 0.85)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	th.set_stylebox("slider", "HSlider", line)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return th


func _box(col: Color, border: int, shadow: Vector2) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.border_color = INK
	b.set_border_width_all(border)
	b.set_corner_radius_all(3)
	b.content_margin_left = 22
	b.content_margin_right = 22
	b.content_margin_top = 6
	b.content_margin_bottom = 8
	b.shadow_color = Color(0, 0, 0, 0.35)
	b.shadow_size = 2
	b.shadow_offset = shadow
	return b


func _on_button(cb: Callable) -> void:
	if main:
		main.ui_click()
	cb.call()


func _outline(l: Label, size: int) -> void:
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", size)


func _button(text: String, cb: Callable, min_w := 300) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 0)
	b.pressed.connect(_on_button.bind(cb))
	b.mouse_entered.connect(func(): b.rotation_degrees = randf_range(-1.5, 1.5))   # wobbly paper scrap
	b.mouse_exited.connect(func(): b.rotation_degrees = 0.0)
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	return b


## A lined notebook-paper panel in the middle of the screen
class PaperPanel extends PanelContainer:
	func _draw() -> void:
		var y := 62.0
		while y < size.y - 8:
			draw_line(Vector2(6, y), Vector2(size.x - 6, y), Color(0.55, 0.68, 0.88, 0.55), 2.0)
			y += 36.0
		draw_line(Vector2(54, 4), Vector2(54, size.y - 4), Color(0.88, 0.4, 0.4, 0.7), 2.0)


func _panel(title: String) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()          # darken the game behind the panel
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(shade)
	holder.add_child(center)
	var p := PaperPanel.new()
	var sb := _box(PAPER, 3, Vector2(6, 8))
	sb.content_margin_left = 80
	sb.content_margin_right = 50
	sb.content_margin_top = 18
	sb.content_margin_bottom = 26
	p.add_theme_stylebox_override("panel", sb)
	p.rotation_degrees = randf_range(-1.2, 1.2)
	p.resized.connect(func(): p.pivot_offset = p.size / 2.0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", MARKER)
	t.add_theme_font_size_override("font_size", 46)
	t.add_theme_color_override("font_color", Color(0.75, 0.12, 0.12))
	v.add_child(t)
	root.add_child(holder)
	return [holder, v]


# ================================================================ button actions
func _back_from_settings() -> void:
	show_screen(back_to)


func _open_settings(from: String) -> void:
	back_to = from
	show_screen("settings")


func _on_difficulty() -> void:
	Game.difficulty = (Game.difficulty + 1) % 3
	Game.save_settings()
	_refresh()


func _on_quality() -> void:
	Game.quality = (Game.quality + 1) % 3
	Game.save_settings()
	main.apply_graphics()
	_refresh()


func _on_volume(x: float) -> void:
	Game.volume = x
	Game.apply_audio()


func _on_shake() -> void:
	Game.shake = not Game.shake
	Game.save_settings()
	_refresh()


func _on_fps() -> void:
	Game.show_fps = not Game.show_fps
	Game.save_settings()
	_refresh()


func _on_fullscreen() -> void:
	Game.fullscreen = not Game.fullscreen
	Game.save_settings()
	if Game.is_web():
		# browsers only allow fullscreen straight from a click, which is where we are now
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if Game.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		Game.apply_window()
	_refresh()


# ================================================================ screens
func _build_menu() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := TextureRect.new()      # dark fade on the left so the text is readable
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.65))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.custom_minimum_size = Vector2(700, 0)
	grad.size = Vector2(700, 0)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(grad)
	var v := VBoxContainer.new()
	v.position = Vector2(70, 60)
	v.add_theme_constant_override("separation", 14)
	holder.add_child(v)
	var title := Label.new()
	title.text = "LOPP\nFIGHT"
	title.add_theme_font_override("font", MARKER)
	title.add_theme_font_size_override("font_size", 104)
	title.add_theme_constant_override("line_spacing", -34)
	_outline(title, 18)
	title.rotation_degrees = -4
	v.add_child(title)
	var sub := Label.new()
	sub.text = "paper fortune tellers. real rips. no mercy."
	sub.add_theme_font_size_override("font_size", 26)
	_outline(sub, 6)
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	v.add_child(gap)
	var fight := _button("FIGHT!", func(): main.start_match())
	fight.add_theme_font_override("font", MARKER)
	fight.add_theme_font_size_override("font_size", 40)
	v.add_child(fight)
	buttons["difficulty"] = _button("", _on_difficulty)
	v.add_child(buttons["difficulty"])
	v.add_child(_button("How to play", func(): show_screen("howto")))
	v.add_child(_button("Settings", _open_settings.bind("menu")))
	if not Game.is_web():
		v.add_child(_button("Quit", func(): get_tree().quit()))
	screens["menu"] = holder
	root.add_child(holder)


func _build_settings() -> void:
	var r := _panel("Settings")
	var v: VBoxContainer = r[1]
	buttons["quality"] = _button("", _on_quality, 420)
	v.add_child(buttons["quality"])
	var note := Label.new()
	note.text = "(paper detail changes from the next round)"
	note.add_theme_font_size_override("font_size", 20)
	v.add_child(note)
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 16)
	var vl := Label.new()
	vl.text = "Volume"
	vol_row.add_child(vl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Game.volume
	slider.custom_minimum_size = Vector2(260, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_volume)
	slider.drag_ended.connect(func(_c): Game.save_settings())
	vol_row.add_child(slider)
	v.add_child(vol_row)
	buttons["shake"] = _button("", _on_shake, 420)
	v.add_child(buttons["shake"])
	buttons["fps"] = _button("", _on_fps, 420)
	v.add_child(buttons["fps"])
	buttons["fullscreen"] = _button("", _on_fullscreen, 420)
	v.add_child(buttons["fullscreen"])
	v.add_child(_button("Back", _back_from_settings, 420))
	screens["settings"] = r[0]


func _build_howto() -> void:
	var r := _panel("How to play")
	var v: VBoxContainer = r[1]
	var l := Label.new()
	l.text = "WASD - hop around (you always face the enemy)\n" + \
		"Hold LEFT CLICK or J - open your jaws, let go to BITE\n" + \
		"      hold longer = bigger bite, longer rips\n" + \
		"RIGHT CLICK or K - SMASH: jump and slam face-first\n" + \
		"      crumples them, but missing leaves you dizzy\n" + \
		"SPACE - dodge hop to the side\n" + \
		"E / SHIFT / MIDDLE CLICK - BASH: ram them with your body\n" + \
		"      little damage, huge knockback - push them off the desk!\n" + \
		"Esc or P - pause\n\n" + \
		"Rips run along the paper and love following creases.\n" + \
		"Tear off a whole point and they lose a lot of HP.\n" + \
		"Knock them off the desk = instant win. Best of 3 rounds!"
	l.add_theme_font_size_override("font_size", 26)
	v.add_child(l)
	v.add_child(_button("Back", func(): show_screen("menu")))
	screens["howto"] = r[0]


func _build_pause() -> void:
	var r := _panel("Paused")
	var v: VBoxContainer = r[1]
	v.add_child(_button("Resume", func(): main.set_paused(false)))
	v.add_child(_button("Restart match", func(): main.start_match()))
	v.add_child(_button("Settings", _open_settings.bind("pause")))
	v.add_child(_button("Main menu", func(): main.to_menu()))
	screens["pause"] = r[0]


func _build_match_over() -> void:
	var r := _panel("")
	var v: VBoxContainer = r[1]
	buttons["over_title"] = v.get_child(0)
	var score := Label.new()
	score.add_theme_font_size_override("font_size", 34)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(score)
	buttons["over_score"] = score
	v.add_child(_button("Rematch", func(): main.start_match()))
	v.add_child(_button("Main menu", func(): main.to_menu()))
	screens["over"] = r[0]


func show_match_over(you_won: bool) -> void:
	buttons["over_title"].text = "YOU WIN THE MATCH!" if you_won else "THE CPU WINS..."
	buttons["over_score"].text = "%d - %d" % [Game.wins[0], Game.wins[1]]
	show_screen("over")


func show_screen(name: String) -> void:
	for k in screens:
		screens[k].visible = k == name
	hud.visible = name == "" or name == "pause" or name == "over"
	_refresh()


func _refresh() -> void:
	buttons["difficulty"].text = "Difficulty: " + Game.DIFF_NAMES[Game.difficulty]
	buttons["quality"].text = "Graphics: " + Game.QUALITY_NAMES[Game.quality]
	buttons["shake"].text = "Screen shake: " + ("On" if Game.shake else "Off")
	buttons["fps"].text = "Show FPS: " + ("On" if Game.show_fps else "Off")
	buttons["fullscreen"].text = "Fullscreen: " + ("On" if Game.fullscreen else "Off")


# ================================================================ HUD
class HudDraw extends Control:
	var ui

	func _draw() -> void:
		var m = ui.main
		if m == null or m.player == null:
			return
		var w := minf(460.0, size.x * 0.36)
		for side in 2:
			var l = m.player if side == 0 else m.cpu
			var x := 28.0 if side == 0 else size.x - 28.0 - w
			var y := 20.0
			var who: String = "YOU" if side == 0 else "CPU (" + String(Game.DIFF_NAMES[Game.difficulty]) + ")"
			var align := HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			draw_string_outline(ui.MARKER, Vector2(x, y + 26), who, align, w, 28, 8, ui.INK)
			draw_string(ui.MARKER, Vector2(x, y + 26), who, align, w, 28, Color.WHITE)
			var bar := Rect2(x, y + 36, w, 24)
			draw_rect(Rect2(bar.position + Vector2(3, 4), bar.size), Color(0, 0, 0, 0.35))
			draw_rect(bar, Color(0.15, 0.13, 0.13, 0.85))
			var f := clampf(l.hp / 100.0, 0.0, 1.0)
			var gf := clampf(ui.ghost[side] / 100.0, 0.0, 1.0)
			var col := Color(0.97, 0.96, 0.9).lerp(Color(0.9, 0.18, 0.12), 1.0 - f)
			if side == 0:
				draw_rect(Rect2(bar.position, Vector2(w * gf, bar.size.y)), Color(1.0, 0.75, 0.3))
				draw_rect(Rect2(bar.position, Vector2(w * f, bar.size.y)), col)
			else:
				draw_rect(Rect2(bar.position + Vector2(w * (1.0 - gf), 0), Vector2(w * gf, bar.size.y)), Color(1.0, 0.75, 0.3))
				draw_rect(Rect2(bar.position + Vector2(w * (1.0 - f), 0), Vector2(w * f, bar.size.y)), col)
			draw_rect(bar, ui.INK, false, 3.0)
			# round wins: little marker dots
			for i in Game.WINS_NEEDED:
				var cx := x + 14 + i * 30 if side == 0 else x + w - 14 - i * 30
				var c := Vector2(cx, y + 78)
				draw_circle(c, 10, ui.INK)
				draw_circle(c, 7, Color(0.95, 0.75, 0.15) if Game.wins[side] > i else Color(0.3, 0.3, 0.32))
		# round number in the middle
		var rt := "ROUND " + str(Game.round_no)
		draw_string_outline(ui.MARKER, Vector2(0, 52), rt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, 8, ui.INK)
		draw_string(ui.MARKER, Vector2(0, 52), rt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color.WHITE)
		# bite charge meter
		var p = m.player
		if p.state == "charge":
			var c := clampf(p.charge_t / p.CHARGE_TIME, 0.0, 1.0)
			var bw := 240.0
			var r := Rect2(size.x / 2 - bw / 2, size.y - 110, bw, 18)
			draw_rect(r, Color(0.15, 0.13, 0.13, 0.85))
			draw_rect(Rect2(r.position, Vector2(bw * c, r.size.y)), Color(0.95, 0.3, 0.2) if c >= 1.0 else Color(1.0, 0.85, 0.3))
			draw_rect(r, ui.INK, false, 3.0)
			var txt := "MAX BITE!" if c >= 1.0 else "BITE"
			draw_string_outline(ui.MARKER, Vector2(0, r.position.y - 8), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, 7, ui.INK)
			draw_string(ui.MARKER, Vector2(0, r.position.y - 8), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color.WHITE)


func _build_hud() -> void:
	hud = HudDraw.new()
	hud.ui = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	msg = Label.new()
	msg.add_theme_font_override("font", MARKER)
	msg.add_theme_font_size_override("font_size", 96)
	_outline(msg, 22)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg.offset_bottom = -200
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(msg)
	hint = Label.new()
	hint.text = "WASD move  ·  hold LEFT CLICK = bite  ·  RIGHT CLICK = smash  ·  SPACE = dodge  ·  E = bash  ·  Esc = pause"
	hint.add_theme_font_size_override("font_size", 22)
	_outline(hint, 6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -40
	hint.offset_bottom = -8
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hint)


## Big text in the middle that pops in (ROUND 1, FIGHT!, K.O.!)
func say(text: String, hold := 1.2) -> void:
	msg.text = text
	msg.pivot_offset = msg.size / 2.0
	msg.scale = Vector2(1.6, 1.6)
	msg.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(msg, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hold > 0.0:
		tw.tween_interval(hold)
		tw.tween_property(msg, "modulate:a", 0.0, 0.3)


func _process(delta: float) -> void:
	if main and main.player:
		for side in 2:
			var hp: float = (main.player if side == 0 else main.cpu).hp
			ghost[side] = hp if hp > ghost[side] else move_toward(ghost[side], hp, 40.0 * delta)
		hud.queue_redraw()
	fps_label.visible = Game.show_fps
	if Game.show_fps:
		fps_label.text = "%d fps" % Engine.get_frames_per_second()
		fps_label.position = Vector2(root.size.x / 2 - 40, root.size.y - 70)
	hint.modulate.a = clampf(1.0 - (main.t - 8.0) / 2.0, 0.25, 1.0) if main else 1.0
