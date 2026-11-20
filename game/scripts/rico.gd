extends Node2D
## Rico, the living bullet. Drawn in code so every part can squash, blink and talk.
## The node origin is the centre of his body; unscaled he is ~70 x 142 px.

signal impact(pos: Vector2, speed: float, normal: Vector2)
signal landed

enum State { IDLE, HOP, DRAG, FLY, SLEEP }

const HALF := Vector2(35, 71)
const GRAVITY := 2600.0

# Palette
const OUTLINE := Color("2a1a10")
const BRASS := Color("e0ab45")
const BRASS_SHADE := Color("b27d22")
const BRASS_LIGHT := Color("fbe08f")
const COPPER := Color("d06d3c")
const COPPER_SHADE := Color("9e4826")
const COPPER_LIGHT := Color("f6a77a")
const EYE_WHITE := Color("fffaf0")
const PUPIL := Color("1c120c")
const MOUTH := Color("5a1d14")
const TONGUE := Color("e86b6b")

var state: State = State.IDLE
var bounds := Rect2(0, 0, 800, 600)   # area Rico can move in (window coords)
var vel := Vector2.ZERO
var spin := 0.0
var hopping_to := -1.0
var hop_cooldown := 0.0
var wander_timer := 6.0
var hop_far := false
var home_x := -1.0              # saved spot for the current app (-1 = none)
var spot_ok: Callable           # func(x) -> bool, false where a focused window is

# Expression / animation
var mood := "smug"
var mood_timer := 0.0
var talking := false
var thinking := false
var listening := false
var alerting := false
var waving := 0.0
var look_at_pos := Vector2.ZERO
var t := 0.0
var blink := 0.0
var blink_timer := 3.0
var lid := 0.35
var sq := 1.0            # vertical squash (1 = normal)
var sq_vel := 0.0
var talk_open := 0.0
var drag_offset := Vector2.ZERO
var drag_vel := Vector2.ZERO
var _last_drag_pos := Vector2.ZERO

# 3D hologram
const Rico3D := preload("res://scripts/rico3d.gd")
const VP_SIZE := Vector2(300, 420)
var _vp: SubViewport
var _r3d: Node3D
var _vp_scale := 0.0
var _glitch := 0.0
var _glitch_timer := 8.0
var _gesture := ""
var _gesture_t := 0.0
var _gesture_timer := 1.5
var _fidget_timer := 12.0
var _spin3d := 0.0
var _yaw := 0.0
var docked := false          # tucked into the corner tab
var print_progress := -1.0   # 0..1 while the printer is busy (shown on his puck)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(VP_SIZE)
	add_child(_vp)
	var cam := Camera3D.new()
	cam.fov = 27.75
	cam.position = Vector3(0, 0.71, 8.5)
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.71, 0))
	_r3d = Rico3D.new()
	_vp.add_child(_r3d)


func half_extents() -> Vector2:
	return HALF * scale.x


func on_floor() -> bool:
	return position.y >= bounds.end.y - half_extents().y - 0.5


func set_mood(m: String, hold := 2.5) -> void:
	mood = m
	mood_timer = hold


func hit_test(p: Vector2) -> bool:
	if docked:
		return p.distance_to(position) < 34.0
	var local := (p - position).rotated(-rotation) / scale.x
	if local.y > 71 or local.y < -73:
		return false
	return absf(local.x) <= 38


## Screen-space bounding rect including a margin for effects.
func visual_rect(margin := 46.0) -> Rect2:
	if docked:
		return Rect2(position - Vector2(44, 34), Vector2(88, 60))
	var h := half_extents()
	var r := maxf(h.x, h.y) + margin * scale.x
	return Rect2(position - Vector2(r, r + 30 * scale.x), Vector2(r * 2, r * 2 + 30 * scale.x))


# ---------------------------------------------------------------- behaviour

func start_drag(mouse: Vector2) -> void:
	state = State.DRAG
	drag_offset = position - mouse
	_last_drag_pos = mouse
	drag_vel = Vector2.ZERO
	set_mood("worried", 999)


func drag_to(mouse: Vector2, delta: float) -> void:
	var target := mouse + drag_offset
	var inst := (mouse - _last_drag_pos) / maxf(delta, 0.001)
	drag_vel = drag_vel.lerp(inst, 0.35)
	_last_drag_pos = mouse
	position = position.lerp(target, 0.6)
	rotation = lerp_angle(rotation, clampf(-drag_vel.x * 0.0009, -0.7, 0.7), 0.2)


func release_drag() -> void:
	vel = drag_vel.limit_length(3200.0)
	spin = clampf(vel.x * 0.012, -18, 18)
	state = State.FLY
	set_mood("shock" if vel.length() > 900 else "smug", 1.0)


func fling(v: Vector2) -> void:
	vel = v
	spin = clampf(v.x * 0.012, -18, 18)
	state = State.FLY


func hop_to(x: float, far := false) -> void:
	if state == State.SLEEP and far:
		state = State.IDLE
		mood = "smug"
	if state in [State.IDLE, State.HOP]:
		hop_far = far
		hopping_to = clampf(x, bounds.position.x + half_extents().x, bounds.end.x - half_extents().x)
		state = State.HOP
		hop_cooldown = 0.15


func jump_for_joy() -> void:
	if on_floor() and state in [State.IDLE, State.HOP]:
		vel = Vector2(0, -760 * sqrt(scale.x))
		sq = 1.18
		state = State.FLY
		spin = 0.0


func sleep() -> void:
	if state in [State.IDLE, State.HOP]:
		state = State.SLEEP
		set_mood("sleep", 999)


func wake() -> void:
	if state == State.SLEEP:
		state = State.IDLE
		set_mood("shock", 0.8)
		sq = 1.15


func _process(delta: float) -> void:
	t += delta
	if docked:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		queue_redraw()
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var h := half_extents()
	var floor_y := bounds.end.y - h.y

	match state:
		State.IDLE:
			position.y = floor_y
			rotation = lerp_angle(rotation, 0.0, 0.15)
			if Cfg.g("wander") and not (talking or thinking or listening or alerting):
				wander_timer -= delta
				if wander_timer <= 0:
					wander_timer = randf_range(14, 45)
					var span := randf_range(80, 320) * (1 if randf() > 0.5 else -1)
					var target := position.x + span
					if home_x >= 0:
						target = home_x + randf_range(-110, 110)
					if spot_ok.is_valid() and not spot_ok.call(target):
						target = position.x - span
					if not spot_ok.is_valid() or spot_ok.call(target):
						hop_to(target)
		State.HOP:
			rotation = lerp_angle(rotation, 0.0, 0.2)
			hop_cooldown -= delta
			if absf(position.x - hopping_to) < 12:
				state = State.IDLE
				hop_far = false
			elif hop_cooldown <= 0 and on_floor():
				var dir := signf(hopping_to - position.x)
				var dist := minf(absf(hopping_to - position.x), (260.0 if hop_far else 70.0) * scale.x)
				var vy := 430.0 * sqrt(scale.x) + dist * 0.6
				vel = Vector2(dir * dist / (2.0 * vy / GRAVITY), -vy)
				sq = 1.12
				_integrate(delta, true)
			else:
				_integrate(delta, true)
		State.FLY:
			_integrate(delta, false)
		State.DRAG:
			pass
		State.SLEEP:
			position.y = floor_y
			rotation = lerp_angle(rotation, 0.0, 0.1)

	# squash spring
	var accel := (1.0 - sq) * 260.0 - sq_vel * 14.0
	sq_vel += accel * delta
	sq += sq_vel * delta

	# blinking
	blink_timer -= delta
	if blink_timer <= 0:
		blink = 1.0
		blink_timer = randf_range(2.0, 5.5)
	blink = maxf(0.0, blink - delta * 7.0)

	if mood_timer < 900:
		mood_timer -= delta
		if mood_timer <= 0 and state != State.SLEEP:
			mood = "smug"
			mood_timer = 999
	waving = maxf(0.0, waving - delta)

	if talking:
		talk_open = 0.5 + 0.5 * sin(t * 22.0) * sin(t * 9.0 + 1.0)
	else:
		talk_open = move_toward(talk_open, 0.0, delta * 6.0)
	_animate(delta)
	queue_redraw()


# ------------------------------------------------------------------ 3D pose + personality

func _animate(delta: float) -> void:
	# gestures while talking
	_gesture_t += delta
	if talking:
		_gesture_timer -= delta
		if _gesture_timer <= 0:
			_gesture_timer = randf_range(1.2, 2.4)
			_gesture = String(["point", "shrug", "", "lean", "point", ""][randi() % 6])
			_gesture_t = 0.0
	elif _gesture_t > 1.2:
		_gesture = ""
	# idle fidgets
	if state == State.IDLE and not (talking or thinking or listening or alerting):
		_fidget_timer -= delta
		if _fidget_timer <= 0:
			_fidget_timer = randf_range(10, 22)
			var f: String = ["spin", "look", "spin", "stretch"][randi() % 4]
			if f == "spin":
				_spin3d = TAU
			else:
				_gesture = f
				_gesture_t = 0.0
	_spin3d = move_toward(_spin3d, 0.0, delta * 7.5)
	# glitches (subtle)
	_glitch_timer -= delta
	if _glitch_timer <= 0:
		_glitch_timer = randf_range(6, 15)
		_glitch = 0.14
	_glitch = maxf(0.0, _glitch - delta)
	var flick := 1.0 - (0.25 if _glitch > 0 else 0.0) - 0.03 * sin(t * 37.0) * sin(t * 13.0)
	if state == State.SLEEP:
		flick *= 0.75
	# viewport size follows Rico's scale so he stays crisp
	if absf(scale.x - _vp_scale) > 0.01:
		_vp_scale = scale.x
		_vp.size = Vector2i(VP_SIZE * scale.x)
	_r3d.set_fx(t, flick)
	_r3d.apply_pose(_pose(delta))


func _pose(delta: float) -> Dictionary:
	var p := {}
	var lid_target := 0.35
	var low := 0.0
	var happy := false
	match mood:
		"smug": lid_target = 0.38
		"happy": happy = true; lid_target = 0.5; low = 0.0
		"worried": lid_target = 0.08
		"shock": lid_target = 0.0
		"annoyed": lid_target = 0.58
		"sleep": lid_target = 1.0
		"think": lid_target = 0.28
	if listening or alerting:
		lid_target = 0.02
	if _gesture == "shrug":
		lid_target = 0.2
	lid = lerpf(lid, lid_target, 0.2)
	p.lid = clampf(maxf(lid, blink), 0.0, 1.0)
	p.low_lid = low
	p.happy = false
	p.shock = mood == "shock"
	# where he looks
	var look := (look_at_pos - position).rotated(-rotation)
	var lv := Vector2(clampf(look.x / 500.0, -1, 1), clampf(-look.y / 400.0, -1, 1))
	if thinking:
		lv = Vector2(0.5, 0.8)
	if state == State.HOP:
		lv = Vector2(signf(hopping_to - position.x), 0)
	p.look = lv
	var yaw_target := lv.x * 0.45 + sin(t * 0.6) * 0.06
	if _gesture == "look":
		yaw_target = sin(_gesture_t * 4.0) * 0.6
	_yaw = lerp_angle(_yaw, yaw_target, minf(1.0, delta * 6.0))
	p.yaw = _yaw + _spin3d
	p.pitch = -lv.y * 0.1
	# brows [tilt, raise] for left, right
	var bl := [0.0, 0.0]
	var br := [0.0, 0.0]
	match mood:
		"smug": bl = [0.05, 0.0]; br = [-0.25, 3.0]
		"worried": bl = [-0.35, 2.0]; br = [0.35, 2.0]
		"shock": bl = [0.0, 4.5]; br = [0.0, 4.5]
		"annoyed": bl = [0.35, 0.0]; br = [-0.35, 0.0]
		"happy": bl = [0.0, 2.5]; br = [0.0, 2.5]
		"think": bl = [0.2, 2.0]; br = [0.2, 0.0]
	if listening or _gesture == "shrug":
		bl = [0.0, 4.0]; br = [0.0, 4.0]
	p.brows = [bl, br]
	# mouth
	var kind := "smirk"
	match mood:
		"happy": kind = "grin"
		"worried", "annoyed": kind = "frown"
		"sleep": kind = "o"
	if _gesture == "shrug" and not talking:
		kind = "flat"
	var open := talk_open
	if mood == "shock" or alerting:
		open = maxf(open, 0.7)
	p.mouth = kind
	p.open = open
	# arms [angle, folded]
	p.arms = [_arm_spec(-1), _arm_spec(1)]
	return p


func _arm_spec(side: int) -> Array:
	var a := 0.35 + 0.05 * sin(t * 2.0 + side)
	var folded := false
	match mood:
		"smug":
			if talking:
				a = 0.5 + 0.25 * sin(t * 5.0 + side)
			else:
				folded = true
		"worried", "shock":
			a = 1.6 + 0.9 * sin(t * 16.0 + side * 1.7)
		"happy":
			a = 2.3 + 0.3 * sin(t * 10.0 + side)
	match _gesture:
		"point":
			if side == 1: a = 2.9 + 0.08 * sin(t * 6.0); folded = false
		"shrug":
			a = 1.9; folded = false
		"stretch":
			a = 2.8 + 0.2 * sin(_gesture_t * 5.0); folded = false
		"lean":
			a = 0.9 + 0.3 * sin(t * 4.0 + side); folded = false
	if state == State.DRAG:
		a = 1.9 + 0.8 * sin(t * 18.0 + side * 2.0); folded = false
	if thinking and side == 1:
		a = 2.75; folded = false
	if listening:
		a = 2.0 if side == 1 else 0.4; folded = false
	if alerting:
		a = 2.6 + 0.45 * sin(t * 14.0 + side * 1.5); folded = false
	if waving > 0 and side == 1:
		a = 2.5 + 0.5 * sin(t * 14.0); folded = false
	if state == State.SLEEP:
		a = 0.15; folded = false
	return [a, folded]


func _integrate(delta: float, hop: bool) -> void:
	var h := half_extents()
	vel.y += GRAVITY * delta
	position += vel * delta
	if not hop:
		rotation += spin * delta
		spin = move_toward(spin, 0.0, delta * 2.0)
	var speed := vel.length()
	# walls
	if position.x - h.x < bounds.position.x:
		position.x = bounds.position.x + h.x
		if vel.x < 0:
			if not hop and absf(vel.x) > 220: impact.emit(position - Vector2(h.x, 0), speed, Vector2.RIGHT)
			vel.x = -vel.x * 0.72
			spin = -spin * 0.8 + vel.y * 0.004
	elif position.x + h.x > bounds.end.x:
		position.x = bounds.end.x - h.x
		if vel.x > 0:
			if not hop and absf(vel.x) > 220: impact.emit(position + Vector2(h.x, 0), speed, Vector2.LEFT)
			vel.x = -vel.x * 0.72
			spin = -spin * 0.8 - vel.y * 0.004
	if position.y - h.y < bounds.position.y:
		position.y = bounds.position.y + h.y
		if vel.y < 0:
			if absf(vel.y) > 220: impact.emit(position - Vector2(0, h.y), speed, Vector2.DOWN)
			vel.y = -vel.y * 0.6
	# floor
	var floor_y := bounds.end.y - h.y
	if position.y >= floor_y:
		position.y = floor_y
		if vel.y > 0:
			if not hop and vel.y > 380:
				impact.emit(position + Vector2(0, h.y), speed, Vector2.UP)
				vel.y = -vel.y * 0.5
				spin *= 0.6
				sq = 0.8
			else:
				sq = 0.82 if vel.y > 200 else sq
				vel.y = 0
				vel.x *= 0.0 if hop else 0.85
				if not hop and absf(vel.x) < 40:
					state = State.IDLE
					vel = Vector2.ZERO
					spin = 0.0
					landed.emit()
				elif not hop:
					rotation = lerp_angle(rotation, 0.0, 0.3)


# ---------------------------------------------------------------- drawing

func _tip_hw(y: float) -> float:
	# ogive from y=-12 (hw 30) to apex y=-73
	var u := clampf((-12.0 - y) / 61.0, 0.0, 1.0)
	return 30.0 * pow(1.0 - pow(u, 2.1), 0.55)


func _band(y0: float, y1: float, f0: float, f1: float, tip: bool, hw := 32.0, steps := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var y := lerpf(y0, y1, float(i) / steps)
		var w := _tip_hw(y) if tip else hw
		pts.append(Vector2(f0 * w, y))
	for i in range(steps, -1, -1):
		var y := lerpf(y0, y1, float(i) / steps)
		var w := _tip_hw(y) if tip else hw
		pts.append(Vector2(f1 * w, y))
	return pts


func _rrect(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[r.position + Vector2(r.size.x - rad, rad), -PI / 2],
		[r.end - Vector2(rad, rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2],
		[r.position + Vector2(rad, rad), PI],
	]
	for c in corners:
		for i in 7:
			var a: float = c[1] + (PI / 2) * i / 6.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return pts


func _outlined(pts: PackedVector2Array, fill: Color, w := 3.0) -> void:
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, OUTLINE, w, true)


func _ellipse(c: Vector2, r: Vector2, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


func _draw() -> void:
	if docked:
		_draw_docked()
		return
	_draw_hologram()
	_draw_extras()


## The corner tab: just his glowing emitter puck, waiting to be clicked.
func _draw_docked() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var glow := Color(1.0, 0.76, 0.42)
	var pulse := 0.6 + 0.4 * sin(t * 2.4)
	draw_colored_polygon(_ellipse(Vector2(0, 8), Vector2(30, 8)), Color("221c18"))
	draw_colored_polygon(_ellipse(Vector2(0, 5), Vector2(30, 8)), Color("4a3a2c"))
	draw_colored_polygon(_ellipse(Vector2(0, 4), Vector2(23, 5.5)), Color("8c6a3c"))
	draw_colored_polygon(_ellipse(Vector2(0, 4), Vector2(16, 3.8)), Color(glow, 0.6 + 0.3 * pulse))
	draw_colored_polygon(_ellipse(Vector2(0, 4), Vector2(7, 1.8)), Color(1, 1, 0.92))
	var beam := PackedVector2Array([Vector2(-12, 3), Vector2(12, 3), Vector2(20, -26), Vector2(-20, -26)])
	draw_polygon(beam, PackedColorArray([Color(glow, 0.25 * pulse), Color(glow, 0.25 * pulse), Color(glow, 0.0), Color(glow, 0.0)]))
	for i in 3:
		var ph := fmod(t * 0.5 + i / 3.0, 1.0)
		draw_circle(Vector2(sin(i * 7.0 + t) * 8.0, 0 - ph * 26), 1.3, Color(1, 0.9, 0.7, (1.0 - ph) * 0.8), true, -1.0, true)
	if print_progress >= 0:
		_draw_progress(Vector2(0, 5), 30.0, 8.0)


func _draw_hologram() -> void:
	var sx := 1.0 / sqrt(maxf(sq, 0.3))
	var h := half_extents()
	# floor shadow
	var floor_gap := (bounds.end.y - h.y) - position.y
	if floor_gap < 300 and state != State.DRAG:
		var sa := clampf(1.0 - floor_gap / 300.0, 0.0, 1.0) * 0.25
		draw_set_transform(Vector2(0, 71 + floor_gap / scale.x).rotated(-rotation), -rotation, Vector2.ONE)
		draw_colored_polygon(_ellipse(Vector2.ZERO, Vector2(36 * (1.0 - floor_gap / 600.0), 6)), Color(0, 0, 0, sa))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var glow := Color(1.0, 0.76, 0.42)
	var bob := sin(t * 2.2) * 2.0
	var dim := 0.6 if state == State.SLEEP else 1.0
	# light cone from the emitter
	var top_y := -78.0
	var base_y := 64.0
	var cone := PackedVector2Array([Vector2(-20, base_y), Vector2(20, base_y), Vector2(50, top_y), Vector2(-50, top_y)])
	var cc := PackedColorArray([Color(glow, 0.22 * dim), Color(glow, 0.22 * dim), Color(glow, 0.0), Color(glow, 0.0)])
	draw_polygon(cone, cc)
	# emitter puck
	draw_colored_polygon(_ellipse(Vector2(0, 70), Vector2(38, 9)), Color("221c18"))
	draw_colored_polygon(_ellipse(Vector2(0, 67), Vector2(38, 9)), Color("4a3a2c"))
	draw_colored_polygon(_ellipse(Vector2(0, 66), Vector2(30, 6.6)), Color("8c6a3c"))
	draw_colored_polygon(_ellipse(Vector2(0, 66), Vector2(21, 4.6)), Color(glow, 0.85 * dim))
	draw_colored_polygon(_ellipse(Vector2(0, 66), Vector2(10, 2.2)), Color(1, 1, 0.92, dim))
	if print_progress >= 0:
		_draw_progress(Vector2(0, 67), 38.0, 9.0)
	# motes drifting up the beam
	for i in 7:
		var ph := fmod(t * 0.35 + i * 0.137, 1.0)
		var mx := sin(i * 12.9 + t * 0.8) * 26.0 * (0.4 + ph)
		draw_circle(Vector2(mx, 60 - ph * 130), 1.4, Color(1, 0.9, 0.7, (1.0 - ph) * 0.6 * dim), true, -1.0, true)
	# the 3D Rico, hovering above the puck
	draw_set_transform(Vector2(0, 71.0 * (1.0 - sq) - 16 + bob), 0.0, Vector2(sx, sq))
	var tex := _vp.get_texture()
	var rect := Rect2(-VP_SIZE.x * 0.5, -VP_SIZE.y * 0.5, VP_SIZE.x, VP_SIZE.y)
	var tint := Color(1, 1, 1, 0.97 * dim)
	if _glitch > 0:
		var strips := 5
		for i in strips:
			var r0 := Rect2(rect.position.x, rect.position.y + rect.size.y * i / strips, rect.size.x, rect.size.y / strips)
			var src := Rect2(0, tex.get_height() * float(i) / strips, tex.get_width(), tex.get_height() / float(strips))
			var off := randf_range(-4, 4) if i % 2 == 0 else 0.0
			draw_texture_rect_region(tex, Rect2(r0.position + Vector2(off, 0), r0.size), src, tint)
	else:
		# soft halo and a faint colour fringe sell the projection
		draw_texture_rect(tex, rect.grow(6), false, Color(1.0, 0.75, 0.4, 0.16 * dim))
		draw_texture_rect(tex, Rect2(rect.position + Vector2(-1.6, 0), rect.size), false, Color(1.0, 0.35, 0.2, 0.22 * dim))
		draw_texture_rect(tex, Rect2(rect.position + Vector2(1.6, 0), rect.size), false, Color(0.3, 0.8, 1.0, 0.18 * dim))
		draw_texture_rect(tex, rect, false, tint)
		# a scan band sweeping up through him every few seconds
		var sweep := fmod(t * 0.35, 1.0)
		var sy := rect.end.y - sweep * rect.size.y
		draw_texture_rect_region(tex, Rect2(rect.position.x, sy, rect.size.x, 6), Rect2(0, (sy - rect.position.y) / rect.size.y * tex.get_height(), tex.get_width(), 6.0 / rect.size.y * tex.get_height()), Color(1.6, 1.4, 1.1, 0.5 * dim))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)



## Elliptical progress ring around the puck while the 3D printer is busy.
func _draw_progress(c: Vector2, rx: float, ry: float) -> void:
	var n := 48
	var pts := PackedVector2Array()
	var done := int(n * clampf(print_progress, 0.0, 1.0))
	for i in n + 1:
		var a := -PI / 2 + TAU * i / n
		pts.append(c + Vector2(cos(a) * (rx + 4), sin(a) * (ry + 2.5)))
	draw_polyline(pts, Color(1, 1, 1, 0.12), 2.5, true)
	if done > 0:
		draw_polyline(pts.slice(0, done + 1), Color("86dba8"), 3.0, true)


func _draw_legacy() -> void:
	var sx := 1.0 / sqrt(maxf(sq, 0.3))
	# floor shadow (only in screen space below him when near the floor)
	var h := half_extents()
	var floor_gap := (bounds.end.y - h.y) - position.y
	if floor_gap < 300 and state != State.DRAG:
		var a := clampf(1.0 - floor_gap / 300.0, 0.0, 1.0) * 0.28
		draw_set_transform(Vector2(0, 71 + floor_gap / scale.x).rotated(-rotation), -rotation, Vector2.ONE)
		draw_colored_polygon(_ellipse(Vector2.ZERO, Vector2(34 * (1.0 - floor_gap / 600.0), 6)), Color(0, 0, 0, a))
	draw_set_transform(Vector2(0, 71.0 * (1.0 - sq)), 0.0, Vector2(sx, sq))

	# casing body (polished metal: a light-to-dark ramp, specular streak and rim light)
	var body := _rrect(Rect2(-32, -10, 64, 64), 5)
	draw_colored_polygon(body, BRASS)
	_metal(-8, 52, false, 32.0, BRASS_RAMP)
	draw_colored_polygon(_band(-6, 50, -0.6, -0.47, false), Color(1, 1, 0.92, 0.55))
	draw_colored_polygon(_band(-6, 50, -0.44, -0.4, false), Color(1, 1, 0.92, 0.25))
	draw_colored_polygon(_band(8, 14, -0.95, 0.95, false), Color(1, 1, 1, 0.07))
	var closed := body.duplicate(); closed.append(body[0])
	draw_polyline(closed, OUTLINE, 3.0, true)
	# decorative band
	draw_line(Vector2(-31, 30), Vector2(31, 30), Color(OUTLINE, 0.45), 2.0, true)
	draw_line(Vector2(-31, 35), Vector2(31, 35), Color(OUTLINE, 0.25), 1.5, true)
	# groove + rim
	_outlined(_rrect(Rect2(-27, 53, 54, 6), 2), BRASS_SHADE, 2.5)
	_outlined(_rrect(Rect2(-35, 58, 70, 13), 4), BRASS, 3.0)
	draw_colored_polygon(_rrect(Rect2(14, 60, 18, 9), 3), BRASS_SHADE)
	draw_line(Vector2(-30, 61), Vector2(-14, 61), BRASS_LIGHT, 2.0, true)

	_draw_arm(-1, true)
	_draw_arm(1, true)

	# copper tip
	var tip := _band(-12, -73, -1.0, 1.0, true, 30.0, 24)
	draw_colored_polygon(tip, COPPER)
	_metal(-12, -71, true, 30.0, COPPER_RAMP)
	draw_colored_polygon(_band(-16, -64, -0.62, -0.5, true), Color(1, 0.95, 0.9, 0.5))
	draw_colored_polygon(_ellipse(Vector2(-11, -60), Vector2(4.5, 6.5)), Color(1, 1, 1, 0.55))
	draw_colored_polygon(_ellipse(Vector2(-8, -66), Vector2(1.8, 2.4)), Color(1, 1, 1, 0.8))
	var tclosed := tip.duplicate(); tclosed.append(tip[0])
	draw_polyline(tclosed, OUTLINE, 3.0, true)
	# crimp ring
	_outlined(_rrect(Rect2(-31, -14, 62, 6), 3), BRASS_SHADE, 2.5)

	_draw_face()
	_draw_accessory()
	_draw_extras()


const BRASS_RAMP := [[-1.0, Color("e9b955")], [-0.8, Color("f8d98a")], [-0.62, Color("fff0c0")], [-0.35, Color("f1c867")], [0.0, Color("e0ab45")], [0.35, Color("c8902f")], [0.7, Color("a06d1c")], [0.88, Color("8a5a14")], [1.0, Color("d6a447")]]
const COPPER_RAMP := [[-1.0, Color("dd7a47")], [-0.8, Color("f29a69")], [-0.6, Color("ffc09a")], [-0.35, Color("e8854f")], [0.0, Color("d06d3c")], [0.35, Color("b65a2e")], [0.7, Color("94431f")], [0.88, Color("7a3418")], [1.0, Color("d27a4c")]]


func _ramp(ramp: Array, f: float) -> Color:
	for i in ramp.size() - 1:
		if f <= ramp[i + 1][0]:
			var a: float = ramp[i][0]
			var b: float = ramp[i + 1][0]
			return (ramp[i][1] as Color).lerp(ramp[i + 1][1], (f - a) / maxf(b - a, 0.001))
	return ramp[-1][1]


## Vertical bands across the width give a smooth polished-metal gradient.
func _metal(y0: float, y1: float, tip: bool, hw: float, ramp: Array) -> void:
	var n := 18
	for i in n:
		var f0 := -0.97 + 1.94 * i / n
		var f1 := -0.97 + 1.94 * (i + 1) / n
		draw_colored_polygon(_band(y0, y1, f0, f1 + 0.01, tip, hw, 12), _ramp(ramp, (f0 + f1) * 0.5))


func _draw_accessory() -> void:
	var acc := String(Cfg.g("accessory", "none"))
	match acc:
		"cap":
			var crown := PackedVector2Array()
			for i in 17:
				var a := PI + PI * i / 16.0
				crown.append(Vector2(cos(a) * 25, -61 + sin(a) * 15))
			crown.append(Vector2(25, -58)); crown.append(Vector2(-25, -58))
			_outlined(crown, Color("3d5a63"), 3.0)
			draw_colored_polygon(_ellipse(Vector2(-9, -69), Vector2(8, 3.5)), Color(1, 1, 1, 0.14))
			for k in 4:
				draw_line(Vector2(-18 + k * 12, -72 + absf(k - 1.5) * 2), Vector2(-20 + k * 12, -59), Color(0, 0, 0, 0.18), 1.5, true)
			var brim := PackedVector2Array([Vector2(8, -60), Vector2(38, -58), Vector2(40, -54), Vector2(10, -55)])
			_outlined(brim, Color("2e474f"), 3.0)
			draw_circle(Vector2(0, -76), 2.6, OUTLINE)
		"headphones":
			var arc := PackedVector2Array()
			for i in 21:
				var a := PI + PI * i / 20.0
				arc.append(Vector2(cos(a) * 31, -42 + sin(a) * 38))
			draw_polyline(arc, OUTLINE, 9.0, true)
			draw_polyline(arc, Color("3a3d46"), 5.0, true)
			for side in [-1, 1]:
				var c := Vector2(30 * side, -38)
				_outlined(_ellipse(c, Vector2(7.5, 12)), Color("2b2e36"), 3.0)
				draw_colored_polygon(_ellipse(c + Vector2(1.5 * side, 0), Vector2(3.5, 7)), Color("e8814c"))
		"scarf":
			var t2 := t * 3.0
			var wrap := _rrect(Rect2(-34, -17, 68, 13), 6)
			_outlined(wrap, Color("b8323a"), 3.0)
			for k in 5:
				draw_line(Vector2(-26 + k * 13, -16), Vector2(-30 + k * 13, -5), Color("f3e3c3", 0.7), 3.0, true)
			var tail := PackedVector2Array([Vector2(16, -8), Vector2(28, -6), Vector2(31 + sin(t2) * 3, 22), Vector2(19 + sin(t2) * 3, 24)])
			_outlined(tail, Color("a72b33"), 3.0)
			draw_line(Vector2(21 + sin(t2) * 3, 18), Vector2(30 + sin(t2) * 3, 17), Color("f3e3c3", 0.8), 3.0, true)
			for k in 4:
				draw_line(Vector2(20 + k * 3 + sin(t2) * 3, 24), Vector2(20 + k * 3 + sin(t2 + 0.5) * 4, 30), OUTLINE, 2.0, true)
		"beanie":
			var hat := PackedVector2Array()
			for i in 17:
				var a := PI + PI * i / 16.0
				hat.append(Vector2(cos(a) * 26, -60 + sin(a) * 18))
			hat.append(Vector2(26, -57)); hat.append(Vector2(-26, -57))
			_outlined(hat, Color("3e7d5a"), 3.0)
			for k in 7:
				var x := -21 + k * 7
				draw_line(Vector2(x, -61 - (18 - absf(x) * 0.5)), Vector2(x, -60), Color(0, 0, 0, 0.16), 2.0, true)
			_outlined(_rrect(Rect2(-28, -62, 56, 9), 4), Color("336b4c"), 3.0)
			draw_circle(Vector2(0, -80), 7.0, OUTLINE)
			draw_circle(Vector2(0, -80), 5.2, Color("f3e3c3"))


func _draw_arm(side: int, _front: bool) -> void:
	var shoulder := Vector2(29 * side, 14)
	var a := 0.35 + 0.05 * sin(t * 2.0 + side)
	match mood:
		"smug":
			a = -1.05 if not talking else 0.5 + 0.25 * sin(t * 5.0 + side)
		"worried", "shock":
			a = 1.6 + 0.9 * sin(t * 16.0 + side * 1.7)
		"happy":
			a = 2.3 + 0.3 * sin(t * 10.0 + side)
	if state == State.DRAG:
		a = 1.9 + 0.8 * sin(t * 18.0 + side * 2.0)
	if thinking and side == 1:
		a = 2.75
	if listening:
		a = 2.0 if side == 1 else 0.4
	if alerting:
		a = 2.6 + 0.45 * sin(t * 14.0 + side * 1.5)
	if waving > 0 and side == 1:
		a = 2.5 + 0.5 * sin(t * 14.0)
	if state == State.SLEEP:
		a = 0.15
	var dir := Vector2(sin(a) * side, cos(a))
	var hand := shoulder + dir * 20.0
	if mood == "smug" and not talking and state != State.DRAG and not thinking and not alerting and waving <= 0 and not listening:
		hand = Vector2(10 * -side, 26 + side * 3)   # arms folded across the casing
	draw_line(shoulder, hand, OUTLINE, 7.0, true)
	draw_line(shoulder, hand, BRASS_SHADE, 3.5, true)
	draw_circle(hand, 6.0, OUTLINE)
	draw_circle(hand, 4.2, BRASS)


func _draw_face() -> void:
	var eye_y := -38.0
	var lid_target := 0.35
	var happy_eyes := false
	match mood:
		"smug": lid_target = 0.38
		"happy": happy_eyes = true
		"worried": lid_target = 0.05
		"shock": lid_target = 0.0
		"annoyed": lid_target = 0.55
		"sleep": lid_target = 1.0
		"think": lid_target = 0.25
	if listening: lid_target = 0.0
	if alerting: lid_target = 0.0
	lid = lerpf(lid, lid_target, 0.2)
	var l := clampf(maxf(lid, blink), 0.0, 1.0)

	# where to look (local space)
	var look := look_at_pos - position
	look = look.rotated(-rotation)
	var pupil_off := look.normalized() * minf(look.length() * 0.02, 4.5)
	if thinking:
		pupil_off = Vector2(3, -4.5)
	if state == State.HOP:
		pupil_off = Vector2(signf(hopping_to - position.x) * 4.5, 0)

	for side in [-1, 1]:
		var c := Vector2(12.5 * side, eye_y)
		var r := Vector2(10.5, 12.5)
		if mood == "shock": r *= 1.12
		if happy_eyes:
			var arc := PackedVector2Array()
			for i in 9:
				var aa := PI + PI * i / 8.0
				arc.append(c + Vector2(cos(aa) * 8, sin(aa) * 7 + 3))
			draw_polyline(arc, OUTLINE, 4.0, true)
			continue
		var eye := _ellipse(c, r)
		draw_colored_polygon(eye, EYE_WHITE)
		var pr := 5.2 if mood != "shock" else 3.6
		var pc := c + pupil_off
		draw_circle(pc, pr, PUPIL)
		draw_circle(pc + Vector2(-1.8, -2.2), 1.6, Color.WHITE)
		# eyelid
		if l > 0.02:
			var lid_y := c.y - r.y + 2 * r.y * l
			var lp := PackedVector2Array()
			for i in 15:
				var a := PI + PI * i / 14.0
				var p := c + Vector2(cos(a) * (r.x + 1.5), sin(a) * (r.y + 1.5))
				lp.append(Vector2(p.x, minf(p.y, lid_y)))
			if l > 0.5:
				for i in 15:
					var a := PI * i / 14.0
					var p := c + Vector2(cos(a) * (r.x + 1.5), sin(a) * (r.y + 1.5))
					lp.append(Vector2(p.x, minf(p.y, lid_y)))
			else:
				lp.append(Vector2(c.x + r.x + 1.5, lid_y))
				lp.append(Vector2(c.x - r.x - 1.5, lid_y))
			draw_colored_polygon(lp, COPPER)
			var half_w := r.x * sqrt(maxf(0.0, 1.0 - pow((lid_y - c.y) / r.y, 2)))
			draw_line(Vector2(c.x - half_w, lid_y), Vector2(c.x + half_w, lid_y), OUTLINE, 2.5, true)
		var outline := eye.duplicate(); outline.append(eye[0])
		draw_polyline(outline, OUTLINE, 2.5, true)

		# brows
		var bc := Vector2(12.5 * side, -55.5)
		var tilt := 0.0
		var raise := 0.0
		match mood:
			"smug":
				tilt = -0.25 * side if side == 1 else 0.05
				raise = 3.0 if side == 1 else 0.0
			"worried": tilt = 0.35 * side; raise = 2.0
			"shock": raise = 4.5
			"annoyed": tilt = -0.35 * side
			"happy": raise = 2.5
			"think": tilt = -0.2 * side if side == -1 else 0.2; raise = 2.0 if side == -1 else 0.0
		if listening: raise = 3.0
		var bd := Vector2(cos(tilt), sin(tilt)) * 7.5
		draw_line(bc - bd + Vector2(0, -raise), bc + bd + Vector2(0, -raise), OUTLINE, 4.0, true)

	_draw_mouth()


func _draw_mouth() -> void:
	var c := Vector2(1, -20.5)
	var open := talk_open
	if mood == "shock" or alerting: open = maxf(open, 0.7)
	if listening: open = maxf(open, 0.2)
	if open > 0.08:
		var m := _ellipse(c, Vector2(7.5 + open * 1.5, 2.0 + open * 5.0), 20)
		draw_colored_polygon(m, MOUTH)
		draw_colored_polygon(_ellipse(c + Vector2(0, 1.5 + open * 2.5), Vector2(4.5, 1.2 + open * 1.8), 14), TONGUE)
		var mc := m.duplicate(); mc.append(m[0])
		draw_polyline(mc, OUTLINE, 2.5, true)
		return
	var pts := PackedVector2Array()
	match mood:
		"happy":
			var grin := PackedVector2Array()
			for i in 13:
				var a := PI * i / 12.0
				grin.append(c + Vector2(cos(a) * 9, sin(a) * 6 - 1))
			draw_colored_polygon(grin, MOUTH)
			grin.append(grin[0])
			draw_polyline(grin, OUTLINE, 2.5, true)
			return
		"worried", "annoyed":
			for i in 9:
				var x := -7.0 + 14.0 * i / 8.0
				pts.append(c + Vector2(x, 0.06 * x * x - 2 + 1.2 * sin(x * 0.9)))
		"sleep":
			draw_circle(c + Vector2(0, 1), 2.6, MOUTH)
			return
		_:
			# lopsided smirk
			for i in 10:
				var x := -8.0 + 17.0 * i / 9.0
				var y := -0.035 * (x - 8.0) * (x - 8.0) * 0.6 + 1.5
				pts.append(c + Vector2(x, y + 2.0))
	draw_polyline(pts, OUTLINE, 3.0, true)


func _draw_extras() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	if state == State.SLEEP:
		for i in 3:
			var ph := fmod(t * 0.5 + i / 3.0, 1.0)
			var p := Vector2(30 + ph * 28 + sin(ph * 6 + i) * 5, -70 - ph * 55)
			draw_string_outline(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 + ph * 14), 4, Color(1, 1, 1, (1.0 - ph) * 0.9))
			draw_string(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 + ph * 14), Color(OUTLINE, 1.0 - ph))
	if alerting:
		var bob := sin(t * 12) * 3
		draw_string(font, Vector2(-9, -86 + bob), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("ffcf3a"))
		draw_string_outline(font, Vector2(-9, -86 + bob), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 5, OUTLINE)
		draw_string(font, Vector2(-9, -86 + bob), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("ffcf3a"))
	if thinking:
		for i in 3:
			var on := int(t * 3.0) % 4 > i
			draw_circle(Vector2(-30 - i * 9, -70 - i * 8), 3.0 + i, Color(OUTLINE, 0.9 if on else 0.25))
	if listening:
		for i in 3:
			var ph := fmod(t * 1.2 + i / 3.0, 1.0)
			var rr := 50.0 + ph * 40.0
			draw_arc(Vector2(0, -20), rr, -PI * 0.85, -PI * 0.15, 32, Color(0.98, 0.35, 0.3, (1.0 - ph) * 0.8), 3.0, true)
