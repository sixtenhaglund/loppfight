extends RigidBody3D
## A paper lopp (fortune teller) that can hop, bite and smash.
##
## HOW THE PAPER WORKS
## The lopp is built from 4 "pockets" (paper pyramids) + a flat back. Every face is cut into lots of
## tiny triangles called CELLS. Neighbouring cells are held together by BONDS (think: invisible tape
## along every shared edge). A hit adds DAMAGE to cells near the hit point. When the damage on both
## sides of a bond gets too big, the bond SNAPS. A line of snapped bonds = a rip.
## After every hit we look for groups of cells that are no longer connected to the main lopp -
## those become loose paper pieces (debris) that fall with physics.
## Dents are separate: each vertex has a "displacement" that hits push around = crumpling.

signal died(lopp, reason)

const S := 1.0            # half the width of the lopp (it is 2 units wide, about 8 cm in real life)
const DEPTH := 1.25       # how far the pockets stick out forward
const SUB := 6            # each paper face is cut into SUB*SUB cells
const VIS_OFF := Vector3(0, 0, -DEPTH * 0.5)   # shifts the paper so the body is centred on the physics box

const HOP_SPEED := 3.2
const HOP_UP := 3.4
const HOP_EVERY := 0.2
const CHARGE_TIME := 0.6

var is_ai := false
var active := false
var paper_kind := 0        # 0 = math paper (squares), 1 = lined paper
var enemy = null
var main = null

var hp := 100.0
var dead := false

# ---- paper cells (3 vertices each) ----
var cv := PackedVector3Array()      # rest position of each vertex
var cdisp := PackedVector3Array()   # crumple displacement of each vertex
var cuv := PackedVector2Array()
var cpart := PackedInt32Array()     # 0 = upper jaw, 1 = lower jaw
var cface := PackedInt32Array()
var calive := PackedByteArray()
var cdmg := PackedFloat32Array()
var ccen := PackedVector3Array()
var cnorm := PackedVector3Array()
var ccurl := PackedVector3Array()   # torn cells curl away a little, so rips actually open up
var ncells := 0
# ---- bonds ----
var bond_a := PackedInt32Array()
var bond_b := PackedInt32Array()
var bond_str := PackedFloat32Array()
var bond_ok := PackedByteArray()
var cell_bonds: Array = []
var nbonds := 0

var noise := FastNoiseLite.new()
var visual: Node3D
var jaw_up: MeshInstance3D
var jaw_lo: MeshInstance3D
var mat: StandardMaterial3D

# ---- fighting state ----
var in_move := Vector3.ZERO
var state := "idle"         # idle / charge / snap / smash / stun
var open := 0.0
var open_target := 0.0
var pitch := 0.0
var pitch_target := 0.0
var shake := 0.0
var charge_t := 0.0
var snap_charge := 0.0
var snap_t := 0.0
var hit_done := false
var smash_t := 0.0
var hop_t := 0.0
var stun_t := 0.0
var invuln_t := 0.0
var bite_cd := 0.0
var smash_cd := 0.0
var dodge_cd := 0.0
var ai_t := 0.0
var ai_strafe := 1.0
var ai_charge_goal := 0.4
var dirty := false
var _ground := false


func _ready() -> void:
	noise.seed = randi()
	noise.frequency = 1.0
	mass = 1.0
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	angular_damp = 4.0
	contact_monitor = true
	max_contacts_reported = 8
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2 * S, 2 * S, DEPTH)
	cs.shape = box
	add_child(cs)

	visual = Node3D.new()
	visual.position = VIS_OFF
	add_child(visual)
	jaw_up = MeshInstance3D.new()
	jaw_lo = MeshInstance3D.new()
	visual.add_child(jaw_up)
	visual.add_child(jaw_lo)
	mat = _paper_material(paper_kind)
	_build_paper()
	_rebuild()


# ================================================================ building the paper
func _build_paper() -> void:
	var face_id := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var part := 0 if sy > 0 else 1
			var c0 := Vector3(0, 0, 0)
			var c1 := Vector3(sx * S, 0, 0)
			var c2 := Vector3(sx * S, sy * S, 0)
			var c3 := Vector3(0, sy * S, 0)
			var apex := Vector3(sx * S * 0.5, sy * S * 0.5, DEPTH)
			var inside := Vector3(sx * S * 0.5, sy * S * 0.5, DEPTH * 0.3)
			var base := [c0, c1, c2, c3]
			for k in 4:
				var a: Vector3 = base[k]
				var b: Vector3 = base[(k + 1) % 4]
				_add_face(a, b, apex, part, (a + b + apex) / 3.0 - inside, face_id)
				face_id += 1
			_add_face(c0, c1, c2, part, Vector3(0, 0, -1), face_id)
			face_id += 1
			_add_face(c0, c2, c3, part, Vector3(0, 0, -1), face_id)
			face_id += 1
	ncells = calive.size()
	cdisp.resize(cv.size())
	ccurl.resize(ncells)
	cdmg.resize(ncells)
	_build_bonds()


func _add_face(p0: Vector3, p1: Vector3, p2: Vector3, part: int, outward: Vector3, face_id: int) -> void:
	var n := (p1 - p0).cross(p2 - p0).normalized()
	if n.dot(outward) < 0.0:
		var tmp := p1
		p1 = p2
		p2 = tmp
		n = -n
	var t := (p1 - p0).normalized()
	var bt := n.cross(t)
	var e1 := (p1 - p0) / SUB
	var e2 := (p2 - p0) / SUB
	for i in SUB:
		for j in SUB - i:
			var a := p0 + e1 * i + e2 * j
			_add_cell(a, a + e1, a + e2, part, n, p0, t, bt, face_id)
			if i + j < SUB - 1:
				_add_cell(a + e1, a + e1 + e2, a + e2, part, n, p0, t, bt, face_id)


func _add_cell(a: Vector3, b: Vector3, c: Vector3, part: int, n: Vector3, o: Vector3, t: Vector3, bt: Vector3, face_id: int) -> void:
	for p in [a, b, c]:
		cv.append(p)
		cuv.append(Vector2((p - o).dot(t), (p - o).dot(bt)) * 0.5)
	cpart.append(part)
	cface.append(face_id)
	calive.append(1)
	ccen.append((a + b + c) / 3.0)
	cnorm.append(n)


func _vkey(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * 1000), roundi(v.y * 1000), roundi(v.z * 1000)]


func _build_bonds() -> void:
	var edges := {}
	for c in ncells:
		for k in 3:
			var ka := _vkey(cv[c * 3 + k])
			var kb := _vkey(cv[c * 3 + (k + 1) % 3])
			var key := ka + "|" + kb if ka < kb else kb + "|" + ka
			if edges.has(key):
				edges[key].append(c)
			else:
				edges[key] = [c]
	cell_bonds.resize(ncells)
	for c in ncells:
		cell_bonds[c] = PackedInt32Array()
	for key in edges:
		var list: Array = edges[key]
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: int = list[i]
				var b: int = list[j]
				bond_a.append(a)
				bond_b.append(b)
				bond_str.append(1.35 if cface[a] != cface[b] else 1.0)   # folds are a bit stronger
				bond_ok.append(1)
				cell_bonds[a].append(bond_a.size() - 1)
				cell_bonds[b].append(bond_a.size() - 1)
	nbonds = bond_a.size()


func _paper_material(kind: int) -> StandardMaterial3D:
	var img := Image.create(512, 512, true, Image.FORMAT_RGB8)
	img.fill(Color(0.93, 0.925, 0.89))
	if kind == 0:   # Swedish math paper: light blue squares
		for i in range(0, 512, 32):
			img.fill_rect(Rect2i(i, 0, 2, 512), Color(0.66, 0.75, 0.88))
			img.fill_rect(Rect2i(0, i, 512, 2), Color(0.66, 0.75, 0.88))
	else:           # lined paper with a red margin
		for i in range(0, 512, 64):
			img.fill_rect(Rect2i(0, i, 512, 2), Color(0.6, 0.7, 0.86))
		img.fill_rect(Rect2i(80, 0, 3, 512), Color(0.86, 0.45, 0.45))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.88
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# light shining through thin paper
	m.backlight_enabled = true
	m.backlight = Color(0.45, 0.43, 0.38)
	# paper fibres
	var fib := FastNoiseLite.new()
	fib.frequency = 0.08
	fib.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 1.2
	nt.noise = fib
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = 0.35
	return m


# ================================================================ mesh
func _rebuild() -> void:
	dirty = false
	var jaws := [jaw_up, jaw_lo]
	for part in 2:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		for c in ncells:
			if calive[c] == 0 or cpart[c] != part:
				continue
			var a := cv[c * 3] + cdisp[c * 3] + ccurl[c]
			var b := cv[c * 3 + 1] + cdisp[c * 3 + 1] + ccurl[c]
			var d := cv[c * 3 + 2] + cdisp[c * 3 + 2] + ccurl[c]
			var n := (b - a).cross(d - a).normalized()
			var shade := clampf(cdmg[c] * 0.18, 0.0, 0.22)
			var col := Color(1.0 - shade, 1.0 - shade, 1.0 - shade * 1.2)
			# Godot treats clockwise triangles as the front, so we add them a, d, b
			for k in [0, 2, 1]:
				verts.append([a, b, d][k])
				norms.append(n)
				uvs.append(cuv[c * 3 + k])
				cols.append(col)
		var mesh := ArrayMesh.new()
		if verts.size() > 0:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_TEX_UV] = uvs
			arr[Mesh.ARRAY_COLOR] = cols
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, mat)
		jaws[part].mesh = mesh


# ================================================================ damage
func _add_dent(center: Vector3, r: float, d: Vector3) -> void:
	var dl := d.length()
	var off := Vector3(randf() * 50, randf() * 50, randf() * 50)
	for i in cv.size():
		var v := cv[i]
		var dist := v.distance_to(center)
		if dist < r:
			var f := 1.0 - dist / r
			f = f * f * (3.0 - 2.0 * f)
			var p := v * 3.3 + off
			var nz := Vector3(noise.get_noise_3dv(p), noise.get_noise_3dv(p + Vector3(19, 7, 3)), noise.get_noise_3dv(p + Vector3(5, 23, 11)))
			cdisp[i] += d * f + nz * dl * 0.9 * f


## Called by the attacker. Returns false if the hit missed (we were dodging).
func receive_hit(gpoint: Vector3, gsource: Vector3, power: float, radius: float, kind: String, hp_dmg: float, knock: Vector3) -> bool:
	if dead or invuln_t > 0.0:
		return false
	var lp := to_local(gpoint) - VIS_OFF
	var ls := to_local(gsource) - VIS_OFF
	var push := lp - ls
	if push.length() < 0.001:
		push = Vector3(0, 0, -1)
	push = push.normalized()

	for c in ncells:
		if calive[c] == 0:
			continue
		var d := ccen[c].distance_to(lp)
		if d < radius:
			cdmg[c] += power * (1.0 - d / radius) * randf_range(0.7, 1.3)

	if kind == "smash":
		_add_dent(lp, radius * 1.5, push * 0.3 * power)
	else:
		_add_dent(lp, radius * 1.1, push * 0.12 * power)

	for bi in nbonds:
		if bond_ok[bi] == 0:
			continue
		var a := bond_a[bi]
		var b := bond_b[bi]
		if calive[a] == 0 or calive[b] == 0:
			continue
		var da := cdmg[a]
		var db := cdmg[b]
		if da < 0.5 and db < 0.5:
			continue
		var stress := (da + db) * 0.5 / bond_str[bi]
		if kind == "bite":
			stress *= 1.3
			if (da > 1.1) != (db > 1.1):
				stress += 0.7     # teeth rip along the edge of the bite
		else:
			stress *= 0.6         # smashing mostly crumples, it rips less
		if stress > 1.0 and randf() < clampf((stress - 1.0) * 1.5 + 0.35, 0.0, 1.0):
			_break_bond(bi)

	var lost := _detach_loose(push)
	hp = maxf(0.0, hp - hp_dmg - lost * 60.0 / ncells)
	linear_velocity += knock
	shake = 0.12 + 0.05 * power
	if state == "charge" or state == "snap":
		open_target = 0.0
	state = "stun"
	stun_t = 0.2 + 0.12 * power
	dirty = true
	if hp <= 0.0:
		_die("destroyed")
	return true


func _break_bond(bi: int) -> void:
	bond_ok[bi] = 0
	for c in [bond_a[bi], bond_b[bi]]:
		ccurl[c] += cnorm[c] * randf_range(0.015, 0.05) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.015


## Finds pieces that are not connected to the biggest piece any more and turns them into debris.
func _detach_loose(push: Vector3) -> int:
	var comp := PackedInt32Array()
	comp.resize(ncells)
	comp.fill(-1)
	var comps: Array = []
	for c in ncells:
		if calive[c] == 0 or comp[c] != -1:
			continue
		var id := comps.size()
		var list := [c]
		comp[c] = id
		var i := 0
		while i < list.size():
			var x: int = list[i]
			i += 1
			for bi in cell_bonds[x]:
				if bond_ok[bi] == 0:
					continue
				var y := bond_a[bi] if bond_b[bi] == x else bond_b[bi]
				if calive[y] == 1 and comp[y] == -1:
					comp[y] = id
					list.append(y)
		comps.append(list)
	if comps.size() <= 1:
		return 0
	var biggest := 0
	for i in comps.size():
		if comps[i].size() > comps[biggest].size():
			biggest = i
	var lost := 0
	for i in comps.size():
		if i == biggest:
			continue
		_spawn_debris(comps[i], push)
		lost += comps[i].size()
		for c in comps[i]:
			calive[c] = 0
	return lost


func _spawn_debris(list: Array, push: Vector3) -> void:
	if main == null:
		return
	var jaws := [jaw_up, jaw_lo]
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var center := Vector3.ZERO
	for c in list:
		var xf: Transform3D = jaws[cpart[c]].global_transform
		for k in [0, 2, 1]:
			var p: Vector3 = xf * (cv[c * 3 + k] + cdisp[c * 3 + k] + ccurl[c])
			pts.append(p)
			uvs.append(cuv[c * 3 + k])
			center += p
	center /= pts.size()
	var norms := PackedVector3Array()
	var aabb := AABB(pts[0] - center, Vector3.ZERO)
	for i in range(0, pts.size(), 3):
		var n := (pts[i + 2] - pts[i]).cross(pts[i + 1] - pts[i]).normalized()
		for k in 3:
			pts[i + k] -= center
			norms.append(n)
			aabb = aabb.expand(pts[i + k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, mat)

	var rb := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3.ONE * 0.04)
	cs.shape = box
	cs.position = aabb.get_center()
	rb.add_child(cs)
	rb.mass = maxf(0.005, 0.004 * list.size())
	rb.linear_damp = 2.2       # paper is light, so air slows it down a lot
	rb.angular_damp = 0.8
	rb.gravity_scale = 0.45
	main.add_debris(rb, center)
	var wpush := global_transform.basis * push
	rb.linear_velocity = linear_velocity * 0.5 + wpush * randf_range(1.5, 4.0) + Vector3.UP * randf_range(1.5, 4.0)
	rb.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	main.sfx("flutter", center, -6.0)


func _die(reason: String) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	state = "dead"
	_add_dent(Vector3(0, 0, DEPTH * 0.5), 1.7, Vector3(0, -0.3, -0.25))
	for bi in nbonds:
		if bond_ok[bi] == 1 and randf() < 0.3:
			_break_bond(bi)
	_detach_loose(Vector3(0, 0.5, 1))
	_rebuild()
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.8)
	open_target = 0.5
	if main:
		main.sfx("crumple", global_position, 2.0)
	died.emit(self, reason)


# ================================================================ commands (player input or AI)
func cmd_bite_start() -> void:
	if dead or not active or state != "idle" or bite_cd > 0.0:
		return
	state = "charge"
	charge_t = 0.0
	main.sfx("open", global_position, -4.0)


func cmd_bite_release() -> void:
	if state != "charge":
		return
	state = "snap"
	snap_charge = clampf(charge_t / CHARGE_TIME, 0.0, 1.0)
	open_target = 0.0
	snap_t = 0.18
	hit_done = false
	var fwd := _flat(global_transform.basis.z)
	linear_velocity += fwd * (3.0 + 5.0 * snap_charge) + Vector3.UP * 2.0


func cmd_smash() -> void:
	if dead or not active or state != "idle" or smash_cd > 0.0 or not _grounded():
		return
	state = "smash"
	smash_t = 0.0
	smash_cd = 1.6
	var to := Vector3.ZERO
	if enemy:
		to = enemy.global_position - global_position
		to.y = 0
	var up := 11.0
	var air := 2.0 * up / 40.0
	var hspeed := clampf(to.length() / air, 0.0, 9.0)
	linear_velocity = (to.normalized() * hspeed if to.length() > 0.01 else Vector3.ZERO) + Vector3.UP * up
	pitch_target = -0.25
	main.sfx("open", global_position, -2.0)


func cmd_dodge() -> void:
	if dead or not active or dodge_cd > 0.0 or not (state == "idle" or state == "charge"):
		return
	var right := _flat(global_transform.basis.x)
	var side := signf(in_move.dot(right))
	if side == 0.0:
		side = 1.0 if randf() < 0.5 else -1.0
	linear_velocity = right * side * 7.5 + Vector3.UP * 3.5
	invuln_t = 0.28
	dodge_cd = 0.9
	state = "idle"
	open_target = 0.0
	main.sfx("hop", global_position, -2.0)


# ================================================================ update
func _flat(v: Vector3) -> Vector3:
	v.y = 0
	return v.normalized() if v.length() > 0.0001 else Vector3.FORWARD


## Standing on something = any contact point whose surface faces up/down (the desk, a pencil,
## or a pile of torn paper scraps). A single ray straight down missed scraps under the edges.
func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	_ground = false
	for i in st.get_contact_count():
		if absf(st.get_contact_local_normal(i).y) > 0.5:
			_ground = true
			return


func _grounded() -> bool:
	if _ground:
		return true
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * (S + 0.12))
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func nearest_cell(gp: Vector3) -> Dictionary:
	var lp := to_local(gp) - VIS_OFF
	var best := -1
	var bd := INF
	for c in ncells:
		if calive[c] == 0:
			continue
		var d := ccen[c].distance_squared_to(lp)
		if d < bd:
			bd = d
			best = c
	if best < 0:
		return {"p": global_position, "d": INF}
	return {"p": to_global(ccen[best] + VIS_OFF), "d": sqrt(bd)}


func _physics_process(delta: float) -> void:
	for t in ["hop_t", "stun_t", "invuln_t", "bite_cd", "smash_cd", "dodge_cd"]:
		set(t, maxf(0.0, get(t) - delta))
	if dead:
		return
	if global_position.y < -4.0:
		_die("fell")
		return
	if not active:
		return
	if is_ai and enemy and not enemy.dead:
		_ai(delta)
	var grounded := _grounded()

	# always turn to face the enemy (lock-on, like in fighting games)
	if enemy and state != "smash":
		var to: Vector3 = enemy.global_position - global_position
		to.y = 0
		if to.length() > 0.05:
			var diff := wrapf(atan2(to.x, to.z) - global_rotation.y, -PI, PI)
			angular_velocity.y = diff * 9.0

	match state:
		"charge":
			charge_t += delta
			open_target = 0.3 + 0.6 * clampf(charge_t / CHARGE_TIME, 0.0, 1.0)
		"snap":
			snap_t -= delta
			if not hit_done and open < 0.3:
				hit_done = true
				_bite_hit()
			if snap_t <= 0.0:
				state = "idle"
				bite_cd = 0.35
		"smash":
			smash_t += delta
			pitch_target = 0.75 if linear_velocity.y < 0.0 else -0.25
			if smash_t > 0.18 and grounded:
				_smash_land()
			elif smash_t > 2.0:
				state = "idle"
				pitch_target = 0.0
		"stun":
			if stun_t <= 0.0:
				state = "idle"

	# moving = little paper hops
	var mv := in_move
	mv.y = 0
	if mv.length() > 1.0:
		mv = mv.normalized()
	if state == "snap" or state == "smash" or state == "stun":
		mv = Vector3.ZERO
	if state == "charge":
		mv *= 0.45
	if grounded and hop_t <= 0.0 and mv.length() > 0.15:
		var v := mv * HOP_SPEED
		linear_velocity = Vector3(v.x, HOP_UP, v.z)
		hop_t = HOP_EVERY
		main.sfx("hop", global_position, -8.0)
	elif grounded and mv.length() <= 0.15 and state != "snap" and state != "smash":
		linear_velocity.x = move_toward(linear_velocity.x, 0.0, 18.0 * delta)
		linear_velocity.z = move_toward(linear_velocity.z, 0.0, 18.0 * delta)


func _process(delta: float) -> void:
	var speed := 16.0 if open_target < open else 3.5
	open = move_toward(open, open_target, speed * delta)
	jaw_up.rotation.x = -open
	jaw_lo.rotation.x = open * 0.3
	if state != "smash" and state != "dead":
		pitch_target = 0.0
	pitch = lerpf(pitch, pitch_target, 1.0 - exp(-12.0 * delta))
	visual.rotation.x = pitch
	shake = maxf(0.0, shake - delta * 0.8)
	visual.position = VIS_OFF + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.4
	if dirty:
		_rebuild()


func _facing_enemy() -> float:
	var to: Vector3 = enemy.global_position - global_position
	return _flat(global_transform.basis.z).dot(_flat(to))


func _bite_hit() -> void:
	var c := snap_charge
	var mouth := to_global(Vector3(0, 0, DEPTH * 0.5 + 0.12))
	main.sfx("snap", mouth, 0.0)
	if enemy == null or enemy.dead:
		return
	var info: Dictionary = enemy.nearest_cell(mouth)
	if info.d < 0.45 + 0.35 * c and _facing_enemy() > 0.4:
		var fwd := _flat(global_transform.basis.z)
		var ok: bool = enemy.receive_hit(info.p, mouth, 0.7 + 1.5 * c, 0.32 + 0.22 * c, "bite", 5.0 + 13.0 * c, fwd * (2.0 + 4.0 * c) + Vector3.UP * 2.0)
		if ok:
			main.sfx("rip", info.p, 0.0)
			main.on_hit(self, enemy, 0.4 + 0.6 * c)


func _smash_land() -> void:
	state = "idle"
	pitch_target = 0.0
	main.sfx("thump", global_position, 0.0)
	var hit := false
	if enemy and not enemy.dead:
		var to: Vector3 = enemy.global_position - global_position
		to.y = 0
		if to.length() < 2.1:
			var info: Dictionary = enemy.nearest_cell(to_global(Vector3(0, -S * 0.6, DEPTH * 0.5)))
			hit = enemy.receive_hit(info.p, global_position + Vector3.UP * 1.5, 1.5, 0.8, "smash", 14.0, _flat(to) * 5.0 + Vector3.UP * 4.5)
			if hit:
				main.sfx("crumple", info.p, 0.0)
				main.on_hit(self, enemy, 1.0)
	# slamming face-first into things crumples your own front a little too
	_add_dent(Vector3(0, -S * 0.4, DEPTH), 0.6, Vector3(0, 0.03, -0.06))
	dirty = true
	if not hit:
		state = "stun"
		stun_t = 0.4


# ================================================================ computer player
func _ai(delta: float) -> void:
	ai_t -= delta
	var to: Vector3 = enemy.global_position - global_position
	to.y = 0
	var d := to.length()
	var dir := to / maxf(d, 0.001)
	var right := Vector3(dir.z, 0, -dir.x)
	if state == "charge":
		if charge_t >= ai_charge_goal or (d < 1.7 and charge_t > 0.2):
			cmd_bite_release()
		in_move = dir * 0.6
		return
	if ai_t <= 0.0:
		ai_t = randf_range(0.12, 0.3)
		if randf() < 0.15:
			ai_strafe = -ai_strafe
		if enemy.state == "charge" and d < 2.6 and randf() < 0.35:
			cmd_dodge()
		elif d < 2.4 and bite_cd <= 0.0 and randf() < 0.55:
			cmd_bite_start()
			ai_charge_goal = randf_range(0.15, 0.65)
		elif d > 1.6 and d < 4.5 and smash_cd <= 0.0 and randf() < 0.12:
			cmd_smash()
	var want_d := 1.9 if bite_cd <= 0.0 else 3.0
	if hp < 35.0:
		want_d += 1.0
	var mv := dir * clampf(d - want_d, -1.0, 1.0) + right * ai_strafe * 0.6
	# stay away from the edge of the desk
	var p := global_position
	var lim: Vector2 = main.desk_half - Vector2(2.5, 2.5)
	if absf(p.x) > lim.x:
		mv.x -= signf(p.x) * 1.5
	if absf(p.z) > lim.y:
		mv.z -= signf(p.z) * 1.5
	in_move = mv
