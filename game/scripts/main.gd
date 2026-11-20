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
const MemScript := preload("res://scripts/memory.gd")
const BrainScript := preload("res://scripts/brain.gd")
const QuickScript := preload("res://scripts/quick.gd")
const SearchScript := preload("res://scripts/search.gd")
const UI := preload("res://scripts/ui.gd")
const UpdaterScript := preload("res://scripts/updater.gd")
const GamesScript := preload("res://scripts/games.gd")
const BambuScript := preload("res://scripts/bambu.gd")
const ShopScript := preload("res://scripts/printshop.gd")
const ShopWindowScript := preload("res://scripts/printshop_window.gd")
const MoneyScript := preload("res://scripts/money.gd")
const MoneyWindowScript := preload("res://scripts/money_window.gd")
const PrintHelp := preload("res://scripts/print_help.gd")

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
var updater
var games
var bambu
var shop
var shop_win
var money
var money_win
var _activity_t := 0.0
var _presence := 1.0
var _ghost := 0.0
var _hover_still := 0.0
var _fs_hidden := false
var _fs_queue: Array = []
var _print_started := 0.0
var _minute_timer := 5.0
var _game_time := 0.0
var _game_tip_timer := 900.0
var _fetching_tips := false
var _update_waiting := false
var mem
var brain
var quick
var search
var _pre_search_x := -1.0
var _voice_for_search := false
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
	updater = UpdaterScript.new()
	add_child(updater)
	if not OS.has_environment("RICO_SHOT_UI") and updater.install_pending():
		return   # installer takes over and relaunches Rico
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
	games = GamesScript.new(); add_child(games)
	bambu = BambuScript.new(); add_child(bambu)
	shop = ShopScript.new(); add_child(shop)
	money = MoneyScript.new(); add_child(money)
	pc = PcScript.new(); add_child(pc)
	pc.approve = _request_approval
	mem = MemScript.new(); add_child(mem)
	ai.mem = mem
	quick = QuickScript.new(); add_child(quick)
	if quick.rates.has("USD") and quick.rates.has("GBP"):
		mem.usd_to_gbp = float(quick.rates.GBP) / float(quick.rates.USD)
	brain = BrainScript.new(); add_child(brain)
	brain.reply.connect(_on_brain_reply)
	brain.failed.connect(_on_brain_failed)
	brain.download_progress.connect(func(p): settings.set_brain_status("Downloading... %d%%" % p))
	brain.download_done.connect(_on_brain_downloaded)
	search = SearchScript.new()
	search.quick = quick
	search.rico_items = _search_rico_items
	add_child(search)
	search.closed.connect(_on_search_closed)
	search.ask_rico.connect(_on_search_ask)
	search.rico_action.connect(_on_search_action)

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
	helper.hotkey_failed.connect(func(n):
		if n == "search":
			get_tree().create_timer(8.0).timeout.connect(func(): _say("Alt+Space is already taken by another app (PowerToys Run?), so my search bar is on the right-click menu and Ctrl+Shift+Space chat instead.", 9)))
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
	settings.updater = updater
	settings.games = games
	settings.mem = mem
	settings.brain = brain
	add_child(settings)
	settings.build()
	settings.test_requested.connect(_test_api)
	settings.brain_download_requested.connect(_start_brain_download)
	reminders.list_changed.connect(settings.refresh_reminders)
	shop_win = ShopWindowScript.new()
	shop_win.shop = shop
	shop_win.bambu = bambu
	add_child(shop_win)
	shop_win.build()
	shop_win.refresh_rates_requested.connect(_refresh_rates)
	shop_win.printer_settings_changed.connect(func(): bambu.reconnect())
	shop_win.sold.connect(func(nm, price): money.add("Sold: " + nm, price, "", "Income", "shop"); _say("Ka-ching! £%.2f logged for %s." % [price, nm], 5))
	money_win = MoneyWindowScript.new()
	money_win.money = money
	add_child(money_win)
	money_win.build()
	bambu.connection.connect(func(t): shop_win.set_printer_status(t))
	bambu.event.connect(_on_print_event)
	get_window().files_dropped.connect(_on_files_dropped)
	settings.refresh_reminders()
	Cfg.changed.connect(_on_cfg_changed)

	_build_menu()
	_build_tray()
	_quip_timer = _next_quip_delay()
	_update_region(true)
	if OS.has_environment("RICO_DODGE_TEST"):
		_run_dodge_test.call_deferred()
		return
	if OS.has_environment("RICO_ROUTER_TEST"):
		for q in ["spent £24.50 on petg", "sold a brio crossing for £8.99 on etsy", "budget", "how much left for groceries", "my print is stringing a lot", "the corners are lifting on my petg print", "price 120g of petg 5 hours", "find me a model of a brio crossing", "subscriptions", "why is my pc so slow", "tidy my downloads", "tell me a joke", "how do I make a one-way platform in godot", "think hard about my game's economy", "install obs for me", "what's your favourite colour", "hello", "remind me in 10 minutes to stretch", "remember that I use Blender 4.2", "open blender", "50 usd in gbp", "game mode on"]:
			var l: String = await _local_command(q)
			print(q, " | local=", "HANDLED" if l == HANDLED else l.left(40), " | groups=", ai.groups_for(q), " hard=", ai.is_hard(q), " claude=", ai.needs_tools(q) or ai.is_hard(q) or _wants_claude(q))
		get_tree().quit()
		return
	if OS.has_environment("RICO_SHOT_SHOP"):
		_run_shop_shot.call_deferred()
		return
	if OS.has_environment("RICO_SHOT_LOOK"):
		_run_look_shot.call_deferred()
		return
	if OS.has_environment("RICO_SHOT_UI"):
		_run_ui_shot.call_deferred()
		return
	if OS.has_environment("RICO_SHOT_SEARCH"):
		_run_search_shot.call_deferred()
		return
	if OS.has_environment("RICO_SHOT"):
		_run_shot_test.call_deferred()
		return
	updater.update_ready.connect(func(_v): _update_waiting = true)
	updater.status.connect(func(t): settings.set_update_status(t))
	_sync_autostart()
	get_tree().create_timer(0.9).timeout.connect(_first_words)


func _first_words() -> void:
	rico.waving = 2.0
	var notes: Dictionary = updater.take_update_notes()
	if not notes.is_empty():
		var body := String(notes.get("notes", "")).strip_edges()
		_say("Fresh upgrade: I'm now v%s.%s" % [notes.get("to", "?"), ("\n" + body.left(400)) if body != "" else ""], -1, false, [["dismiss", "Nice"]])
		return
	if not Cfg.g("welcomed", false):
		_welcome(1)
		return
	_say(Lines.pick(Lines.GREET), 6)


## First-run walkthrough in the bubble.
func _welcome(step: int) -> void:
	match step:
		1: _say("Hi, I'm Rico. A tiny brass bullet who lives on your desktop and does your chores. Quick tour?", -1, false, [["wel2", "Show me"], ["wel_skip", "Skip"]])
		2:
			if ai.has_key():
				_welcome(3)
				return
			_say("First, my brain. Paste a Claude API key in Settings and I can chat, help with Godot and Blender, and look after your PC. Without one I still do timers, search and PC jobs.", -1, false, [["wel_key", "Add API key"], ["wel3", "Later"]])
		3: _say("Shortcuts that work anywhere:\nAlt+Space  search everything\nCtrl+Shift+Space  chat with me\nCtrl+Alt+Space  talk to me\nController: hold View, then A chat, RB search, X talk.", -1, false, [["wel4", "Next"]])
		4:
			if brain.installed():
				_welcome(5)
				return
			_say("Want my offline brain? It's a one-off 2 GB download that makes small talk free and private.", -1, false, [["wel_brain", "Download it"], ["wel5", "Not now"]])
		5:
			Cfg.s("welcomed", true)
			_say("That's it. Right-click me for the menu, drag me about, or fling me if you're feeling brave.", 8, false, [["dismiss", "Let's go"]])


func _sync_autostart() -> void:
	if OS.get_name() != "Windows":
		return
	var out := []
	OS.execute("reg", ["query", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", "Rico"], out)
	var on := "Rico" in "".join(out)
	if on != bool(Cfg.g("start_with_windows", false)):
		Cfg.data.start_with_windows = on
		Cfg.save()


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


func _run_shop_shot() -> void:
	var out := OS.get_environment("RICO_SHOT_SHOP")
	_shot_mode = true
	Cfg.data.volume = 0.0
	Cfg.data.welcomed = true
	_open_shop()
	await shop_win.set_manual("PETG", 120.0, 5.0, "Brio crossing")
	shop_win._pack_checks["Small box"].button_pressed = true
	shop_win._labour.value = 15
	await get_tree().create_timer(1.0).timeout
	shop_win.get_texture().get_image().save_png(out.path_join("shop.png"))
	shop_win.hide()
	for d in [["2026-11-02", "TESCO STORES 2041", -46.2], ["2026-11-03", "NETFLIX.COM", -10.99], ["2026-11-05", "STEAM PURCHASE", -24.99], ["2026-11-07", "BAMBU LAB EU", -39.98], ["2026-11-09", "DELIVEROO", -21.5], ["2026-11-12", "SAINSBURYS", -38.4], ["2026-11-14", "TFL TRAVEL CH", -12.6], ["2026-11-15", "SALARY ACME LTD", 2150.0], ["2026-11-18", "AMAZON MKTPLACE", -58.0]]:
		money.add(d[1], d[2], d[0])
	money.add_bill("Netflix", 10.99, 3, "Subscriptions")
	money.add_bill("Council tax", 142.0, 1, "Bills")
	_open_money()
	await get_tree().create_timer(1.0).timeout
	money_win.get_texture().get_image().save_png(out.path_join("money.png"))
	money_win.hide()
	rico.scale = Vector2.ONE * 2.0
	_dock()
	rico.position = Vector2(300, 300)
	rico.print_progress = 0.42
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("docked.png"))
	get_tree().quit()


func _run_look_shot() -> void:
	var out := OS.get_environment("RICO_SHOT_LOOK")
	_shot_mode = true
	Cfg.data.volume = 0.0
	Cfg.data.wander = false
	Cfg.data.welcomed = true
	bubble.hide_bubble()
	rico.scale = Vector2.ONE * 2.0
	rico.state = RicoScript.State.IDLE
	rico.position.x = 500
	rico.bounds = Rect2(0, 0, 1000, 700)
	rico.position.y = 700 - rico.half_extents().y
	rico._fidget_timer = 999
	var shots := [
		["smug", func(): rico.set_mood("smug", 99); rico.look_at_pos = Vector2(900, 200)],
		["talk", func(): rico.talking = true; rico._gesture = "point"; rico.look_at_pos = Vector2(700, 100)],
		["happy", func(): rico.talking = false; rico._gesture = ""; rico.set_mood("happy", 99); rico.look_at_pos = Vector2(500, 300)],
		["shock", func(): rico.set_mood("shock", 99); rico.look_at_pos = Vector2(100, 300)],
		["think", func(): rico.set_mood("think", 99); rico.thinking = true],
		["shrug", func(): rico.thinking = false; rico.set_mood("smug", 99); rico._gesture = "shrug"; rico._gesture_t = 0.0; rico.look_at_pos = Vector2(500, 500)],
		["sleep", func(): rico._gesture = ""; rico.sleep()],
	]
	for sh in shots.slice(0, 7 if not OS.has_environment("RICO_FEW") else 3):
		sh[1].call()
		rico._gesture_t = 0.0
		await get_tree().create_timer(0.8).timeout
		rico._glitch = 0.0
		get_viewport().get_texture().get_image().save_png(out.path_join("holo_%s.png" % sh[0]))
	get_tree().quit()


func _run_ui_shot() -> void:
	var out := OS.get_environment("RICO_SHOT_UI")
	Cfg.data.volume = 0.0
	Cfg.data.wander = false
	var tree := get_tree()
	var snap := func(n: String): get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
	rico.position.x = 700
	await tree.create_timer(1.2).timeout
	_say("Rico, reporting for duty. Try not to make it boring.", 99)
	await tree.create_timer(2.0).timeout
	snap.call("u_say")
	bubble.hide_bubble()
	await tree.create_timer(0.4).timeout
	bubble.chat_mode = true
	_say("...", -1, true)
	await tree.create_timer(0.7).timeout
	snap.call("u_dots")
	_reply("Bake your normals with Cycles: select the low poly last, tick Selected to Active and nudge the extrusion until the lumps vanish.", "Haiku · 0.02p")
	await tree.create_timer(3.0).timeout
	snap.call("u_chat")
	_request_approval("Clean up junk? Up to 2340 MB can be freed. Untick anything you want to keep.", "Get-ChildItem $env:TEMP -Recurse | Remove-Item", [["a", "Your temp files: 1210 MB", true], ["b", "Browser caches: 860 MB", true], ["c", "Recycle Bin: 270 MB", false]])
	await tree.create_timer(0.5).timeout
	bubble.toggle_details()
	await tree.create_timer(2.5).timeout
	snap.call("u_approve")
	_answer_approval(false)
	await tree.create_timer(0.3).timeout
	_on_reminder_due({"text": "Check the render, it's been an hour."})
	await tree.create_timer(2.0).timeout
	snap.call("u_alert")
	bubble.hide_bubble()
	rico.alerting = false
	await tree.create_timer(0.5).timeout
	search.apps = [{"name": "Blender 4.2", "id": "x"}, {"name": "Godot Engine", "id": "z"}]
	await _open_search("ble")
	search._files = [{"name": "bullet_hero.blend", "path": "C:/Users/Pierre/Art/bullet_hero.blend", "size": 48234567.0, "modified": "2026-11-19 22:10", "folder": false},
		{"name": "Blender renders", "path": "C:/Users/Pierre/Pictures/Blender renders", "size": -1.0, "modified": "2026-11-12 18:40", "folder": true}]
	search._rebuild()
	search.move(1)
	await tree.create_timer(1.0).timeout
	snap.call("u_search")
	search.close()
	await tree.create_timer(1.0).timeout
	_refresh_projects_menu()
	_refresh_pc_menu()
	menu.position = Vector2i(900, 300)
	menu.popup()
	await tree.create_timer(0.6).timeout
	menu.get_texture().get_image().save_png(out.path_join("u_menu.png"))
	menu.hide()
	_open_settings(8)
	await tree.create_timer(1.0).timeout
	settings.get_texture().get_image().save_png(out.path_join("u_settings.png"))
	_open_settings(6)
	await tree.create_timer(1.0).timeout
	settings.get_texture().get_image().save_png(out.path_join("u_settings_pc.png"))
	tree.quit()


func _run_search_shot() -> void:
	var out := OS.get_environment("RICO_SHOT_SEARCH")
	Cfg.data.volume = 0.0
	Cfg.data.projects = [{"name": "Zuri", "path": "C:/Games/Zuri/project.godot"}]
	quick.rates = {"EUR": 1.0, "GBP": 0.85, "USD": 1.08}
	quick.rates_date = Time.get_date_string_from_system()
	search.apps = [{"name": "Blender 4.2", "id": "x"}, {"name": "Blender 3.6", "id": "y"}, {"name": "Godot Engine", "id": "z"}, {"name": "Bluetooth settings", "id": "w"}]
	var icon := ProjectSettings.globalize_path("res://assets/icon.png")
	rico.position.x = 400
	await _open_search("")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("s_empty.png"))
	search.set_query("ble")
	search._files = [{"name": "bullet_hero.blend", "path": "C:/Users/Pierre/Art/bullet_hero.blend", "size": 48234567.0, "modified": "2026-11-19 22:10", "folder": false},
		{"name": "blend_concepts.png", "path": icon, "size": 120345.0, "modified": "2026-11-18 09:02", "folder": false}]
	search._rebuild()
	search.move(4)
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("s_files.png"))
	search.set_query("50 usd in gbp")
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("s_answer.png"))
	search.close()
	await get_tree().create_timer(1.5).timeout
	_reply("Haiku answer goes here, short and smug.", "Haiku · 0.02p")
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(out.path_join("s_cost.png"))
	get_tree().quit()


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
	menu.theme = UI.theme()
	add_child(menu)
	timer_menu = PopupMenu.new()
	timer_menu.theme = UI.theme()
	for m in [5, 10, 15, 25, 45, 60]:
		timer_menu.add_item(UI.icon("clock") + "   %d minutes" % m, m)
	timer_menu.id_pressed.connect(func(id):
		reminders.add("Your %d minute timer's done." % id, id)
		_say("Timer set: %d minutes. Tick tock." % id, 4))
	projects_menu = PopupMenu.new()
	projects_menu.theme = UI.theme()
	projects_menu.id_pressed.connect(func(id):
		var list: Array = Cfg.g("projects")
		if id < list.size():
			_open_project(list[id]))
	menu.add_item(UI.icon("search") + "   Search          Alt+Space", 8)
	menu.add_item(UI.icon("chat") + "   Chat with Rico", 0)
	menu.add_item(UI.icon("mic") + "   Talk", 1)
	menu.add_separator()
	menu.add_submenu_node_item(UI.icon("clock") + "   Quick timer", timer_menu)
	menu.add_submenu_node_item(UI.icon("rocket") + "   Open project", projects_menu)
	pc_menu = PopupMenu.new()
	pc_menu.theme = UI.theme()
	pc_menu.id_pressed.connect(_on_pc_menu)
	menu.add_submenu_node_item(UI.icon("cpu") + "   PC", pc_menu)
	menu.add_item(UI.icon("bell") + "   Reminders", 2)
	menu.add_item(UI.icon("cube") + "   Print Shop", 10)
	menu.add_item(UI.icon("coin") + "   Money", 11)
	menu.add_separator()
	menu.add_item(UI.icon("settings") + "   Settings", 3)
	menu.add_item(UI.icon("history") + "   New conversation", 4)
	menu.add_item(UI.icon("desktop") + "   Forget my spot for this app", 7)
	menu.add_item(UI.icon("notes") + "   Take a nap", 5)
	menu.add_item(UI.icon("x") + "   Hide for 30 minutes", 6)
	menu.add_separator()
	menu.add_item(UI.icon("power") + "   Quit Rico", 9)
	menu.id_pressed.connect(_on_menu)
	menu.about_to_popup.connect(_refresh_projects_menu)
	menu.about_to_popup.connect(_refresh_pc_menu)


func _refresh_pc_menu() -> void:
	pc_menu.clear()
	pc_menu.add_item(UI.icon("activity") + "   What's slowing me down?", 0)
	pc_menu.add_item(UI.icon("trash") + "   Clean up junk", 1)
	var perf_on: bool = Cfg.g("perf_state", {}).get("on", false)
	pc_menu.add_item(UI.icon("rocket") + ("   Game/Render mode: turn off" if perf_on else "   Game/Render mode: turn on"), 2)
	pc_menu.add_item(UI.icon("shield") + "   Health check", 3)
	pc_menu.add_item(UI.icon("power") + "   Startup apps", 4)
	if not Cfg.g("last_undo", {}).is_empty():
		pc_menu.add_item(UI.icon("history") + "   Undo last %s" % Cfg.g("last_undo").label, 5)
	pc_menu.add_item(UI.icon("notes") + "   Activity log", 6)
	var routines: Array = Cfg.g("routines", [])
	if not routines.is_empty():
		pc_menu.add_separator("Routines")
		for i in routines.size():
			pc_menu.add_item(UI.icon("play") + "   " + String(routines[i].name), 100 + i)
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
		8: _open_search()
		9: _quit()
		10: _open_shop()
		11: _open_money()


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
	if tab == 6:
		settings.refresh_startup()
	settings.refresh_games()
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
	if rico.docked or _ghost > 0:
		_wake_up()
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
	if not ai.has_key() and not brain.enabled():
		bubble.open_chat(_no_brain_line())
	elif bubble.is_open() and bubble.chat_mode:
		bubble.open_chat()
	else:
		bubble.open_chat(Lines.pick(["What now?", "Go on then. Ask.", "Rico's listening. Mostly.", "Yes? Make it interesting."]))


func _on_submitted(text: String) -> void:
	_last_was_voice = false
	_handle_request(text)


const HANDLED := "\u0001"


## The token-saving router: local command -> answer cache -> offline brain or Claude.
func _handle_request(text: String) -> void:
	voice.stop_speaking()
	if ai.busy or brain.busy:
		return
	# 1. things Rico can just do (free)
	var local: String = await _local_command(text)
	if local == HANDLED:
		mem.count("local")
		return
	if local != "":
		mem.count("local")
		ai.note_exchange(text, local)
		_reply(local, "Done locally · free")
		return
	# 2. asked before? (free)
	var cached: String = mem.cache_get(text)
	if cached != "":
		mem.count("cache")
		ai.note_exchange(text, cached)
		_reply(cached, "From memory · free")
		return
	# 3. pick a brain
	var capped: bool = float(Cfg.g("daily_cap_gbp", 0.0)) > 0.0 and mem.today_gbp() >= float(Cfg.g("daily_cap_gbp", 0.0))
	var claude_ok: bool = ai.has_key() and not capped
	var wants_claude: bool = ai.needs_tools(text) or ai.is_hard(text) or _wants_claude(text)
	if claude_ok and (wants_claude or not brain.enabled()):
		rico.thinking = true
		_say("...", -1, true)
		ai.ask(text)
		if not brain.installed() and not brain.downloading and not Cfg.g("brain_offered", false) and not wants_claude:
			Cfg.s("brain_offered", true)
			_offer_brain_later = true
		return
	if brain.enabled():
		rico.thinking = true
		_say("...", -1, true)
		_brain_question = text
		brain.chat(_brain_messages(text))
		return
	if capped:
		_say("I've hit today's Claude budget (%s). Raise it in Settings > Usage, or get my offline brain there." % MemScript.fmt_gbp(float(Cfg.g("daily_cap_gbp"))), -1, true)
	elif brain.downloading:
		_say("Still downloading my offline brain (%d%%). Give me a minute." % brain.download_percent(), -1, true)
	else:
		_say(_no_brain_line(), -1, true, [["brain_dl", "Download my brain"]] if Cfg.g("local_only", true) and not brain.installed() else [])


func _no_brain_line() -> String:
	if Cfg.g("local_only", true):
		if brain.downloading:
			return "My brain's still downloading (%d%%). Meanwhile I can do timers, search, maths, PC jobs, prices and money stuff." % brain.download_percent()
		return "I'm in Local-only mode, so my brain lives on your PC and needs a one-off 2 GB download. Until then I still do timers, search, maths, PC jobs, prices and money stuff."
	return Lines.NO_KEY


var _offer_brain_later := false
var _brain_question := ""


## Questions the small offline model would likely fumble.
func _wants_claude(text: String) -> bool:
	var t := text.to_lower()
	if text.length() > 140:
		return true
	for k in ["godot", "blender", "unity", "unreal", "code", "script", "how do i", "how to", "how can i", "why ", "explain", "write ", "draft", "email", "plan ", "recommend", "design", "error", "bug", "fix", "help me", "steps", "tutorial", "translate", "summar", "difference between", "what's the best", "which is better", "?"]:
		if k in t and not (k == "?" and text.length() < 40):
			return true
	return false


func _brain_messages(text: String) -> Array:
	var sys := "You are Rico, a tiny holographic brass bullet who lives on Pierre's Windows desktop. Pierre games, illustrates, designs games (Godot, Blender), does UX/UI design (Figma) and 3D prints on a Bambu Lab H2D. You are cheeky, sarcastic and funny with British humour, but warm and genuinely helpful: open with a quick quip, then give practical, specific help. Keep it to 1-3 short sentences unless he asks for steps; plain text, no emoji. You run fully offline, so you cannot browse or check the latest patches. If you're not sure of a game-specific detail, say so honestly with a joke instead of making something up. For spoilers, hint first."
	if games.current() != "":
		sys += " He's currently playing %s." % games.current()
	var facts: Array = mem.relevant(text, 4)
	if not facts.is_empty():
		sys += " Things you know: " + "; ".join(facts) + "."
	var msgs := [{"role": "system", "content": sys}]
	for h in ai.history.slice(-4):
		msgs.append({"role": h.role, "content": String(h.content)})
	msgs.append({"role": "user", "content": text})
	return msgs


func _on_brain_reply(text: String) -> void:
	rico.thinking = false
	mem.count("mini")
	ai.note_exchange(_brain_question, text)
	mem.cache_put(_brain_question, text, "mini")
	_reply(text, "Offline brain · free")


func _on_brain_failed(msg: String) -> void:
	rico.thinking = false
	if ai.has_key() and _brain_question != "":
		_say("...", -1, true)
		ai.ask(_brain_question)   # fall back to Claude
		return
	_say("Ugh. " + msg, -1, true)


func _reply(text: String, meta := "") -> void:
	rico.thinking = false
	_say(text, -1, true)
	bubble.set_meta_text(meta)
	var mode := int(Cfg.g("speak_replies", 1))
	if mode == 2 or (mode == 1 and _last_was_voice):
		voice.speak(text)


func _on_ai_reply(text: String, meta: Dictionary) -> void:
	var name := "Sonnet" if "sonnet" in String(meta.get("model", "")) else "Haiku"
	if not meta.get("tools", false):
		mem.cache_put(ai._question, text, name)
	_reply(text, "%s · %s" % [name, MemScript.fmt_gbp(float(meta.get("cost", 0.0)))])
	if _offer_brain_later:
		_offer_brain_later = false
		await get_tree().create_timer(6.0).timeout
		if not bubble.is_busy_with_user():
			_say("Psst: small talk like that could be free. Want my offline brain? It's a one-off 2 GB download and runs on your PC.", -1, false, [["brain_dl", "Download"], ["dismiss", "Not now"]])


func _on_ai_failed(msg: String, details: String) -> void:
	rico.thinking = false
	rico.set_mood("annoyed", 3)
	if brain.enabled() and ai._question != "" and not "key" in msg:
		_brain_question = ai._question
		brain.chat(_brain_messages(ai._question))
		return
	var keep: bool = bubble.chat_mode
	bubble.say("Ugh. " + msg, -1, [["details", "Show details"]], details)
	bubble.chat_mode = keep
	bubble.input_row.visible = keep
	sfx.play("pop")
	settings.set_status(msg)


func _test_api() -> void:
	if not ai.has_key():
		settings.set_status("Paste a key first.")
		return
	settings.set_status("Testing...")
	var once := func(t, _m): settings.set_status("Works! Rico says: " + t)
	ai.reply.connect(once, CONNECT_ONE_SHOT)
	_say("...", -1, true)
	ai.ask("Say a one-line hello to prove you're connected.")


func _start_brain_download() -> void:
	if not FileAccess.file_exists(brain.server_path()):
		_say("My offline brain files are missing from the Rico folder (brain\\). Re-unzip Rico.", 6)
		return
	brain.download()
	_say("Downloading my offline brain (2 GB). I'll keep chatting through Claude meanwhile.", 6)


const PC_TOOLS := ["get_top_processes", "scan_junk", "list_startup_apps", "list_power_plans", "system_health", "find_files",
	"get_activity_log", "close_apps", "clean_junk", "set_startup_app", "set_power_plan", "performance_mode", "tidy_folder",
	"rename_files", "undo_last_file_change", "recycle_files", "run_powershell", "save_routine", "run_routine", "open_app_or_file"]


func _run_tool(name: String, input: Dictionary) -> String:
	if name in PC_TOOLS:
		if not pc.enabled():
			return "PC tools are switched off (Settings > PC) or this isn't Windows."
		return await _run_pc_tool(name, input)
	match name:
		"game_checklist_set":
			return games.set_list(String(input.get("game", games.current())), String(input.get("title", "Checklist")), input.get("items", []))
		"game_checklist_tick":
			var tr: String = games.tick(String(input.get("game", games.current())), String(input.get("item", "")), bool(input.get("done", true)))
			return tr if tr != "" else "No matching checklist item."
		"game_checklist_show":
			return games.show(String(input.get("game", games.current())))
		"remember_fact":
			mem.add_fact(String(input.get("fact", "")))
			return "Saved to local memory."
		"forget_fact":
			return "Removed %d facts." % mem.forget(String(input.get("about", "")))
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


func _cap1(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1) if t != "" else t


## Everyday requests handled entirely offline (no AI). Returns "" if not recognised,
## a reply to show, or HANDLED when a flow already drove the bubble.
func _local_command(text: String) -> String:
	var t := text.to_lower().strip_edges().trim_suffix(".").trim_suffix("!").trim_suffix("?").strip_edges()
	var re := RegEx.new()
	# greetings and thanks
	if t in ["hi", "hello", "hey", "hiya", "yo", "morning", "good morning", "evening", "sup", "alright", "you there"]:
		return Lines.pick(["Hello. What do you want?", "Hi. I was busy doing nothing. What's up?", "Yo. Rico at your service, grudgingly."])
	if t in ["thanks", "thank you", "cheers", "ta", "nice", "great", "cool", "ok", "okay", "lol", "haha", "nice one"]:
		return Lines.pick(["You're welcome. Obviously.", "Any time. Well, most times.", "I know, I'm brilliant."])
	# timers + reminders
	re.compile("(\\d+(?:\\.\\d+)?)\\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)\\b(?:\\s*(?:to|about|that)\\s+(.+))?")
	if "remind" in t or "timer" in t:
		var m := re.search(t)
		if m:
			var n := float(m.get_string(1))
			var unit := m.get_string(2)
			var mins := n / 60.0 if unit.begins_with("s") else (n * 60.0 if unit.begins_with("h") else n)
			var what := _cap1(m.get_string(3).strip_edges())
			var r: Dictionary = reminders.add(what if what != "" else "Time's up.", mins)
			return "Done. " + reminders.describe(r)
		var at := RegEx.new()
		at.compile("(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?(?:\\s*(?:to|about)\\s+(.+))?")
		var a := at.search(t.substr(t.find(" at ")) if " at " in t else "")
		if a:
			var h := int(a.get_string(1))
			if a.get_string(3) == "pm" and h < 12: h += 12
			if a.get_string(3) == "am" and h == 12: h = 0
			var r2: Dictionary = reminders.add_at(_cap1(a.get_string(4).strip_edges()) if a.get_string(4) != "" else "Reminder", "%d:%s" % [h, a.get_string(2) if a.get_string(2) != "" else "00"])
			return "Done. " + reminders.describe(r2)
	if t in ["reminders", "my reminders", "list reminders", "what reminders do i have", "what reminders have i got", "show reminders"]:
		var out := []
		for r in reminders.pending():
			out.append(reminders.describe(r))
		return "Nothing pending. Living dangerously." if out.is_empty() else "\n".join(out)
	# memory
	re.compile("^(?:please )?remember (?:that )?(.+)$")
	var mm := re.search(t)
	if mm:
		mem.add_fact(_cap1(text.strip_edges().substr(text.to_lower().find(mm.get_string(1)))))
		return Lines.pick(["Noted. Filed under 'things Pierre thinks are important'.", "Got it. Stored locally, no cloud nonsense.", "Remembered. Unlike your last save."])
	re.compile("^forget (?:about |that )?(.+)$")
	mm = re.search(t)
	if mm:
		var n2: int = mem.forget(mm.get_string(1))
		return "Forgotten (%d note%s). Blissful ignorance." % [n2, "" if n2 == 1 else "s"] if n2 > 0 else "I didn't have anything about that anyway."
	if t in ["what do you know about me", "what do you remember", "what have you remembered", "show memory", "your memory"]:
		if mem.facts.is_empty():
			return "Nothing yet. Tell me things with \"remember that...\"."
		return "Here's what I've got:\n" + "\n".join(mem.facts.map(func(f): return String(f.t)).slice(-8))
	# quick answers (maths, units, currency)
	var qa: Dictionary = quick.answer(text)
	if not qa.is_empty() and String(qa.copy) != "":
		return String(qa.title).trim_prefix("= ")
	# search
	re.compile("^(?:search|find|look for|spotlight)(?: for)? (.+)$")
	mm = re.search(t)
	if mm and not ai.needs_tools(t) and not ("model" in t or "stl" in t or "to print" in t):
		_open_search(mm.get_string(1))
		return HANDLED
	# open projects or apps
	re.compile("^(?:open|launch|start|run) (.+)$")
	mm = re.search(t)
	if mm and not " routine" in t and not "mode" in t:
		var what3 := mm.get_string(1).trim_prefix("up ").trim_prefix("my ")
		var p := _find_project(what3)
		if not p.is_empty():
			_open_project(p)
			return HANDLED
		var best := {}
		var best_s := 0.0
		for app in search.apps:
			var sc: float = search.score(String(app.name), what3)
			if sc > best_s:
				best_s = sc
				best = app
		if best_s >= 75.0:
			OS.create_process("explorer.exe", ["shell:AppsFolder\\" + String(best.id)])
			return "Opening %s." % best.name
	# routines
	re.compile("^(?:run|start|do)(?: the| my)? (.+?)(?: routine)?$")
	mm = re.search(t)
	if mm and pc.enabled():
		for r in Cfg.g("routines", []):
			if String(r.name).to_lower() == mm.get_string(1).strip_edges():
				_pc_busy_say("Running %s..." % r.name)
				_say(await pc.run_routine(String(r.name), true), 6)
				return HANDLED
	# PC actions with fixed flows
	if pc.enabled():
		if t in ["game mode on", "render mode on", "performance mode on", "game mode", "render mode", "turn on game mode", "turn on render mode", "start game mode", "start render mode"]:
			if Cfg.g("perf_state", {}).get("on", false):
				_say("Game/Render mode is already on.", 4)
			else:
				_on_pc_menu(2)
			return HANDLED
		if t in ["game mode off", "render mode off", "performance mode off", "turn off game mode", "turn off render mode", "stop game mode", "stop render mode"]:
			if Cfg.g("perf_state", {}).get("on", false):
				_on_pc_menu(2)
			else:
				_say("Game/Render mode isn't on.", 4)
			return HANDLED
		re.compile("^(clean|clear)( up)?( my)? (junk|temp files|pc|computer|laptop)$|^free up (some )?(disk )?space$|^clean up$")
		if re.search(t):
			_on_pc_menu(1)
			return HANDLED
		re.compile("^(why is|why's|is) (my |the )?(pc|computer|laptop|it|everything) (so |really |running )?(slow|laggy|sluggish)|(what'?s|what is) (slowing|hogging|using|eating) (me|my|the)|^(my )?(pc|computer|laptop) (is|feels) (so |really )?(slow|laggy)")
		if re.search(t):
			_flow_slow()
			return HANDLED
		re.compile("^(run a |do a |give me a )?(health check|check ?up|pc health)$|^(check|how'?s|how is) (on )?my (pc|computer|laptop)( doing)?$")
		if re.search(t):
			_flow_health(false)
			return HANDLED
		if t in ["undo", "undo that", "undo last"]:
			_say(await pc.undo_last(), 5)
			return HANDLED
		re.compile("^(?:tidy|organise|organize|sort)(?: up)?(?: my)? (downloads|desktop|documents|pictures|videos|music)(?: folder)?(?: by (type|month))?$")
		mm = re.search(t)
		if mm:
			_pc_busy_say("Looking at your %s..." % mm.get_string(1))
			_say(await pc.tidy(mm.get_string(1), mm.get_string(2) if mm.get_string(2) != "" else "type"), 6)
			return HANDLED
	# games
	re.compile("^(?:i'm|im|i am) (?:now )?playing (.+)$")
	mm = re.search(t)
	if mm:
		games.override = text.strip_edges().substr(text.to_lower().find(mm.get_string(1))).trim_suffix(".")
		ai.game = games.current()
		return Lines.pick(Lines.GAME_SET) % games.override
	if t in ["i'm not playing anything", "stop playing", "not playing", "done gaming", "finished playing"]:
		games.override = ""
		ai.game = games.current()
		return "Back to work then. Probably."
	if games.current() != "":
		re.compile("^(?:i )?(?:got|found|collected|done|finished|completed) (?:the )?(.+)$")
		mm = re.search(t)
		if mm:
			var r: String = games.tick(games.current(), mm.get_string(1))
			if r != "":
				return Lines.pick(["Nice. ", "Look at you go. ", "One down. "]) + r
		if t in ["what's left", "whats left", "what is left", "checklist", "show checklist", "what collectibles are left", "what have i got left"]:
			return games.show(games.current())
		if t in ["tip", "game tip", "give me a tip", "any tips"]:
			var tip: String = games.next_tip(games.current())
			if tip != "":
				return tip
	# ---- 3D printing
	if t in ["print shop", "open print shop", "printshop", "quote", "pricing"]:
		_open_shop()
		return HANDLED
	if t in ["how's my print", "hows my print", "how is my print", "print status", "printer status", "is my print done", "how long left on my print", "how long's left"]:
		return bambu.status_text()
	if "maintenance" in t and ("printer" in t or "due" in t or t == "maintenance"):
		_open_shop()
		shop_win.tabs.current_tab = 6
		return "Opened your printer's maintenance list. Anything glowing gold is overdue."
	re.compile("^(?:find|search for|look for|get me)(?: me)? (?:a |an |some )?(?:3d )?(?:printable )?(?:models?|stls?|prints?)(?: of| for)? (.+)$")
	mm = re.search(t)
	if not mm:
		re.compile("^(?:find|search for)(?: me)? (?:a |an )?(.+?) (?:model|stl|to print|3d model)s?$")
		mm = re.search(t)
	if mm:
		for u in PrintHelp.model_search_urls(mm.get_string(1)):
			OS.shell_open(u)
		return "Opened MakerWorld, Printables and Thingiverse searches for \"%s\" in your browser. Pick a good one and drop the 3MF on me for a price." % mm.get_string(1)
	var diag: String = PrintHelp.diagnose(t)
	if diag != "":
		return diag
	re.compile("(?:price|quote|charge|sell).*?(\\d+(?:\\.\\d+)?)\\s*g(?:rams?)?(?: of)?\\s*([a-z ]*?)\\s*(?:,|and|for|at)?\\s*(\\d+(?:\\.\\d+)?)\\s*(h|hr|hrs|hours?|m|mins?|minutes?)\\b")
	mm = re.search(t)
	if mm:
		var grams := float(mm.get_string(1))
		var mat := mm.get_string(2).strip_edges()
		if mat == "": mat = "PLA"
		var hrs := float(mm.get_string(3)) / (60.0 if mm.get_string(4).begins_with("m") else 1.0)
		_open_shop()
		await shop_win.set_manual(mat, grams, hrs)
		var q: Dictionary = shop.quote(shop_win._job())
		return Lines.pick(["Pricing gun loaded. ", "Right then. ", "Let's make some money. "]) + shop.text_summary(q)
	# ---- money (all local)
	if t in ["money", "open money", "finances", "my finances", "budget window"]:
		_open_money()
		return HANDLED
	re.compile("^(?:i )?(?:spent|paid|bought .* for) £?(\\d+(?:\\.\\d{1,2})?)(?: quid| pounds)?(?: on| for| at)? ?(.*)$")
	mm = re.search(t)
	if mm:
		var amt := float(mm.get_string(1))
		var what := mm.get_string(2).strip_edges()
		var tx: Dictionary = money.add(_cap1(what) if what != "" else "Spending", -amt)
		var left: String = money.category_left(tx.cat)
		return Lines.pick(["Logged. ", "Noted, big spender. ", "Into the ledger it goes. "]) + "£%.2f on %s (%s). %s" % [amt, what if what != "" else "something", tx.cat, left]
	re.compile("^(?:i )?sold (?:a |an |the |my )?(.+?) for £?(\\d+(?:\\.\\d{1,2})?)(?: on (.+))?$")
	mm = re.search(t)
	if mm:
		var amt2 := float(mm.get_string(2))
		money.add("Sold: " + _cap1(mm.get_string(1)) + ((" (" + mm.get_string(3) + ")") if mm.get_string(3) != "" else ""), amt2, "", "Income", "shop")
		return Lines.pick(["Ka-ching! ", "Business is booming. ", "Look at you, entrepreneur. "]) + "Logged £%.2f income for %s." % [amt2, mm.get_string(1)]
	re.compile("^(?:i )?(?:got paid|earned|received) £?(\\d+(?:\\.\\d{1,2})?)(?: (?:for|from) (.+))?$")
	mm = re.search(t)
	if mm:
		money.add(_cap1(mm.get_string(2)) if mm.get_string(2) != "" else "Income", float(mm.get_string(1)), "", "Income")
		return "Logged £%.2f coming in. Don't spend it all on filament." % float(mm.get_string(1))
	if t in ["budget", "my budget", "how's my budget", "hows my budget", "how much have i spent", "how much have i spent this month", "spending", "how am i doing for money", "money check"]:
		return money.month_summary() + "\n" + Lines.pick(["Proud of you. Mostly.", "Your wallet says hi. Weakly.", "Not bad. I've seen worse. I've also seen better."])
	re.compile("^how much (?:is |have i got |do i have )?left (?:for|in|on) (.+)$")
	mm = re.search(t)
	if mm:
		var cat: String = money.find_category(mm.get_string(1))
		return money.category_left(cat) if cat != "" else "I don't have a category called that. Check Money > Budget."
	if t in ["bills", "bills this week", "what bills are due", "upcoming bills", "bills due"]:
		var due: Array = money.due_within(7)
		if due.is_empty():
			return "Nothing due in the next week. Enjoy it while it lasts."
		return "Due this week:\n" + "\n".join(due.map(func(b): return "%s £%.2f on %s" % [b.name, float(b.amount), money.next_due(b)]))
	if t in ["subscriptions", "my subscriptions", "what am i subscribed to", "how much do i spend on subscriptions"]:
		var subs: Array = money.data.bills.filter(func(b): return b.cat == "Subscriptions")
		if subs.is_empty():
			var found: Array = money.detect_subscriptions()
			return "None tracked yet. %s" % ("I spotted %d regular payments in your statements: see Money > Bills." % found.size() if not found.is_empty() else "Add them in Money > Bills or import a bank CSV.")
		var tot: float = money.subscriptions_total()
		var roast := ""
		var streams := subs.filter(func(b): return ["netflix", "disney", "prime", "now tv", "paramount", "apple tv", "youtube"].any(func(k): return k in String(b.name).to_lower())).size()
		if streams >= 3:
			roast = " Also, %d streaming services? You have one pair of eyes." % streams
		return "%d subscriptions, £%.2f a month (£%.0f a year).%s" % [subs.size(), tot, tot * 12, roast]
	re.compile("^add (?:a )?(?:bill|subscription) (.+?) £?(\\d+(?:\\.\\d{1,2})?)(?: on the (\\d{1,2})(?:st|nd|rd|th)?)?$")
	mm = re.search(t)
	if mm:
		var sub := "subscription" in t
		money.add_bill(_cap1(mm.get_string(1)), float(mm.get_string(2)), int(mm.get_string(3)) if mm.get_string(3) != "" else 1, "Subscriptions" if sub else "Bills")
		return "Added. I'll nudge you the day before it's due."
	# Rico himself
	if t in ["hide", "go away", "hide rico", "shoo"]:
		_hide_for(30 * 60)
		return HANDLED
	if t in ["sleep", "nap", "take a nap", "go to sleep"]:
		bubble.hide_bubble()
		rico.sleep()
		return HANDLED
	if t in ["settings", "open settings"]:
		_open_settings(0)
		return HANDLED
	if t in ["usage", "how much have you cost", "how much have i spent", "spending", "cost today"]:
		return "Today: %s on Claude. This month: %s. Saved by doing things locally: %d times." % [MemScript.fmt_gbp(mem.today_gbp()), MemScript.fmt_gbp(float(mem.month_stats().usd) * mem.usd_to_gbp), int(mem.month_stats().local) + int(mem.month_stats().cache) + int(mem.month_stats().mini)]
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
		4: _open_settings(6)
		5: _say(await pc.undo_last(), 5)
		6: _open_settings(7)
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
	_remember_pc(r)
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


# ------------------------------------------------------------------ search bar (Rico perches on it)

func _open_search(prefill := "") -> void:
	_show()
	rico.wake()
	bubble.hide_bubble()
	DisplayServer.window_move_to_foreground()
	search.open(prefill)
	await get_tree().process_frame
	_place_search()
	if _pre_search_x < 0:
		_pre_search_x = rico.position.x
	var top: Vector2 = search.position
	var h: Vector2 = rico.half_extents()
	rico.state = RicoScript.State.IDLE
	rico.bounds = Rect2(area.position, Vector2(area.size.x, top.y + 6))
	rico.position = Vector2(top.x + search.panel.size.x - 70, top.y + 6 - h.y)
	rico.rotation = 0
	rico.sq = 1.25
	rico.set_mood("smug", 999)
	sfx.play("pop", 1.2)
	for i in 8:
		sparks.append({"p": rico.position + Vector2(randf_range(-30, 30), h.y), "v": Vector2(randf_range(-200, 200), randf_range(-300, -80)), "life": 0.35, "max": 0.35})


func _place_search() -> void:
	search.reset_size()
	search.position = Vector2(round(area.get_center().x - search.WIDTH * 0.5), round(area.size.y * 0.24))


func _on_search_closed() -> void:
	rico.bounds = area
	rico.state = RicoScript.State.FLY
	rico.vel = Vector2(randf_range(-80, 80), -200)
	rico.set_mood("shock", 0.6)
	_return_after_land = true
	_voice_for_search = false
	if voice.recording:
		voice.stop()


var _return_after_land := false


func _search_rico_items() -> Array:
	var items := []
	var perf_on: bool = Cfg.g("perf_state", {}).get("on", false)
	items.append({"title": "Chat with Rico", "subtitle": "Rico", "id": "chat", "keywords": "talk ask ai"})
	if pc.enabled():
		items.append({"title": "What's slowing me down?", "subtitle": "PC", "id": "pc:0", "keywords": "slow cpu ram hog performance task manager"})
		items.append({"title": "Clean up junk", "subtitle": "PC", "id": "pc:1", "keywords": "temp cache space disk free recycle"})
		items.append({"title": "Game/Render mode: " + ("turn off" if perf_on else "turn on"), "subtitle": "PC", "id": "pc:2", "keywords": "performance fps boost power"})
		items.append({"title": "Health check", "subtitle": "PC", "id": "pc:3", "keywords": "temps temperature updates disk drivers check up"})
		items.append({"title": "Startup apps", "subtitle": "PC", "id": "pc:4", "keywords": "boot launch windows start"})
		items.append({"title": "Activity log", "subtitle": "PC", "id": "pc:6", "keywords": "history what did rico do"})
		for i in Cfg.g("routines", []).size():
			items.append({"title": "Run routine: " + String(Cfg.g("routines")[i].name), "subtitle": "Routine", "id": "pc:%d" % (100 + i), "keywords": "routine"})
	for i in Cfg.g("projects", []).size():
		items.append({"title": String(Cfg.g("projects")[i].name), "subtitle": "Project · " + String(Cfg.g("projects")[i].path), "id": "proj:%d" % i, "keywords": "project open"})
	var tabs := ["Chat", "Voice", "Reminders", "Projects", "Rico", "Games", "PC", "Activity", "Usage", "Help"]
	for i in tabs.size():
		items.append({"title": "Settings: " + tabs[i], "subtitle": "Rico settings", "id": "set:%d" % i, "keywords": "settings preferences options"})
	items.append({"title": "Reminders", "subtitle": "%d pending" % reminders.pending().size(), "id": "set:2", "keywords": "timer alarm remind"})
	items.append({"title": "Hide Rico for 30 minutes", "subtitle": "Rico", "id": "hide", "keywords": "hide away"})
	items.append({"title": "Print Shop", "subtitle": "Quotes, products, shipping, printer", "id": "shop", "keywords": "3d print price quote sell etsy filament bambu h2d"})
	items.append({"title": "Money", "subtitle": "Budget, bills, subscriptions (stays on this PC)", "id": "money", "keywords": "budget spend bank finance bills subscriptions"})
	items.append({"title": "Printer status", "subtitle": "Your Bambu H2D", "id": "printer", "keywords": "print progress h2d bambu"})
	return items


func _on_search_ask(t: String) -> void:
	_show()
	bubble.chat_mode = true
	bubble.input_row.visible = true
	_last_was_voice = false
	_handle_request(t)


func _on_search_action(id: String) -> void:
	if id == "shop":
		_open_shop()
	elif id == "money":
		_open_money()
	elif id == "printer":
		_reply(bambu.status_text(), "Local · free")
	elif id == "chat":
		_open_chat()
	elif id == "hide":
		_hide_for(30 * 60)
	elif id.begins_with("pc:"):
		_on_pc_menu(int(id.substr(3)))
	elif id.begins_with("set:"):
		_open_settings(int(id.substr(4)))
	elif id.begins_with("proj:"):
		var list: Array = Cfg.g("projects")
		var i := int(id.substr(5))
		if i < list.size():
			_open_project(list[i])


func _on_brain_downloaded(ok: bool) -> void:
	settings.set_brain_status("")
	if ok:
		_say("Offline brain installed. Small talk and simple questions are free from now on.", 6)
		sfx.play("pop")
	else:
		_say("The offline brain download failed. Try again from Settings > Usage.", 6)


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
		_: if bubble.is_open(): bubble.text_label.text = "Downloading my ears... %s%%" % p


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
	if _voice_for_search and search.is_open():
		_voice_for_search = false
		bubble.hide_bubble()
		search.set_query(text)
		return
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
	_say(text, -1, false, [["done", "Done"], ["snooze5", "5 min"], ["snooze15", "15 min"]])
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
	if id.begins_with("wel"):
		match id:
			"wel_skip":
				Cfg.s("welcomed", true)
				bubble.hide_bubble()
			"wel_key":
				_open_settings(0)
				_welcome(3)
			"wel_brain":
				_start_brain_download()
				await get_tree().create_timer(3.0).timeout
				_welcome(5)
			_:
				_welcome(int(id.substr(3)))
		return
	if id == "brain_dl":
		_start_brain_download()
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
			if bubble.is_open() and bubble.chat_mode and get_window().visible:
				bubble.hide_bubble()
			else:
				_open_chat()
		"voice":
			if not bubble.chat_mode:
				bubble.chat_mode = true
			_toggle_voice()
		"toggle":
			_toggle_visible()
		"search":
			if search.is_open():
				search.close()
			else:
				_open_search()


func _on_foreground(title: String) -> void:
	_fg_title = title
	ai.foreground_app = title
	var kind: String = Lines.app_kind(title)
	if kind != _fg_kind:
		_fg_kind = kind
		_kind_time = 0.0


# ------------------------------------------------------------------ dodging + per-app spots

func _remember_pc(r: Dictionary) -> void:
	var gpus := []
	for g in r.get("gpus", []):
		gpus.append(String(g.name))
	var disks := []
	for d in r.get("drives", []):
		disks.append("%s %s GB" % [d.drive, d.size_gb])
	mem.add_fact("PC: %s, %s; %s GB RAM; GPU %s; drives %s" % [r.get("windows", "Windows"), r.get("cpu", "?"), r.get("ram_total_gb", "?"), ", ".join(gpus), ", ".join(disks)], "pc")


# ------------------------------------------------------------------ staying out of the way

func _wake_up() -> void:
	_activity_t = 0.0
	_ghost = 0.0
	if rico.docked:
		_undock()
	rico.wake()


func _dock() -> void:
	if rico.docked:
		return
	bubble.hide_bubble()
	rico.docked = true
	rico.state = RicoScript.State.IDLE
	rico.rotation = 0
	rico.position = Vector2(area.end.x - 40, area.end.y - 14)
	sfx.play("stop", 1.3, 0.5)


func _undock() -> void:
	if not rico.docked:
		return
	rico.docked = false
	var x: float = rico.home_x if rico.home_x >= 0 else area.end.x - 90
	if _covered(x):
		x = _free_x()
	rico.position = Vector2(x, area.end.y - rico.half_extents().y)
	rico.state = RicoScript.State.IDLE
	rico.sq = 1.3
	_presence = 0.5
	sfx.play("start", 1.2, 0.5)


func _no_space() -> bool:
	if not Cfg.g("dodge", true) or _fg_rect.size.x <= 0:
		return false
	var pad: float = rico.half_extents().x + 10.0
	return _covered(area.position.x + pad) and _covered(area.end.x - pad) and _fg_rect.position.x <= area.position.x + pad * 2 and _fg_rect.end.x >= area.end.x - pad * 2


var _shot_mode := false


func _update_presence(delta: float, mouse: Vector2) -> void:
	if _shot_mode:
		return
	var busy: bool = bubble.is_open() or search.is_open() or rico.talking or rico.listening or rico.thinking or _approval_pending \
		or rico.state in [RicoScript.State.DRAG, RicoScript.State.FLY, RicoScript.State.HOP] or _pressing or rico.alerting
	if busy:
		_activity_t = 0.0
	else:
		_activity_t += delta
	if busy and rico.docked:
		_undock()
	elif not busy and not rico.docked and rico.state in [RicoScript.State.IDLE, RicoScript.State.SLEEP] and (_activity_t > 90.0 or (_no_space() and _activity_t > 3.0)):
		_dock()
	# smaller when idle
	var target := 1.0 if (busy or _activity_t < 20.0) else 0.62
	_presence = move_toward(_presence, target, delta * 1.5)
	var sc: float = Cfg.size_scale() * _presence
	if absf(rico.scale.x - sc) > 0.004:
		rico.scale = Vector2.ONE * sc
		if rico.state == RicoScript.State.IDLE and not rico.docked:
			rico.position.y = rico.bounds.end.y - rico.half_extents().y
	# fade away when the cursor comes near; hover still for a moment to bring him back
	var near: bool = not busy and not rico.docked and rico.visual_rect(10.0).grow(60.0).has_point(mouse)
	if near:
		if mouse.distance_to(_mouse_prev) < 1.5:
			_hover_still += delta
		else:
			_hover_still = 0.0
	else:
		_hover_still = 0.0
	var ghost_target := 1.0 if (near and _hover_still < 0.8) else 0.0
	_ghost = move_toward(_ghost, ghost_target, delta * (5.0 if ghost_target > _ghost else 3.0))
	rico.modulate.a = 1.0 - _ghost


func _check_fullscreen(r: Rect2i) -> void:
	if r.size.x <= 0:
		_set_fs_hidden(false)
		return
	var scr := DisplayServer.window_get_current_screen()
	var sp := DisplayServer.screen_get_position(scr)
	var ss := DisplayServer.screen_get_size(scr)
	var full := r.position.x <= sp.x + 1 and r.position.y <= sp.y + 1 and r.end.x >= sp.x + ss.x - 1 and r.end.y >= sp.y + ss.y - 1
	_set_fs_hidden(full)


func _set_fs_hidden(on: bool) -> void:
	if on == _fs_hidden:
		return
	_fs_hidden = on
	if on:
		if get_window().visible:
			bubble.hide_bubble()
			get_window().visible = false
	else:
		if _hidden_until < 0 and not get_window().visible:
			get_window().visible = true
			get_window().always_on_top = true
			_update_region(true)
		for t in _fs_queue:
			_say(t, 12)
		_fs_queue.clear()


# ------------------------------------------------------------------ print shop, money, printer

func _open_shop() -> void:
	shop_win.refresh_products()
	shop_win.popup_centered()
	shop_win.grab_focus()


func _open_money() -> void:
	money_win.popup_centered()
	money_win.grab_focus()
	money_win._on_tab(money_win.tabs.current_tab)


func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty():
		return
	var f: String = files[0]
	var ext := f.get_extension().to_lower()
	_show()
	_wake_up()
	if ext in ["3mf", "gcode", "gco", "bgcode"]:
		_open_shop()
		var r: Dictionary = await shop_win.load_file(f)
		if r.get("ok", false):
			var q: Dictionary = shop.quote(shop_win._job())
			_reply(Lines.pick(["Ooh, a print job. ", "Right, let's put a price on it. ", "Pricing gun loaded. "]) + shop.text_summary(q), "Local · free")
		else:
			_say(String(r.get("note", "I couldn't read that file.")), 7)
	elif ext == "csv":
		_open_money()
		var r2: Dictionary = money_win.import_file(f)
		_say(("Imported %d transactions. Want the damage report? Say \"budget\"." % r2.added) if r2.ok else String(r2.note), 8)
	elif ext in ["png", "jpg", "jpeg", "webp"]:
		_say("I can't look at pictures in Local-only mode. Describe it instead (\"it's stringy\", \"corners lifted\") and I'll diagnose it.", 8)
	else:
		_say("Not sure what to do with a .%s file. Drop .3mf/.gcode to price a print, or a bank .csv for Money." % ext, 6)


func _refresh_rates(kind: String) -> void:
	if Cfg.g("local_only", true) or not ai.has_key():
		OS.shell_open("https://www.royalmail.com/prices" if kind == "shipping" else "https://www.etsy.com/legal/fees/")
		_say("Local-only mode, so I've opened the official page for you instead. Update the numbers in the table and I'll use them.", 7)
		return
	_say("Checking today's %s..." % ("Royal Mail prices" if kind == "shipping" else "selling fees"), -1)
	var prompt := ""
	if kind == "shipping":
		prompt = "Look up today's Royal Mail ONLINE prices (UK) for: Tracked 48 and Tracked 24 Large Letter (up to 750g), Small Parcel (2kg), Medium Parcel (2kg and 10kg), plus 1st and 2nd Class Small Parcel. Reply ONLY with JSON: [{\"name\": \"Royal Mail Tracked 48 Small Parcel\", \"price\": 3.65}, ...] using exactly these name patterns: \"Royal Mail Tracked 48 Large Letter\", \"Royal Mail Tracked 24 Large Letter\", \"Royal Mail Tracked 48 Small Parcel\", \"Royal Mail Tracked 24 Small Parcel\", \"Royal Mail 2nd Class Small Parcel\", \"Royal Mail 1st Class Small Parcel\", \"Royal Mail Tracked 48 Medium Parcel (2 kg)\", \"Royal Mail Tracked 48 Medium Parcel (10 kg)\"."
	else:
		prompt = "Look up current UK seller fees for: Etsy (transaction + payment processing + listing, as one percent and one fixed GBP amount per order), eBay UK business sellers (typical final value fee), Shopify Basic UK online card payments, SumUp in person. Reply ONLY with JSON: [{\"name\": \"Etsy\", \"percent\": 10.5, \"fixed\": 0.36}, ...] with names \"Etsy\", \"eBay (business)\", \"Shopify\", \"In person (card)\"."
	var txt: String = await ai.quick_call(prompt, true, 700)
	var a := txt.find("[")
	var b := txt.rfind("]")
	var arr = JSON.parse_string(txt.substr(a, b - a + 1)) if a >= 0 and b > a else null
	if not (arr is Array):
		_say("Couldn't get clean numbers back. The table's unchanged.", 6)
		return
	var key := "shipping" if kind == "shipping" else "platforms"
	var n := 0
	for item in arr:
		for row in shop.data[key]:
			if String(row.name) == String(item.get("name", "")):
				for k in ["price", "percent", "fixed"]:
					if item.has(k):
						row[k] = float(item[k])
				n += 1
	if kind == "shipping":
		shop.data.shipping_checked = "checked by Rico on " + Time.get_date_string_from_system()
	shop.save()
	_say("Updated %d %s. Reopen the Print Shop to see them." % [n, "prices" if kind == "shipping" else "fee rates"], 6)


func _on_print_event(kind: String, info: Dictionary) -> void:
	match kind:
		"connected":
			if String(info.get("state", "")) == "":
				pass
		"done":
			var mins := (Time.get_unix_time_from_system() - _print_started) / 60.0 if _print_started > 0 else 0.0
			if mins > 0:
				Cfg.data.last_print_minutes = mins
			Cfg.data.last_print_name = String(info.get("job", ""))
			Cfg.save()
			_print_started = 0.0
			_big_moment(Lines.pick(["Print's done! %s came out of the oven. Go and admire it.", "Ding! %s is finished. Careful, the plate's still warm.", "%s: complete. Another flawless victory for the machines."]) % (String(info.get("job", "Your print")) if String(info.get("job", "")) != "" else "Your print"), "happy")
		"failed":
			_print_started = 0.0
			_big_moment(Lines.pick(["Bad news: %s failed. Tell me what it looks like and I'll work out why.", "Uh oh. %s didn't make it. Describe the carnage and I'll diagnose it."]) % (String(info.get("job", "The print")) if String(info.get("job", "")) != "" else "The print"), "shock")
		"attention":
			_big_moment("Your printer needs you: it's %s%s. Probably filament, or it just misses you." % ["paused" if String(info.get("state", "")) == "PAUSE" else "flagging a problem", (" (error %d)" % int(info.error)) if int(info.get("error", 0)) != 0 else ""], "worried")


func _big_moment(text: String, mood: String) -> void:
	if _fs_hidden:
		voice.speak(text)
		_fs_queue.append(text)
		return
	_show()
	_wake_up()
	rico.set_mood(mood, 3.0)
	rico.jump_for_joy()
	sfx.play("alert")
	_say(text, 15)
	if int(Cfg.g("speak_replies", 1)) == 2:
		voice.speak(text)


func _minute_checks() -> void:
	# bills due tomorrow
	var notified: Dictionary = Cfg.g("bills_notified", {})
	for b in money.data.bills:
		var due: String = money.next_due(b)
		var unix := Time.get_unix_time_from_datetime_string(due + "T09:00:00")
		var key := "%s|%s" % [b.name, due]
		if unix - Time.get_unix_time_from_system() < 36 * 3600 and not notified.has(key):
			notified[key] = true
			Cfg.s("bills_notified", notified)
			_big_moment("Heads up: %s takes £%.2f on %s. Make sure there's money in the pot." % [b.name, float(b.amount), due], "think")
			return
	# printer maintenance, at most once a day
	if bambu.configured() and Time.get_unix_time_from_system() - float(Cfg.g("maint_nagged", 0)) > 86400 and bambu.progress() < 0:
		var hours := float(Cfg.g("print_hours", 0.0))
		var done: Dictionary = Cfg.g("maint_done", {})
		for m in ShopWindowScript.MAINTENANCE:
			if hours - float(done.get(m.id, 0.0)) >= float(m.every):
				Cfg.s("maint_nagged", Time.get_unix_time_from_system())
				if not bubble.is_busy_with_user():
					_say("Printer TLC time: %s. Tick it off in Print Shop > Printer when done." % String(m.name).to_lower(), 12)
				return


# ------------------------------------------------------------------ games

func _on_game_started(g: String) -> void:
	var e: Dictionary = games.entry(g)
	var first := int(e.get("played_min", 0)) == 0
	if Cfg.g("game_help", true) and not bubble.is_busy_with_user():
		var line := (Lines.pick(Lines.GAME_FIRST) if first else Lines.pick(Lines.GAME_BACK)) % g
		_say(line, 6)


func _game_tick(delta: float) -> void:
	var g: String = games.current()
	if g == "":
		return
	_game_time += delta
	if int(_game_time) % 60 == 0 and int(_game_time) > 0 and int(_game_time - delta) % 60 != 0:
		var e: Dictionary = games.entry(g)
		e.played_min = int(e.get("played_min", 0)) + 1
		games.save()
	if not Cfg.g("game_tips", true) or not Cfg.g("game_help", true):
		return
	_game_tip_timer -= delta
	if _game_tip_timer > 0:
		return
	_game_tip_timer = 900.0
	var tip: String = games.next_tip(g)
	if tip == "":
		_fetch_tips(g)
		_game_tip_timer = 60.0
		return
	if not bubble.is_busy_with_user():
		_say(tip, 10)
		voice.speak(tip)


func _fetch_tips(g: String) -> void:
	if _fetching_tips or not ai.has_key():
		return
	var cap: float = float(Cfg.g("daily_cap_gbp", 0.0))
	if cap > 0 and mem.today_gbp() >= cap:
		return
	_fetching_tips = true
	var prompt := "Pierre is playing %s right now. Give 8 short, genuinely useful gameplay tips for it, in your voice: each one sentence, a little cheeky, no story spoilers, a mix of beginner and clever tricks, and correct for the current version (use web_search once if you're not sure). Reply with ONLY a JSON array of 8 strings." % g
	var txt: String = await ai.quick_call(prompt, true, 900)
	_fetching_tips = false
	var start := txt.find("[")
	var end := txt.rfind("]")
	if start >= 0 and end > start:
		var arr = JSON.parse_string(txt.substr(start, end - start + 1))
		if arr is Array:
			games.add_tips(g, arr)


func _app_label(exe: String) -> String:
	return exe.get_basename().capitalize() if exe != "" else "this app"


func _on_focus_rect(r: Rect2i, exe_path: String) -> void:
	var exe := exe_path.get_file().to_lower() if exe_path != "" else ""
	var g: String = GamesScript.detect(exe_path, _fg_title) if exe_path != "" else ""
	if exe_path != "" and g != games.detected:
		games.detected = g
		ai.game = games.current()
		if g != "":
			_game_time = 0.0
			_game_tip_timer = 600.0
			_on_game_started(g)
	_check_fullscreen(r)
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
	if rico.docked:
		return
	if _no_space():
		_dock()
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
	if _return_after_land:
		_return_after_land = false
		if _pre_search_x >= 0 and rico.home_x < 0:
			rico.hop_to(_pre_search_x, true)
		_pre_search_x = -1.0
		_dodge_check = 0.5
		return
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
	if bubble.is_open() and not bubble.typing and bubble.chat_mode and mouse.distance_to(rico.position) > 600:
		rico.look_at_pos = bubble.position + bubble.size * 0.5
	rico.talking = bubble.is_open() and bubble.typing and bubble._full_text != "..."
	rico.thinking = (ai.busy or voice.busy or bubble._full_text.ends_with("...")) and not _approval_pending
	if rico.talking and Cfg.g("talk_blips"):
		_blip_acc += delta
		if _blip_acc > 0.075:
			_blip_acc = 0.0
			sfx.play("blip%d" % (randi() % 3), randf_range(0.9, 1.15), 0.5)

	if search.visible:
		_place_search()
		rico.look_at_pos = search.caret_point()
		if rico.state == RicoScript.State.IDLE and rico.bounds.end.y < area.end.y:
			rico.position.x = search.position.x + search.panel.size.x - 70
		var has_answer: bool = not search.results.is_empty() and search.results[0].kind == "answer"
		if has_answer:
			rico.set_mood("happy", 0.5)
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
	if _mouse_still > 300.0 and not bubble.is_open() and rico.state == RicoScript.State.IDLE:
		rico.sleep()

	# idle quips + app tips
	var chat := int(Cfg.g("chattiness", 1))
	if not bubble.is_open() and rico.state in [RicoScript.State.IDLE, RicoScript.State.HOP] and win.visible:
		_quip_timer -= delta
		if _quip_timer <= 0 and chat > 0:
			_quip_timer = _next_quip_delay()
			_say(Lines.pick(Lines.IDLE), 6)
	_kind_time += delta
	_tip_cooldown -= delta
	if Cfg.g("app_tips") and _fg_kind != "" and _kind_time > 150.0 and _tip_cooldown <= 0 and not bubble.is_open() and win.visible and rico.state != RicoScript.State.SLEEP:
		_tip_cooldown = [1800.0, 720.0, 360.0][chat]
		_say(_next_tip(_fg_kind), 9)

	_poll_controller()
	_game_tick(delta)
	_update_presence(delta, mouse)
	rico.print_progress = bambu.progress()
	if bambu.progress() >= 0 and _print_started <= 0:
		_print_started = Time.get_unix_time_from_system() - float(bambu.state.get("mc_percent", 0)) / 100.0 * 0.0
	_minute_timer -= delta
	if _minute_timer <= 0:
		_minute_timer = 60.0
		_minute_checks()
	if _update_waiting and _mouse_still > 900.0 and not bubble.is_open() and not search.is_open() and not ai.busy and not _approval_pending:
		_update_waiting = false
		updater.install_pending()
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
	if now - last < 7 * 86400 or bubble.is_open() or rico.state == RicoScript.State.SLEEP:
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
	if _ghost > 0.97 and not bubble.visible and not search.visible:
		r = Rect2(0, 0, 1, 1)   # faded out: let every click through
	if bubble.visible:
		r = r.merge(bubble.rect_with_tail())
	if search.visible:
		r = r.merge(Rect2(search.position - Vector2(16, 16), search.size + Vector2(32, 40)))
	r = r.intersection(area.grow(-0.0))
	if (r.size.x < 4 or r.size.y < 4) and _ghost <= 0.97:
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
	if event is InputEventMouseButton and event.pressed and rico.hit_test(event.position) and _ghost < 0.5:
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
	if rico.docked:
		_wake_up()
		_say(Lines.pick(["You rang?", "Back from my little corner. What's up?", "Ta-da. Hologram deployed."]), 4)
		return
	if rico.state == RicoScript.State.SLEEP:
		rico.wake()
		_say(Lines.pick(Lines.WAKE), 4)
		return
	if bubble.is_open() and bubble.chat_mode:
		bubble.input.grab_focus()
		return
	if bubble.is_busy_with_user():
		return
	rico.sq = 0.85
	_open_chat()


func _poll_controller() -> void:
	var pads := Input.get_connected_joypads()
	if search.is_open():
		for b in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
			var dn := false
			for d in pads:
				dn = dn or Input.is_joy_button_pressed(d, b)
			var was_s: bool = _joy_prev.get(100 + b, false)
			_joy_prev[100 + b] = dn
			if dn and not was_s:
				match b:
					JOY_BUTTON_DPAD_UP: search.move(-1)
					JOY_BUTTON_DPAD_DOWN: search.move(1)
					JOY_BUTTON_A: search.activate(false)
					JOY_BUTTON_B: search.close()
					JOY_BUTTON_X: _search_voice()
					JOY_BUTTON_Y: search.ask_about_current()
		return
	var held_back := false
	for d in pads:
		if Input.is_joy_button_pressed(d, JOY_BUTTON_BACK):
			held_back = true
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_RIGHT_SHOULDER]:
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
		JOY_BUTTON_RIGHT_SHOULDER:
			await _open_search()
			_search_voice()


func _search_voice() -> void:
	_voice_for_search = true
	if voice.recording:
		voice.stop()
	else:
		voice.toggle()


func _on_cfg_changed(key: String) -> void:
	match key:
		"size":
			rico.scale = Vector2.ONE * Cfg.size_scale()
			rico.position.y = area.end.y - rico.half_extents().y
		"chattiness":
			_quip_timer = _next_quip_delay()
