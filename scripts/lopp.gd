extends RigidBody3D
## A paper lopp (fortune teller) that can hop, bite and smash.
##
## THE SHAPE
## 4 pointed "pockets" whose tips meet in the middle (like a closed beak), so the whole lopp looks
## like a pyramid split into 4. Each point's outside is one coloured square folded along its diagonal.
## On the back are the 4 finger pockets, each with a slit that bulges open a little.
##
## HOW THE PAPER WORKS
## Every face is cut into lots of tiny triangles called CELLS (with an uneven grid, so rips look jagged).
## Neighbouring cells are held together by BONDS (invisible tape along every shared edge).
## A hit damages cells -> overloaded bonds SNAP. Then the rip RUNS: it keeps snapping the next bond in
## roughly the same direction, and it likes to follow folds, because creases are the weakest part of
## real paper. Pieces that are no longer connected to the lopp fall off as real physics objects.
## Dents are separate: every vertex can be pushed around = crumpling.

signal died(lopp, reason)

const PaperPiece := preload("res://scripts/paper_piece.gd")
const PaperShader := preload("res://scripts/paper.gdshader")

const S := 1.0            # half the width (the lopp is 2 units wide, about 8 cm in real life)
const DEPTH := 1.15       # how far the points stick out (about as tall as they are wide, like a real one)
var SUB := 9              # each paper face is cut into SUB*SUB cells (set from the graphics setting)
const THICK := 0.008      # paper thickness you see on cut/torn edges (thin printer paper)
const HZ := -0.3           # the fold-in-half line sticks out at the back (it is also the jaw hinge)
const VIS_OFF := Vector3(0, 0, -(DEPTH + HZ) * 0.5)

const HOP_SPEED := 3.2
const HOP_UP := 3.4
const HOP_EVERY := 0.2
const CHARGE_TIME := 0.6

const PALETTES := [
	[Color(0.86, 0.12, 0.12), Color(0.12, 0.32, 0.86), Color(0.12, 0.62, 0.22), Color(0.98, 0.82, 0.1)],
	[Color(0.55, 0.15, 0.75), Color(0.98, 0.5, 0.08), Color(0.95, 0.3, 0.6), Color(0.05, 0.6, 0.62)],
]

var is_ai := false
var ai_level := 1          # 0 easy, 1 normal, 2 hard
var active := false
var paper_kind := 0        # 0 = math paper (squares), 1 = lined paper
var enemy = null
var main = null

var hp := 100.0
var dead := false

# ---- per vertex (3 per cell) ----
var cv := PackedVector3Array()      # rest position
var cdisp := PackedVector3Array()   # crumple displacement
var cuv := PackedVector2Array()
var cao := PackedFloat32Array()     # darkness in crevices
var cmark := PackedFloat32Array()   # marker amount
var ccol := PackedColorArray()      # marker colour
var cvid := PackedInt32Array()      # same id = same point on the same face (for smooth shading)
var cgid := PackedInt32Array()      # same id = same point in space (for following rips across folds)
var nvid := 0
# ---- per cell ----
var cpart := PackedInt32Array()     # 0 = upper jaw, 1 = lower jaw
var cface := PackedInt32Array()
var ckind := PackedInt32Array()     # 0 outside, 1 inside of the mouth, 2 back
var cquad := PackedInt32Array()
var calive := PackedByteArray()
var cdmg := PackedFloat32Array()
var ccen := PackedVector3Array()
var cnorm := PackedVector3Array()
var ccurl := PackedVector3Array()
var ncells := 0
var nfaces := 0
# ---- bonds ----
var bond_a := PackedInt32Array()
var bond_b := PackedInt32Array()
var bond_g1 := PackedInt32Array()
var bond_g2 := PackedInt32Array()
var bond_str := PackedFloat32Array()
var bond_ok := PackedByteArray()
var cedge: Array = []               # per cell edge: bonds across that edge
var gid_bonds: Array = []           # per point: bonds whose edge touches it
var gpos := PackedVector3Array()
var gid_corners: Array = []        # per point: every cell corner sitting on it
var nbonds := 0

var noise := FastNoiseLite.new()
var visual: Node3D
var jaw_up: MeshInstance3D
var jaw_lo: MeshInstance3D
var mat: ShaderMaterial
var mat_debris: ShaderMaterial

# ---- fighting state ----
var in_move := Vector3.ZERO
var state := "idle"         # idle / charge / snap / smash / stun / dead
var open := 0.0
var open_v := 0.0
var open_target := 0.0
var pitch := 0.0
var pitch_target := 0.0
var lean := Vector2.ZERO
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
var dirty_q := 0             # which of the 4 points need a new mesh (bit per point)
var pockets: Array = []       # one mesh per point, so a bite only rebuilds what it touched
var coff := PackedVector3Array()   # cached peel offsets (see _corner_offsets)
var torn_g := {}              # points in space that touch a rip
var coff_dirty := {}          # points whose peel offset must be recalculated
var peel_seeds := {}          # cell -> how much the paper peels up there (collected during a hit)
var snaps_since_check := 0    # no snapped bonds = nothing can have come loose
var _ground := false

# ---- floppy paper: every point is a spring that lags behind, wobbles and droops ----
var tips: Array = []            # rest position of each point's tip
var pocket_mats: Array = []     # one material per point, so each can bend on its own
var bend: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var bend_v: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var bend_set: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # permanent folds from hard hits
var fold_at: Array = [0.25, 0.25, 0.25, 0.25]  # where along the point it bends (0 = base, 1 = tip)
var bend_rot: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var base_c: Array = []           # middle of the square under each point
var stiff: Array = []           # hand-folded: some points are softer than others
var last_vel := Vector3.ZERO
var last_yaw := 0.0
var squash := 0.0
var squash_v := 0.0
var was_ground := true


func _ready() -> void:
	noise.seed = randi()
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED   # ridges = sharp crumple creases
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
	box.size = Vector3(2 * S, 2 * S, DEPTH - HZ)
	cs.shape = box
	add_child(cs)

	visual = Node3D.new()
	visual.position = VIS_OFF
	add_child(visual)
	jaw_up = MeshInstance3D.new()
	jaw_lo = MeshInstance3D.new()
	visual.add_child(jaw_up)
	visual.add_child(jaw_lo)
	jaw_up.position = Vector3(0, 0, HZ)   # jaws turn around the middle fold line
	jaw_lo.position = Vector3(0, 0, HZ)
	_make_materials()
	_build_paper()
	for q in 4:
		var mi := MeshInstance3D.new()
		(jaw_up if q % 2 == 1 else jaw_lo).add_child(mi)   # q = 1,3 are the upper points
		mi.position = Vector3(0, 0, -HZ)
		pockets.append(mi)
		var pmat: ShaderMaterial = mat.duplicate()
		pocket_mats.append(pmat)
		mi.material_override = pmat
		stiff.append(randf_range(90.0, 170.0))
	last_yaw = global_rotation.y
	coff.resize(ncells * 3)
	dirty_q = 15
	_rebuild()


# ================================================================ building the paper
func _hrand(h: int) -> float:
	return float(h & 0xffff) / 65535.0 - 0.5


func _build_paper() -> void:
	var pal: Array = PALETTES[paper_kind]
	var q := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var part := 0 if sy > 0 else 1
			# hand folded = never perfect: the corners and the bottom edge are a bit off.
			# Corners shared by two points must move the same way, so _corner() remembers them.
			# the middle fold line (c0-c1) sticks out at the back, like a real lopp folded in half
			var c0 := Vector3(0, 0, HZ)
			var c1 := _corner(Vector3(sx * S, 0, HZ), true)
			var c2 := _corner(Vector3(sx * S * 1.08, sy * S * 1.08, 0.04), false)   # bottom corner flares out
			var c3 := _corner(Vector3(0, sy * S, HZ * 0.45), false)
			base_c.append((c0 + c1 + c2 + c3) / 4.0)
			# the tip sits above the middle of its own square (each point is its own pyramid)
			var tip := Vector3(sx * S * randf_range(0.44, 0.56), sy * S * randf_range(0.44, 0.56), DEPTH * randf_range(0.93, 1.05))
			tips.append(tip)
			var inside := Vector3(sx * S * 0.35, sy * S * 0.35, DEPTH * 0.25)
			var col: Color = pal[q]
			var outer := {"bow": randf_range(0.06, 0.1), "col": col, "marker": 0.93, "lift_opp": -1, "lift": Vector3.ZERO}
			var inner := {"bow": randf_range(0.01, 0.025), "col": Color.WHITE, "marker": 0.0, "lift_opp": -1, "lift": Vector3.ZERO}
			# outside of the point: one square folded along the diagonal (c2 -> tip)
			# the pocket opening flares out and curls back a little (bent paper, not a cut edge)
			var outer_a: Dictionary = outer.duplicate()
			outer_a.lift_opp = 2
			outer_a.lift = Vector3(sx * randf_range(0.04, 0.09), 0, -randf_range(0.03, 0.08))
			var outer_b: Dictionary = outer.duplicate()
			outer_b.lift_opp = 2
			outer_b.lift = Vector3(0, sy * randf_range(0.04, 0.09), -randf_range(0.03, 0.08))
			_add_face(c1, c2, tip, part, (c1 + c2 + tip) / 3.0 - inside, 0, q, outer_a)
			_add_face(c2, c3, tip, part, (c2 + c3 + tip) / 3.0 - inside, 0, q, outer_b)
			# inside of the mouth (the walls between the points)
			_add_face(c0, c1, tip, part, (c0 + c1 + tip) / 3.0 - inside, 1, q, inner)
			_add_face(c3, c0, tip, part, (c3 + c0 + tip) / 3.0 - inside, 1, q, inner)
			# NO back: like a real lopp, the underside is 4 open finger pockets (the hollow points)
			q += 1
	ncells = calive.size()
	cdisp.resize(cv.size())
	ccurl.resize(ncells)
	cdmg.resize(ncells)
	_build_bonds()
	# real paper is never perfectly flat: a gentle wave over the whole sheet (same for shared points)
	var wave := FastNoiseLite.new()
	wave.seed = randi()
	wave.frequency = 0.9
	for i in cv.size():
		var g := gpos[cgid[i]]
		var keep := clampf((absf(g.y) + absf(g.z - HZ)) / 0.25, 0.0, 1.0)   # stay put on the hinge
		cdisp[i] = Vector3(wave.get_noise_3dv(g), wave.get_noise_3dv(g + Vector3(31, 0, 0)), wave.get_noise_3dv(g + Vector3(0, 47, 0))) * 0.03 * keep


var _corners := {}


func _corner(p: Vector3, on_hinge: bool) -> Vector3:
	var key := Vector3i(roundi(p.x * 10), roundi(p.y * 10), 0)
	if not _corners.has(key):
		var j := Vector3(randf_range(-0.05, 0.05), 0.0 if on_hinge else randf_range(-0.05, 0.05), randf_range(-0.07, 0.05))
		if p.x == 0.0:
			j.x = 0.0
		if on_hinge:
			j.z = 0.0   # the hinge line has to stay straight or the jaws pull apart
		_corners[key] = p + j
	return _corners[key]


func _add_face(p0: Vector3, p1: Vector3, p2: Vector3, part: int, outward: Vector3, kind: int, quad: int, o: Dictionary) -> void:
	var face_id := nfaces
	nfaces += 1
	var n := (p1 - p0).cross(p2 - p0).normalized()
	var lab := [0, 1, 2]
	if n.dot(outward) < 0.0:
		var tmp := p1
		p1 = p2
		p2 = tmp
		n = -n
		lab = [0, 2, 1]
	var t := (p1 - p0).normalized()
	var bt := n.cross(t)
	var e1 := (p1 - p0) / SUB
	var e2 := (p2 - p0) / SUB
	var grid := {}
	for i in SUB + 1:
		for j in SUB + 1 - i:
			var w := [1.0 - float(i + j) / SUB, float(i) / SUB, float(j) / SUB]
			var p := p0 + e1 * i + e2 * j
			if i > 0 and j > 0 and i + j < SUB:
				var h := hash(Vector3i(face_id, i, j) + Vector3i(get_instance_id() % 1000, 0, 0))
				p += e1 * _hrand(h) * 0.7 + e2 * _hrand(h >> 16) * 0.7   # uneven grid -> jagged rips
			p += n * o.bow * 27.0 * w[0] * w[1] * w[2]                     # paper bulges a little
			var liftw := 0.0
			if o.lift_opp >= 0:
				var wo := [0.0, 0.0, 0.0]
				for k in 3:
					wo[lab[k]] = w[k]
				liftw = 4.0 * wo[(o.lift_opp + 1) % 3] * wo[(o.lift_opp + 2) % 3]
				p += o.lift * liftw
			var ao := 1.0
			var mark := 0.0
			match kind:
				0:
					ao = 1.0 - 0.4 * exp(-minf(absf(p.x), absf(p.y)) / 0.1)   # dark in the cracks
					# coloured by hand: the marker never quite reaches the folds
					mark = o.marker * clampf(minf(w[0], minf(w[1], w[2])) * SUB * 0.8 - 0.1, 0.0, 1.0)
				1:
					ao = 0.45 + 0.45 * clampf(p.z / DEPTH, 0.0, 1.0)
				2:
					ao = 0.93 - 0.5 * liftw
			grid[Vector2i(i, j)] = [p, Vector2((p - p0).dot(t), (p - p0).dot(bt)) * 0.5, ao, mark, nvid]
			nvid += 1
	for i in SUB:
		for j in SUB - i:
			_add_cell(grid[Vector2i(i, j)], grid[Vector2i(i + 1, j)], grid[Vector2i(i, j + 1)], part, face_id, kind, quad, o.col, n)
			if i + j < SUB - 1:
				_add_cell(grid[Vector2i(i + 1, j)], grid[Vector2i(i + 1, j + 1)], grid[Vector2i(i, j + 1)], part, face_id, kind, quad, o.col, n)


func _add_cell(a: Array, b: Array, c: Array, part: int, face_id: int, kind: int, quad: int, col: Color, fn: Vector3) -> void:
	for v in [a, b, c]:
		cv.append(v[0])
		cuv.append(v[1])
		cao.append(v[2])
		cmark.append(v[3])
		cvid.append(v[4])
		ccol.append(Color(col.r, col.g, col.b, clampf(v[0].z / DEPTH, 0.0, 1.0)))
	cpart.append(part)
	cface.append(face_id)
	ckind.append(kind)
	cquad.append(quad)
	calive.append(1)
	ccen.append((a[0] + b[0] + c[0]) / 3.0)
	var n: Vector3 = (b[0] - a[0]).cross(c[0] - a[0]).normalized()
	cnorm.append(n if n.dot(fn) > 0 else -n)


func _build_bonds() -> void:
	# give every distinct point in space an id
	var gids := {}
	cgid.resize(cv.size())
	for i in cv.size():
		var v := cv[i]
		var key := Vector3i(roundi(v.x * 1000), roundi(v.y * 1000), roundi(v.z * 1000))
		if not gids.has(key):
			gids[key] = gpos.size()
			gpos.append(v)
		cgid[i] = gids[key]
	gid_bonds.resize(gpos.size())
	gid_corners.resize(gpos.size())
	for g in gpos.size():
		gid_bonds[g] = PackedInt32Array()
		gid_corners[g] = PackedInt32Array()
	for i in cv.size():
		gid_corners[cgid[i]].append(i)
	cedge.resize(ncells * 3)
	for i in ncells * 3:
		cedge[i] = PackedInt32Array()
	var edges := {}
	for c in ncells:
		for k in 3:
			var g1 := cgid[c * 3 + k]
			var g2 := cgid[c * 3 + (k + 1) % 3]
			var key := mini(g1, g2) * 1000000 + maxi(g1, g2)
			if edges.has(key):
				edges[key].append(c * 3 + k)
			else:
				edges[key] = [c * 3 + k]
	for key in edges:
		var list: Array = edges[key]
		var g1: int = key / 1000000
		var g2: int = key % 1000000
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: int = list[i] / 3
				var b: int = list[j] / 3
				# the slit of a finger pocket is NOT glued
				if ckind[a] == 2 and ckind[b] == 2 and cquad[a] == cquad[b] and cface[a] != cface[b]:
					continue
				var bi := bond_a.size()
				bond_a.append(a)
				bond_b.append(b)
				bond_g1.append(g1)
				bond_g2.append(g2)
				bond_str.append(0.8 if cface[a] != cface[b] else 1.0)   # creases are weaker
				bond_ok.append(1)
				cedge[list[i]].append(bi)
				cedge[list[j]].append(bi)
				gid_bonds[g1].append(bi)
				gid_bonds[g2].append(bi)
	nbonds = bond_a.size()


func _make_materials() -> void:
	var img := Image.create(512, 512, true, Image.FORMAT_RGB8)
	img.fill(Color(0.94, 0.935, 0.9))
	if paper_kind == 0:   # Swedish math paper: light blue squares
		for i in range(0, 512, 32):
			img.fill_rect(Rect2i(i, 0, 2, 512), Color(0.68, 0.77, 0.89))
			img.fill_rect(Rect2i(0, i, 512, 2), Color(0.68, 0.77, 0.89))
	else:                 # lined paper with a red margin
		for i in range(0, 512, 64):
			img.fill_rect(Rect2i(0, i, 512, 2), Color(0.62, 0.72, 0.87))
		img.fill_rect(Rect2i(80, 0, 3, 512), Color(0.87, 0.47, 0.47))
	img.generate_mipmaps()
	var fib := FastNoiseLite.new()
	fib.frequency = 0.09
	fib.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 1.4
	nt.noise = fib
	var mot := FastNoiseLite.new()
	mot.frequency = 0.02
	mot.fractal_octaves = 5
	var mt := NoiseTexture2D.new()
	mt.width = 512
	mt.height = 512
	mt.seamless = true
	mt.generate_mipmaps = true
	mt.noise = mot
	mat = ShaderMaterial.new()
	mat.shader = PaperShader
	mat.set_shader_parameter("paper_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("fiber_normal", nt)
	mat.set_shader_parameter("mottle", mt)
	mat.set_shader_parameter("inside_dark", 0.6)
	mat.set_shader_parameter("web", 1.0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0.0)
	mat_debris = mat.duplicate()
	mat_debris.set_shader_parameter("inside_dark", 0.85)


# ================================================================ mesh
func _edge_free(c: int, k: int) -> bool:
	for bi in cedge[c * 3 + k]:
		if bond_ok[bi] == 1:
			var o := bond_b[bi] if bond_a[bi] == c else bond_a[bi]
			if calive[o] == 1:
				return false
	return true


## Turns a list of cells into mesh arrays. xfs = transform for each jaw part, center is subtracted.
func _arrays_for(cells: PackedInt32Array, xfs: Array, center: Vector3, bent := false) -> Array:
	var cnt := cells.size()
	var pos := PackedVector3Array()
	pos.resize(cnt * 3)
	var fn := PackedVector3Array()
	fn.resize(cnt)
	var acc := PackedVector3Array()
	acc.resize(nvid)
	for idx in cnt:
		var c := cells[idx]
		var xf: Transform3D = xfs[cquad[c]]
		for k in 3:
			var p := cv[c * 3 + k] + cdisp[c * 3 + k] + coff[c * 3 + k]
			if bent:
				p = _bent(cquad[c], p, cv[c * 3 + k].z)
			pos[idx * 3 + k] = xf * p - center
		var nn := (pos[idx * 3 + 1] - pos[idx * 3]).cross(pos[idx * 3 + 2] - pos[idx * 3]).normalized()
		fn[idx] = nn
		for k in 3:
			acc[cvid[c * 3 + k]] += nn
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	for idx in cnt:
		var c := cells[idx]
		var torn := false
		var dshade := 1.0 - clampf(cdmg[c] * 0.12, 0.0, 0.28)
		# Godot treats clockwise triangles as the front, so add them 0, 2, 1
		for kk in 3:
			var k := kk if kk == 0 else 3 - kk
			var vi := c * 3 + k
			verts.append(pos[idx * 3 + k])
			var sn: Vector3 = acc[cvid[vi]]
			norms.append(fn[idx] if torn or sn.length_squared() < 0.0001 else sn.normalized())
			uvs.append(cuv[vi])
			uv2s.append(Vector2(cao[vi] * dshade, cmark[vi]))
			cols.append(ccol[vi])
		# paper thickness on every edge that is cut or torn: a thin white strip
		var cen := (pos[idx * 3] + pos[idx * 3 + 1] + pos[idx * 3 + 2]) / 3.0
		for k in 3:
			if not _edge_free(c, k):
				continue
			var a := pos[idx * 3 + k]
			var b := pos[idx * 3 + (k + 1) % 3]
			var off := -fn[idx] * THICK
			var outn := (b - a).cross(fn[idx]).normalized()
			if outn.dot(a - cen) < 0.0:
				outn = -outn
			if cedge[c * 3 + k].size() > 0:   # this edge used to be glued = it is a RIP, not a cut edge
				var ga := cgid[c * 3 + k]
				var gb := cgid[c * 3 + (k + 1) % 3]
				var wa := 0.01 + 0.025 * absf(_hrand(hash(ga) >> 3) * 2.0)
				var wb := 0.01 + 0.025 * absf(_hrand(hash(gb) >> 3) * 2.0)
				var mid := (a + b) * 0.5
				var wm := 0.006 + 0.03 * absf(_hrand(hash(ga * 7 + gb) >> 5) * 2.0)
				var lift_n := fn[idx] * 0.002
				var fa := a + outn * wa + lift_n
				var fb := b + outn * wb + lift_n
				var fm := mid + outn * wm + lift_n
				var da := clampf(cv[c * 3 + k].z / DEPTH, 0.0, 1.0)
				for tri in [[a, mid, fm], [a, fm, fa], [mid, b, fb], [mid, fb, fm]]:
					var q0: Vector3 = tri[0]
					var q1: Vector3 = tri[1]
					var q2: Vector3 = tri[2]
					var ord := [q0, q2, q1] if (q1 - q0).cross(q2 - q0).dot(fn[idx]) > 0.0 else [q0, q1, q2]
					for p in ord:
						verts.append(p)
						norms.append(fn[idx])
						uvs.append(cuv[c * 3 + k])
						uv2s.append(Vector2(1.08, 0.0))
						cols.append(Color(1, 1, 1, da))
			for tri in [[a, b, b + off], [a, b + off, a + off]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var order := [p0, p2, p1] if (p1 - p0).cross(p2 - p0).dot(outn) > 0.0 else [p0, p1, p2]
				for p in order:
					verts.append(p)
					norms.append(outn)
					uvs.append(cuv[c * 3 + k])
					uv2s.append(Vector2(1.05, 0.0))
					cols.append(Color(1, 1, 1, clampf(p.z / DEPTH, 0.0, 1.0)))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	return arr


## How far each cell corner peels up. Cells that are still glued together around a point all get the
## SAME offset there (so paper that is in one piece stays in one piece), but cells on different
## sides of a rip get different offsets - that is what opens the rip without making spiky teeth.
func _corner_offsets() -> void:
	var off := coff
	for g in coff_dirty:
		var corners: PackedInt32Array = gid_corners[g]
		# group the cells around this point that are still connected to each other here
		var group := {}
		for ci in corners:
			group[ci / 3] = ci / 3
		for bi in gid_bonds[g]:
			if bond_ok[bi] == 1 and calive[bond_a[bi]] == 1 and calive[bond_b[bi]] == 1:
				var ra: int = _root(group, bond_a[bi])
				var rb: int = _root(group, bond_b[bi])
				if ra != rb:
					group[ra] = rb
		var sum := {}
		var cnt := {}
		for ci in corners:
			var r: int = _root(group, ci / 3)
			sum[r] = sum.get(r, Vector3.ZERO) + ccurl[ci / 3]
			cnt[r] = cnt.get(r, 0) + 1
		for ci in corners:
			var r: int = _root(group, ci / 3)
			off[ci] = sum[r] / cnt[r]
	coff_dirty.clear()


func _root(group: Dictionary, x: int) -> int:
	while group[x] != x:
		x = group[x]
	return x


func _rebuild(all := true) -> void:
	dirty = false
	var t0 := Time.get_ticks_usec()
	_corner_offsets()
	var ident := [Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY]
	for q in 4:
		if dirty_q & (1 << q) == 0:
			continue
		dirty_q &= ~(1 << q)
		var list := PackedInt32Array()
		for c in ncells:
			if calive[c] == 1 and cquad[c] == q:
				list.append(c)
		var mesh := ArrayMesh.new()
		if list.size() > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays_for(list, ident, Vector3.ZERO))
			mesh.surface_set_material(0, mat)
		pockets[q].mesh = mesh
		if not all:
			break
	if main:
		main.perf_note("rebuild", Time.get_ticks_usec() - t0)


# ================================================================ damage
func _touch(c: int) -> void:
	dirty_q |= 1 << cquad[c]
	if calive[c] == 0 and ccurl[c] != Vector3.ZERO:
		for k in 3:
			coff_dirty[cgid[c * 3 + k]] = true


func _add_dent(center: Vector3, r: float, d: Vector3) -> void:
	var dl := d.length()
	var off := Vector3(randf() * 50, randf() * 50, randf() * 50)
	for i in cv.size():
		var v := cv[i]
		var dist := v.distance_to(center)
		if dist < r:
			var f := 1.0 - dist / r
			f = f * f * (3.0 - 2.0 * f)
			var p := v * 3.6 + off
			var nz := Vector3(noise.get_noise_3dv(p), noise.get_noise_3dv(p + Vector3(19, 7, 3)), noise.get_noise_3dv(p + Vector3(5, 23, 11)))
			cdisp[i] += d * f + nz * dl * 1.5 * f   # dent + sharp crumple creases
			dirty_q |= 1 << cquad[i / 3]


## Called by the attacker. Returns false if the hit missed (we were dodging).
## tear = how far the rip runs (in cells) after the first bonds snap.
func receive_hit(gpoint: Vector3, gsource: Vector3, power: float, radius: float, kind: String, hp_dmg: float, knock: Vector3, tear: float) -> bool:
	if dead or invuln_t > 0.0:
		return false
	var t0 := Time.get_ticks_usec()
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
			_touch(c)

	if kind == "smash":
		_add_dent(lp, radius * 1.4, push * 0.38 * power)
	else:
		# teeth marks: the two jaws pinch the paper from above and below
		var up := Vector3(0, 0.14, 0)
		_add_dent(lp + up, radius * 0.8, (push + Vector3(0, -0.6, 0)).normalized() * 0.16 * power)
		_add_dent(lp - up, radius * 0.8, (push + Vector3(0, 0.6, 0)).normalized() * 0.16 * power)

	var snapped := PackedInt32Array()
	# only bonds next to damaged cells can snap
	var near := {}
	for c in ncells:
		if calive[c] == 1 and cdmg[c] >= 0.5:
			for k in 3:
				for bi in cedge[c * 3 + k]:
					near[bi] = true
	for bi in near:
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
			stress *= 0.6         # smashing mostly crumples
		if stress > 1.0 and randf() < clampf((stress - 1.0) * 1.5 + 0.35, 0.0, 1.0):
			_break_bond(bi)
			snapped.append(bi)

	# the rip keeps running from where it started
	if snapped.is_empty() and tear >= 4.0:
		var best := -1
		var bd := INF
		for bi in nbonds:
			if bond_ok[bi] == 1 and calive[bond_a[bi]] == 1 and calive[bond_b[bi]] == 1:
				var d := ((gpos[bond_g1[bi]] + gpos[bond_g2[bi]]) * 0.5).distance_squared_to(lp)
				if d < bd:
					bd = d
					best = bi
		if best >= 0:
			_break_bond(best)
			snapped.append(best)
	var tips := mini(snapped.size(), 3 if kind == "bite" else 2)
	for i in tips:
		var bi := snapped[randi() % snapped.size()]
		_run_tear(bi, int(tear * randf_range(0.6, 1.3)), lp)

	_apply_peel()
	var lost := _detach_loose(push)
	hp = maxf(0.0, hp - hp_dmg - lost * 90.0 / ncells)
	linear_velocity += knock
	shake = 0.12 + 0.05 * power
	if state == "charge" or state == "snap":
		open_target = 0.0
	state = "stun"
	stun_t = 0.2 + 0.12 * power
	kick_points(push, 2.5 * power, lp)
	fold_points(push, power, lp)
	if main:
		main.paper_bits(gpoint, -(global_transform.basis * push), 18 + int(power * 14))
		if lost > 30:
			main.sfx("rip", gpoint, 2.0)
	if main:
		main.perf_note("hit", Time.get_ticks_usec() - t0)
	if hp <= 0.0:
		_die("destroyed")
	return true


func _break_bond(bi: int) -> void:
	bond_ok[bi] = 0
	snaps_since_check += 1
	for g in [bond_g1[bi], bond_g2[bi]]:
		torn_g[g] = true
		for ci in gid_corners[g]:
			dirty_q |= 1 << cquad[ci / 3]
	# a rip lets the paper on ONE side peel up like a flap: strongest at the rip, fading out
	# over a few cells (cells that are still glued together move together, see _corner_offsets)
	var a := bond_a[bi]
	var b := bond_b[bi]
	var side := a if randf() < 0.5 else b
	var other := b if side == a else a
	var lift := randf_range(0.015, 0.05)
	peel_seeds[side] = maxf(float(peel_seeds.get(side, 0.0)), lift)   # spread later, all at once
	ccurl[other] += cnorm[other] * lift * 0.15
	for k in 3:
		coff_dirty[cgid[other * 3 + k]] = true


## Spread the peel from every rip of this hit in ONE search: each cell takes the strongest peel
## that reaches it, fading out over 3 rings of neighbours (on the same face of paper).
func _apply_peel() -> void:
	if peel_seeds.is_empty():
		return
	var best := {}
	var ring: Array = []
	for c in peel_seeds:
		best[c] = peel_seeds[c]
		ring.append(c)
	for depth in 4:
		var next: Array = []
		var f := 1.0 - depth / 4.0
		for c in ring:
			if calive[c] == 0:
				continue
			var lift: float = best[c]
			ccurl[c] += cnorm[c] * lift * f
			dirty_q |= 1 << cquad[c]
			for k in 3:
				coff_dirty[cgid[c * 3 + k]] = true
				if depth == 3:
					continue
				for nb in cedge[c * 3 + k]:
					if bond_ok[nb] == 0:
						continue
					var o := bond_b[nb] if bond_a[nb] == c else bond_a[nb]
					if cface[o] == cface[c] and not best.has(o):
						best[o] = lift
						next.append(o)
		ring = next
	peel_seeds.clear()


## A rip running through the paper: from its tip, snap the next edge that goes roughly the same way.
func _run_tear(bi: int, steps: int, from: Vector3) -> void:
	var g1 := bond_g1[bi]
	var g2 := bond_g2[bi]
	var tip := g1
	var prev := g2
	if gpos[g2].distance_to(from) > gpos[g1].distance_to(from):
		tip = g2
		prev = g1
	for s in steps:
		var dir := (gpos[tip] - gpos[prev]).normalized()
		var best := -1
		var best_score := -INF
		for nb in gid_bonds[tip]:
			if bond_ok[nb] == 0 or calive[bond_a[nb]] == 0 or calive[bond_b[nb]] == 0:
				continue
			var other := bond_g2[nb] if bond_g1[nb] == tip else bond_g1[nb]
			if other == prev:
				continue
			var sc := (gpos[other] - gpos[tip]).normalized().dot(dir) + randf() * 0.6
			if cface[bond_a[nb]] != cface[bond_b[nb]]:
				sc += 0.7      # creases tear easily
			if sc > best_score:
				best_score = sc
				best = other
		if best < 0 or best_score < 0.0:
			return
		for nb in gid_bonds[tip]:
			var other := bond_g2[nb] if bond_g1[nb] == tip else bond_g1[nb]
			if other == best and bond_ok[nb] == 1:
				_break_bond(nb)
		prev = tip
		tip = best


## Finds pieces that are not connected to the biggest piece any more and turns them into debris.
func _detach_loose(push: Vector3) -> int:
	if snaps_since_check == 0:
		return 0
	snaps_since_check = 0
	# loose teeth along a rip (a torn cell hanging on by a single edge) get pulled off as fibres
	var crumbs := 0
	for pass_i in 2:
		for c in ncells:
			if calive[c] == 0 or ccurl[c] == Vector3.ZERO:
				continue
			var links := 0
			for k in 3:
				if not _edge_free(c, k):
					links += 1
			if links <= 1:
				calive[c] = 0
				_touch(c)
				crumbs += 1
				if main and crumbs % 4 == 1:
					main.paper_bits(to_global(ccen[c] + VIS_OFF), global_transform.basis * push, 2)
	var comp := PackedInt32Array()
	comp.resize(ncells)
	comp.fill(-1)
	var comps: Array = []
	for c in ncells:
		if calive[c] == 0 or comp[c] != -1:
			continue
		var id := comps.size()
		var list := PackedInt32Array([c])
		comp[c] = id
		var i := 0
		while i < list.size():
			var x := list[i]
			i += 1
			for k in 3:
				for bi in cedge[x * 3 + k]:
					if bond_ok[bi] == 0:
						continue
					var y := bond_a[bi] if bond_b[bi] == x else bond_b[bi]
					if calive[y] == 1 and comp[y] == -1:
						comp[y] = id
						list.append(y)
		comps.append(list)
	if comps.size() <= 1:
		return crumbs
	var biggest := 0
	for i in comps.size():
		if comps[i].size() > comps[biggest].size():
			biggest = i
	var lost := crumbs
	for i in comps.size():
		if i == biggest:
			continue
		_spawn_debris(comps[i], push)
		lost += comps[i].size()
		for c in comps[i]:
			calive[c] = 0
			_touch(c)
	return lost


func _spawn_debris(list: PackedInt32Array, push: Vector3) -> void:
	if main == null:
		return
	var xfs := [pockets[0].global_transform, pockets[1].global_transform, pockets[2].global_transform, pockets[3].global_transform]
	if list.size() < 4:   # crumbs: just fibres flying off, no physics object
		main.paper_bits(xfs[cquad[list[0]]] * ccen[list[0]], global_transform.basis * push, 3)
		return
	_corner_offsets()
	var center := Vector3.ZERO
	var avg_n := Vector3.ZERO
	for c in list:
		var xf: Transform3D = xfs[cquad[c]]
		center += xf * _bent(cquad[c], ccen[c] + ccurl[c], ccen[c].z)
		avg_n += xf.basis * cnorm[c]
	center /= list.size()
	var arr := _arrays_for(list, xfs, center, true)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var pmat: ShaderMaterial = mat_debris.duplicate()
	var pn := avg_n.normalized() if avg_n.length() > 0.01 else Vector3.UP
	var pax := pn.cross(Vector3.UP if absf(pn.y) < 0.9 else Vector3.RIGHT).normalized()
	pmat.set_shader_parameter("piece_n", pn)
	pmat.set_shader_parameter("piece_axis", pax)
	pmat.set_shader_parameter("curl", randf_range(0.25, 0.9) * (1.0 if randf() < 0.5 else -1.0))   # torn paper curls up
	pmat.set_shader_parameter("phase", randf() * TAU)
	mesh.surface_set_material(0, pmat)
	var aabb := mesh.get_aabb()

	var rb = PaperPiece.new()
	rb.cells = list.size()
	rb.mat = pmat
	rb.nrm_local = avg_n.normalized() if avg_n.length() > 0.01 else Vector3.UP
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3.ONE * 0.03)
	cs.shape = box
	cs.position = aabb.get_center()
	rb.add_child(cs)
	rb.mass = maxf(0.004, 0.003 * list.size())
	main.add_debris(rb, center)
	var wpush := global_transform.basis * push
	rb.linear_velocity = linear_velocity * 0.5 + wpush * randf_range(1.5, 3.5) + Vector3.UP * randf_range(2.0, 4.0)
	rb.angular_velocity = Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7))
	main.sfx("flutter", center, -6.0 + minf(6.0, list.size() * 0.05))


func _die(reason: String) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	state = "dead"
	# a beaten lopp doesn't explode: it goes limp, the points sag, the jaws hang open and it tips over
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.5)
	open_target = 0.45
	if main:
		main.sfx("thump", global_position, -4.0)
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
	# the jaws are springy paper: they overshoot and bounce when they snap shut
	var k := 170.0 if not dead else 25.0
	open_v += ((open_target - open) * k - open_v * 9.0) * delta
	open += open_v * delta
	if open < 0.0:
		open = 0.0
		open_v = -open_v * 0.35
	jaw_up.rotation.x = -open
	jaw_lo.rotation.x = open * 0.3
	if state != "smash" and state != "dead":
		pitch_target = 0.0
	pitch = lerpf(pitch, pitch_target, 1.0 - exp(-12.0 * delta))
	# lean into the movement a little, like something light being pushed around
	var lv := global_transform.basis.inverse() * linear_velocity
	lean = lean.lerp(Vector2(clampf(lv.z * 0.035, -0.25, 0.25), clampf(-lv.x * 0.05, -0.25, 0.25)), 1.0 - exp(-10.0 * delta))
	visual.rotation = Vector3(pitch + lean.x, 0, lean.y)
	shake = maxf(0.0, shake - delta * 0.8)
	visual.position = VIS_OFF + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.4
	_flop(delta)
	if dirty_q != 0:
		_rebuild(false)   # spread the work: one point per frame


## Paper is floppy: when the lopp jumps, turns or gets hit, the points lag behind and wobble
## (like a jelly glued at the bottom). The bending itself happens in the shader, so no mesh rebuild.
func _flop(delta: float) -> void:
	if delta <= 0.0:
		return
	var inv := visual.global_transform.basis.inverse()
	var vel: Vector3 = inv * linear_velocity
	var dv := (vel - last_vel).limit_length(12.0)
	last_vel = vel
	var dyaw := wrapf(global_rotation.y - last_yaw, -PI, PI)
	last_yaw = global_rotation.y
	var down: Vector3 = inv * Vector3.DOWN
	var grounded := _ground
	if grounded and not was_ground:
		squash_v -= clampf(-dv.y, 0.0, 10.0) * 0.12   # landing: squish a little
	was_ground = grounded
	for q in 4:
		var kq: float = stiff[q] * (0.3 if dead else 1.0)
		var tipv: Vector3 = tips[q]
		# the body moved, the soft tips get left behind; turning swings them sideways
		bend_v[q] += -dv * 0.32 + Vector3(-dyaw * tipv.z * 1.4, 0, 0)
		var f: Vector3 = -(bend[q] - bend_set[q]) * kq - bend_v[q] * 4.5 + down * kq * (0.3 if dead else 0.045)   # spring + damping + droop (dead = limp)
		bend_v[q] += f * delta
		bend[q] = (bend[q] + bend_v[q] * delta).limit_length(1.3)
		var jaw: Node3D = pockets[q].get_parent()
		_update_fold(q, jaw.transform.basis.inverse() * bend[q])
	squash_v += (-squash * 260.0 - squash_v * 10.0) * delta
	squash += squash_v * delta
	visual.scale = Vector3(1.0 - squash * 0.5, 1.0 + squash, 1.0 - squash * 0.5)


## Paper bends, it doesn't slide: turn the tip movement into a rotation around a spot along the point
## (pivot). Everything beyond the pivot curves around it - more and more towards the tip.
func _update_fold(q: int, tip_move: Vector3) -> void:
	var b: Vector3 = base_c[q]
	var tip: Vector3 = tips[q]
	var pivot := b.lerp(tip, fold_at[q])
	var arm := tip - pivot
	var rot := arm.normalized().cross(tip_move) / maxf(arm.length(), 0.2)
	bend_rot[q] = rot
	pocket_mats[q].set_shader_parameter("bend_rot", rot)
	pocket_mats[q].set_shader_parameter("pivot", pivot)
	pocket_mats[q].set_shader_parameter("fold_start", fold_at[q])


## Same bend as the shader does, for when a bent piece tears off (so it doesn't jump)
func _bent(q: int, p: Vector3, rest_z: float) -> Vector3:
	var rot: Vector3 = bend_rot[q]
	var ang := rot.length()
	if ang < 0.0001:
		return p
	var s := smoothstep(fold_at[q], 1.0, clampf(rest_z / DEPTH, 0.0, 1.0))
	var pivot: Vector3 = (base_c[q] as Vector3).lerp(tips[q], fold_at[q])
	return pivot + (p - pivot).rotated(rot / ang, ang * s)


## A hard hit leaves a permanent fold where it landed
func fold_points(push: Vector3, power: float, near: Vector3) -> void:
	for q in 4:
		var f := clampf(1.2 - (tips[q] as Vector3).distance_to(near) / 1.4, 0.0, 1.0)
		var amount := power * f - 0.8
		if amount <= 0.0:
			continue
		var axis: Vector3 = ((tips[q] as Vector3) - (base_c[q] as Vector3)).normalized()
		var side := push - axis * push.dot(axis)            # only the sideways part folds it
		bend_set[q] = ((bend_set[q] as Vector3) + side * amount * 0.32).limit_length(0.75)
		fold_at[q] = lerpf(fold_at[q], clampf(near.z / DEPTH - 0.15, 0.1, 0.75), 0.6)   # crease where it was hit


func kick_points(dir: Vector3, amount: float, near := Vector3.INF) -> void:
	for q in 4:
		var f := 1.0
		if near != Vector3.INF:
			f = clampf(1.2 - (tips[q] as Vector3).distance_to(near) / 1.6, 0.25, 1.0)
		bend_v[q] += dir * amount * f * randf_range(0.8, 1.2)


func _facing_enemy() -> float:
	var to: Vector3 = enemy.global_position - global_position
	return _flat(global_transform.basis.z).dot(_flat(to))


func _bite_hit() -> void:
	var c := snap_charge
	var mouth := to_global(Vector3(0, 0, DEPTH * 0.5 + 0.1))
	main.sfx("snap", mouth, 0.0)
	kick_points(Vector3(0, 0, 1), 1.6 + 1.5 * snap_charge)
	if enemy == null or enemy.dead:
		return
	var info: Dictionary = enemy.nearest_cell(mouth)
	if info.d < 0.45 + 0.35 * c and _facing_enemy() > 0.4:
		var fwd := _flat(global_transform.basis.z)
		var ok: bool = enemy.receive_hit(info.p, mouth, 0.8 + 1.5 * c, 0.35 + 0.25 * c, "bite", 4.0 + 9.0 * c,
			fwd * (2.0 + 4.0 * c) + Vector3.UP * 2.0, 3.0 + 10.0 * c)
		if ok:
			main.sfx("rip", info.p, 0.0)
			main.on_hit(self, enemy, 0.4 + 0.6 * c)


func _smash_land() -> void:
	state = "idle"
	pitch_target = 0.0
	main.sfx("thump", global_position, 0.0)
	kick_points(Vector3(0, -1, 0.3), 3.5)
	squash_v -= 1.2
	var hit := false
	if enemy and not enemy.dead:
		var to: Vector3 = enemy.global_position - global_position
		to.y = 0
		if to.length() < 2.1:
			var info: Dictionary = enemy.nearest_cell(to_global(Vector3(0, -S * 0.6, DEPTH * 0.5)))
			hit = enemy.receive_hit(info.p, global_position + Vector3.UP * 1.5, 1.5, 0.8, "smash", 11.0,
				_flat(to) * 5.0 + Vector3.UP * 4.5, 4.0)
			if hit:
				main.sfx("crumple", info.p, 0.0)
				main.on_hit(self, enemy, 1.0)
	# slamming face-first into things crumples your own front a little too
	_add_dent(Vector3(0, -S * 0.3, DEPTH), 0.6, Vector3(0, 0.03, -0.06))
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
		# difficulty: how fast it thinks, how often it bites/dodges/smashes, how long it charges
		var think: Array = [[0.3, 0.55], [0.12, 0.3], [0.06, 0.16]][ai_level]
		var bite_p: float = [0.3, 0.55, 0.75][ai_level]
		var dodge_p: float = [0.08, 0.35, 0.6][ai_level]
		var smash_p: float = [0.05, 0.12, 0.18][ai_level]
		ai_t = randf_range(think[0], think[1])
		if randf() < 0.15:
			ai_strafe = -ai_strafe
		if enemy.state == "charge" and d < 2.6 and randf() < dodge_p:
			cmd_dodge()
		elif d < 2.4 and bite_cd <= 0.0 and randf() < bite_p:
			cmd_bite_start()
			ai_charge_goal = randf_range(0.1, 0.4) if ai_level == 0 else randf_range(0.2 + 0.1 * ai_level, 0.7)
		elif d > 1.6 and d < 4.5 and smash_cd <= 0.0 and randf() < smash_p:
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
