extends RefCounted
## Rico's "smoked glass" look: colours, icons, a shared Theme and small motion helpers.

const GLASS := Color(0.08, 0.075, 0.095, 0.70)
const GLASS_SOLID := Color(0.10, 0.095, 0.115, 1.0)
const GLASS_HI := Color(1, 1, 1, 0.07)
const EDGE := Color(1, 1, 1, 0.18)
const TEXT := Color(0.96, 0.94, 0.91)
const TEXT_2 := Color(0.96, 0.94, 0.91, 0.62)
const TEXT_3 := Color(0.96, 0.94, 0.91, 0.38)
const COPPER := Color("e8814c")
const COPPER_HI := Color("f39a69")
const COPPER_LO := Color("c4632f")
const BRASS := Color("eec25f")
const FIELD := Color(0, 0, 0, 0.28)
const SHADOW := Color(0, 0, 0, 0.45)

const ICONS := {
	"mic": 0xeaf0, "stop": 0xed4a, "send": 0xeb1e, "x": 0xeb55, "check": 0xea5e, "shield": 0xeb22,
	"file": 0xeaa4, "folder": 0xeaad, "photo": 0xeb0a, "app": 0xefe6, "web": 0xeb54, "chat": 0xeaed,
	"bolt": 0xea38, "settings": 0xeb20, "clock": 0xea70, "calc": 0xeb80, "search": 0xeb1c, "sparkles": 0xf6d7,
	"brain": 0xf59f, "cpu": 0xef8e, "trash": 0xeb41, "sliders": 0xea03, "chevron": 0xea61, "play": 0xed46,
	"bell": 0xea35, "rocket": 0xec45, "zip": 0xed4e, "cube": 0xfa97, "code": 0xea77, "movie": 0xeafa,
	"music": 0xeafc, "download": 0xea96, "info": 0xeac5, "alert": 0xea06, "copy": 0xea7a, "grid": 0xedba,
	"activity": 0xed23, "coin": 0xeb82, "power": 0xeb0d, "desktop": 0xea89, "keyboard": 0xebd6,
	"history": 0xebea, "gamepad": 0xf1d2, "trophy": 0xeb45, "bulb": 0xea51, "notes": 0xeb6e, "user": 0xef68,
}

static var _theme: Theme
static var _icon_font: FontFile
static var _bold: FontVariation


static func icon(name: String) -> String:
	return String.chr(ICONS.get(name, 0xeac5))


## Make the icon font a fallback of the main font so any label can mix text and icons.
static func setup_fonts() -> void:
	if _icon_font:
		return
	_icon_font = load("res://assets/tabler-icons.ttf")
	var main: FontFile = load("res://assets/Fredoka.ttf")
	if main and _icon_font:
		var fb := main.fallbacks.duplicate()
		if not _icon_font in fb:
			fb.append(_icon_font)
			main.fallbacks = fb
	_bold = FontVariation.new()
	_bold.base_font = main
	_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 560}


static func bold() -> Font:
	setup_fonts()
	return _bold


static func box(bg: Color, radius := 14, border := Color(0, 0, 0, 0), bw := 0, margin := 10, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_color = SHADOW
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.45)
	return s


static func glass_panel(radius := 18, margin := 16, solid := false) -> StyleBoxFlat:
	return box(GLASS_SOLID if solid else GLASS, radius, EDGE, 1, margin, 0 if solid else 18)


## A soft top-to-bottom sheen drawn behind a glass panel's contents.
static var _sheen_tex: GradientTexture2D


static func add_sheen(panel: Control, radius := 18.0) -> void:
	if _sheen_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.075))
		g.set_color(1, Color(1, 1, 1, 0.0))
		_sheen_tex = GradientTexture2D.new()
		_sheen_tex.gradient = g
		_sheen_tex.width = 4
		_sheen_tex.height = 64
		_sheen_tex.fill_from = Vector2(0, 0)
		_sheen_tex.fill_to = Vector2(0, 1)
	panel.draw.connect(func():
		var h := minf(panel.size.y * 0.55, 110.0)
		panel.draw_texture_rect(_sheen_tex, Rect2(radius * 0.55, 1.5, panel.size.x - radius * 1.1, h), false)
	)


static func theme() -> Theme:
	if _theme:
		return _theme
	setup_fonts()
	var t := Theme.new()
	t.default_font = load("res://assets/Fredoka.ttf")
	t.default_font_size = 16

	for c in ["Label", "CheckBox", "CheckButton", "ItemList", "LineEdit", "TextEdit", "SpinBox", "RichTextLabel", "PopupMenu", "Tree"]:
		t.set_color("font_color", c, TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_focus_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_3)
	t.set_color("caret_color", "LineEdit", COPPER_HI)
	t.set_color("selection_color", "LineEdit", Color(COPPER, 0.4))
	t.set_color("font_readonly_color", "TextEdit", TEXT_2)

	# buttons: soft glass pills; "Primary" variation is copper
	var b_n := box(Color(1, 1, 1, 0.08), 12, Color(1, 1, 1, 0.12), 1, 9)
	b_n.content_margin_left = 16; b_n.content_margin_right = 16
	var b_h := box(Color(1, 1, 1, 0.14), 12, Color(1, 1, 1, 0.22), 1, 9)
	b_h.content_margin_left = 16; b_h.content_margin_right = 16
	var b_p := box(Color(1, 1, 1, 0.04), 12, Color(1, 1, 1, 0.10), 1, 9)
	b_p.content_margin_left = 16; b_p.content_margin_right = 16
	var b_f := box(Color(1, 1, 1, 0.08), 12, BRASS, 2, 9)
	b_f.content_margin_left = 16; b_f.content_margin_right = 16
	for c in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", c, b_n)
		t.set_stylebox("hover", c, b_h)
		t.set_stylebox("pressed", c, b_p)
		t.set_stylebox("hover_pressed", c, b_h)
		t.set_stylebox("focus", c, b_f)
		t.set_stylebox("disabled", c, box(Color(1, 1, 1, 0.03), 12, Color(1, 1, 1, 0.06), 1, 9))
		for k in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(k, c, TEXT)
		t.set_color("font_pressed_color", c, TEXT_2)
		t.set_color("font_disabled_color", c, TEXT_3)
		t.set_color("icon_normal_color", c, TEXT)
	t.add_type("Primary")
	t.set_type_variation("Primary", "Button")
	var p_n := box(COPPER, 12, Color(1, 1, 1, 0.18), 1, 9)
	p_n.content_margin_left = 18; p_n.content_margin_right = 18
	var p_h := box(COPPER_HI, 12, Color(1, 1, 1, 0.28), 1, 9)
	p_h.content_margin_left = 18; p_h.content_margin_right = 18
	p_h.shadow_color = Color(COPPER, 0.45); p_h.shadow_size = 8
	var p_p := box(COPPER_LO, 12, Color(1, 1, 1, 0.1), 1, 9)
	p_p.content_margin_left = 18; p_p.content_margin_right = 18
	var p_f := box(COPPER, 12, BRASS, 2, 9)
	p_f.content_margin_left = 18; p_f.content_margin_right = 18
	t.set_stylebox("normal", "Primary", p_n)
	t.set_stylebox("hover", "Primary", p_h)
	t.set_stylebox("pressed", "Primary", p_p)
	t.set_stylebox("hover_pressed", "Primary", p_h)
	t.set_stylebox("focus", "Primary", p_f)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(k, "Primary", Color.WHITE)
	t.add_type("Ghost")
	t.set_type_variation("Ghost", "Button")
	var g_n := box(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 0, 6)
	var g_h := box(Color(1, 1, 1, 0.09), 10, Color(0, 0, 0, 0), 0, 6)
	t.set_stylebox("normal", "Ghost", g_n)
	t.set_stylebox("hover", "Ghost", g_h)
	t.set_stylebox("pressed", "Ghost", g_h)
	t.set_stylebox("hover_pressed", "Ghost", g_h)
	t.set_stylebox("focus", "Ghost", box(Color(0, 0, 0, 0), 10, BRASS, 2, 6))
	t.set_color("font_color", "Ghost", TEXT_2)
	t.set_color("font_hover_color", "Ghost", TEXT)
	t.set_color("font_focus_color", "Ghost", TEXT)

	# fields
	var f_n := box(FIELD, 12, Color(1, 1, 1, 0.10), 1, 10)
	var f_f := box(FIELD, 12, COPPER, 1, 10)
	f_f.shadow_color = Color(COPPER, 0.30)
	f_f.shadow_size = 6
	for c in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", c, f_n)
		t.set_stylebox("focus", c, f_f)
		t.set_stylebox("read_only", c, f_n)
	t.set_stylebox("normal", "TextEdit", f_n)
	t.set_stylebox("focus", "TextEdit", f_f)
	t.set_stylebox("read_only", "TextEdit", f_n)
	t.set_stylebox("panel", "ItemList", f_n)
	t.set_stylebox("focus", "ItemList", box(Color(0, 0, 0, 0), 12, Color(COPPER, 0.6), 1, 10))
	t.set_stylebox("selected", "ItemList", box(Color(COPPER, 0.35), 8, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color(COPPER, 0.5), 8, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("hovered", "ItemList", box(Color(1, 1, 1, 0.06), 8, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_constant("v_separation", "ItemList", 6)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)

	# popup menus (right-click + tray)
	var pm := box(GLASS_SOLID, 14, EDGE, 1, 8, 14)
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", box(Color(COPPER, 0.85), 9, Color(0, 0, 0, 0), 0, 4))
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.09)
	sep.thickness = 1
	sep.grow_begin = -6; sep.grow_end = -6
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_left", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_right", "PopupMenu", sep)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_3)
	t.set_color("font_separator_color", "PopupMenu", TEXT_3)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 12)
	t.set_constant("item_end_padding", "PopupMenu", 16)
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_font_size("font_separator_size", "PopupMenu", 12)

	# tabs, scrollbars, sliders, separators
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	t.set_constant("separation", "HSeparator", 12)
	var hl := StyleBoxLine.new()
	hl.color = Color(1, 1, 1, 0.08)
	hl.thickness = 1
	t.set_stylebox("separator", "HSeparator", hl)
	var sb_grab := box(Color(1, 1, 1, 0.18), 4, Color(0, 0, 0, 0), 0, 0)
	sb_grab.content_margin_left = 3; sb_grab.content_margin_right = 3
	for c in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", c, box(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0, 0))
		t.set_stylebox("grabber", c, sb_grab)
		t.set_stylebox("grabber_highlight", c, box(Color(1, 1, 1, 0.3), 4, Color(0, 0, 0, 0), 0, 0))
		t.set_stylebox("grabber_pressed", c, box(Color(COPPER, 0.8), 4, Color(0, 0, 0, 0), 0, 0))
	var sl := box(Color(1, 1, 1, 0.12), 3, Color(0, 0, 0, 0), 0, 0)
	sl.content_margin_top = 3; sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	var sla := box(COPPER, 3, Color(0, 0, 0, 0), 0, 0)
	sla.content_margin_top = 3; sla.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", sla)
	t.set_stylebox("grabber_area_highlight", "HSlider", sla)
	t.set_icon("grabber", "HSlider", _dot_tex(18, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _dot_tex(18, BRASS))
	# check boxes: rounded glass squares
	t.set_icon("unchecked", "CheckBox", _check_tex(false))
	t.set_icon("checked", "CheckBox", _check_tex(true))
	t.set_constant("h_separation", "CheckBox", 10)
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(k, "CheckBox", box(Color(1, 1, 1, 0.06) if k == "hover" else Color(0, 0, 0, 0), 8, BRASS if k == "focus" else Color(0, 0, 0, 0), 1 if k == "focus" else 0, 4))
	t.set_stylebox("panel", "TooltipPanel", box(GLASS_SOLID, 8, EDGE, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	_theme = t
	return t


static func _dot_tex(sz: int, c: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var r := sz * 0.5
	for y in sz:
		for x in sz:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(c, clampf(r - 1 - d, 0, 1)))
	return ImageTexture.create_from_image(img)


static func _check_tex(on: bool) -> ImageTexture:
	var sz := 22
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rad := 6.0
	for y in sz:
		for x in sz:
			var px := Vector2(x + 0.5, y + 0.5)
			var q := (px - Vector2(sz, sz) * 0.5).abs() - Vector2(sz * 0.5 - 1 - rad, sz * 0.5 - 1 - rad)
			var d := Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0) - rad
			var inside := clampf(-d, 0, 1)
			var edge := clampf(1.0 - absf(d + 0.75), 0, 1)
			var col: Color
			if on:
				col = Color(COPPER, inside)
			else:
				col = Color(1, 1, 1, inside * 0.06 + edge * 0.35)
			img.set_pixel(x, y, col)
	if on:
		# tick
		var pts := [Vector2(6, 11.5), Vector2(9.5, 15), Vector2(16, 7.5)]
		for s in 2:
			var a: Vector2 = pts[s]
			var b: Vector2 = pts[s + 1]
			for i in 40:
				var p := a.lerp(b, i / 39.0)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var ix := int(p.x) + ox
						var iy := int(p.y) + oy
						if ix >= 0 and iy >= 0 and ix < sz and iy < sz:
							var dd := Vector2(ix + 0.5, iy + 0.5).distance_to(p)
							var a2 := clampf(1.6 - dd, 0, 1)
							var prev := img.get_pixel(ix, iy)
							img.set_pixel(ix, iy, prev.lerp(Color.WHITE, a2))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ motion

static func pop_in(c: Control, from_scale := 0.88, dur := 0.22) -> void:
	c.visible = true
	c.modulate.a = 0.0
	c.scale = Vector2.ONE * from_scale
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.7)
	tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func pop_out(c: Control, dur := 0.13, done := Callable()) -> void:
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 0.0, dur)
	tw.tween_property(c, "scale", Vector2.ONE * 0.92, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		c.visible = false
		c.scale = Vector2.ONE
		c.modulate.a = 1.0
		if done.is_valid(): done.call())


## Hover lift + press squish for a button.
static func juice(b: Control) -> void:
	var setp := func(): b.pivot_offset = b.size * 0.5
	b.resized.connect(setp)
	setp.call()
	var to := func(s: float, d: float):
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE * s, d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func(): to.call(1.045, 0.16))
	b.mouse_exited.connect(func(): to.call(1.0, 0.16))
	if b is BaseButton:
		b.button_down.connect(func(): to.call(0.94, 0.07))
		b.button_up.connect(func(): to.call(1.045 if b.is_hovered() else 1.0, 0.18))
