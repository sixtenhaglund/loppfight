extends Node3D
## LOPP FIGHT - main scene: builds the desk, the light, the camera, the two lopps and the HUD.

const LoppScript := preload("res://scripts/lopp.gd")
const DEBRIS_MAX := 160

var desk_half := Vector2(15, 8)
var player
var cpu
var cam: Camera3D
var cam_attr: CameraAttributesPractical
var cam_shake := 0.0
var debris_root: Node3D
var debris: Array = []
var sounds := {}
var last_sfx := {}
var state := "intro"
var t := 0.0
var hitstop_until := 0
var ko_until := 0
var autotest := false
var hits := 0

var hp_fill := {}
var msg: Label
var hint: Label


func _ready() -> void:
	randomize()
	autotest = "autotest" in OS.get_cmdline_user_args()
	_inputs()
	_load_sounds()
	_environment()
	_desk()
	_props()
	debris_root = Node3D.new()
	add_child(debris_root)
	player = _make_lopp(Vector3(0, LoppScript.S + 0.05, 3.2), PI, 0, autotest)
	cpu = _make_lopp(Vector3(0, LoppScript.S + 0.05, -3.2), 0.0, 1, true)
	player.enemy = cpu
	cpu.enemy = player
	player.died.connect(_on_died)
	cpu.died.connect(_on_died)
	_camera()
	_hud()
	if autotest:
		print("AUTOTEST: cells per lopp = ", player.ncells, ", bonds = ", player.nbonds)


func _make_lopp(pos: Vector3, yaw: float, kind: int, ai: bool):
	var l = LoppScript.new()
	l.paper_kind = kind
	l.is_ai = ai
	l.main = self
	l.position = pos
	l.rotation.y = yaw
	add_child(l)
	return l


# ================================================================ input
func _key(action: String, keys: Array, mouse := -1) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	if mouse >= 0:
		var m := InputEventMouseButton.new()
		m.button_index = mouse
		InputMap.action_add_event(action, m)


func _inputs() -> void:
	_key("left", [KEY_A, KEY_LEFT])
	_key("right", [KEY_D, KEY_RIGHT])
	_key("up", [KEY_W, KEY_UP])
	_key("down", [KEY_S, KEY_DOWN])
	_key("bite", [KEY_J], MOUSE_BUTTON_LEFT)
	_key("smash", [KEY_K], MOUSE_BUTTON_RIGHT)
	_key("dodge", [KEY_SPACE])
	_key("restart", [KEY_R])
	_key("quit", [KEY_ESCAPE])


# ================================================================ sound (all cut from Sixten's own paper recordings)
func _load_sounds() -> void:
	var counts := {"snap": 3, "rip": 5, "crumple": 3, "flutter": 3, "hop": 3, "open": 3}
	for k in counts:
		sounds[k] = []
		for i in counts[k]:
			sounds[k].append(load("res://assets/sounds/%s_%d.wav" % [k, i]))
	sounds["thump"] = [load("res://assets/sounds/thump.wav")]


func sfx(name: String, pos: Vector3, db := 0.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(last_sfx.get(name, -1000)) < 50:
		return
	last_sfx[name] = now
	var p := AudioStreamPlayer3D.new()
	p.stream = sounds[name].pick_random()
	p.volume_db = db
	p.pitch_scale = randf_range(0.92, 1.08)
	p.unit_size = 8.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func add_debris(rb: RigidBody3D, pos: Vector3) -> void:
	debris_root.add_child(rb)
	rb.global_position = pos
	debris.append(rb)
	while debris.size() > DEBRIS_MAX:
		var old = debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func on_hit(_attacker, _victim, strength: float) -> void:
	hits += 1
	cam_shake = maxf(cam_shake, 0.08 + 0.12 * strength)
	hitstop_until = Time.get_ticks_msec() + int(40 + 50 * strength)   # tiny freeze = hits feel heavy


# ================================================================ world
func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/hdri/room.hdr")
	pm.energy_multiplier = 0.9
	sky.sky_material = pm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()   # window light
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_energy = 2.4
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.light_angular_distance = 2.0
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_blur = 1.5
	add_child(sun)


func _desk() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/textures/desk_diff.jpg")
	wood.normal_enabled = true
	wood.normal_texture = load("res://assets/textures/desk_nor_gl.jpg")
	wood.roughness_texture = load("res://assets/textures/desk_rough.jpg")
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(0.05, 0.05, 0.05)
	wood.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var desk := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(desk_half.x * 2, 1.0, desk_half.y * 2)
	mi.mesh = bm
	mi.material_override = wood
	desk.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	desk.add_child(cs)
	desk.position = Vector3(0, -0.5, 0)
	add_child(desk)

	# metal school-desk legs + floor far below (it gets blurry, like a real close-up photo)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.33, 0.35)
	metal.metallic = 0.9
	metal.roughness = 0.35
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 18.0
			leg.mesh = cm
			leg.material_override = metal
			leg.position = Vector3(sx * (desk_half.x - 1.5), -10.0, sz * (desk_half.y - 1.5))
			add_child(leg)
	var floor_mi := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(300, 300)
	floor_mi.mesh = pmesh
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.34, 0.31)
	fm.roughness = 0.5
	floor_mi.material_override = fm
	floor_mi.position = Vector3(0, -19.0, 0)
	add_child(floor_mi)


func _props() -> void:
	_pencil(Vector3(-10.5, 0, 5.0), 20.0, Color(0.95, 0.75, 0.12))
	_pencil(Vector3(10.0, 0, 5.6), -35.0, Color(0.7, 0.12, 0.1))
	# eraser
	var er := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.45, 0.65)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.8, 0.78)
	m.roughness = 0.95
	mi.material_override = m
	er.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	er.add_child(cs)
	er.position = Vector3(11.0, 0.225, -5.0)
	er.rotation.y = 0.4
	add_child(er)


func _pencil(pos: Vector3, yaw_deg: float, paint: Color) -> void:
	var r := 0.17
	var body := StaticBody3D.new()
	var holder := Node3D.new()   # the pencil lies on its side
	holder.rotation.z = PI / 2
	body.add_child(holder)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 4.5
	cm.radial_segments = 6
	mi.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = paint
	pm.roughness = 0.35
	mi.material_override = pm
	holder.add_child(mi)
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = r
	tm.height = 0.55
	tm.radial_segments = 12
	tip.mesh = tm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.85, 0.68, 0.48)
	wm.roughness = 0.8
	tip.material_override = wm
	tip.position = Vector3(0, 2.25 + 0.275, 0)
	holder.add_child(tip)
	var lead := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.0
	lm.bottom_radius = 0.05
	lm.height = 0.16
	lead.mesh = lm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.12, 0.12, 0.13)
	gm.metallic = 0.6
	gm.roughness = 0.4
	lead.material_override = gm
	lead.position = Vector3(0, 2.25 + 0.55 - 0.07, 0)
	holder.add_child(lead)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = 5.0
	cs.shape = shape
	holder.add_child(cs)
	body.position = pos + Vector3(0, r * 0.87, 0)
	body.rotation_degrees.y = yaw_deg
	add_child(body)


# ================================================================ camera
func _camera() -> void:
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.05
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_transition = 8.0
	cam_attr.dof_blur_near_enabled = true
	cam_attr.dof_blur_near_distance = 2.0
	cam_attr.dof_blur_near_transition = 1.5
	cam_attr.dof_blur_amount = 0.09
	cam.attributes = cam_attr
	add_child(cam)
	cam.global_position = Vector3(9, 6, 10)
	cam.look_at(Vector3.ZERO)


func _update_camera(delta: float) -> void:
	var p: Vector3 = player.global_position
	var e: Vector3 = cpu.global_position
	var dir := e - p
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, -1)
	var side := Vector3(dir.z, 0, -dir.x)
	var want := p - dir * 5.5 + Vector3.UP * 3.3 + side * 1.3
	var look := p.lerp(e, 0.4) + Vector3.UP * 0.3
	var k := 1.0 - exp(-(1.5 if state == "intro" else 4.0) * delta)
	cam.global_position = cam.global_position.lerp(want, k)
	cam.look_at(look)
	cam_shake = maxf(0.0, cam_shake - delta * 0.6)
	cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * cam_shake
	cam_attr.dof_blur_far_distance = cam.global_position.distance_to(look) + 3.0


# ================================================================ HUD
func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	for who in ["YOU", "CPU"]:
		var lbl := Label.new()
		lbl.text = who
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 6)
		layer.add_child(lbl)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.55)
		layer.add_child(bg)
		var fill := ColorRect.new()
		fill.color = Color(0.93, 0.92, 0.88)
		layer.add_child(fill)
		hp_fill[who] = [lbl, bg, fill]
	msg = Label.new()
	msg.add_theme_font_size_override("font_size", 64)
	msg.add_theme_color_override("font_outline_color", Color.BLACK)
	msg.add_theme_constant_override("outline_size", 12)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(msg)
	hint = Label.new()
	hint.text = "WASD move   ·   hold LEFT CLICK / J = bite (hold longer = bigger bite)   ·   RIGHT CLICK / K = smash   ·   SPACE = dodge   ·   R = restart"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 5)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(hint)
	msg.text = "LOPP FIGHT"


func _update_hud() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := minf(420.0, vs.x * 0.36)
	for who in ["YOU", "CPU"]:
		var l = player if who == "YOU" else cpu
		var parts: Array = hp_fill[who]
		var x := 30.0 if who == "YOU" else vs.x - 30.0 - w
		parts[0].position = Vector2(x, 14)
		parts[1].position = Vector2(x, 46)
		parts[1].size = Vector2(w, 20)
		var f := clampf(l.hp / 100.0, 0.0, 1.0)
		parts[2].size = Vector2(w * f, 20)
		parts[2].position = Vector2(x if who == "YOU" else x + w * (1.0 - f), 46)
		parts[2].color = Color(0.93, 0.92, 0.88).lerp(Color(0.85, 0.2, 0.15), 1.0 - f)
	msg.position = Vector2(0, vs.y * 0.3)
	msg.size = Vector2(vs.x, 80)
	hint.position = Vector2(0, vs.y - 34)
	hint.size = Vector2(vs.x, 24)


# ================================================================ game flow
func _on_died(l, reason: String) -> void:
	if state == "over":
		return
	state = "over"
	ko_until = Time.get_ticks_msec() + 1400   # slow motion KO
	if l == player:
		msg.text = "YOUR LOPP FELL OFF THE DESK" if reason == "fell" else "YOUR LOPP GOT DESTROYED"
	else:
		msg.text = "YOU WIN!" if reason != "fell" else "YOU WIN!  (it fell off the desk)"
	msg.text += "\n[R] fight again"
	if autotest:
		print("AUTOTEST: ", "player" if l == player else "cpu", " died (", reason, ") at t=", snappedf(t, 0.1))


func _process(delta: float) -> void:
	t += delta
	var now := Time.get_ticks_msec()
	if now < hitstop_until:
		Engine.time_scale = 0.08
	elif now < ko_until:
		Engine.time_scale = 0.3
	else:
		Engine.time_scale = 1.0

	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("restart"):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
		return

	if state == "intro" and t > (0.3 if autotest else 1.6):
		state = "fight"
		msg.text = "FIGHT!"
		player.active = true
		cpu.active = true
	if state == "fight" and t > 2.6 and msg.text == "FIGHT!":
		msg.text = ""

	if state == "fight" and not autotest:
		var x := Input.get_axis("left", "right")
		var y := Input.get_axis("down", "up")
		var f := -cam.global_transform.basis.z
		f.y = 0
		f = f.normalized()
		var r := cam.global_transform.basis.x
		r.y = 0
		r = r.normalized()
		player.in_move = r * x + f * y
		if Input.is_action_just_pressed("bite"):
			player.cmd_bite_start()
		if Input.is_action_just_released("bite"):
			player.cmd_bite_release()
		if Input.is_action_just_pressed("smash"):
			player.cmd_smash()
		if Input.is_action_just_pressed("dodge"):
			player.cmd_dodge()

	_update_camera(delta)
	_update_hud()

	if autotest:
		if int(t * 2) != int((t - delta) * 2) and int(t * 2) % 10 == 0:
			print("AUTOTEST t=", snappedf(t, 0.1), " hp ", snappedf(player.hp, 0.1), "/", snappedf(cpu.hp, 0.1),
				" hits ", hits, " debris ", debris.size(), " fps ", Engine.get_frames_per_second(),
				" | P ", player.state, " ", player.global_position.snappedf(0.1), " C ", cpu.state, " ", cpu.global_position.snappedf(0.1),
				" cells ", player.calive.count(1), "/", cpu.calive.count(1))
		if (state == "over" and now > ko_until + 500) or t > 60.0:
			print("AUTOTEST DONE t=", snappedf(t, 0.1), " hp ", snappedf(player.hp, 0.1), "/", snappedf(cpu.hp, 0.1), " hits ", hits, " debris ", debris.size())
			get_tree().quit()
