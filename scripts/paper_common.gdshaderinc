// Shared by paper.gdshader and tape.gdshader: everything that MOVES the paper,
// so tape stuck on a point bends, opens and lies on the desk exactly like the paper under it.

// ---- a lopp point bending (floppy paper + permanent folds) ----
uniform vec3 bend_rot = vec3(0.0);   // rotation axis * angle
uniform vec3 pivot = vec3(0.0);      // the spot along the point where it bends
uniform float fold_start = 0.25;     // 0 = bends from the base, 1 = only the tip
// ---- a torn-off piece: curled and flapping in the air ----
uniform float curl = 0.0;
uniform float flutter = 0.0;
uniform vec3 piece_n = vec3(0.0, 1.0, 0.0);
uniform vec3 piece_axis = vec3(1.0, 0.0, 0.0);
uniform float phase = 0.0;
// ---- jaws + desk ----
uniform float jaw = 0.0;             // jaw opening angle for this point
uniform float hinge_z0 = -0.5;       // depth of the back fold line in the middle (the back tip)
uniform float hinge_z1 = -0.05;      // ... and out at the sides
uniform float floor_y = -1000.0;     // desk height: paper can lie on it but never go through
uniform vec4 desk = vec4(-15.0, 15.0, -8.0, 8.0);   // desk edges (x min, x max, z min, z max)

vec3 rot3(vec3 v, vec3 ax, float a) {
	return v * cos(a) + cross(ax, v) * sin(a) + ax * dot(ax, v) * (1.0 - cos(a));
}

// depth = how far out along the point (0 base .. 1 tip), t = time, model = MODEL_MATRIX
void deform(inout vec3 v, inout vec3 n, float depth, float t, mat4 model) {
	// the point bends around its pivot, more and more towards the tip
	float ang = length(bend_rot);
	if (ang > 0.0001) {
		float s = smoothstep(fold_start, 1.0, clamp(depth, 0.0, 1.0));
		vec3 ax = bend_rot / ang;
		v = pivot + rot3(v - pivot, ax, ang * s);
		n = rot3(n, ax, ang * s);
	}
	// the jaws open by BENDING the paper around the back fold line
	if (jaw != 0.0) {
		vec3 xa = vec3(1.0, 0.0, 0.0);
		float hz = mix(hinge_z0, hinge_z1, clamp(abs(v.x), 0.0, 1.0));
		float hd = length(vec2(v.y, v.z - hz));
		float a = jaw * smoothstep(0.03, 0.45, hd);
		vec3 piv = vec3(0.0, 0.0, hz);
		v = piv + rot3(v - piv, xa, a);
		n = rot3(n, xa, a);
	}
	// torn pieces: curl like a scrap of paper, ripple while flying
	if (curl != 0.0 || flutter != 0.0) {
		vec3 bx = normalize(cross(piece_n, piece_axis));
		float a = dot(v, piece_axis);
		float b = dot(v, bx);
		float h = curl * a * a + flutter * (sin(a * 7.0 + t * 15.0 + phase) + 0.6 * sin(b * 5.0 + t * 11.0));
		float dh = 2.0 * curl * a + flutter * 7.0 * cos(a * 7.0 + t * 15.0 + phase);
		v += piece_n * h;
		float side = sign(dot(n, piece_n));
		n = normalize(n - piece_axis * dh * side);
	}
	// lie on the desk, never through it
	if (floor_y > -999.0) {
		vec4 wp = model * vec4(v, 1.0);
		if (wp.y < floor_y && wp.x > desk.x && wp.x < desk.y && wp.z > desk.z && wp.z < desk.w) {
			wp.y = floor_y;
			v = (inverse(model) * wp).xyz;
		}
	}
}
