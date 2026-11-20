extends Node2D
## Rico's main controller: the floating window, input, and wiring everything together.

const Lines := preload("res://scripts/lines.gd")
const RicoScript := preload("res://scripts/rico.gd")
const BubbleScript := preload("res://scripts/bubble.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const HelperScript := preload("res://scripts/helper_bridge.gd")
const AiScript := preload("res://scripts/ai.gd")
const VoiceScript := preload("res://scripts/voice.gd")
const RemindersScript := preload("res://scripts/reminders.gd")
const SettingsScript := preload("res://scripts/settings_window.gd")
const PcScript := preload("res://scripts/pc.gd")

signal _approval_answered(result: Dictionary)

var rico
var bubble
var sfx
var helper
var ai
var voice
var reminders
var settings
var pc
var pc_menu: PopupMenu
var _approval_pending := false
var _report_timer := 30.0
var menu: PopupMenu
var timer_menu: PopupMenu
var projects_menu: PopupMenu
var tray: StatusIndicator
var fx: Node2D

var area := Rect2()
var sparks: Array = []
var _pressing := false
var _press_pos := Vector2.ZERO
var _press_button := 0
var _last_region := Rect2()
var _mouse_prev := Vector2.ZERO
var _mouse_still := 0.0
var _quip_timer := 0.0
var _hidden_until := -1.0
var _fg_title := ""
var _fg_kind := ""
var _kind_time := 0.0
var _tip_cooldown := 240.0
var _tip_queues := {}
var _last_was_voice := false
var _current_reminder := {}
var _blip_acc := 0.0
var _joy_prev := {}
var _pong_count := 0
var _fg_exe := ""
var _fg_rect := Rect2()          # focused window in our window coords (size 0 = none)
var _dodge_check := -1.0
var _user_placed := false


func _ready() -> void:
	randomize()
	var win := get_window()
	win.title = "Rico"
	_fit_to_screen()

	fx = Node2D.new()
	fx.draw.connect(_draw_fx)
	sfx = SfxScript.new(); add_child(sfx)
	rico = RicoScript.new(); add_child(rico)
	add_child(fx)
	bubble = BubbleScript.new(); add_child(bubble)
	helper = HelperScript.new(); add_child(helper)
	ai = AiScript.new(); add_child(ai)
	voice = VoiceScript.new(); add_child(voice)
	reminders = RemindersScript.new(); add_child(reminders)
	pc = PcScript.new(); add_child(pc)
	pc.approve = _request_approval

	rico.scale = Vector2.ONE * Cfg.size_scale()
	rico.bounds = area
	var saved_x := float(Cfg.g("rico_x", -1.0))
	rico.position = Vector2(saved_x if saved_x > 0 else area.end.x - 160, area.end.y - rico.half_extents().y)
	rico.position.x = clampf(rico.position.x, area.position.x + 60, area.end.x - 60)
	rico.impact.connect(_on_impact)
	rico.landed.connect(_on_landed)

	bubble.submitted.connect(_on_submitted)
	bubble.mic_pressed.connect(_toggle_voice)
	bubble.action.connect(_on_bubble_action)
	bubble.closed.connect(_on_bubble_closed)

	helper.hotkey.connect(_on_hotkey)
	helper.foreground_changed.connect(_on_foreground)
	helper.focus_rect.connect(_on_focus_rect)
	rico.spot_ok = func(x): return not _covered(x)
	ai.reply.connect(_on_ai_reply)
	ai.failed.connect(_on_ai_failed)
	ai.tool_handler = _run_tool
	voice.started.connect(_on_voice_started)
	voice.transcribing.connect(_on_transcribing)
	voice.heard.connect(_on_voice_heard)
	voice.download_progress.connect(_on_model_download)
	voice.failed.connect(_on_voice_failed)
	reminders.due.connect(_on_reminder_due)
	reminders.break_due.connect(_on_break_due)

	settings = SettingsScript.new()
	settings.reminders = reminders
	settings.voice = voice
	settings.pc = pc
	add_child(settings)
	settings.build()
	settings.test_requested.connect(_test_api)
	reminders.list_changed.connect(settings.refresh_reminders)
	settings.refresh_reminders()
	Cfg.changed.connect(_on_cfg_changed)

	_build_menu()
	_build_tray()
	_quip_timer = _next_quip_delay()
	_update_region(true)
	if OS.has_environment("RICO_DODGE_TEST"):
		_run_dodge_test.call_deferred()
		return
	if OS.has_environment("RICO_SHOT"):
		_run_shot_test.call_deferred()
		return
	get_tree().create_timer(0.9).timeout.connect(func():
		rico.waving = 2.0
		_say(Lines.pick(Lines.GREET), 6))


func _run_dodge_test() -> void:
	var tree := get_tree()
	Cfg.data.wander = false
	Cfg.data.volume = 0.0
	Cfg.data.app_spots = {}
	rico.position.x = 1500
	var wp := get_window().position
	print("area ", area, " start x ", rico.position.x)
	_on_focus_rect(Rect2i(wp.x + 900, wp.y + 100, 1000, int(area.size.y)), "blender.exe")
	await tree.create_timer(6.0).timeout
	print("blender covering right: x=", rico.position.x, " covered=", _covered(rico.position.x))
	_on_focus_rect(Rect2i(wp.x, wp.y, int(area.size.x), int(area.size.y)), "godot.exe")
	await tree.create_timer(6.0).timeout
	print("godot maximised: x=", rico.position.x)
	rico.start_drag(rico.position); _user_placed = true; rico.position.x = 700; rico.release_drag()
	await tree.create_timer(3.0).timeout
	print("dropped in godot at x=", rico.position.x, " spots=", Cfg.g("app_spots"))
	_on_focus_rect(Rect2i(wp.x + 900, wp.y + 100, 1000, int(area.size.y)), "blender.exe")
	await tree.create_timer(6.0).timeout
	print("back to blender: x=", rico.position.x)
	_on_focus_rect(Rect2i(wp.x, wp.y, int(area.size.x), int(area.size.y)), "godot.exe")
	await tree.create_timer(6.0).timeout
	print("back to godot (saved spot): x=", rico.position.x)
	_on_focus_rect(Rect2i(wp.x + 200, wp.y + 100, 600, 400), "notepad.exe")
	await tree.create_timer(3.0).timeout
	print("small window up top: x=", rico.position.x)
	tree.quit()


## Dev-only: render scenarios to PNG for checking the art (RICO_SHOT=<folder>).
func _run_shot_test() -> void:
	var out := OS.get_environment("RICO_SHOT")
	Cfg.data.wander = false
	Cfg.data.talk_blips = false
	Cfg.data.volume = 0.0
	var tree := get_tree()
	var shots := [
		["approve", func(): rico.position.x = 900; _request_approval("Clean up junk? Up to 2340 MB can be freed. Untick anything you want to keep.", "Temp files used in the last 24 hours are skipped.", [["a", "Your temp files: 1210 MB", true], ["b", "Browser caches (Chrome, Edge, Firefox): 860 MB", true], ["c", "Recycle Bin: 270 MB", false]])],
		["command", func(): _answer_approval(false); _request_approval("Check how much space each folder in Downloads takes.", "Get-ChildItem \"$env:USERPROFILE\\Downloads\" -Directory | ForEach-Object { [pscustomobject]@{ Name = $_.Name; MB = [math]::Round((Get-ChildItem $_.FullName -Recurse -File | Measure-Object Length -Sum).Sum / 1MB) } } | Sort-Object MB -Descending", [], false); await get_tree().create_timer(0.3).timeout; bubble.toggle_details()],
		["slow", func(): _answer_approval(false); _say("CPU 64%, RAM 88% of 32 GB used.\nblender: 41% CPU, 9120 MB\nchrome (x23): 12% CPU, 5400 MB\nDiscord: 3% CPU, 910 MB\nRAM's nearly full, that's your slowdown.", -1, false, [["close:chrome", "Close chrome"], ["close:Discord", "Close Discord"], ["dismiss", "Thanks"]])],
		["idle", func(): rico.position.x = 900; rico.set_mood("smug", 99)],
		["happy", func(): rico.set_mood("happy", 99)],
		["talk", func(): rico.set_mood("smug", 99); _say("Rico, reporting for duty. Try not to make it boring.", 99)],
		["chat", func(): bubble.hide_bubble(); bubble.open_chat("Go on then. Ask. I've got all day, apparently.")],
		["think", func(): bubble.hide_bubble(); rico.thinking = true; _say("...", -1, true)],
		["alert", func(): rico.thinking = false; ai.busy = false; _on_reminder_due({"text": "Check the render, it's been an hour."})],
		["listen", func(): bubble.hide_bubble(); rico.alerting = false; rico.listening = true; _say("Listening... (press Ctrl+Alt+Space or Stop when you're done)", -1, true)],
		["sleep", func(): bubble.hide_bubble(); rico.listening = false; rico.state = RicoScript.State.IDLE; rico.sleep()],
		["worried", func(): rico.wake(); rico.state = RicoScript.State.DRAG; rico.position.y = 500; rico.rotation = 0.35; rico.set_mood("worried", 99)],
		["fly", func(): rico.state = RicoScript.State.FLY; rico.rotation = 1.9; rico.set_mood("shock", 99); _on_impact(Vector2(rico.position.x + 40, 520), 1500, Vector2.LEFT)],
	]
	for s in shots:
		s[1].call()
		await tree.create_timer(1.6).timeout
		if s[0] in ["worried", "fly"]:
			rico.state = RicoScript.State.DRAG
		var img := get_viewport().get_texture().get_image()
		img.save_png(out.path_join(s[0] + ".png"))
		if s[0] == "slow" and OS.has_environment("RICO_SHOT_PC"):
			get_tree().quit()
			return
	# icon render
	bubble.hide_bubble()
	sparks.clear()
	rico.state = RicoScript.State.DRAG
	rico.rotation = 0
	rico.set_mood("smug", 99)
	rico.waving = 0
	rico.scale = Vector2.ONE * 3.0
	rico.position = Vector2(300, 300)
	rico.look_at_pos = Vector2(300, 600)
	await tree.create_timer(0.8).timeout
	var full := get_viewport().get_texture().get_image()
	full.save_png(out.path_join("icon_raw.png"))
	tree.quit()


func _fit_to_screen() -> void:
	var win := get_window()
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	# 1 px short of the usable area so Windows never treats us as a fullscreen app.
	win.position = usable.position
	win.size = Vector2i(usable.size.x, usable.size.y - 1)
	area = Rect2(Vector2.ZERO, Vector2(win.size))


# ------------------------------------------------------------------ menus

func _build_menu() -> void:
	menu = PopupMenu.new()
	add_child(menu)
	timer_menu = PopupMenu.new()
	for m in [5, 10, 15, 25, 45, 60]:
		timer_menu.add_item("%d minutes" % m, m)
	timer_menu.id_pressed.connect(func(id):
		reminders.add("Your %d minute timer's done." % id, id)
		_say("Timer set: %d minutes. Tick tock." % id, 4))
	projects_menu = PopupMenu.new()
	projects_menu.id_pressed.connect(func(id):
		var list: Array = Cfg.g("projects")
		if id < list.size():
			_open_project(list[id]))
	menu.add_item("Chat with Rico", 0)
	menu.add_item("Talk (voice)", 1)
	menu.add_separator()
	menu.add_submenu_node_item("Quick timer", timer_menu)
	menu.add_submenu_node_item("Open project", projects_menu)
	pc_menu = PopupMenu.new()
	pc_menu.id_pressed.connect(_on_pc_menu)
	menu.add_submenu_node_item("PC", pc_menu)
	menu.add_item("Reminders...", 2)
	menu.add_separator()
	menu.add_item("Settings...", 3)
	menu.add_item("New conversation", 4)
	menu.add_item("Forget my spot for this app", 7)
	menu.add_item("Take a nap", 5)
	menu.add_item("Hide for 30 minutes", 6)
	menu.add_separator()
	menu.add_item("Quit Rico", 9)
	menu.id_pressed.connect(_on_menu)
	menu.about_to_popup.connect(_refresh_projects_menu)
	menu.about_to_popup.connect(_refresh_pc_menu)


func _refresh_pc_menu() -> void:
	pc_menu.clear()
	pc_menu.add_item("What's slowing me down?", 0)
	pc_menu.add_item("Clean up junk...", 1)
	var perf_on: bool = Cfg.g("perf_state", {}).get("on", false)
	pc_menu.add_item("Game/Render mode: turn OFF" if perf_on else "Game/Render mode: turn ON", 2)
	pc_menu.add_item("Health check", 3)
	pc_menu.add_item("Startup apps...", 4)
	if not Cfg.g("last_undo", {}).is_empty():
		pc_menu.add_item("Undo last %s" % Cfg.g("last_undo").label, 5)
	pc_menu.add_item("Activity log...", 6)
	var routines: Array = Cfg.g("routines", [])
	if not routines.is_empty():
		pc_menu.add_separator("Routines")
		for i in routines.size():
			pc_menu.add_item("Run: " + String(routines[i].name), 100 + i)
	if not pc.enabled():
		for i in pc_menu.item_count:
			pc_menu.set_item_disabled(i, true)


func _refresh_projects_menu() -> void:
	projects_menu.clear()
	var list: Array = Cfg.g("projects")
	if list.is_empty():
		projects_menu.add_item("No projects yet. Add some in Settings.", 999)
		projects_menu.set_item_disabled(0, true)
	for i in list.size():
		projects_menu.add_item(list[i].name, i)


func _popup_menu(screen_pos: Vector2i) -> void:
	_refresh_projects_menu()
	_refresh_pc_menu()
	menu.reset_size()
	menu.position = screen_pos
	menu.popup()


func _on_menu(id: int) -> void:
	match id:
		0: _open_chat()
		1: _toggle_voice()
		2: _open_settings(2)
		3: _open_settings(0)
		4:
			ai.clear()
			_say("Fresh start. I've already forgotten everything. Bliss.", 4)
		5: rico.sleep()
		6: _hide_for(30 * 60)
		7:
			var spots: Dictionary = Cfg.g("app_spots", {}).duplicate()
			if spots.erase(_fg_exe):
				Cfg.s("app_spots", spots)
				rico.home_x = -1.0
				_say("Forgotten. I'll freestyle in %s from now on." % _app_label(_fg_exe), 4)
			else:
				_say("I didn't have a spot saved for this app anyway.", 4)
		9: _quit()


func _build_tray() -> void:
	tray = StatusIndicator.new()
	tray.tooltip = "Rico"
	tray.icon = load("res://assets/tray.png")
	tray.pressed.connect(func(button, pos):
		if button == MOUSE_BUTTON_LEFT:
			_toggle_visible()
		else:
			_popup_menu(pos))
	add_child(tray)


func _open_settings(tab := 0) -> void:
	settings.tabs.current_tab = tab
	settings.refresh_pc()
	settings.refresh_log()
	if tab == 5:
		settings.refresh_startup()
	settings.refresh_reminders()
	settings.refresh_projects()
	settings.popup_centered()
	settings.grab_focus()


# ------------------------------------------------------------------ visibility

func _toggle_visible() -> void:
	if get_window().visible:
		_hide_for(-1)
	else:
		_show()


func _hide_for(seconds: float) -> void:
	bubble.hide_bubble()
	get_window().visible = false
	_hidden_until = Time.get_ticks_msec() / 1000.0 + seconds if seconds > 0 else -1.0


func _show() -> void:
	_hidden_until = -1.0
	if not get_window().visible:
		get_window().visible = true
		get_window().always_on_top = true
		_update_region(true)
		rico.waving = 1.5
		_say("Miss me?", 3)


func _quit() -> void:
	Cfg.s("rico_x", rico.position.x)
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


# ------------------------------------------------------------------ talking

func _say(text: String, timeout := 6.0, keep_chat := false, buttons: Array = []) -> void:
	if not keep_chat and bubble.chat_mode and buttons.is_empty():
		keep_chat = true
	bubble.chat_mode = keep_chat
	bubble.say(text, timeout, buttons)
	sfx.play("pop", randf_range(0.95, 1.1), 0.7)


func _open_chat() -> void:
	_show()
	rico.wake()
	DisplayServer.window_move_to_foreground()
	rico.waving = 1.2
	if not ai.has_key():
		bubble.open_chat(Lines.NO_KEY)
	elif bubble.visible and bubble.chat_mode:
		bubble.open_chat()
	else:
		bubble.open_chat(Lines.pick(["What now?", "Go on then. Ask.", "Rico's listening. Mostly.", "Yes? Make it interesting."]))


func _on_submitted(text: String) -> void:
	_last_was_voice = false
	_handle_request(text)


func _handle_request(text: String) -> void:
	voice.stop_speaking()
	if not ai.has_key():
		var local := _local_command(text)
		_say(local if local != "" else Lines.NO_KEY, -1, true)
		return
	if ai.busy:
		return
	rico.thinking = true
	_say("...", -1, true)
	ai.ask(text)


func _on_ai_reply(text: String) -> void:
	rico.thinking = false
	_say(text, -1, true)
	var mode := int(Cfg.g("speak_replies", 1))
	if mode == 2 or (mode == 1 and _last_was_voice):
		voice.speak(text)


func _on_ai_failed(msg: String) -> void:
	rico.thinking = false
	rico.set_mood("annoyed", 3)
	_say("Ugh. " + msg, -1, true)
	settings.set_status(msg)


func _test_api() -> void:
	if not ai.has_key():
		settings.set_status("Paste a key first.")
		return
	settings.set_status("Testing...")
	var once := func(t): settings.set_status("Works! Rico says: " + t)
	ai.reply.connect(once, CONNECT_ONE_SHOT)
	_handle_request("Say a one-line hello to prove you're connected.")


const PC_TOOLS := ["get_top_processes", "scan_junk", "list_startup_apps", "list_power_plans", "system_health", "find_files",
	"get_activity_log", "close_apps", "clean_junk", "set_startup_app", "set_power_plan", "performance_mode", "tidy_folder",
	"rename_files", "undo_last_file_change", "recycle_files", "run_powershell", "save_routine", "run_routine", "open_app_or_file"]


func _run_tool(name: String, input: Dictionary) -> String:
	if name in PC_TOOLS:
		if not pc.enabled():
			return "PC tools are switched off (Settings > PC) or this isn't Windows."
		return await _run_pc_tool(name, input)
	match name:
		"set_reminder":
			var text := String(input.get("text", "Reminder"))
			var rep := float(input.get("repeat_minutes", 0))
			var r := {}
			if input.has("at_time") and String(input.at_time) != "":
				r = reminders.add_at(text, String(input.at_time), rep)
			else:
				r = reminders.add(text, maxf(0.1, float(input.get("minutes_from_now", 10))), rep)
			if r.is_empty():
				return "Couldn't understand that time."
			return "Set: " + reminders.describe(r)
		"list_reminders":
			var out := []
			for r in reminders.pending():
				out.append(reminders.describe(r))
			return "No reminders." if out.is_empty() else "\n".join(out)
		"cancel_reminder":
			return "Cancelled." if reminders.cancel(int(input.get("id", -1))) else "No reminder with that id."
		"open_project":
			var p := _find_project(String(input.get("name", "")))
			if p.is_empty():
				return "No saved project matches that. Saved: " + ", ".join(Cfg.g("projects").map(func(x): return x.name))
			_open_project(p)
			return "Opened " + p.name
	return "Unknown tool."


func _run_pc_tool(name: String, i: Dictionary) -> String:
	match name:
		"get_top_processes":
			return await pc.top_processes_text(String(i.get("sort", "cpu")), int(i.get("count", 8)))
		"scan_junk":
			return JSON.stringify(await pc.junk_scan())
		"list_startup_apps":
			return JSON.stringify(await pc.startup_list())
		"list_power_plans":
			return JSON.stringify(await pc.power_list())
		"system_health":
			return JSON.stringify(await pc.health(bool(i.get("check_updates", false)), bool(i.get("admin_temps", false))))
		"find_files":
			return JSON.stringify(await pc.find_files(String(i.folder), String(i.get("kind", "big")), float(i.get("min_mb", 50)), int(i.get("limit", 15)))).left(6000)
		"get_activity_log":
			return pc.read_log(40)
		"close_apps":
			return await pc.close_apps(i.get("names", []), bool(i.get("force", false)), String(i.get("reason", "")))
		"clean_junk":
			return await pc.junk_clean(i.get("categories", []))
		"set_startup_app":
			return await pc.startup_set(String(i.name), bool(i.enabled))
		"set_power_plan":
			return await pc.power_set(String(i.plan))
		"performance_mode":
			if bool(i.get("on", true)):
				return await pc.perf_mode_on(i.get("suggested_apps", []))
			return await pc.perf_mode_off()
		"tidy_folder":
			return await pc.tidy(String(i.folder), String(i.get("by", "type")))
		"rename_files":
			return await pc.rename(String(i.folder), String(i.get("find", "")), String(i.get("replace", "")), String(i.get("prefix", "")), bool(i.get("number", false)), String(i.get("ext", "")))
		"undo_last_file_change":
			return await pc.undo_last()
		"recycle_files":
			return await pc.recycle(i.get("paths", []))
		"run_powershell":
			return await pc.run_command(String(i.command), String(i.get("explanation", "Run this command?")), bool(i.get("needs_admin", false)))
		"save_routine":
			return pc.save_routine(String(i.name), String(i.get("description", "")), i.get("steps", []))
		"run_routine":
			return await pc.run_routine(String(i.name))
		"open_app_or_file":
			return pc.open_target(String(i.target))
	return "Unknown tool."


func _find_project(q: String) -> Dictionary:
	q = q.to_lower().strip_edges()
	if q == "":
		return {}
	for p in Cfg.g("projects"):
		if String(p.name).to_lower() == q:
			return p
	for p in Cfg.g("projects"):
		if q in String(p.name).to_lower() or String(p.name).to_lower() in q:
			return p
	return {}


func _open_project(p: Dictionary) -> void:
	var err := OS.shell_open(String(p.path))
	if err != OK:
		_say("Couldn't open %s. Has it moved?" % p.name, 5)
	else:
		_say("Opening %s. Try not to break anything." % p.name, 4)


## Simple offline commands for when there's no API key.
func _local_command(text: String) -> String:
	var t := text.to_lower().strip_edges()
	var re := RegEx.new()
	re.compile("(\\d+(?:\\.\\d+)?)\\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)\\b(?:\\s*(?:to|about|that)\\s+(.+))?")
	if "remind" in t or "timer" in t:
		var at := RegEx.new()
		at.compile("(?:at\\s+)?(\\d{1,2}):(\\d{2})(?:\\s*(?:to|about)\\s+(.+))?")
		var m := re.search(t)
		if m:
			var n := float(m.get_string(1))
			var unit := m.get_string(2)
			var mins := n / 60.0 if unit.begins_with("s") else (n * 60.0 if unit.begins_with("h") else n)
			var what := m.get_string(3).strip_edges()
			if what == "":
				what = "Time's up."
			var r: Dictionary = reminders.add(what.capitalize() if what != "Time's up." else what, mins)
			return "Done. " + reminders.describe(r)
		var a := at.search(t)
		if a:
			var what2 := a.get_string(3).strip_edges()
			var r2: Dictionary = reminders.add_at(what2.capitalize() if what2 != "" else "Reminder", "%s:%s" % [a.get_string(1), a.get_string(2)])
			return "Done. " + reminders.describe(r2)
	if t.begins_with("open ") or t.begins_with("launch "):
		var p := _find_project(t.split(" ", true, 1)[1])
		if not p.is_empty():
			_open_project(p)
			return "Opening %s." % p.name
		return "I don't have a project called that. Add it in Settings, Projects."
	if "reminders" in t:
		var out := []
		for r in reminders.pending():
			out.append(reminders.describe(r))
		return "Nothing pending. Living dangerously." if out.is_empty() else "\n".join(out)
	return ""


# ------------------------------------------------------------------ PC: approvals + menu flows

## Shows an Allow / Deny card in the bubble and waits for the answer.
func _request_approval(summary: String, details := "", checklist: Array = [], admin := false) -> Dictionary:
	while _approval_pending:
		await _approval_answered
	_approval_pending = true
	_show()
	rico.wake()
	rico.set_mood("think", 999)
	var buttons := [["allow", "Allow"], ["deny", "Deny"]]
	if details != "":
		buttons.append(["details", "Show details"])
	var text := summary + ("\n(This needs admin rights: Windows will ask too.)" if admin else "")
	var keep: bool = bubble.chat_mode
	bubble.say(text, -1, buttons, details, checklist)
	bubble.chat_mode = keep
	bubble.input_row.visible = keep
	sfx.play("pop")
	var res: Dictionary = await _approval_answered
	rico.set_mood("smug", 1)
	return res


func _answer_approval(allowed: bool) -> void:
	if not _approval_pending:
		return
	var checks: Array = bubble.get_checks()
	_approval_pending = false
	if allowed:
		_say("On it...", -1, bubble.chat_mode)
		rico.set_mood("happy", 1.2)
	else:
		_say("Fine, I won't.", 3, bubble.chat_mode)
		rico.set_mood("annoyed", 1.5)
	_approval_answered.emit({"allowed": allowed, "checked": checks})


func _on_bubble_closed() -> void:
	voice.stop_speaking()
	if _approval_pending:
		_answer_approval(false)


func _pc_busy_say(text: String) -> void:
	rico.thinking = true
	_say(text, -1, bubble.chat_mode)


func _on_pc_menu(id: int) -> void:
	if _approval_pending:
		_say("Answer my last question first.", 3)
		return
	match id:
		0: _flow_slow()
		1:
			_pc_busy_say("Measuring your junk...")
			var r: String = await pc.junk_clean()
			_say(r, 8)
		2:
			if Cfg.g("perf_state", {}).get("on", false):
				_pc_busy_say("Putting everything back...")
				_say(await pc.perf_mode_off(), 6)
			else:
				_pc_busy_say("Checking what's running...")
				var top: Dictionary = await pc.top_processes("memory", 12)
				var suggest := []
				var fg := _fg_exe.trim_suffix(".exe").to_lower()
				for p in top.get("processes", []):
					if not p.protected and p.name.to_lower() != fg and float(p.mem_mb) > 300:
						suggest.append(p.name)
				_say(await pc.perf_mode_on(suggest), 8)
		3: _flow_health(false)
		4: _open_settings(5)
		5: _say(await pc.undo_last(), 5)
		6: _open_settings(6)
		_:
			if id >= 100:
				var routines: Array = Cfg.g("routines", [])
				if id - 100 < routines.size():
					_pc_busy_say("Running %s..." % routines[id - 100].name)
					_say(await pc.run_routine(routines[id - 100].name, true), 6)


func _flow_slow() -> void:
	_pc_busy_say("Having a look at what's chewing your CPU...")
	var r: Dictionary = await pc.top_processes("cpu", 8)
	if r.has("error"):
		_say("Couldn't check: " + str(r.error), 6)
		return
	var lines := ["CPU %s%%, RAM %s%% of %s GB used." % [r.total_cpu_percent, r.ram_used_percent, r.ram_total_gb]]
	var buttons := []
	var fg := _fg_exe.trim_suffix(".exe").to_lower()
	for p in r.get("processes", []).slice(0, 5):
		lines.append("%s: %s%% CPU, %s MB" % [p.name, p.cpu, p.mem_mb])
		if not p.protected and buttons.size() < 2 and String(p.name).to_lower() != fg and (float(p.cpu) > 5 or float(p.mem_mb) > 800):
			buttons.append(["close:" + String(p.name), "Close " + String(p.name)])
	if float(r.ram_used_percent) > 85:
		lines.append("RAM's nearly full, that's your slowdown.")
	buttons.append(["dismiss", "Thanks"])
	_say("\n".join(lines), -1, false, buttons)


func _flow_health(admin_temps: bool) -> void:
	_pc_busy_say("Giving your PC a check-up. Checking for updates takes about half a minute...")
	var r: Dictionary = await pc.health(true, admin_temps)
	if r.has("error"):
		_say("Check-up failed: " + str(r.error), 6)
		return
	_say(_health_summary(r), -1, false, [["dismiss", "Nice"], ["temps_admin", "Check CPU temps (admin)"]] if not r.get("is_admin", false) else [["dismiss", "Nice"]])


func _health_summary(r: Dictionary) -> String:
	var out := []
	for d in r.get("drives", []):
		out.append("%s %s GB free (%s%%)%s" % [d.drive, d.free_gb, d.free_percent, ", getting tight" if float(d.free_percent) < 10 else ""])
	out.append("RAM %s%% used of %s GB" % [r.get("ram_used_percent"), r.get("ram_total_gb")])
	var up := float(r.get("uptime_days", 0))
	out.append("Up %s days%s" % [up, ", a restart wouldn't hurt" if up > 7 else ""])
	if r.get("reboot_pending", false):
		out.append("A restart is pending for updates")
	if r.get("pending_updates") != null:
		out.append("%d updates waiting" % int(r.pending_updates) if int(r.pending_updates) > 0 else "Windows is up to date")
	for g in r.get("gpus", []):
		out.append("%s, driver from %s" % [g.name, g.driver_date])
	var temps := []
	for t in r.get("temperatures", []):
		temps.append("%s %d C" % [t.device, int(t.celsius)])
	if not temps.is_empty():
		out.append("Temps: " + ", ".join(temps))
	if String(r.get("temperature_note", "")) != "":
		out.append(String(r.temperature_note))
	return "Check-up:\n" + "\n".join(out)


# ------------------------------------------------------------------ voice

func _toggle_voice() -> void:
	_show()
	rico.wake()
	if voice.recording:
		voice.stop()
	else:
		voice.toggle()


func _on_model_download(p: String) -> void:
	match p:
		"start": _say("First time talking? I need to grab my ears (a ~150 MB offline speech model). One sec...", -1, bubble.chat_mode)
		"done":
			_say("Ears installed. Press Ctrl+Alt+Space (or Mic) and talk.", 6, bubble.chat_mode)
			sfx.play("pop")
		_: if bubble.visible: bubble.text_label.text = "Downloading my ears... %s%%" % p


func _on_transcribing() -> void:
	rico.listening = false
	bubble.set_listening(false)
	sfx.play("stop")
	_say("Transcribing your mumbling...", -1, true)


func _on_voice_failed(m: String) -> void:
	rico.listening = false
	bubble.set_listening(false)
	_say(m, 6, bubble.chat_mode)


func _on_voice_started() -> void:
	rico.listening = true
	bubble.set_listening(true)
	sfx.play("start")
	_say("Listening... (press Ctrl+Alt+Space or Stop when you're done)", -1, bubble.chat_mode)


func _on_voice_heard(text: String) -> void:
	rico.listening = false
	bubble.chat_mode = true
	_last_was_voice = true
	bubble.input_row.visible = true
	_say("You said: \"%s\"" % text, -1, true)
	await get_tree().create_timer(0.6).timeout
	_handle_request(text)


# ------------------------------------------------------------------ reminders

func _on_reminder_due(r: Dictionary) -> void:
	_show()
	rico.wake()
	_current_reminder = r
	rico.alerting = true
	rico.jump_for_joy()
	sfx.play("alert")
	var text := "Oi! %s" % r.text
	_say(text, -1, false, [["done", "Done"], ["snooze5", "Snooze 5 min"], ["snooze15", "15 min"]])
	if int(Cfg.g("speak_replies", 1)) == 2:
		voice.speak(text)


func _on_break_due() -> void:
	if bubble.is_busy_with_user():
		reminders._active_seconds = maxf(0.0, float(Cfg.g("break_minutes", 60)) * 60.0 - 300.0)
		return
	_show()
	rico.alerting = true
	rico.jump_for_joy()
	sfx.play("alert", 0.8)
	_current_reminder = {"break": true}
	_say(Lines.pick(Lines.BREAK), -1, false, [["done", "On it"], ["snooze15", "In 15 min"]])


func _on_bubble_action(id: String) -> void:
	if id == "details":
		bubble.toggle_details()
		return
	if id == "allow" or id == "deny":
		_answer_approval(id == "allow")
		return
	if id.begins_with("close:"):
		var name := id.substr(6)
		_pc_busy_say("Closing %s..." % name)
		_say(await pc.close_apps([name]), 6)
		return
	if id == "temps_admin":
		_flow_health(true)
		return
	rico.alerting = false
	match id:
		"dismiss":
			bubble.hide_bubble()
		"done":
			rico.set_mood("happy", 1.5)
			bubble.hide_bubble()
		"snooze5", "snooze15":
			var mins := 5.0 if id == "snooze5" else 15.0
			if _current_reminder.get("break", false):
				reminders._active_seconds = maxf(0.0, float(Cfg.g("break_minutes", 60)) - mins) * 60.0
			elif not _current_reminder.is_empty():
				reminders.snooze(_current_reminder, mins)
			_say("Fine. %d more minutes. I'm counting." % mins, 3)
	_current_reminder = {}


# ------------------------------------------------------------------ helper events

func _on_hotkey(name: String) -> void:
	match name:
		"chat":
			if bubble.visible and bubble.chat_mode and get_window().visible:
				bubble.hide_bubble()
			else:
				_open_chat()
		"voice":
			if not bubble.chat_mode:
				bubble.chat_mode = true
			_toggle_voice()
		"toggle":
			_toggle_visible()


func _on_foreground(title: String) -> void:
	_fg_title = title
	ai.foreground_app = title
	var kind: String = Lines.app_kind(title)
	if kind != _fg_kind:
		_fg_kind = kind
		_kind_time = 0.0


# ------------------------------------------------------------------ dodging + per-app spots

func _app_label(exe: String) -> String:
	return exe.get_basename().capitalize() if exe != "" else "this app"


func _on_focus_rect(r: Rect2i, exe: String) -> void:
	if r.size.x <= 0:
		_fg_rect = Rect2()
		exe = "desktop"
	else:
		_fg_rect = Rect2(Vector2(r.position - get_window().position), Vector2(r.size))
	if exe != "" and exe != _fg_exe:
		_fg_exe = exe
		var spots: Dictionary = Cfg.g("app_spots", {})
		rico.home_x = float(spots[exe]) if spots.has(exe) else -1.0
		_dodge_check = 0.15
	else:
		_dodge_check = 0.5   # window moved or resized: settle, then check


## True if Rico standing at x would be on top of the focused window.
func _covered(x: float) -> bool:
	if not Cfg.g("dodge", true) or _fg_rect.size.x <= 0:
		return false
	var h: Vector2 = rico.half_extents()
	if _fg_rect.end.y < area.end.y - h.y * 1.2 or _fg_rect.position.y > area.end.y:
		return false   # window doesn't reach down to where Rico stands
	return x + h.x > _fg_rect.position.x and x - h.x < _fg_rect.end.x


func _free_x() -> float:
	var h: Vector2 = rico.half_extents()
	var pad := h.x + 10.0
	var x: float = rico.position.x
	var best := INF
	var best_x := -1.0
	for gap in [Vector2(area.position.x + pad, _fg_rect.position.x - pad), Vector2(_fg_rect.end.x + pad, area.end.x - pad)]:
		if gap.y < gap.x:
			continue
		var cand := clampf(x, gap.x, gap.y)
		if absf(cand - x) < best:
			best = absf(cand - x)
			best_x = cand
	if best_x < 0:
		# no free space (maximised window): go to the nearer bottom corner
		best_x = area.end.x - pad if x > area.get_center().x else area.position.x + pad
	return best_x


func _apply_placement() -> void:
	if rico.state in [RicoScript.State.DRAG, RicoScript.State.FLY] or _pressing:
		_dodge_check = 0.5
		return
	if rico.home_x >= 0:
		if absf(rico.position.x - rico.home_x) > 14:
			rico.hop_to(rico.home_x, true)
		return
	if _covered(rico.position.x):
		var target := _free_x()
		if absf(target - rico.position.x) > 14:
			rico.hop_to(target, true)


# ------------------------------------------------------------------ physics fx

func _on_impact(pos: Vector2, speed: float, normal: Vector2) -> void:
	var n := clampi(int(speed / 120.0), 4, 16)
	for i in n:
		var dir := normal.rotated(randf_range(-1.2, 1.2))
		sparks.append({"p": pos, "v": dir * randf_range(150, 520), "life": randf_range(0.25, 0.5), "max": 0.5})
	sfx.play("ping", randf_range(0.85, 1.25), clampf(speed / 1500.0, 0.3, 1.0))
	_pong_count += 1
	rico.set_mood("shock", 0.5)


func _on_landed() -> void:
	sfx.play("thud", 1.0, 0.6)
	if _pong_count >= 2:
		rico.set_mood("happy", 2.0)
		if randf() < 0.6:
			_say(Lines.pick(Lines.FLUNG), 4)
	else:
		rico.set_mood("smug", 1.0)
	_pong_count = 0
	Cfg.data.rico_x = rico.position.x
	if _user_placed:
		_user_placed = false
		if _fg_exe != "":
			var spots: Dictionary = Cfg.g("app_spots", {}).duplicate()
			var first := not spots.has(_fg_exe)
			spots[_fg_exe] = rico.position.x
			Cfg.s("app_spots", spots)
			rico.home_x = rico.position.x
			if first:
				_say("Noted. This is my %s spot now." % _app_label(_fg_exe), 4)


func _draw_fx() -> void:
	for s in sparks:
		var a: float = clampf(s.life / s.max, 0.0, 1.0)
		var tail: Vector2 = s.p - s.v.normalized() * 10.0 * a
		fx.draw_line(tail, s.p, Color(1.0, 0.85, 0.35, a), 3.0, true)
		fx.draw_circle(s.p, 1.6, Color(1, 1, 0.9, a))


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if _hidden_until > 0 and Time.get_ticks_msec() / 1000.0 > _hidden_until:
		_show()
	var win := get_window()
	var mouse := Vector2(DisplayServer.mouse_get_position() - win.position)

	# drag
	if _pressing and _press_button == MOUSE_BUTTON_LEFT:
		if rico.state != RicoScript.State.DRAG and mouse.distance_to(_press_pos) > 6.0:
			rico.start_drag(_press_pos)
			bubble.hide_bubble()
		if rico.state == RicoScript.State.DRAG:
			rico.drag_to(mouse, delta)

	# eyes
	rico.look_at_pos = mouse
	if bubble.visible and not bubble.typing and bubble.chat_mode and mouse.distance_to(rico.position) > 600:
		rico.look_at_pos = bubble.position + bubble.size * 0.5
	rico.talking = bubble.visible and bubble.typing and bubble._full_text != "..."
	rico.thinking = (ai.busy or voice.busy or bubble._full_text.ends_with("...")) and not _approval_pending
	if rico.talking and Cfg.g("talk_blips"):
		_blip_acc += delta
		if _blip_acc > 0.075:
			_blip_acc = 0.0
			sfx.play("blip%d" % (randi() % 3), randf_range(0.9, 1.15), 0.5)

	# bubble follows Rico
	if bubble.visible:
		var h: Vector2 = rico.half_extents()
		bubble.place(rico.position - Vector2(0, h.y), rico.position + Vector2(0, h.y), area)
	elif rico.alerting:
		rico.alerting = false

	# idle / sleep
	if mouse.distance_to(_mouse_prev) > 2.0:
		_mouse_still = 0.0
		if rico.state == RicoScript.State.SLEEP:
			rico.wake()
			if randf() < 0.4:
				_say(Lines.pick(Lines.WAKE), 4)
	else:
		_mouse_still += delta
	_mouse_prev = mouse
	if _mouse_still > 300.0 and not bubble.visible and rico.state == RicoScript.State.IDLE:
		rico.sleep()

	# idle quips + app tips
	var chat := int(Cfg.g("chattiness", 1))
	if not bubble.visible and rico.state in [RicoScript.State.IDLE, RicoScript.State.HOP] and win.visible:
		_quip_timer -= delta
		if _quip_timer <= 0 and chat > 0:
			_quip_timer = _next_quip_delay()
			_say(Lines.pick(Lines.IDLE), 6)
	_kind_time += delta
	_tip_cooldown -= delta
	if Cfg.g("app_tips") and _fg_kind != "" and _kind_time > 150.0 and _tip_cooldown <= 0 and not bubble.visible and win.visible and rico.state != RicoScript.State.SLEEP:
		_tip_cooldown = [1800.0, 720.0, 360.0][chat]
		_say(_next_tip(_fg_kind), 9)

	_poll_controller()
	_report_timer -= delta
	if _report_timer <= 0:
		_report_timer = 60.0
		_maybe_weekly_report()
	if _dodge_check > 0:
		_dodge_check -= delta
		if _dodge_check <= 0:
			_apply_placement()

	# sparks
	for s in sparks:
		s.v.y += 900.0 * delta
		s.p += s.v * delta
		s.life -= delta
	sparks = sparks.filter(func(s): return s.life > 0)
	fx.queue_redraw()

	_update_region()


func _maybe_weekly_report() -> void:
	if not Cfg.g("weekly_report", true) or not pc.enabled():
		return
	var now := Time.get_unix_time_from_system()
	var last := float(Cfg.g("last_report", 0))
	if last <= 0:
		Cfg.s("last_report", now)
		return
	if now - last < 7 * 86400 or bubble.visible or rico.state == RicoScript.State.SLEEP:
		return
	Cfg.s("last_report", now)
	_say("Weekly check-up time. Hold still.", -1)
	_flow_health(false)


func _next_quip_delay() -> float:
	match int(Cfg.g("chattiness", 1)):
		2: return randf_range(120, 300)
		1: return randf_range(420, 780)
	return 99999.0


func _next_tip(kind: String) -> String:
	if not _tip_queues.has(kind) or _tip_queues[kind].is_empty():
		var q: Array = Lines.TIPS[kind].duplicate()
		q.shuffle()
		_tip_queues[kind] = q
	return _tip_queues[kind].pop_back()


func _update_region(force := false) -> void:
	var r: Rect2 = rico.visual_rect(70.0)
	if bubble.visible:
		r = r.merge(bubble.rect_with_tail())
	r = r.intersection(area.grow(-0.0))
	if r.size.x < 4 or r.size.y < 4:
		r = Rect2(rico.position - Vector2(40, 40), Vector2(80, 80))
	r = Rect2(r.position.floor(), r.size.ceil())
	if not force and absf(r.position.x - _last_region.position.x) < 2 and absf(r.position.y - _last_region.position.y) < 2 \
			and absf(r.size.x - _last_region.size.x) < 2 and absf(r.size.y - _last_region.size.y) < 2:
		return
	_last_region = r
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	# Joypad presses only reach Rico's buttons when his window has focus, so a
	# game you're playing never clicks his buttons by accident.
	if event is InputEventJoypadButton and not get_window().has_focus():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed and _pressing and event.button_index == _press_button:
		_pressing = false
		if rico.state == RicoScript.State.DRAG:
			rico.release_drag()
			_user_placed = true
		elif _press_button == MOUSE_BUTTON_LEFT and rico.hit_test(event.position):
			_on_rico_clicked()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and rico.hit_test(event.position):
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pressing = true
			_press_button = MOUSE_BUTTON_LEFT
			_press_pos = event.position
			if event.double_click:
				rico.jump_for_joy()
				rico.set_mood("happy", 1.5)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_popup_menu(DisplayServer.mouse_get_position())
		get_viewport().set_input_as_handled()


func _on_rico_clicked() -> void:
	_mouse_still = 0.0
	if rico.state == RicoScript.State.SLEEP:
		rico.wake()
		_say(Lines.pick(Lines.WAKE), 4)
		return
	if bubble.visible and bubble.chat_mode:
		bubble.input.grab_focus()
		return
	if bubble.is_busy_with_user():
		return
	rico.sq = 0.85
	_open_chat()


func _poll_controller() -> void:
	var pads := Input.get_connected_joypads()
	var held_back := false
	for d in pads:
		if Input.is_joy_button_pressed(d, JOY_BUTTON_BACK):
			held_back = true
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
		var down := false
		for d in pads:
			down = down or Input.is_joy_button_pressed(d, b)
		var was: bool = _joy_prev.get(b, false)
		_joy_prev[b] = down
		if down and not was and held_back:
			_on_combo(b)


func _on_combo(b: int) -> void:
	match b:
		JOY_BUTTON_A:
			if bubble.actions_box.visible and bubble.actions_box.get_child_count() > 0:
				_on_bubble_action(String(bubble.actions_box.get_child(0).get_meta("id", "done")))
			else:
				_open_chat()
		JOY_BUTTON_X:
			bubble.chat_mode = true
			_toggle_voice()
		JOY_BUTTON_B:
			if _approval_pending:
				_answer_approval(false)
			bubble.hide_bubble()
			voice.stop_speaking()
		JOY_BUTTON_Y:
			_toggle_visible()


func _on_cfg_changed(key: String) -> void:
	match key:
		"size":
			rico.scale = Vector2.ONE * Cfg.size_scale()
			rico.position.y = area.end.y - rico.half_extents().y
		"chattiness":
			_quip_timer = _next_quip_delay()
