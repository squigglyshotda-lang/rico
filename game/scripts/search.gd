extends Control
## Spotlight-style search bar. Rico perches on top of it (handled by main).
## Sources: quick answers, apps, Rico's own actions, files (Windows Search index),
## then Google and "Ask Rico" as fallbacks.

signal closed
signal ask_rico(text: String)
signal rico_action(id: String)
signal voice_requested

const INK := Color("2a1a10")
const PAPER := Color("fffaf0")
const ACCENT := Color("d06d3c")
const MAX_ROWS := 9
const WIDTH := 640.0
const PREVIEW_W := 250.0
const IMAGE_EXT := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]

var quick: Node
var rico_items: Callable          # func() -> Array of {title, subtitle, id, keywords}

var panel: PanelContainer
var input: LineEdit
var rows_box: VBoxContainer
var footer: Label
var preview: PanelContainer
var pv_image: TextureRect
var pv_title: Label
var pv_body: Label
var rows: Array = []

var results: Array = []
var selected := 0
var apps: Array = []
var _files: Array = []
var _files_for := ""
var _time_answer := {}
var _time_for := ""
var _debounce := -1.0
var _req_id := 0
var _pipe: FileAccess
var _pid := -1
var _thread: Thread
var _running := false
var _thumbs := {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)

	panel = PanelContainer.new()
	panel.custom_minimum_size.x = WIDTH
	panel.add_theme_stylebox_override("panel", _box(PAPER, INK, 3, 20, 14))
	h.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var glass := Label.new()
	glass.text = "⌕"
	glass.add_theme_font_size_override("font_size", 30)
	glass.add_theme_color_override("font_color", ACCENT)
	top.add_child(glass)
	input = LineEdit.new()
	input.placeholder_text = "Search apps, files, or ask Rico..."
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = 48
	input.add_theme_font_size_override("font_size", 24)
	input.add_theme_color_override("font_color", INK)
	input.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	input.add_theme_color_override("caret_color", ACCENT)
	var empty := StyleBoxEmpty.new()
	input.add_theme_stylebox_override("normal", empty)
	input.add_theme_stylebox_override("focus", empty)
	input.text_changed.connect(_on_text)
	input.gui_input.connect(_on_input_key)
	top.add_child(input)

	var sep := HSeparator.new()
	var sl := StyleBoxLine.new()
	sl.color = Color(INK, 0.15)
	sl.thickness = 2
	sep.add_theme_stylebox_override("separator", sl)
	v.add_child(sep)

	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 2)
	v.add_child(rows_box)
	for i in MAX_ROWS:
		rows.append(_make_row(i))

	footer = Label.new()
	footer.text = "Enter open   Ctrl+Enter show in folder   Tab ask Rico   Ctrl+C copy   Esc close"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(INK, 0.5))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(footer)

	preview = PanelContainer.new()
	preview.custom_minimum_size = Vector2(PREVIEW_W, 0)
	preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	preview.add_theme_stylebox_override("panel", _box(PAPER, INK, 3, 18, 14))
	h.add_child(preview)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	preview.add_child(pv)
	pv_image = TextureRect.new()
	pv_image.custom_minimum_size = Vector2(PREVIEW_W - 28, 160)
	pv_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.add_child(pv_image)
	pv_title = Label.new()
	pv_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv_title.add_theme_font_size_override("font_size", 17)
	pv_title.add_theme_color_override("font_color", INK)
	pv.add_child(pv_title)
	pv_body = Label.new()
	pv_body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	pv_body.add_theme_font_size_override("font_size", 13)
	pv_body.add_theme_color_override("font_color", Color(INK, 0.7))
	pv.add_child(pv_body)
	preview.visible = false


func _box(bg: Color, border: Color, bw: int, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.28)
	s.shadow_size = 10 if bw > 0 else 0
	s.shadow_offset = Vector2(0, 4)
	return s


func _make_row(i: int) -> Dictionary:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	var badge := Label.new()
	badge.custom_minimum_size = Vector2(40, 34)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color.WHITE)
	h.add_child(badge)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 17)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	tv.add_child(title)
	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", 12)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	tv.add_child(sub)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 12)
	h.add_child(hint)
	pc.mouse_entered.connect(func(): _select(i))
	pc.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select(i)
			activate(ev.ctrl_pressed))
	rows_box.add_child(pc)
	return {"panel": pc, "badge": badge, "title": title, "sub": sub, "hint": hint}


# ------------------------------------------------------------------ open / close

func open(prefill := "") -> void:
	_ensure_server()
	visible = true
	input.text = prefill
	input.caret_column = prefill.length()
	_on_text(prefill)
	input.grab_focus()
	if quick:
		quick.refresh_rates()


func close() -> void:
	if not visible:
		return
	visible = false
	input.release_focus()
	closed.emit()


func set_query(t: String) -> void:
	input.text = t
	input.caret_column = t.length()
	_on_text(t)


func panel_rect() -> Rect2:
	return Rect2(position, size)


func bar_top_left() -> Vector2:
	return position


func caret_point() -> Vector2:
	var f := input.get_theme_font("font")
	var w := f.get_string_size(input.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	return input.global_position + Vector2(minf(w, input.size.x), input.size.y * 0.5)


# ------------------------------------------------------------------ search server

func _ensure_server() -> void:
	if _running or OS.get_name() != "Windows":
		return
	var dir := OS.get_user_data_dir().path_join("ps")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("search_server.ps1")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	f.store_string(FileAccess.get_file_as_string("res://ps/search_server.ps1"))
	f.close()
	var info := OS.execute_with_pipe("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", path], true)
	if info.is_empty():
		return
	_pipe = info.stdio
	_pid = info.pid
	_running = true
	_thread = Thread.new()
	_thread.start(_read_loop)
	_send({"op": "apps"})


func _read_loop() -> void:
	while _running and _pipe and _pipe.is_open():
		var line := _pipe.get_line()
		if line == "" and _pipe.get_error() != OK:
			break
		if line.strip_edges() != "":
			call_deferred("_on_server_line", line)
	call_deferred("_server_died")


func _server_died() -> void:
	_running = false


func _send(d: Dictionary) -> void:
	if not _running:
		return
	_req_id += 1
	d.id = _req_id
	_pipe.store_line(JSON.stringify(d))
	_pipe.flush()


func _on_server_line(line: String) -> void:
	var d = JSON.parse_string(line.strip_edges().trim_prefix("﻿"))
	if not (d is Dictionary):
		return
	match String(d.get("op", "")):
		"apps":
			apps = d.get("items", [])
			if visible: _rebuild()
		"files":
			if String(d.get("q", "")) == input.text.strip_edges():
				_files = d.get("items", [])
				_files_for = String(d.q)
				_rebuild()
		"time":
			if d.has("time"):
				_time_answer = {"title": "%s  %s" % [d.time, d.day], "subtitle": _time_for, "copy": String(d.time)}
				_rebuild()


func _exit_tree() -> void:
	_running = false
	if _pid > 0:
		OS.kill(_pid)
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# ------------------------------------------------------------------ searching

func _on_text(t: String) -> void:
	selected = 0
	_files = []
	_time_answer = {}
	_debounce = 0.15
	if quick:
		var tq: Dictionary = quick.time_query(t)
		if not tq.is_empty():
			_time_for = String(tq.label)
			_send({"op": "time", "tz_to": tq.tz_to, "tz_from": tq.tz_from, "hour": tq.hour, "minute": tq.minute})
	_rebuild()


func _process(delta: float) -> void:
	if _debounce > 0:
		_debounce -= delta
		if _debounce <= 0:
			var q := input.text.strip_edges()
			if q.length() >= 2:
				_send({"op": "files", "q": q})


static func score(title: String, q: String, keywords := "") -> float:
	var t := title.to_lower()
	var ql := q.to_lower().strip_edges()
	if ql.is_empty():
		return 0.0
	if t == ql: return 100.0
	if t.begins_with(ql): return 90.0 - t.length() * 0.05
	for w in t.split(" ", false):
		if w.begins_with(ql): return 75.0
	if ql in t: return 60.0
	if keywords != "" and ql in keywords.to_lower(): return 50.0
	# fuzzy: letters in order (e.g. "vsc" -> "Visual Studio Code")
	var i := 0
	for c in t:
		if i < ql.length() and c == ql[i]:
			i += 1
	if i == ql.length() and ql.length() >= 2:
		return 30.0
	return 0.0


func _human_size(b: float) -> String:
	if b < 0: return ""
	if b < 1024: return "%d B" % b
	if b < 1048576: return "%.0f KB" % (b / 1024.0)
	if b < 1073741824: return "%.1f MB" % (b / 1048576.0)
	return "%.2f GB" % (b / 1073741824.0)


func _rebuild() -> void:
	var q := input.text.strip_edges()
	var out: Array = []
	if q.is_empty():
		# nothing typed: show Rico's handy actions
		if rico_items.is_valid():
			for it in rico_items.call().slice(0, 6):
				out.append(_rico_result(it, 1.0))
		_show(out)
		return
	if quick:
		var a: Dictionary = quick.answer(q)
		if not a.is_empty():
			out.append({"kind": "answer", "title": a.title, "subtitle": a.subtitle, "copy": a.copy, "score": 1000.0, "badge": "=", "color": Color("4c9a62")})
	if not _time_answer.is_empty():
		out.append({"kind": "answer", "title": _time_answer.title, "subtitle": _time_answer.subtitle, "copy": _time_answer.copy, "score": 999.0, "badge": "TIME", "color": Color("4c9a62")})
	var ranked: Array = []
	for app in apps:
		var s := score(String(app.name), q)
		if s > 0:
			ranked.append({"kind": "app", "title": app.name, "subtitle": "App", "id": app.id, "copy": app.name, "score": s + 15.0, "badge": "APP", "color": Color("3f6fb5")})
	if rico_items.is_valid():
		for it in rico_items.call():
			var s := score(String(it.title), q, String(it.get("keywords", "")))
			if s > 0:
				ranked.append(_rico_result(it, s + 10.0))
	for f in _files:
		var name := String(f.name)
		var s := score(name.get_basename() if not f.folder else name, q)
		ranked.append({"kind": "folder" if f.folder else "file", "title": name, "subtitle": String(f.path).get_base_dir(), "path": f.path,
			"copy": f.path, "size": f.size, "modified": f.modified, "score": maxf(s, 20.0),
			"badge": "DIR" if f.folder else _ext_badge(name), "color": Color("8a6a3a") if f.folder else Color("6b5a8e")})
	ranked.sort_custom(func(a, b): return a.score > b.score)
	# keep a mix: at most 4 apps, 3 Rico actions, 5 files
	var caps := {"app": 4, "rico": 3, "file": 5, "folder": 2}
	var counts := {}
	for r in ranked:
		var k: String = r.kind
		counts[k] = counts.get(k, 0) + 1
		if counts[k] <= caps.get(k, 3):
			out.append(r)
	out = out.slice(0, MAX_ROWS - 2)
	out.append({"kind": "web", "title": "Search Google for \"%s\"" % q, "subtitle": "Opens your browser", "score": -1.0, "badge": "WEB", "color": Color("5b7f9a")})
	out.append({"kind": "ask", "title": "Ask Rico: \"%s\"" % q, "subtitle": "Tab", "score": -2.0, "badge": "RICO", "color": ACCENT})
	_show(out)


func _rico_result(it: Dictionary, s: float) -> Dictionary:
	return {"kind": "rico", "title": it.title, "subtitle": it.get("subtitle", "Rico"), "id": it.id, "copy": it.title, "score": s, "badge": "RICO", "color": ACCENT}


func _ext_badge(name: String) -> String:
	var e := name.get_extension().to_upper()
	return e.left(4) if e != "" else "FILE"


func _show(list: Array) -> void:
	results = list
	selected = clampi(selected, 0, maxi(0, list.size() - 1))
	if not list.is_empty() and input.text.strip_edges() != "":
		selected = 0 if selected >= list.size() else selected
	for i in rows.size():
		var r: Dictionary = rows[i]
		var p: PanelContainer = r.panel
		if i >= list.size():
			p.visible = false
			continue
		var it: Dictionary = list[i]
		p.visible = true
		r.title.text = it.title
		r.sub.text = it.subtitle
		r.badge.text = it.badge
		var bs := StyleBoxFlat.new()
		bs.bg_color = it.color
		bs.set_corner_radius_all(9)
		r.badge.add_theme_stylebox_override("normal", bs)
		var hints := {"app": "Open", "file": "Open", "folder": "Open", "rico": "Do it", "answer": "Copy", "web": "Search", "ask": "Ask"}
		r.hint.text = hints.get(it.kind, "")
	_style_rows()
	_update_preview()
	reset_size()


func _style_rows() -> void:
	for i in rows.size():
		var r: Dictionary = rows[i]
		var sel := i == selected
		r.panel.add_theme_stylebox_override("panel", _box(ACCENT if sel else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12, 6))
		r.title.add_theme_color_override("font_color", Color.WHITE if sel else INK)
		r.sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.8) if sel else Color(INK, 0.55))
		r.hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.9) if sel else Color(INK, 0.35))


func _select(i: int) -> void:
	if i < 0 or i >= results.size():
		return
	selected = i
	_style_rows()
	_update_preview()


func move(d: int) -> void:
	if results.is_empty():
		return
	_select(wrapi(selected + d, 0, results.size()))


func current() -> Dictionary:
	return results[selected] if selected < results.size() else {}


func _update_preview() -> void:
	var it := current()
	var k: String = it.get("kind", "")
	if k in ["web", "ask", ""] or (k == "rico"):
		preview.visible = false
		reset_size()
		return
	preview.visible = true
	pv_image.texture = null
	pv_image.visible = false
	pv_title.text = String(it.title)
	match k:
		"answer":
			pv_title.add_theme_font_size_override("font_size", 26)
			pv_body.text = String(it.subtitle) + "\n\nEnter or Ctrl+C copies it."
		"app":
			pv_title.add_theme_font_size_override("font_size", 17)
			pv_body.text = "Application\n\nEnter opens it."
		"file", "folder":
			pv_title.add_theme_font_size_override("font_size", 17)
			var lines := []
			var sz := _human_size(float(it.get("size", -1)))
			if sz != "" and k == "file": lines.append(sz)
			if String(it.get("modified", "")) != "": lines.append("Modified " + String(it.modified))
			lines.append(String(it.path))
			pv_body.text = "\n".join(lines)
			var ext := String(it.path).get_extension().to_lower()
			if k == "file" and ext in IMAGE_EXT and float(it.get("size", 0)) < 25e6:
				pv_image.texture = _thumb(String(it.path))
				pv_image.visible = pv_image.texture != null
	reset_size()


func _thumb(path: String) -> Texture2D:
	if _thumbs.has(path):
		return _thumbs[path]
	var img := Image.load_from_file(path)
	var tex: Texture2D = null
	if img and not img.is_empty():
		var scale := minf(1.0, 440.0 / maxf(img.get_width(), img.get_height()))
		if scale < 1.0:
			img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
		tex = ImageTexture.create_from_image(img)
	_thumbs[path] = tex
	if _thumbs.size() > 40:
		_thumbs.clear()
	return tex


# ------------------------------------------------------------------ actions

func activate(ctrl := false) -> void:
	var it := current()
	if it.is_empty():
		return
	var q := input.text.strip_edges()
	match String(it.kind):
		"answer":
			if String(it.copy) != "":
				DisplayServer.clipboard_set(String(it.copy))
		"app":
			OS.create_process("explorer.exe", ["shell:AppsFolder\\" + String(it.id)])
		"file", "folder":
			if ctrl:
				OS.create_process("explorer.exe", ["/select," + String(it.path).replace("/", "\\")])
			else:
				OS.shell_open(String(it.path))
		"rico":
			close()
			rico_action.emit(String(it.id))
			return
		"web":
			OS.shell_open("https://www.google.com/search?q=" + q.uri_encode())
		"ask":
			close()
			ask_rico.emit(q)
			return
	close()


func ask_about_current() -> void:
	var it := current()
	var q := input.text.strip_edges()
	var text := q
	if String(it.get("kind", "")) in ["file", "folder"]:
		text = "Tell me about this %s and what I could do with it: %s" % [it.kind, it.path]
	elif String(it.get("kind", "")) == "app":
		text = "Tell me about the app %s and any handy tips for it." % it.title
	if text == "":
		return
	close()
	ask_rico.emit(text)


func copy_current() -> void:
	var it := current()
	if String(it.get("copy", "")) != "":
		DisplayServer.clipboard_set(String(it.copy))
		footer.text = "Copied: " + String(it.copy).left(60)


func _on_input_key(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed):
		return
	match ev.keycode:
		KEY_DOWN:
			move(1)
		KEY_UP:
			move(-1)
		KEY_ENTER, KEY_KP_ENTER:
			activate(ev.ctrl_pressed)
		KEY_TAB:
			ask_about_current()
		KEY_ESCAPE:
			close()
		KEY_C:
			if ev.ctrl_pressed and not input.has_selection():
				copy_current()
			else:
				return
		_:
			return
	input.accept_event()
