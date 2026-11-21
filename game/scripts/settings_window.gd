extends Window
## Rico's settings: API key, voice, reminders, project shortcuts, behaviour, help.

signal test_requested
signal brain_download_requested

const UI := preload("res://scripts/ui.gd")
const BG := Color(0.085, 0.08, 0.095)
const CARD := Color(1, 1, 1, 0.035)
const INK := UI.TEXT
const ACCENT := UI.COPPER_HI
const TAB_ICONS := {"Games": "gamepad", "Chat": "chat", "Voice": "mic", "Reminders": "bell", "Projects": "rocket", "Rico": "sparkles", "PC": "cpu", "Activity": "activity", "Usage": "coin", "Help": "info"}

var _nav: VBoxContainer
var _nav_buttons: Array = []

var reminders: Node
var voice: Node
var pc: Node
var updater: Node
var games: Node
var _game_label: Label
var _game_lists: ItemList
var _game_items: Array = []
var _update_label: Label
var mem: Node
var brain: Node
var voice_out: Node
var _voice_btn: Button
var _voice_label: Label
var _usage_label: Label
var _brain_label: Label
var _brain_btn: Button
var _facts_list: ItemList
var _perf_list: ItemList
var _startup_list: ItemList
var _startup_items: Array = []
var _routine_list: ItemList
var _log_view: TextEdit
var tabs: TabContainer
var _rem_list: ItemList
var _proj_list: ItemList
var _file_dialog: FileDialog
var _status: Label


func _init() -> void:
	title = "Rico Settings"
	size = Vector2i(820, 660)
	min_size = Vector2i(700, 520)
	transient = false
	exclusive = false
	wrap_controls = false
	visible = false
	close_requested.connect(hide)


func build() -> void:
	theme = UI.theme()
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", UI.box(BG, 0, Color(0, 0, 0, 0), 0, 0))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# sidebar
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 200
	side.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.25), 0, Color(0, 0, 0, 0), 0, 14))
	root.add_child(side)
	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 4)
	side.add_child(_nav)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	_nav.add_child(brand)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/icon.png")
	logo.custom_minimum_size = Vector2(36, 36)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(logo)
	var bl := Label.new()
	bl.text = "Rico"
	bl.add_theme_font_override("font", UI.bold())
	bl.add_theme_font_size_override("font_size", 22)
	brand.add_child(bl)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14
	_nav.add_child(spacer)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + m, 22)
	root.add_child(margin)
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	margin.add_child(tabs)

	_build_chat()
	_build_voice()
	_build_reminders()
	_build_projects()
	_build_rico()
	_build_games()
	_build_pc()
	_build_activity()
	_build_usage()
	_build_help()

	for i in tabs.get_tab_count():
		var nm := tabs.get_tab_title(i)
		var b := Button.new()
		b.text = UI.icon(TAB_ICONS.get(nm, "info")) + "   " + nm
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "Ghost"
		b.custom_minimum_size.y = 40
		b.add_theme_font_size_override("font_size", 16)
		var idx := i
		b.pressed.connect(func(): tabs.current_tab = idx)
		_nav.add_child(b)
		_nav_buttons.append(b)
	tabs.tab_changed.connect(_mark_nav)
	_mark_nav(0)

	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_file_dialog.title = "Pick a project folder or file"
	_file_dialog.file_selected.connect(_add_project)
	_file_dialog.dir_selected.connect(_add_project)
	add_child(_file_dialog)


func _mark_nav(cur: int) -> void:
	for i in _nav_buttons.size():
		var b: Button = _nav_buttons[i]
		var on := i == cur
		if on:
			b.add_theme_stylebox_override("normal", UI.box(Color(UI.COPPER, 0.9), 10, Color(1, 1, 1, 0.15), 1, 6))
			b.add_theme_stylebox_override("hover", UI.box(UI.COPPER_HI, 10, Color(1, 1, 1, 0.2), 1, 6))
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_stylebox_override("hover")
			b.remove_theme_color_override("font_color")
			b.remove_theme_color_override("font_hover_color")


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
		l.add_theme_color_override("font_color", UI.TEXT_2)
	parent.add_child(l)
	return l


func _heading(parent: Node, text: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 8
		parent.add_child(gap)
	var l := _label(parent, text)
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_override("font", UI.bold())
	l.add_theme_font_size_override("font_size", 19)


func _check(parent: Node, text: String, key: String, cb := Callable()) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = bool(Cfg.g(key))
	c.toggled.connect(func(on):
		Cfg.s(key, on)
		if cb.is_valid(): cb.call(on))
	parent.add_child(c)
	return c


## values: optional stored values per item (default: the item index).
func _option(parent: Node, text: String, key: String, items: Array, values: Array = []) -> OptionButton:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := _label(h, text)
	l.custom_minimum_size.x = 190
	var o := OptionButton.new()
	for i in items:
		o.add_item(i)
	if values.is_empty():
		o.selected = int(Cfg.g(key))
		o.item_selected.connect(func(i): Cfg.s(key, i))
	else:
		o.selected = maxi(0, values.find(Cfg.g(key)))
		o.item_selected.connect(func(i):
			Cfg.s(key, values[i])
			if voice_out and key == "voice_device":
				voice_out.stop_servers()
				voice_out.warm_up())
	h.add_child(o)
	return o


# ------------------------------------------------------------------ tabs

func _build_chat() -> void:
	var v := _page("Chat")
	_heading(v, "Privacy")
	_check(v, "Local-only mode: nothing about you leaves this PC", "local_only")
	_label(v, "On: Rico chats with his offline brain (Settings > Usage to download it), and Claude and web lookups are never used. Your money, prints, memory and chats all stay here. Rico still checks GitHub for app updates and fetches exchange rates; neither sends anything about you, and both can be switched off below.\nOff: harder questions, game help, model searches and PC jobs can use Claude with your API key.", true)
	_check(v, "Fetch daily exchange rates (for currency conversions)", "fetch_rates")
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
	_option(v, "His voice", "voice_engine", ["Rico's own voice", "Windows voice (basic)"], ["rico", "windows"])
	_heading(v, "Rico's own voice")
	_label(v, "An expressive voice that runs entirely on this PC (2 GB, uses your graphics card). In games he switches to the Windows voice so you don't lose frames.", true)
	var vh := HBoxContainer.new()
	vh.add_theme_constant_override("separation", 8)
	v.add_child(vh)
	_voice_btn = Button.new()
	_voice_btn.pressed.connect(func():
		if voice_out.installed():
			voice_out.uninstall()
		elif voice_out.downloading:
			voice_out.cancel_download()
		else:
			voice_out.download()
		refresh_voice())
	vh.add_child(_voice_btn)
	_voice_label = Label.new()
	_voice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vh.add_child(_voice_label)
	_voice_slider(v, "Cartoon pitch", "voice_pitch", 1.0, 1.45)
	_voice_slider(v, "Hologram shimmer", "voice_shimmer", 0.0, 1.0)
	_option(v, "Run his voice on", "voice_device", ["Graphics card (fast)", "Processor (slower)"], ["gpu", "cpu"])
	var try := Button.new()
	try.text = "Hear Rico"
	try.pressed.connect(func(): voice.speak(preload("res://scripts/lines.gd").pick([
		"Rico here. <chuckle> Loaded, cocked and mildly sarcastic.",
		"Testing, testing. Yep, still the best-sounding thing on this desk.",
		"Oh, you want to hear me talk? <laugh> Finally, some taste."])))
	v.add_child(try)
	tabs.tab_changed.connect(func(_t): refresh_voice())
	_heading(v, "Windows voice (used in games)")
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
	_heading(v, "Updates")
	_label(v, "You're on Rico v%s." % ProjectSettings.get_setting("application/config/version", "?"), true)
	_check(v, "Update automatically (downloads quietly, installs next time Rico starts or while you're away)", "auto_update")
	var uh := HBoxContainer.new()
	uh.add_theme_constant_override("separation", 10)
	v.add_child(uh)
	var chk := Button.new()
	chk.text = UI.icon("refresh_x") + "  Check now"
	chk.text = "Check now"
	chk.pressed.connect(func(): if updater: updater.check_now())
	uh.add_child(chk)
	var inst := Button.new()
	inst.text = "Install downloaded update"
	inst.theme_type_variation = "Primary"
	inst.pressed.connect(func():
		if updater and not updater.pending().is_empty():
			updater.install_pending()
		else:
			set_update_status("No downloaded update waiting."))
	uh.add_child(inst)
	_update_label = Label.new()
	_update_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_label.add_theme_color_override("font_color", UI.TEXT_2)
	v.add_child(_update_label)


func set_update_status(t: String) -> void:
	if _update_label:
		_update_label.text = t


func _set_autostart(on: bool) -> void:
	if OS.get_name() != "Windows":
		return
	var key := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
	if on:
		OS.execute("reg", ["add", key, "/v", "Rico", "/t", "REG_SZ", "/d", "\"%s\"" % OS.get_executable_path().replace("/", "\\"), "/f"])
	else:
		OS.execute("reg", ["delete", key, "/v", "Rico", "/f"])


func _build_games() -> void:
	var v := _page("Games")
	_heading(v, "Game help")
	_label(v, "Rico spots the game you're playing (Steam, Epic, GOG, Xbox and more) and helps with bosses, builds, quests and collectibles. He gives hints first and full answers when you say \"just tell me\". Ask him in chat or by voice: hold View and press X on your controller.", true)
	_check(v, "Game help", "game_help")
	_check(v, "Occasional tips while I play (spoken aloud, about every 15 minutes)", "game_tips")
	_game_label = _label(v, "")
	_heading(v, "Checklists")
	_label(v, "Ask Rico to make one (\"make me a checklist of the collectibles\") and tick things off by saying \"got the X\". Double-click an item to toggle it here.", true)
	_game_lists = ItemList.new()
	_game_lists.custom_minimum_size = Vector2(0, 260)
	_game_lists.item_activated.connect(func(i):
		if i < _game_items.size() and games:
			var it: Dictionary = _game_items[i]
			if it.has("ref"):
				it.ref.done = not it.ref.done
				games.save()
				refresh_games())
	v.add_child(_game_lists)
	tabs.tab_changed.connect(func(_t): refresh_games())


func refresh_games() -> void:
	if _game_lists == null or games == null:
		return
	var cur: String = games.current()
	_game_label.text = ("Playing now: " + cur) if cur != "" else "No game detected right now."
	_game_lists.clear()
	_game_items = []
	for g in games.data.keys():
		var lists: Dictionary = games.data[g].get("lists", {})
		for title in lists.keys():
			var lst: Array = lists[title]
			var done := lst.filter(func(x): return x.done).size()
			_game_lists.add_item("%s: %s (%d/%d)" % [g, title, done, lst.size()])
			_game_items.append({})
			for it in lst:
				_game_lists.add_item(("     " + UI.icon("check") + "  " if it.done else "     ○  ") + String(it.t))
				_game_items.append({"ref": it})


func _build_pc() -> void:
	var v := _page("PC")
	_heading(v, "PC tools")
	_check(v, "Let Rico look after my PC (he always asks before changing anything)", "pc_tools")
	_check(v, "Weekly check-up (disk, updates, temperatures)", "weekly_report")

	_heading(v, "Game/Render mode: apps to close")
	_label(v, "Process names, e.g. Discord, Spotify, steamwebhelper, OneDrive. Rico also suggests extra hogs each time; you tick what goes.", true)
	_perf_list = ItemList.new()
	_perf_list.custom_minimum_size = Vector2(0, 110)
	v.add_child(_perf_list)
	var h := HBoxContainer.new()
	v.add_child(h)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Process name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_edit)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(func():
		var n := name_edit.text.strip_edges().trim_suffix(".exe")
		if n != "":
			var l: Array = Cfg.g("perf_apps", []).duplicate()
			if not n in l:
				l.append(n)
			Cfg.s("perf_apps", l)
			name_edit.clear()
			refresh_pc())
	h.add_child(add)
	var rem := Button.new()
	rem.text = "Remove"
	rem.pressed.connect(func():
		var l: Array = Cfg.g("perf_apps", []).duplicate()
		var sel := _perf_list.get_selected_items()
		sel.reverse()
		for i in sel:
			l.remove_at(i)
		Cfg.s("perf_apps", l)
		refresh_pc())
	h.add_child(rem)

	_heading(v, "Startup apps")
	_startup_list = ItemList.new()
	_startup_list.custom_minimum_size = Vector2(0, 150)
	v.add_child(_startup_list)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 8)
	v.add_child(sh)
	var ref := Button.new()
	ref.text = "Load list"
	ref.pressed.connect(refresh_startup)
	sh.add_child(ref)
	for on in [false, true]:
		var b := Button.new()
		b.text = "Turn on" if on else "Turn off"
		b.pressed.connect(func():
			for i in _startup_list.get_selected_items():
				if i < _startup_items.size():
					await pc.startup_set(String(_startup_items[i].name), on)
			refresh_startup())
		sh.add_child(b)
	_label(v, "Rico shows an Allow card on screen before switching anything.", true)

	_heading(v, "Routines")
	_label(v, "Make them by asking Rico, e.g. \"make a Work routine that opens Godot and Blender and closes Discord\". Run them here or from Rico's right-click menu, PC.", true)
	_routine_list = ItemList.new()
	_routine_list.custom_minimum_size = Vector2(0, 110)
	v.add_child(_routine_list)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 8)
	v.add_child(rh)
	var run := Button.new()
	run.text = "Run"
	run.pressed.connect(func():
		var sel := _routine_list.get_selected_items()
		if not sel.is_empty():
			await pc.run_routine(String(Cfg.g("routines")[sel[0]].name), true))
	rh.add_child(run)
	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func():
		var l: Array = Cfg.g("routines", []).duplicate(true)
		var sel := _routine_list.get_selected_items()
		sel.reverse()
		for i in sel:
			l.remove_at(i)
		Cfg.s("routines", l)
		refresh_pc())
	rh.add_child(del)
	refresh_pc()


func refresh_pc() -> void:
	if _perf_list == null:
		return
	_perf_list.clear()
	for n in Cfg.g("perf_apps", []):
		_perf_list.add_item(String(n))
	_routine_list.clear()
	for r in Cfg.g("routines", []):
		_routine_list.add_item("%s   —   %s" % [r.name, r.get("description", "%d steps" % r.get("steps", []).size())])


func refresh_startup() -> void:
	_startup_list.clear()
	_startup_list.add_item("Loading...")
	var r: Dictionary = await pc.startup_list()
	_startup_list.clear()
	_startup_items = r.get("items", [])
	if r.has("error"):
		_startup_list.add_item(str(r.error))
	for it in _startup_items:
		_startup_list.add_item("%s %s%s" % ["[on] " if it.enabled else "[off]", it.name, "  (admin)" if it.needs_admin else ""])


func _build_activity() -> void:
	var v := _page("Activity")
	_heading(v, "What Rico has done on this PC")
	_log_view = TextEdit.new()
	_log_view.editable = false
	_log_view.custom_minimum_size = Vector2(0, 420)
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.add_theme_color_override("font_readonly_color", INK)
	_log_view.add_theme_font_size_override("font_size", 13)
	var lbg := StyleBoxFlat.new()
	lbg.bg_color = Color("1a120d")
	lbg.set_corner_radius_all(8)
	lbg.set_content_margin_all(8)
	_log_view.add_theme_stylebox_override("read_only", lbg)
	_log_view.add_theme_stylebox_override("normal", lbg)
	v.add_child(_log_view)
	var b := Button.new()
	b.text = "Refresh"
	b.pressed.connect(refresh_log)
	v.add_child(b)


func refresh_log() -> void:
	if _log_view and pc:
		_log_view.text = pc.read_log()


func _build_usage() -> void:
	var v := _page("Usage")
	_heading(v, "Claude spending")
	_usage_label = _label(v, "")
	var h := HBoxContainer.new()
	v.add_child(h)
	var cl := _label(h, "Daily cap (0 = no cap)")
	cl.custom_minimum_size.x = 220
	var cap := SpinBox.new()
	cap.min_value = 0
	cap.max_value = 20
	cap.step = 0.05
	cap.prefix = "£"
	cap.value = float(Cfg.g("daily_cap_gbp", 0.0))
	cap.value_changed.connect(func(val): Cfg.s("daily_cap_gbp", val))
	h.add_child(cap)
	_label(v, "When the cap is hit, Rico switches to his offline brain and local commands until tomorrow.", true)

	_heading(v, "Offline mini-brain")
	_label(v, "A small AI (Llama 3.2 3B, 2 GB) that runs on this PC for chat and simple questions: free and private. Claude still handles PC jobs, files, code, Godot/Blender help and harder questions.", true)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	v.add_child(bh)
	_brain_btn = Button.new()
	_brain_btn.pressed.connect(func():
		if brain.installed():
			brain.uninstall()
		elif brain.downloading:
			brain.cancel_download()
		else:
			brain_download_requested.emit()
		refresh_usage())
	bh.add_child(_brain_btn)
	_brain_label = Label.new()
	_brain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_brain_label)
	_check(v, "Use the offline brain when it's installed", "mini_brain")

	_heading(v, "What Rico remembers about you")
	_label(v, "Stored only on this PC. Rico sends Claude just the notes relevant to each question. Add notes by saying \"remember that...\".", true)
	_facts_list = ItemList.new()
	_facts_list.custom_minimum_size = Vector2(0, 140)
	v.add_child(_facts_list)
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 8)
	v.add_child(fh)
	var del := Button.new()
	del.text = "Forget selected"
	del.pressed.connect(func():
		var sel := _facts_list.get_selected_items()
		sel.reverse()
		for i in sel:
			mem.remove_fact_at(i)
		refresh_usage())
	fh.add_child(del)
	var cc := Button.new()
	cc.text = "Clear answer cache"
	cc.pressed.connect(func(): mem.clear_cache(); refresh_usage())
	fh.add_child(cc)
	tabs.tab_changed.connect(func(_t): refresh_usage())


func _voice_slider(parent: Node, text: String, key: String, lo: float, hi: float) -> void:
	_slider(parent, text, key, lo, hi)
	var sl: HSlider = parent.get_child(parent.get_child_count() - 1).get_child(1)
	sl.step = 0.01
	sl.value_changed.connect(func(_v): voice_out.apply_settings())


func set_voice_status(t: String) -> void:
	if _voice_label:
		_voice_label.text = t
		if t == "":
			refresh_voice()


func refresh_voice() -> void:
	if _voice_btn == null or voice_out == null:
		return
	if voice_out.installed():
		_voice_btn.text = "Remove Rico's voice"
		_voice_label.text = "Installed" + (", awake" if voice_out.ready_now() else "")
	elif voice_out.downloading:
		_voice_btn.text = "Cancel download"
	else:
		_voice_btn.text = "Download Rico's voice (2 GB)"
		_voice_label.text = "Not installed: using the Windows voice"


func set_brain_status(t: String) -> void:
	if _brain_label:
		_brain_label.text = t
		if t == "":
			refresh_usage()


func refresh_usage() -> void:
	if _usage_label == null or mem == null:
		return
	var d: Dictionary = mem.today_stats()
	var m: Dictionary = mem.month_stats()
	var r: float = mem.usd_to_gbp
	_usage_label.text = "Today: %s  (%d Haiku, %d Sonnet calls)\nThis month: %s  (%d Haiku, %d Sonnet calls)\nTokens this month: %s in, %s out, %s read from cache\nFree answers this month: %d local commands, %d from memory, %d offline brain" % [
		mem.fmt_gbp(float(d.usd) * r), int(d.haiku), int(d.sonnet),
		mem.fmt_gbp(float(m.usd) * r), int(m.haiku), int(m.sonnet),
		_k(int(m["in"]) + int(m.cw)), _k(int(m.out)), _k(int(m.cr)),
		int(m.local), int(m.cache), int(m.mini)]
	if brain:
		if brain.installed():
			_brain_btn.text = "Remove offline brain"
			_brain_label.text = "Installed"
		elif brain.downloading:
			_brain_btn.text = "Cancel download"
		else:
			_brain_btn.text = "Download offline brain (2 GB)"
			_brain_label.text = "Not installed"
	_facts_list.clear()
	for f in mem.facts:
		_facts_list.add_item(String(f.t))


func _k(n: int) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 1000 else str(n)


func _build_help() -> void:
	var v := _page("Help")
	_heading(v, "Mouse")
	_label(v, "Left-click Rico: chat.  Right-click: menu.  Drag: move him.  Drag and let go fast: fling him and watch him ricochet.")
	_heading(v, "Keyboard (works from any app)")
	_label(v, "Alt+Space: search bar (apps, files, maths, conversions, Rico actions)\nCtrl+Shift+Space: open chat\nCtrl+Alt+Space: talk (press again to stop)\nCtrl+Alt+R: hide or show Rico\nEsc: close the bubble")
	_heading(v, "Controller (hold View/Back, then press)")
	_label(v, "A: open chat or confirm\nRB: search bar, listening (D-pad picks, A opens, Y asks Rico)\nX: talk / stop talking\nB: close the bubble\nY: hide or show Rico\nD-pad: move between buttons")
	_heading(v, "PC jobs to try")
	_label(v, "\"Why is my PC slow?\"\n\"Clean up my junk\"\n\"Game mode on\" / \"Game mode off\"\n\"Tidy my Downloads\"\n\"Find my biggest files in Documents\"\n\"How hot is my PC running?\"\n\"Stop Spotify starting with Windows\"\n\"Make a Work routine that opens Godot and Blender\"")
	_heading(v, "Things to say")
	_label(v, "\"Remind me in 25 minutes to check the bake\"\n\"Set a timer for 5 minutes\"\n\"What reminders have I got?\"\n\"Open Zuri\"\n\"How do I make a one-way collision platform in Godot?\"")
