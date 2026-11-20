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


func half_extents() -> Vector2:
	return HALF * scale.x


func on_floor() -> bool:
	return position.y >= bounds.end.y - half_extents().y - 0.5


func set_mood(m: String, hold := 2.5) -> void:
	mood = m
	mood_timer = hold


func hit_test(p: Vector2) -> bool:
	var local := (p - position).rotated(-rotation) / scale.x
	if local.y > 71 or local.y < -73:
		return false
	return absf(local.x) <= 38


## Screen-space bounding rect including a margin for effects.
func visual_rect(margin := 46.0) -> Rect2:
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


func hop_to(x: float) -> void:
	if state in [State.IDLE, State.HOP]:
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
					hop_to(position.x + span)
		State.HOP:
			rotation = lerp_angle(rotation, 0.0, 0.2)
			hop_cooldown -= delta
			if absf(position.x - hopping_to) < 12:
				state = State.IDLE
			elif hop_cooldown <= 0 and on_floor():
				var dir := signf(hopping_to - position.x)
				var dist := minf(absf(hopping_to - position.x), 70.0 * scale.x)
				vel = Vector2(dir * dist * 2.6, -430 * sqrt(scale.x))
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
	queue_redraw()


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
	var sx := 1.0 / sqrt(maxf(sq, 0.3))
	# floor shadow (only in screen space below him when near the floor)
	var h := half_extents()
	var floor_gap := (bounds.end.y - h.y) - position.y
	if floor_gap < 300 and state != State.DRAG:
		var a := clampf(1.0 - floor_gap / 300.0, 0.0, 1.0) * 0.28
		draw_set_transform(Vector2(0, 71 + floor_gap / scale.x).rotated(-rotation), -rotation, Vector2.ONE)
		draw_colored_polygon(_ellipse(Vector2.ZERO, Vector2(34 * (1.0 - floor_gap / 600.0), 6)), Color(0, 0, 0, a))
	draw_set_transform(Vector2(0, 71.0 * (1.0 - sq)), 0.0, Vector2(sx, sq))

	# casing body
	var body := _rrect(Rect2(-32, -10, 64, 64), 5)
	draw_colored_polygon(body, BRASS)
	draw_colored_polygon(_band(-8, 52, 0.5, 0.97, false), BRASS_SHADE)
	draw_colored_polygon(_band(-6, 50, -0.78, -0.55, false), BRASS_LIGHT)
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
	draw_colored_polygon(_band(-12, -70, 0.52, 0.99, true), COPPER_SHADE)
	draw_colored_polygon(_band(-14, -62, -0.8, -0.58, true), COPPER_LIGHT)
	var tclosed := tip.duplicate(); tclosed.append(tip[0])
	draw_polyline(tclosed, OUTLINE, 3.0, true)
	# crimp ring
	_outlined(_rrect(Rect2(-31, -14, 62, 6), 3), BRASS_SHADE, 2.5)

	_draw_face()
	_draw_extras()


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
