extends RigidBody3D
## A torn-off piece of paper. Paper is so light and flat that AIR matters more than weight:
## moving flat-side-first through the air is very hard (big drag), moving edge-first is easy.
## That difference is what makes real paper flutter and glide instead of dropping like a stone.

var nrm_local := Vector3.UP   # which way the flat side faces (in the piece's own space)
var cells := 1
var mat: ShaderMaterial      # its own material, so it can ripple on its own


func _ready() -> void:
	custom_integrator = false
	linear_damp = 0.3
	angular_damp = 1.2
	can_sleep = true


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	var v := st.linear_velocity
	if v.length_squared() < 0.0004:
		return
	var n := st.transform.basis * nrm_local
	var vn := v.dot(n)
	var k := 0.012 * cells   # bigger piece = more air pushing on it
	# drag against the flat side
	st.apply_central_force(-n * vn * absf(vn) * k)
	# air also tips the piece so it rocks back and forth (falling-leaf motion)
	st.apply_torque(n.cross(v.normalized()) * vn * k * 0.05)


func _process(_delta: float) -> void:
	if mat == null:
		return
	if freeze:
		mat.set_shader_parameter("flutter", 0.0)   # landed: keep the curl, stop rippling
		set_process(false)
		return
	mat.set_shader_parameter("flutter", clampf(linear_velocity.length() * 0.012, 0.0, 0.05))
