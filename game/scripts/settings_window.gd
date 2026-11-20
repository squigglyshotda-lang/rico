extends Window
## Rico's settings: API key, voice, reminders, project shortcuts, behaviour, help.

signal test_requested

const BG := Color("231812")
const CARD := Color("33231a")
const INK := Color("fff3df")
const ACCENT := Color("e0ab45")

var reminders: Node
var voice: Node
var tabs: TabContainer
var _rem_list: ItemList
var _proj_list: ItemList
var _file_dialog: FileDialog
var _status: Label


func _init() -> void:
	title = "Rico Settings"
	size = Vector2i(600, 640)
	min_size = Vector2i(520, 520)
	transient = false
	exclusive = false
	wrap_controls = false
	visible = false
	close_requested.connect(hide)


func build() -> void:
	theme = _make_theme()
	var bg := Panel.new()
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = BG
	bg.add_theme_stylebox_override("panel", bgs)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	tabs = TabContainer.new()
	margin.add_child(tabs)

	_build_chat()
	_build_voice()
	_build_reminders()
	_build_projects()
	_build_rico()
	_build_help()

	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_file_dialog.title = "Pick a project folder or file"
	_file_dialog.file_selected.connect(_add_project)
	_file_dialog.dir_selected.connect(_add_project)
	add_child(_file_dialog)


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 16
	th.set_color("font_color", "Label", INK)
	th.set_color("font_color", "CheckBox", INK)
	th.set_color("font_hover_color", "CheckBox", Color.WHITE)
	th.set_color("font_pressed_color", "CheckBox", INK)
	th.set_color("font_color", "ItemList", INK)
	th.set_color("font_selected_color", "TabContainer", ACCENT)
	th.set_color("font_unselected_color", "TabContainer", Color(INK, 0.6))
	th.set_color("font_hovered_color", "TabContainer", INK)
	var card := StyleBoxFlat.new()
	card.bg_color = CARD
	card.set_corner_radius_all(10)
	card.set_content_margin_all(14)
	th.set_stylebox("panel", "TabContainer", card)
	var field := StyleBoxFlat.new()
	field.bg_color = Color("1a120d")
	field.border_color = Color("5a4434")
	field.set_border_width_all(2)
	field.set_corner_radius_all(8)
	field.set_content_margin_all(8)
	var field_focus: StyleBoxFlat = field.duplicate()
	field_focus.border_color = ACCENT
	for t in ["LineEdit", "SpinBox"]:
		th.set_stylebox("normal", t, field)
		th.set_stylebox("focus", t, field_focus)
	th.set_color("font_color", "LineEdit", INK)
	th.set_stylebox("panel", "ItemList", field)
	th.set_stylebox("focus", "ItemList", field_focus)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("d06d3c")
	btn.set_corner_radius_all(8)
	btn.set_content_margin_all(8)
	btn.content_margin_left = 14
	btn.content_margin_right = 14
	var btn_h: StyleBoxFlat = btn.duplicate(); btn_h.bg_color = Color("e2834f")
	var btn_p: StyleBoxFlat = btn.duplicate(); btn_p.bg_color = Color("9e4826")
	var btn_f: StyleBoxFlat = btn.duplicate(); btn_f.border_color = Color("ffcf3a"); btn_f.set_border_width_all(2)
	for t in ["Button", "OptionButton"]:
		th.set_stylebox("normal", t, btn)
		th.set_stylebox("hover", t, btn_h)
		th.set_stylebox("pressed", t, btn_p)
		th.set_stylebox("focus", t, btn_f)
		th.set_color("font_color", t, Color.WHITE)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_focus_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, Color.WHITE)
	return th


func _page(name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	return v


func _label(parent: Node, text: String, small := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if small:
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(INK, 0.65))
	parent.add_child(l)
	return l


func _heading(parent: Node, text: String) -> void:
	var l := _label(parent, text)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_font_size_override("font_size", 18)


func _check(parent: Node, text: String, key: String, cb := Callable()) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = bool(Cfg.g(key))
	c.toggled.connect(func(on):
		Cfg.s(key, on)
		if cb.is_valid(): cb.call(on))
	parent.add_child(c)
	return c


func _option(parent: Node, text: String, key: String, items: Array) -> OptionButton:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := _label(h, text)
	l.custom_minimum_size.x = 190
	var o := OptionButton.new()
	for i in items:
		o.add_item(i)
	o.selected = int(Cfg.g(key))
	o.item_selected.connect(func(i): Cfg.s(key, i))
	h.add_child(o)
	return o


# ------------------------------------------------------------------ tabs

func _build_chat() -> void:
	var v := _page("Chat")
	_heading(v, "Claude API key")
	_label(v, "Rico's brain runs on Claude. Paste an API key from console.anthropic.com. It's stored only on this PC, in Rico's settings file.", true)
	var key := LineEdit.new()
	key.secret = true
	key.placeholder_text = "sk-ant-..."
	key.text = String(Cfg.g("api_key", ""))
	key.text_changed.connect(func(t): Cfg.s("api_key", t.strip_edges()))
	v.add_child(key)
	var show := CheckBox.new()
	show.text = "Show key"
	show.toggled.connect(func(on): key.secret = not on)
	v.add_child(show)

	_heading(v, "Model")
	var model := LineEdit.new()
	model.text = String(Cfg.g("model", "claude-haiku-5-5"))
	model.text_changed.connect(func(t): Cfg.s("model", t.strip_edges()))
	v.add_child(model)
	_label(v, "claude-haiku-5-5 is quick and cheap. claude-sonnet-5-5 is smarter but slower and pricier.", true)

	var h := HBoxContainer.new()
	v.add_child(h)
	var test := Button.new()
	test.text = "Test connection"
	test.pressed.connect(func(): test_requested.emit())
	h.add_child(test)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_status)


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func _build_voice() -> void:
	var v := _page("Voice")
	_heading(v, "Talking to Rico")
	_label(v, "Press Ctrl+Alt+Space (or the Mic button) to start listening, and again to stop. Speech is turned into text on this PC with offline Whisper; nothing leaves your machine until it's sent to Claude as a message.", true)
	_heading(v, "Rico talking back")
	_option(v, "Read replies aloud", "speak_replies", ["Never", "When I talk to him", "Always"])
	var h := HBoxContainer.new()
	v.add_child(h)
	var l := _label(h, "Voice")
	l.custom_minimum_size.x = 190
	var vo := OptionButton.new()
	vo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vo.add_item("Default English voice")
	vo.set_item_metadata(0, "")
	var cur := String(Cfg.g("tts_voice", ""))
	for voice_info in DisplayServer.tts_get_voices():
		vo.add_item("%s (%s)" % [voice_info.get("name", "?"), voice_info.get("language", "")])
		vo.set_item_metadata(vo.item_count - 1, voice_info.get("id", ""))
		if voice_info.get("id", "") == cur:
			vo.selected = vo.item_count - 1
	vo.item_selected.connect(func(i): Cfg.s("tts_voice", vo.get_item_metadata(i)))
	h.add_child(vo)
	_slider(v, "Voice pitch", "tts_pitch", 0.6, 1.8)
	_slider(v, "Voice speed", "tts_rate", 0.7, 1.6)
	var try := Button.new()
	try.text = "Hear Rico"
	try.pressed.connect(func(): voice.speak("Rico here. Loaded, cocked and mildly sarcastic."))
	v.add_child(try)
	_check(v, "Talk blips while text types out", "talk_blips")


func _slider(parent: Node, text: String, key: String, lo: float, hi: float) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := _label(h, text)
	l.custom_minimum_size.x = 190
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = float(Cfg.g(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(val): Cfg.s(key, val))
	h.add_child(s)


func _build_reminders() -> void:
	var v := _page("Reminders")
	_heading(v, "Pending reminders and timers")
	_rem_list = ItemList.new()
	_rem_list.custom_minimum_size = Vector2(0, 200)
	v.add_child(_rem_list)
	var del := Button.new()
	del.text = "Cancel selected"
	del.pressed.connect(func():
		for i in _rem_list.get_selected_items():
			reminders.cancel(int(_rem_list.get_item_metadata(i))))
	v.add_child(del)

	_heading(v, "Add one")
	var h := HBoxContainer.new()
	v.add_child(h)
	var txt := LineEdit.new()
	txt.placeholder_text = "e.g. Check the render"
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(txt)
	var mins := SpinBox.new()
	mins.min_value = 1
	mins.max_value = 1440
	mins.value = 15
	mins.suffix = "min"
	h.add_child(mins)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(func():
		if txt.text.strip_edges() != "":
			reminders.add(txt.text.strip_edges(), mins.value)
			txt.clear())
	h.add_child(add)
	_label(v, "Tip: you can also just tell Rico, e.g. \"remind me at 17:30 to send the build\".", true)

	_heading(v, "Break nudges")
	var bh := HBoxContainer.new()
	v.add_child(bh)
	var bl := _label(bh, "Nudge me to take a break every")
	bl.custom_minimum_size.x = 260
	var bm := SpinBox.new()
	bm.min_value = 0
	bm.max_value = 240
	bm.step = 5
	bm.value = float(Cfg.g("break_minutes"))
	bm.suffix = "min"
	bm.value_changed.connect(func(val): Cfg.s("break_minutes", val))
	bh.add_child(bm)
	_label(v, "Set to 0 to turn break nudges off.", true)


func refresh_reminders() -> void:
	if _rem_list == null:
		return
	_rem_list.clear()
	for r in reminders.pending():
		var i := _rem_list.add_item(reminders.describe(r))
		_rem_list.set_item_metadata(i, int(r.id))


func _build_projects() -> void:
	var v := _page("Projects")
	_heading(v, "Project shortcuts")
	_label(v, "Folders or files Rico can open for you: Godot projects (project.godot), .blend files, art folders, anything. Open them from Rico's right-click menu, or just ask him (\"open Zuri\").", true)
	_proj_list = ItemList.new()
	_proj_list.custom_minimum_size = Vector2(0, 220)
	_proj_list.item_activated.connect(func(i): OS.shell_open(Cfg.g("projects")[i].path))
	v.add_child(_proj_list)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var add := Button.new()
	add.text = "Add folder or file..."
	add.pressed.connect(func(): _file_dialog.popup_centered(Vector2i(800, 560)))
	h.add_child(add)
	var rem := Button.new()
	rem.text = "Remove"
	rem.pressed.connect(func():
		var list: Array = Cfg.g("projects").duplicate()
		var sel := _proj_list.get_selected_items()
		sel.reverse()
		for i in sel:
			list.remove_at(i)
		Cfg.s("projects", list)
		refresh_projects())
	h.add_child(rem)
	var rn := Button.new()
	rn.text = "Rename"
	h.add_child(rn)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "New name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_edit)
	rn.pressed.connect(func():
		var sel := _proj_list.get_selected_items()
		if sel.is_empty() or name_edit.text.strip_edges() == "":
			return
		var list: Array = Cfg.g("projects").duplicate(true)
		list[sel[0]].name = name_edit.text.strip_edges()
		Cfg.s("projects", list)
		name_edit.clear()
		refresh_projects())
	refresh_projects()


func _add_project(path: String) -> void:
	var name := path.get_file()
	if name == "project.godot" or name == "":
		name = path.get_base_dir().get_file()
	if name.get_extension() != "":
		name = name.get_basename()
	var list: Array = Cfg.g("projects").duplicate()
	list.append({"name": name, "path": path})
	Cfg.s("projects", list)
	refresh_projects()


func refresh_projects() -> void:
	if _proj_list == null:
		return
	_proj_list.clear()
	for p in Cfg.g("projects"):
		_proj_list.add_item("%s   —   %s" % [p.name, p.path])


func _build_rico() -> void:
	var v := _page("Rico")
	_heading(v, "Behaviour")
	_option(v, "Size", "size", ["Small", "Medium", "Large"])
	_option(v, "Chattiness", "chattiness", ["Quiet", "Normal", "Chatty"])
	_check(v, "Wander around the bottom of the screen", "wander")
	_check(v, "Hop out of the way of the window I'm using", "dodge")
	_label(v, "Drag Rico somewhere while an app is in front and he'll go back to that spot whenever you use that app.", true)
	var forget := Button.new()
	forget.text = "Forget all saved app spots"
	forget.pressed.connect(func(): Cfg.s("app_spots", {}))
	v.add_child(forget)
	_check(v, "Tips for the app I'm using (Godot, Blender, VS Code, Figma, art apps)", "app_tips")
	_slider(v, "Sound volume", "volume", 0.0, 1.0)
	_heading(v, "Startup")
	_check(v, "Start Rico when Windows starts", "start_with_windows", func(on): _set_autostart(on))


func _set_autostart(on: bool) -> void:
	if OS.get_name() != "Windows":
		return
	var key := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
	if on:
		OS.execute("reg", ["add", key, "/v", "Rico", "/t", "REG_SZ", "/d", "\"%s\"" % OS.get_executable_path().replace("/", "\\"), "/f"])
	else:
		OS.execute("reg", ["delete", key, "/v", "Rico", "/f"])


func _build_help() -> void:
	var v := _page("Help")
	_heading(v, "Mouse")
	_label(v, "Left-click Rico: chat.  Right-click: menu.  Drag: move him.  Drag and let go fast: fling him and watch him ricochet.")
	_heading(v, "Keyboard (works from any app)")
	_label(v, "Ctrl+Shift+Space: open chat\nCtrl+Alt+Space: talk (press again to stop)\nCtrl+Alt+R: hide or show Rico\nEsc: close the bubble")
	_heading(v, "Controller (hold View/Back, then press)")
	_label(v, "A: open chat or confirm\nX: talk / stop talking\nB: close the bubble\nY: hide or show Rico\nD-pad: move between buttons")
	_heading(v, "Things to say")
	_label(v, "\"Remind me in 25 minutes to check the bake\"\n\"Set a timer for 5 minutes\"\n\"What reminders have I got?\"\n\"Open Zuri\"\n\"How do I make a one-way collision platform in Godot?\"")
