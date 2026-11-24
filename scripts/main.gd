extends Node3D
## LOPP FIGHT - main scene: builds the desk, the light, the camera, the two lopps and the UI.
## Game.mode decides what happens: "menu" = main menu with a CPU-vs-CPU fight behind it,
## "fight" = you play a round. Every new round reloads this scene; the score lives in Game.

const LoppScript := preload("res://scripts/lopp.gd")
const UIScript := preload("res://scripts/ui.gd")

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
var shooting := false
var shot_cam := false
var hits := 0
var menu := false          # true = main menu demo fight
var ui
var env: Environment
var sun: DirectionalLight3D
var paused := false
var resume_block := 0      # ignore the click that pressed Resume
var orbit := 0.0


func _ready() -> void:
	randomize()
	autotest = "autotest" in OS.get_cmdline_user_args()
	shooting = "shot" in OS.get_cmdline_user_args()
	_inputs()
	_load_sounds()
	_environment()
	_desk()
	_props()
	debris_root = Node3D.new()
	add_child(debris_root)
	var uishot := "uishot" in OS.get_cmdline_user_args()
	if uishot and "fight" in OS.get_cmdline_user_args() and Game.mode == "menu":
		Game.new_match()
	menu = Game.mode == "menu" and not autotest and not shooting
	player = _make_lopp(Vector3(0, LoppScript.S + 0.05, 3.2), PI, 0, autotest or menu)
	cpu = _make_lopp(Vector3(0, LoppScript.S + 0.05, -3.2), 0.0, 1, true)
	cpu.ai_level = 1 if menu else Game.difficulty
	player.enemy = cpu
	cpu.enemy = player
	player.died.connect(_on_died)
	cpu.died.connect(_on_died)
	_camera()
	ui = UIScript.new()
	ui.main = self
	add_child(ui)
	apply_graphics()
	if menu:
		ui.show_screen("menu")
	else:
		ui.show_screen("")
		ui.say("ROUND " + str(Game.round_no), 0.6)
	paper_bits(Vector3(0, -60, 0), Vector3.UP, 1)   # warm-up: prepares the fibre graphics before the first hit
	if shooting:
		autotest = true
		player.is_ai = true
		_shots()
	if uishot:
		_uishots()
	if autotest:
		print("AUTOTEST: cells per lopp = ", player.ncells, ", bonds = ", player.nbonds)


func _make_lopp(pos: Vector3, yaw: float, kind: int, ai: bool):
	var l = LoppScript.new()
	l.paper_kind = kind
	l.SUB = Game.paper_detail()
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
	_key("pause", [KEY_ESCAPE, KEY_P])


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
	p.volume_db = db - (10.0 if menu else 0.0)
	p.pitch_scale = randf_range(0.92, 1.08)
	p.unit_size = 8.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func add_debris(rb: RigidBody3D, pos: Vector3) -> void:
	debris_root.add_child(rb)
	rb.global_position = pos
	rb.set_meta("born", t)
	debris.append(rb)
	while debris.size() > Game.max_debris():
		var old = debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()


var bit_mesh: QuadMesh
var perf := {}


func perf_note(what: String, usec: int) -> void:
	var p: Array = perf.get(what, [0, 0, 0])
	perf[what] = [p[0] + 1, p[1] + usec, maxi(p[2], usec)]




## Little paper fibres and crumbs that fly out of a hit.
func paper_bits(pos: Vector3, dir: Vector3, amount: int) -> void:
	if bit_mesh == null:
		bit_mesh = QuadMesh.new()
		bit_mesh.size = Vector2(0.05, 0.035)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.95, 0.94, 0.9)
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		bit_mesh.material = m
	var p := CPUParticles3D.new()
	p.mesh = bit_mesh
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.6
	p.explosiveness = 0.95
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -5.0, 0)
	p.damping_min = 2.0
	p.damping_max = 5.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	p.particle_flag_align_y = false
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)


func on_hit(_attacker, _victim, strength: float) -> void:
	hits += 1
	if Game.shake:
		cam_shake = maxf(cam_shake, 0.08 + 0.12 * strength)
	hitstop_until = Time.get_ticks_msec() + int(40 + 50 * strength)   # tiny freeze = hits feel heavy


# ================================================================ world
func _environment() -> void:
	env = Environment.new()
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

	sun = DirectionalLight3D.new()   # window light
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_energy = 2.4
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.light_angular_distance = 2.0
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_blur = 1.5
	add_child(sun)

	# The web version (Compatibility renderer) has no SSAO/SSIL bounce light, so shadowed sides go
	# black. There we add soft extra light instead.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		env.ambient_light_energy = 2.2
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED   # no mirror-like shine on the web
		sun.shadow_bias = 0.15          # thin paper confuses web shadows ("shadow acne"), so keep a safety gap
		sun.shadow_normal_bias = 3.0
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-25, 35 + 180, 0)
		fill.light_energy = 0.75
		fill.light_color = Color(0.85, 0.9, 1.0)
		fill.light_specular = 0.0
		add_child(fill)
		var top := DirectionalLight3D.new()
		top.rotation_degrees = Vector3(-90, 0, 0)
		top.light_energy = 0.35
		top.light_specular = 0.0
		add_child(top)

	var lamp := SpotLight3D.new()   # warm desk lamp from the other side: makes the folds pop
	lamp.position = Vector3(-9, 9, -5)
	lamp.look_at_from_position(lamp.position, Vector3(0, 0, 0))
	lamp.light_color = Color(1.0, 0.82, 0.6)
	lamp.light_energy = 18.0
	lamp.spot_range = 30.0
	lamp.spot_angle = 40.0
	lamp.spot_attenuation = 1.0
	add_child(lamp)


func _desk() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/textures/desk_diff.jpg")
	wood.normal_enabled = true
	wood.normal_texture = load("res://assets/textures/desk_nor_gl.jpg")
	wood.roughness_texture = load("res://assets/textures/desk_rough.jpg")
	wood.albedo_color = Color(0.78, 0.72, 0.66)   # less orange
	wood.metallic_specular = 0.25                 # less plastic shine
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		wood.albedo_color = Color(0.6, 0.55, 0.52)   # the web renderer shows colours stronger
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
	if menu:
		orbit += delta * 0.12
		var mid: Vector3 = (player.global_position + cpu.global_position) * 0.5
		mid.y = 0.8
		var want_m := mid + Vector3(sin(orbit) * 7.5, 3.2, cos(orbit) * 7.5)
		cam.global_position = cam.global_position.lerp(want_m, 1.0 - exp(-2.0 * delta))
		cam.look_at(mid + Vector3(-1.2, 0, 0).rotated(Vector3.UP, orbit))   # aim a bit off-centre: the menu is on the left
		cam_attr.dof_blur_far_distance = cam.global_position.distance_to(mid) + 3.0
		return
	var p: Vector3 = player.global_position
	var e: Vector3 = cpu.global_position
	var dir := e - p
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, -1)
	var side := Vector3(dir.z, 0, -dir.x)
	# three-quarter view: you see both lopps from the side, so you see their shape, not just a back
	var want := p - dir * 3.6 + Vector3.UP * 2.6 + side * 3.6
	var look := p.lerp(e, 0.45) + Vector3.UP * 0.1
	var k := 1.0 - exp(-(1.5 if state == "intro" else 4.0) * delta)
	cam.global_position = cam.global_position.lerp(want, k)
	cam.look_at(look)
	cam_shake = maxf(0.0, cam_shake - delta * 0.6)
	cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * cam_shake
	cam_attr.dof_blur_far_distance = cam.global_position.distance_to(look) + 3.0


# ================================================================ graphics settings
func apply_graphics() -> void:
	var q := Game.quality
	var web := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	env.ssao_enabled = q >= 1 and not web
	env.ssil_enabled = q >= 2 and not web
	env.glow_enabled = q >= 1
	sun.shadow_enabled = q >= 1
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096 if web else 8192][q], true)
	cam_attr.dof_blur_far_enabled = q >= 1
	cam_attr.dof_blur_near_enabled = q >= 2
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q >= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = [0.75, 1.0, 1.0][q]   # Low draws the 3D in fewer pixels


## Paper scraps that have landed and stopped moving get frozen: the physics engine stops simulating
## them until a lopp comes close again.
var settle_t := 0.0


func _settle_debris(delta: float) -> void:
	settle_t -= delta
	if settle_t > 0.0:
		return
	settle_t = 0.5
	for rb in debris:
		if not is_instance_valid(rb):
			continue
		if rb.freeze:
			# a lopp is coming: wake the scrap up so it gets pushed around instead of walked through
			for l in [player, cpu]:
				var d: Vector3 = rb.global_position - l.global_position
				if Vector2(d.x, d.z).length() < 1.9:
					rb.freeze = false
					rb.set_meta("born", t)
					rb.set_process(true)
					break
			continue
		var age: float = t - float(rb.get_meta("born", t))
		if rb.sleeping or (age > 2.5 and rb.linear_velocity.length() < 0.08 and rb.angular_velocity.length() < 0.3):
			rb.freeze = true   # still solid, but the physics engine stops simulating it


# ================================================================ game flow
func ui_click() -> void:
	sfx("hop", cam.global_position + cam.global_transform.basis.z * -2.0, 4.0)


func start_match() -> void:
	Game.new_match()
	_reload()


func to_menu() -> void:
	Game.mode = "menu"
	_reload()


func _reload() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func set_paused(p: bool) -> void:
	if menu or state == "over":
		return
	paused = p
	get_tree().paused = p
	Engine.time_scale = 1.0
	if p:
		player.cmd_bite_release()
		ui.show_screen("pause")
	else:
		resume_block = Time.get_ticks_msec() + 250
		ui.show_screen("")


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		if paused and ui.screens["settings"].visible:
			ui.show_screen("pause")
		else:
			set_paused(not paused)


func _on_died(l, reason: String) -> void:
	if state == "over":
		return
	state = "over"
	ko_until = Time.get_ticks_msec() + 1400   # slow motion KO
	if autotest:
		print("AUTOTEST: ", "player" if l == player else "cpu", " died (", reason, ") at t=", snappedf(t, 0.1))
		return
	if menu:
		get_tree().create_timer(3.5, true, false, true).timeout.connect(_reload)   # next demo fight
		return
	var winner := 1 if l == player else 0
	Game.wins[winner] += 1
	if reason == "fell":
		ui.say("OFF THE DESK!", 1.6)
	else:
		ui.say("K.O.!", 1.6)
	get_tree().create_timer(2.6, true, false, true).timeout.connect(_after_round.bind(winner))


func _after_round(winner: int) -> void:
	if Game.wins[winner] >= Game.WINS_NEEDED:
		Engine.time_scale = 1.0
		ui.show_match_over(winner == 0)
	else:
		Game.round_no += 1
		_reload()


func _process(delta: float) -> void:
	t += delta
	var now := Time.get_ticks_msec()
	if now < hitstop_until:
		Engine.time_scale = 0.08
	elif now < ko_until:
		Engine.time_scale = 0.3
	else:
		Engine.time_scale = 1.0

	if state == "intro" and not shooting and t > (0.3 if autotest or menu else 1.4):
		state = "fight"
		if not menu and not autotest:
			ui.say("FIGHT!", 0.5)
		player.active = true
		cpu.active = true

	if state == "fight" and not autotest and not menu and now > resume_block:
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

	_settle_debris(delta)
	if not shot_cam:
		_update_camera(delta)

	if autotest:
		if int(t * 2) != int((t - delta) * 2) and int(t * 2) % 10 == 0:
			print("AUTOTEST t=", snappedf(t, 0.1), " hp ", snappedf(player.hp, 0.1), "/", snappedf(cpu.hp, 0.1),
				" hits ", hits, " debris ", debris.size(), " fps ", Engine.get_frames_per_second(),
				" | P ", player.state, " ", player.global_position.snappedf(0.1), " C ", cpu.state, " ", cpu.global_position.snappedf(0.1),
				" cells ", player.calive.count(1), "/", cpu.calive.count(1))
		if not shooting and ((state == "over" and now > ko_until + 500) or t > 60.0):
			for k in perf:
				print("PERF ", k, ": ", perf[k][0], " times, avg ", perf[k][1] / perf[k][0] / 1000.0, " ms, max ", perf[k][2] / 1000.0, " ms")
			print("AUTOTEST DONE t=", snappedf(t, 0.1), " hp ", snappedf(player.hp, 0.1), "/", snappedf(cpu.hp, 0.1), " hits ", hits, " debris ", debris.size())
			get_tree().quit()


# ================================================================ screenshots (for checking the look):  godot --path . -- shot
func _shots() -> void:
	await get_tree().create_timer(1.5).timeout
	var dir := OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var p: Vector3 = player.global_position
	var f: Vector3 = player.global_transform.basis.z
	var views := {
		"front": [p + f * 3.2 + Vector3(0.6, 0.6, 0), p],
		"back": [p - f * 3.2 + Vector3(0.8, 0.8, 0), p],
		"side": [p + Vector3(3.2, 1.0, 0.3), p],
		"game": [Vector3.ZERO, Vector3.ZERO],
		"damage": [Vector3.ZERO, Vector3.ZERO],
	}
	for name in views:
		shot_cam = name != "game"
		if name == "damage":
			await get_tree().create_timer(7.0).timeout
			var c: Vector3 = cpu.global_position
			var cf: Vector3 = cpu.global_transform.basis.z
			views[name] = [c + cf * 2.6 + cpu.global_transform.basis.x * 1.6 + Vector3.UP * 1.2, c]
		if shot_cam:
			cam.global_position = views[name][0]
			cam.look_at(views[name][1])
			cam_attr.dof_blur_far_distance = 20.0
		else:
			state = "fight"
			player.active = true
			cpu.active = true
			await get_tree().create_timer(6.0).timeout
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(dir + "/" + name + ".png")
	print("SHOTS ", dir)
	get_tree().quit()


## UI screenshots:  godot --path . -- uishot   (menu + settings)   /   -- uishot fight   (HUD + pause)
func _uishots() -> void:
	var dir := OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var tm := get_tree().create_timer(3.0, true, false, true)
	await tm.timeout
	if menu:
		get_viewport().get_texture().get_image().save_png(dir + "/ui_menu.png")
		ui.show_screen("settings")
		await get_tree().create_timer(0.5, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png(dir + "/ui_settings.png")
	else:
		player.cmd_bite_start()
		await get_tree().create_timer(0.4, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png(dir + "/ui_hud.png")
		set_paused(true)
		await get_tree().create_timer(0.5, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png(dir + "/ui_pause.png")
	print("UISHOTS ", dir)
	get_tree().quit()
