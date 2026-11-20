extends Node3D
## Rico as a real 3D model with a subtle hologram shader. Built from code:
## a lathed bullet (brass casing + copper tip), 3D eyes with lids, brows, mouth and arms.
## rico.gd drives the pose every frame through apply_pose().

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back;
uniform vec3 base_color : source_color = vec3(0.88, 0.67, 0.27);
uniform vec3 hi_color : source_color = vec3(1.0, 0.94, 0.75);
uniform vec3 shade_color : source_color = vec3(0.45, 0.28, 0.08);
uniform vec3 glow_color : source_color = vec3(1.0, 0.78, 0.45);
uniform float alpha = 0.9;
uniform float glow = 0.95;
uniform float spec_power = 40.0;
uniform float spec_amount = 1.1;
uniform float metal_band = 0.3;
uniform float scan = 0.24;
uniform float flicker = 1.0;
uniform float time_s = 0.0;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize(vec3(-0.55, 0.65, 0.55));
	float diff = clamp(dot(n, l), 0.0, 1.0);
	vec3 h = normalize(l + v);
	float spec = pow(clamp(dot(n, h), 0.0, 1.0), spec_power) * spec_amount;
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.2);
	vec3 col = mix(shade_color, base_color, smoothstep(-0.1, 0.85, diff));
	col += hi_color * spec;
	col += hi_color * metal_band * smoothstep(0.12, 0.0, abs(n.x + 0.45)) ;
	col += glow_color * fres * glow;
	float s = 1.0 - scan * (0.5 + 0.5 * sin(FRAGCOORD.y * 1.7 - time_s * 5.0));
	ALBEDO = col * s * flicker;
	ALPHA = clamp(alpha + fres * 0.25, 0.0, 1.0) * mix(1.0, flicker, 0.6);
}
"""

const U := 0.01   # 1 unit = 100 px of the 2D design

var mats := {}
var body: MeshInstance3D
var eyes: Array = []      # [{eye, pupil, glint, lid, low_lid, brow}]
var mouth_dots: Array = []
var mouth_open: MeshInstance3D
var tongue: MeshInstance3D
var arms: Array = []      # [{arm, hand}]
var pivot: Node3D


func _ready() -> void:
	mats.brass = _mat(Color(0.88, 0.67, 0.27), Color(1.0, 0.95, 0.76), Color(0.42, 0.26, 0.07), Color(1.0, 0.8, 0.45))
	mats.copper = _mat(Color(0.85, 0.44, 0.24), Color(1.0, 0.82, 0.68), Color(0.38, 0.15, 0.06), Color(1.0, 0.62, 0.4))
	mats.white = _mat(Color(1.0, 0.98, 0.94), Color(1, 1, 1), Color(0.78, 0.74, 0.7), Color(1, 0.9, 0.8), 0.9, 0.3, 0.0)
	mats.ink = _mat(Color(0.12, 0.07, 0.05), Color(0.6, 0.5, 0.45), Color(0.05, 0.03, 0.02), Color(0.6, 0.35, 0.2), 0.98, 0.25, 0.0)
	mats.mouth = _mat(Color(0.33, 0.09, 0.07), Color(0.6, 0.3, 0.25), Color(0.18, 0.04, 0.03), Color(0.6, 0.3, 0.2), 0.97, 0.2, 0.0)
	mats.tongue = _mat(Color(0.93, 0.45, 0.45), Color(1, 0.8, 0.8), Color(0.6, 0.25, 0.25), Color(1, 0.6, 0.6), 0.97, 0.2, 0.0)
	pivot = Node3D.new()
	add_child(pivot)
	_build_body()
	_build_face()
	_build_arms()


func _mat(base: Color, hi: Color, shade: Color, glow_c: Color, alpha := 0.76, glow := 0.95, band := 0.3) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("hi_color", hi)
	m.set_shader_parameter("shade_color", shade)
	m.set_shader_parameter("glow_color", glow_c)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("metal_band", band)
	return m


func set_fx(time_s: float, flicker: float) -> void:
	for m in mats.values():
		m.set_shader_parameter("time_s", time_s)
		m.set_shader_parameter("flicker", flicker)


# ------------------------------------------------------------------ geometry

static func tip_r(y2d: float) -> float:
	# same ogive as the 2D design: y2d from -12 (r 30) to -73 (apex)
	var u := clampf((-12.0 - y2d) / 61.0, 0.0, 1.0)
	return 30.0 * pow(1.0 - pow(u, 2.1), 0.55)


## 2D design y (down, centre origin) -> 3D height (up, base at 0).
static func h(y2d: float) -> float:
	return (71.0 - y2d) * U


func _lathe(profile: Array, mat: Material, segs := 48) -> MeshInstance3D:
	# profile: [[radius_px, y2d], ...] from bottom to top
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size() - 1:
		var r0: float = profile[i][0] * U
		var r1: float = profile[i + 1][0] * U
		var y0 := h(profile[i][1])
		var y1 := h(profile[i + 1][1])
		var slope := Vector2(r1 - r0, y1 - y0)
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p := [Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
				Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a0) * r1, y1, sin(a0) * r1)]
			var n := []
			for a in [a0, a1, a1, a0]:
				var radial := Vector3(cos(a), 0, sin(a))
				n.append((radial * slope.y - Vector3.UP * slope.x).normalized() if slope.length() > 0.0001 else radial)
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(n[idx])
				st.add_vertex(p[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


func _build_body() -> void:
	# casing: rim, groove, body, crimp
	var casing := [[0.1, 71], [33, 71], [35, 69], [35, 60], [33, 58.5], [27, 58], [27, 53], [31, 52.5], [32, 51], [32, -6], [31, -8],
		[29.5, -9], [31, -10], [31, -13], [30, -14.5]]
	pivot.add_child(_lathe(casing, mats.brass))
	var tip := []
	for i in 25:
		var y := lerpf(-12.0, -73.0, float(i) / 24.0)
		tip.append([tip_r(y), y])
	tip[0] = [30.5, -13.0]
	pivot.add_child(_lathe(tip, mats.copper))


func _sphere(r: float, mat: Material, hemi := false) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * (1.0 if hemi else 2.0)
	m.is_hemisphere = hemi
	m.radial_segments = 28
	m.rings = 14
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	pivot.add_child(mi)
	return mi


func _capsule(r: float, len: float, mat: Material) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = len
	m.radial_segments = 16
	m.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	pivot.add_child(mi)
	return mi


## Point on the front of the tip surface at design coords (x px, y2d).
func surface_point(x: float, y2d: float, out := 0.0) -> Vector3:
	var r := tip_r(y2d) if y2d < -12 else 32.0
	var xx := clampf(x, -r + 0.5, r - 0.5)
	var z := sqrt(maxf(r * r - xx * xx, 0.0))
	var p := Vector3(xx * U, h(y2d), z * U)
	var n := Vector3(xx, 0, z).normalized()
	return p + n * out


func _build_face() -> void:
	for side in [-1, 1]:
		var e := {}
		e.eye = _sphere(0.105, mats.white)
		e.pupil = _sphere(0.05, mats.ink)
		e.glint = _sphere(0.016, mats.white)
		e.lid = _sphere(0.114, mats.copper, true)
		e.low_lid = _sphere(0.113, mats.copper, true)
		e.brow = _capsule(0.022, 0.17, mats.ink)
		e.side = side
		eyes.append(e)
	for i in 11:
		mouth_dots.append(_sphere(0.019, mats.ink))
	mouth_open = _sphere(0.09, mats.mouth)
	tongue = _sphere(0.05, mats.tongue)


func _build_arms() -> void:
	for side in [-1, 1]:
		var a := {}
		a.arm = _capsule(0.032, 0.24, mats.brass)
		a.hand = _sphere(0.055, mats.brass)
		a.side = side
		arms.append(a)


# ------------------------------------------------------------------ posing

## pose: yaw, pitch, look (Vector2 -1..1), lid, low_lid, happy, brows [[tilt, raise] x2],
## mouth ("smirk"/"flat"/"frown"/"grin"/"o"), open (0..1), arms [[angle, folded] x2], shock
func apply_pose(p: Dictionary) -> void:
	pivot.rotation = Vector3(p.get("pitch", 0.0), p.get("yaw", 0.0), 0.0)
	var look: Vector2 = p.get("look", Vector2.ZERO)
	for e in eyes:
		var side: int = e.side
		var c := surface_point(12.5 * side, -38.0, -0.035)
		var r := 0.105 * (1.12 if p.get("shock", false) else 1.0)
		e.eye.position = c
		e.eye.scale = Vector3(1.0, 1.15, 0.8) * (r / 0.105)
		var dir := Vector3(look.x * 0.55, look.y * 0.5, 1.0).normalized()
		e.pupil.position = c + dir * r * 0.86
		e.pupil.scale = Vector3.ONE * (0.75 if p.get("shock", false) else 1.0)
		e.glint.position = e.pupil.position + Vector3(-0.018, 0.022, 0.035)
		# lids: hemisphere caps rotated down over the eye
		var lid: float = clampf(p.get("lid", 0.35), 0.0, 1.0)
		e.lid.position = c
		e.lid.scale = Vector3(1.0, 1.15, 0.85) * (r / 0.105)
		e.lid.rotation = Vector3(lerpf(-1.75, 1.55, lid), 0, 0)
		var low: float = clampf(p.get("low_lid", 0.0), 0.0, 1.0)
		e.low_lid.visible = low > 0.02
		e.low_lid.position = c
		e.low_lid.scale = e.lid.scale
		e.low_lid.rotation = Vector3(PI + lerpf(1.75, -1.2, low), 0, 0)
		var hide_pupil: bool = lid > 0.9 or bool(p.get("happy", false))
		e.pupil.visible = not hide_pupil
		e.glint.visible = not hide_pupil
		# brows
		var bw: Array = p.get("brows", [[0.0, 0.0], [0.0, 0.0]])[0 if side < 0 else 1]
		e.brow.position = surface_point(12.5 * side, -56.0 - float(bw[1]), 0.02)
		e.brow.rotation = Vector3(0, -side * 0.35, PI / 2 - float(bw[0]) * side)
	# mouth
	var open: float = p.get("open", 0.0)
	var kind: String = p.get("mouth", "smirk")
	mouth_open.visible = open > 0.08 or kind == "grin"
	tongue.visible = mouth_open.visible
	for d in mouth_dots:
		d.visible = not mouth_open.visible
	if mouth_open.visible:
		var o := maxf(open, 0.55 if kind == "grin" else 0.0)
		mouth_open.position = surface_point(1.0, -20.0 + (2 if kind == "grin" else 0), -0.045)
		mouth_open.scale = Vector3(0.95 + o * 0.25, 0.25 + o * 0.6, 0.45)
		tongue.position = mouth_open.position + Vector3(0, -0.03 - o * 0.02, 0.03)
		tongue.scale = Vector3(0.9, 0.35 + o * 0.25, 0.5)
	else:
		for i in mouth_dots.size():
			var x := lerpf(-8.5, 9.5, float(i) / (mouth_dots.size() - 1))
			var y := -20.0
			match kind:
				"smirk": y = -20.0 + 0.021 * (x - 9.0) * (x - 9.0) * -1.0 + 2.6
				"frown": y = -21.5 + 0.035 * x * x
				"flat": y = -20.0
				"o": y = -20.0
			mouth_dots[i].position = surface_point(x, y, 0.004)
			mouth_dots[i].visible = kind != "o" or absf(x) < 3.0
	# arms
	for a in arms:
		var side: int = a.side
		var spec: Array = p.get("arms", [[0.35, false], [0.35, false]])[0 if side < 0 else 1]
		var ang: float = spec[0]
		var shoulder := Vector3(0.30 * side, h(14.0), 0.06)
		var hand: Vector3
		if spec[1]:
			hand = Vector3(0.10 * -side, h(26.0 + side * 3.0), 0.36)
		else:
			var d2 := Vector3(sin(ang) * side, -cos(ang), 0.18).normalized()
			hand = shoulder + d2 * 0.22
		var mid := (shoulder + hand) * 0.5
		a.arm.position = mid
		var dir := (hand - shoulder)
		a.arm.scale = Vector3(1, dir.length() / 0.24, 1)
		a.arm.basis = Basis(Quaternion(Vector3.UP, dir.normalized())) * Basis.from_scale(Vector3(1, dir.length() / 0.24, 1))
		a.hand.position = hand
