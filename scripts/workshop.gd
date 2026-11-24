extends CanvasLayer
## MY LOPP - the workshop: draw on your lopp and buy upgrades with coins.
## Everything you do is saved in Game.loadout / Game.paint (and on disk) and used in every fight.
##
## Mouse:  LEFT = use the tool on the lopp   RIGHT-drag or A/D = turn around it   wheel = zoom   R = rotate

const UIScript := preload("res://scripts/ui.gd")
const LoppScript := preload("res://scripts/lopp.gd")
const COLORS := [Color(0.1, 0.1, 0.13), Color(0.85, 0.12, 0.12), Color(0.13, 0.33, 0.85), Color(0.12, 0.6, 0.22),
	Color(0.98, 0.82, 0.1), Color(0.55, 0.15, 0.75), Color(0.98, 0.5, 0.08), Color(0.95, 0.35, 0.65), Color(0.45, 0.28, 0.15)]

var main
var tool := "draw"            # draw / erase / tape / glue / shield / rod
var color: Color = COLORS[0]
var brush := 0.05
var place_rot := 0.0          # R turns shields and rods
var holding := false
var last_pos := Vector3.INF
var stroke: Array = []        # points of the tape / glue you are putting on right now
var stroke_n: Array = []
var undo: Array = []          # what you did, newest last (so it can be undone + refunded)

var root: Control
var info: Label
var coins_lbl: Label
var tool_btns := {}
var layer_btn: Button
var teeth_btn: Button
var swatches: HBoxContainer
var size_row: HBoxContainer
var preview_mi: MeshInstance3D      # tape / glue you are putting on (before you let go)
var ghost: MeshInstance3D           # shield / rod following your mouse
var ghost_kind := ""
var rotating := false


func _ready() -> void:
	layer = 9
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = main.ui.root.theme
	add_child(root)
	_build_panel()
	preview_mi = MeshInstance3D.new()
	preview_mi.mesh = ImmediateMesh.new()
	preview_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(preview_mi)
	_set_tool("draw")


# ================================================================ panel
func _build_panel() -> void:
	var p := UIScript.PaperPanel.new()
	var sb: StyleBoxFlat = main.ui._box(UIScript.PAPER, 3, Vector2(5, 6))
	sb.content_margin_left = 70
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(20, 20)
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var title := Label.new()
	title.text = "My lopp"
	title.add_theme_font_override("font", UIScript.MARKER)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.75, 0.12, 0.12))
	v.add_child(title)
	coins_lbl = Label.new()
	coins_lbl.add_theme_font_size_override("font_size", 28)
	v.add_child(coins_lbl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for t in [["draw", "Draw"], ["erase", "Eraser"], ["tape", "Tape  2/bit"], ["glue", "Glue  1/dab"],
			["shield", "Shield  60"], ["rod", "Paper rod  40"]]:
		var b: Button = main.ui._button(t[1], _set_tool.bind(t[0]), 190)
		b.add_theme_font_size_override("font_size", 24)
		grid.add_child(b)
		tool_btns[t[0]] = b
	swatches = HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 4)
	for c in COLORS:
		var s := Button.new()
		s.custom_minimum_size = Vector2(36, 36)
		var st: StyleBoxFlat = main.ui._box(c, 3, Vector2(1, 2))
		st.content_margin_left = 0
		st.content_margin_right = 0
		s.add_theme_stylebox_override("normal", st)
		s.add_theme_stylebox_override("hover", st)
		s.add_theme_stylebox_override("pressed", st)
		s.pressed.connect(_pick_color.bind(c))
		swatches.add_child(s)
	v.add_child(swatches)
	size_row = HBoxContainer.new()
	var sl := Label.new()
	sl.text = "Size"
	sl.add_theme_font_size_override("font_size", 24)
	size_row.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 0.02
	slider.max_value = 0.16
	slider.step = 0.005
	slider.value = brush
	slider.custom_minimum_size = Vector2(250, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_set_brush)
	size_row.add_child(slider)
	v.add_child(size_row)
	layer_btn = main.ui._button("", _toggle_layer, 386)
	layer_btn.add_theme_font_size_override("font_size", 24)
	v.add_child(layer_btn)
	teeth_btn = main.ui._button("", _toggle_teeth, 386)
	teeth_btn.add_theme_font_size_override("font_size", 24)
	v.add_child(teeth_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var ub: Button = main.ui._button("Undo", _undo, 120)
	var cb: Button = main.ui._button("Clear drawing", _clear_drawing, 260)
	for b in [ub, cb]:
		b.add_theme_font_size_override("font_size", 24)
		row.add_child(b)
	v.add_child(row)
	var done: Button = main.ui._button("Done", _done, 386)
	done.add_theme_font_override("font", UIScript.MARKER)
	v.add_child(done)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 24)
	_outline(info)
	info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_top = -78
	info.offset_bottom = -12
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)


func _outline(l: Label) -> void:
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", UIScript.INK)
	l.add_theme_constant_override("outline_size", 7)


func _refresh() -> void:
	coins_lbl.text = "%d coins" % Game.coins
	for k in tool_btns:
		tool_btns[k].modulate = Color(1, 0.9, 0.4) if k == tool else Color.WHITE
	swatches.visible = tool == "draw"
	size_row.visible = tool == "draw" or tool == "erase"
	if Game.loadout.layer:
		layer_btn.text = "Extra layer: ON  (remove, +%d back)" % (Game.PRICES.layer / 2)
	else:
		layer_btn.text = "Buy extra layer  (%d)" % Game.PRICES.layer
	if Game.loadout.teeth:
		teeth_btn.text = "Paper teeth: ON  (remove, +%d back)" % (Game.PRICES.teeth / 2)
	else:
		teeth_btn.text = "Buy paper teeth  (%d)" % Game.PRICES.teeth
	info.text = {
		"draw": "Draw on your lopp with markers. Hold LEFT mouse and paint.  Right-drag / A D = turn,  wheel = zoom",
		"erase": "Erase your drawing.",
		"tape": "TAPE: press on the paper and drag. The tape follows your mouse over the folds. 2 coins per bit. Taped paper almost can't rip.",
		"glue": "GLUE: paint glue on. It dries stiff and shiny: tougher paper that bends less. 1 coin per dab.",
		"shield": "SHIELD: 6 sheets of paper glued together. Click to stick it on, R = rotate. It catches hits until it crumples and falls off. 60 coins.",
		"rod": "PAPER ROD: rolled-up paper glued on. Smash and bash hit harder. Click to stick it on, R = rotate. 40 coins.",
	}[tool]


func _set_tool(t: String) -> void:
	tool = t
	_refresh()


func _pick_color(c: Color) -> void:
	color = c
	_set_tool("draw")


func _set_brush(x: float) -> void:
	brush = x


# ================================================================ buying / undo
func _spend(cost: int) -> bool:
	if Game.coins < cost:
		info.text = "Not enough coins! Win fights to earn more."
		return false
	Game.coins -= cost
	return true


func _commit(entry: Dictionary, rebuild := true) -> void:
	undo.append(entry)
	Game.save_lopp()
	if rebuild:
		main.rebuild_player()
	_refresh()


func _toggle_layer() -> void:
	if Game.loadout.layer:
		Game.loadout.layer = false
		Game.coins += Game.PRICES.layer / 2
		_commit({"kind": "layer_off"})
	elif _spend(Game.PRICES.layer):
		Game.loadout.layer = true
		_commit({"kind": "layer", "cost": Game.PRICES.layer})


func _toggle_teeth() -> void:
	if Game.loadout.teeth:
		Game.loadout.teeth = false
		Game.coins += Game.PRICES.teeth / 2
		_commit({"kind": "teeth_off"})
	elif _spend(Game.PRICES.teeth):
		Game.loadout.teeth = true
		_commit({"kind": "teeth", "cost": Game.PRICES.teeth})


func _clear_drawing() -> void:
	undo.append({"kind": "paint", "before": Game.paint.duplicate()})
	Game.paint.fill(Color(0, 0, 0, 0))
	main.player.paint_dirty = true
	Game.save_lopp()


func _undo() -> void:
	if undo.is_empty():
		return
	var e: Dictionary = undo.pop_back()
	var lo: Dictionary = Game.loadout
	match e.kind:
		"paint":
			Game.paint.copy_from(e.before)
			main.player.paint_dirty = true
			Game.save_lopp()
			return
		"tape":
			lo.tapes.pop_back()
		"glue":
			lo.glue.resize(lo.glue.size() - int(e.count))
		"shield":
			lo.shields.pop_back()
		"rod":
			lo.rods.pop_back()
		"layer":
			lo.layer = false
		"teeth":
			lo.teeth = false
		"layer_off":
			if not _spend(Game.PRICES.layer / 2):
				undo.append(e)
				return
			lo.layer = true
		"teeth_off":
			if not _spend(Game.PRICES.teeth / 2):
				undo.append(e)
				return
			lo.teeth = true
	Game.coins += int(e.get("cost", 0))
	Game.save_lopp()
	main.rebuild_player()
	_refresh()


func _done() -> void:
	Game.save_lopp()
	preview_mi.queue_free()
	main.to_menu()


# ================================================================ using the tools on the lopp
func _pick() -> Dictionary:
	var mp := root.get_viewport().get_mouse_position()
	return main.player.pick(main.cam.project_ray_origin(mp), main.cam.project_ray_normal(mp))


func _to_world(p: Vector3) -> Vector3:
	return (main.player.global_transform * Transform3D(Basis(), LoppScript.VIS_OFF)) * p


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			rotating = e.pressed
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			main.ws_dist = maxf(2.8, main.ws_dist - 0.35)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			main.ws_dist = minf(9.0, main.ws_dist + 0.35)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press()
			else:
				_release()
	elif e is InputEventMouseMotion:
		if rotating:
			main.ws_yaw -= e.relative.x * 0.008
			main.ws_pitch = clampf(main.ws_pitch + e.relative.y * 0.006, -0.25, 1.3)
		elif holding:
			_drag()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_R:
			place_rot += PI / 8.0
		elif e.physical_keycode == KEY_ESCAPE:
			_done()


func _process(delta: float) -> void:
	var turn := Input.get_axis("left", "right")
	main.ws_yaw -= turn * delta * 1.6
	# shield / rod ghost follows the mouse
	var want_ghost := tool if tool == "shield" or tool == "rod" else ""
	if want_ghost != ghost_kind:
		if ghost:
			ghost.queue_free()
			ghost = null
		ghost_kind = want_ghost
		if ghost_kind != "":
			ghost = MeshInstance3D.new()
			ghost.mesh = LoppScript.make_att_mesh(ghost_kind)
			var gm := LoppScript.make_att_material(ghost_kind)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.albedo_color.a = 0.6
			ghost.material_override = gm
			main.add_child(ghost)
	if ghost:
		var h := _pick()
		ghost.visible = not h.is_empty()
		if ghost.visible:
			ghost.global_transform = _place_xform(h)


func _place_xform(h: Dictionary) -> Transform3D:
	var off: float = 0.05 if tool == "shield" else 0.07
	var b: Basis = main.player._att_basis(h.normal, place_rot)
	var lx := Transform3D(b, h.pos + h.normal * off)
	return main.player.global_transform * Transform3D(Basis(), LoppScript.VIS_OFF) * lx


func _press() -> void:
	var h := _pick()
	if h.is_empty():
		return
	match tool:
		"draw", "erase":
			holding = true
			undo.append({"kind": "paint", "before": Game.paint.duplicate()})
			last_pos = h.pos
			main.player.paint_at(h.pos, brush, color, tool == "erase")
		"tape", "glue":
			holding = true
			stroke = [h.pos]
			stroke_n = [h.normal]
			_draw_preview()
		"shield", "rod":
			var price: int = Game.PRICES[tool]
			if _spend(price):
				var list: Array = Game.loadout.shields if tool == "shield" else Game.loadout.rods
				list.append([h.pos, h.normal, place_rot])
				_commit({"kind": tool, "cost": price})
				main.sfx("crumple", _to_world(h.pos), -6.0)


func _drag() -> void:
	var h := _pick()
	if h.is_empty():
		return
	match tool:
		"draw", "erase":
			# fill in dots between mouse positions so fast strokes stay a line
			var steps := int(ceilf(last_pos.distance_to(h.pos) / (brush * 0.4)))
			for i in range(1, steps + 1):
				main.player.paint_at(last_pos.lerp(h.pos, float(i) / steps), brush, color, tool == "erase")
			last_pos = h.pos
		"tape", "glue":
			var step := 0.1 if tool == "tape" else 0.09
			var last: Vector3 = stroke[-1]
			if last.distance_to(h.pos) < step:
				return
			var cost: int = Game.PRICES[tool]
			if Game.coins < _stroke_cost() + cost:
				info.text = "Not enough coins for more " + tool + "!"
				return
			stroke.append(h.pos)
			stroke_n.append(h.normal)
			_draw_preview()
			coins_lbl.text = "%d coins  (-%d)" % [Game.coins, _stroke_cost()]


func _stroke_cost() -> int:
	if tool == "tape":
		return (stroke.size() - 1) * Game.PRICES.tape
	return stroke.size() * Game.PRICES.glue


func _release() -> void:
	if not holding:
		return
	holding = false
	match tool:
		"draw", "erase":
			Game.save_lopp()
		"tape":
			if stroke.size() >= 2:
				var cost := _stroke_cost()
				Game.coins -= cost
				Game.loadout.tapes.append(PackedVector3Array(stroke))
				_commit({"kind": "tape", "cost": cost})
				main.sfx("open", _to_world(stroke[0]), -4.0)
		"glue":
			var cost := _stroke_cost()
			Game.coins -= cost
			for p in stroke:
				Game.loadout.glue.append(p)
			_commit({"kind": "glue", "cost": cost, "count": stroke.size()})
	stroke = []
	stroke_n = []
	(preview_mi.mesh as ImmediateMesh).clear_surfaces()


## Show the tape / glue you are putting on before you let go of the mouse
func _draw_preview() -> void:
	var im: ImmediateMesh = preview_mi.mesh
	im.clear_surfaces()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.95, 0.95, 0.8, 0.55) if tool == "tape" else Color(1.0, 0.92, 0.5, 0.5)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, m)
	var xf: Transform3D = main.player.global_transform * Transform3D(Basis(), LoppScript.VIS_OFF)
	if tool == "tape":
		for i in range(stroke.size() - 1):
			var p0: Vector3 = stroke[i]
			var p1: Vector3 = stroke[i + 1]
			var n: Vector3 = stroke_n[i]
			var side: Vector3 = (p1 - p0).cross(n).normalized() * LoppScript.TAPE_HALF
			var q := [p0 + side + n * 0.01, p0 - side + n * 0.01, p1 + side + n * 0.01, p1 - side + n * 0.01]
			for k in [0, 2, 1, 1, 2, 3]:
				im.surface_add_vertex(xf * (q[k] as Vector3))
	else:
		for i in stroke.size():
			var c: Vector3 = stroke[i]
			var n: Vector3 = stroke_n[i]
			var a := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized() * 0.12
			var b := n.cross(a).normalized() * 0.12
			var q := [c - a - b + n * 0.01, c + a - b + n * 0.01, c - a + b + n * 0.01, c + a + b + n * 0.01]
			for k in [0, 2, 1, 1, 2, 3]:
				im.surface_add_vertex(xf * (q[k] as Vector3))
	im.surface_end()
