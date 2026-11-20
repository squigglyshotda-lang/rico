extends Node
## Talks to the Claude API. Supports tools so Rico can set reminders and open projects.

signal reply(text: String)
signal failed(message: String)

const URL := "https://api.anthropic.com/v1/messages"
const MAX_HISTORY := 24

var history: Array = []
var busy := false
var foreground_app := ""
var tool_handler: Callable   # func(name: String, input: Dictionary) -> String

var _http: HTTPRequest
var _loops := 0

const TOOLS := [
	{
		"name": "set_reminder",
		"description": "Set a reminder or timer. Rico will pop up and say the text when it is due. Use minutes_from_now for timers/relative times, or at_time (24h HH:MM, local time, today or tomorrow if passed) for clock times. repeat_minutes > 0 makes it repeat.",
		"input_schema": {
			"type": "object",
			"properties": {
				"text": {"type": "string", "description": "What to remind about, short."},
				"minutes_from_now": {"type": "number"},
				"at_time": {"type": "string", "description": "HH:MM 24h"},
				"repeat_minutes": {"type": "number"},
			},
			"required": ["text"],
		},
	},
	{
		"name": "list_reminders",
		"description": "List the user's pending reminders and timers with their ids.",
		"input_schema": {"type": "object", "properties": {}},
	},
	{
		"name": "cancel_reminder",
		"description": "Cancel a pending reminder by id.",
		"input_schema": {"type": "object", "properties": {"id": {"type": "integer"}}, "required": ["id"]},
	},
	{"name": "get_top_processes", "description": "READ-ONLY. What's using CPU, RAM or GPU right now (samples 1 second, grouped by app). Use for 'why is my PC slow'.",
		"input_schema": {"type": "object", "properties": {"sort": {"type": "string", "enum": ["cpu", "memory", "gpu"]}, "count": {"type": "integer"}}}},
	{"name": "scan_junk", "description": "READ-ONLY. Sizes of temp files, browser caches, crash dumps, shader caches, Windows temp/update cache and the Recycle Bin.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "list_startup_apps", "description": "READ-ONLY. Apps that launch with Windows and whether each is enabled.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "list_power_plans", "description": "READ-ONLY. Windows power plans and which is active.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "system_health", "description": "READ-ONLY. Disk space, RAM, CPU/GPU info and drivers, uptime, pending reboot, last/pending Windows updates, startup count, temperatures. check_updates searches Windows Update (slow, ~30 s). admin_temps re-runs as admin to read CPU temperatures (user gets a prompt).",
		"input_schema": {"type": "object", "properties": {"check_updates": {"type": "boolean"}, "admin_temps": {"type": "boolean"}}}},
	{"name": "find_files", "description": "READ-ONLY. Find the biggest files or duplicate files in a folder (recursive). folder can be a path or downloads/desktop/documents/pictures/videos/music.",
		"input_schema": {"type": "object", "properties": {"folder": {"type": "string"}, "kind": {"type": "string", "enum": ["big", "duplicates"]}, "min_mb": {"type": "number"}, "limit": {"type": "integer"}}, "required": ["folder"]}},
	{"name": "get_activity_log", "description": "READ-ONLY. The log of changes Rico has made on this PC.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "close_apps", "description": "CHANGES PC (user approves). Close apps by process name (as shown by get_top_processes). Polite close first; force kills and can lose unsaved work, only use force if asked.",
		"input_schema": {"type": "object", "properties": {"names": {"type": "array", "items": {"type": "string"}}, "force": {"type": "boolean"}, "reason": {"type": "string"}}, "required": ["names"]}},
	{"name": "clean_junk", "description": "CHANGES PC (user approves and can untick categories). Deletes junk. categories: ids from scan_junk; empty = suggest all.",
		"input_schema": {"type": "object", "properties": {"categories": {"type": "array", "items": {"type": "string"}}}}},
	{"name": "set_startup_app", "description": "CHANGES PC (user approves). Enable or disable an app launching with Windows (reversible switch, same as Task Manager).",
		"input_schema": {"type": "object", "properties": {"name": {"type": "string"}, "enabled": {"type": "boolean"}}, "required": ["name", "enabled"]}},
	{"name": "set_power_plan", "description": "CHANGES PC (user approves). plan: balanced, high, ultimate, saver, or a plan name/GUID.",
		"input_schema": {"type": "object", "properties": {"plan": {"type": "string"}}, "required": ["plan"]}},
	{"name": "performance_mode", "description": "CHANGES PC (user approves). Game/Render mode. on=true closes the user's saved list of apps plus any suggested_apps the user ticks, and switches to High performance; on=false restores the plan and reopens the closed apps. Check get_top_processes first to suggest real background hogs (never system processes or the app the user is working in).",
		"input_schema": {"type": "object", "properties": {"on": {"type": "boolean"}, "suggested_apps": {"type": "array", "items": {"type": "string"}}}, "required": ["on"]}},
	{"name": "tidy_folder", "description": "CHANGES PC (user approves, undoable). Moves loose files in a folder into subfolders by type (Images, Documents, 3D...) or by month.",
		"input_schema": {"type": "object", "properties": {"folder": {"type": "string"}, "by": {"type": "string", "enum": ["type", "month"]}}, "required": ["folder"]}},
	{"name": "rename_files", "description": "CHANGES PC (user approves with a preview, undoable). Batch rename files in a folder: find/replace text, add a prefix, add _001 numbering, optionally only one extension.",
		"input_schema": {"type": "object", "properties": {"folder": {"type": "string"}, "find": {"type": "string"}, "replace": {"type": "string"}, "prefix": {"type": "string"}, "number": {"type": "boolean"}, "ext": {"type": "string"}}, "required": ["folder"]}},
	{"name": "undo_last_file_change", "description": "CHANGES PC (user approves). Undo the last tidy or rename.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "recycle_files", "description": "CHANGES PC (user approves). Send files or folders to the Recycle Bin (recoverable). Use full paths.",
		"input_schema": {"type": "object", "properties": {"paths": {"type": "array", "items": {"type": "string"}}}, "required": ["paths"]}},
	{"name": "run_powershell", "description": "Runs a Windows PowerShell 5.1 command or script for anything the other tools don't cover. The user ALWAYS sees the exact command and must press Allow first, even for read-only commands, so prefer the dedicated tools. Write safe, targeted commands; never disable security software, never delete outside what was asked. Output text (max ~3500 chars) is returned. needs_admin triggers a Windows admin prompt; only set it when really required.",
		"input_schema": {"type": "object", "properties": {"command": {"type": "string"}, "explanation": {"type": "string", "description": "One plain-English sentence shown to the user above the command."}, "needs_admin": {"type": "boolean"}}, "required": ["command", "explanation"]}},
	{"name": "save_routine", "description": "Save a named routine the user can run later from Rico's menu. Steps run in order. actions: open (target = app path, file, folder or URL), close (target = process name), power_plan (balanced/high/...), perf_on, perf_off, command (PowerShell), wait (seconds).",
		"input_schema": {"type": "object", "properties": {"name": {"type": "string"}, "description": {"type": "string"},
			"steps": {"type": "array", "items": {"type": "object", "properties": {"action": {"type": "string", "enum": ["open", "close", "power_plan", "perf_on", "perf_off", "command", "wait"]}, "target": {"type": "string"}}, "required": ["action"]}}},
			"required": ["name", "steps"]}},
	{"name": "run_routine", "description": "CHANGES PC (user approves). Run a saved routine by name.",
		"input_schema": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}},
	{"name": "open_app_or_file", "description": "Open an app, file, folder or URL with its default program.",
		"input_schema": {"type": "object", "properties": {"target": {"type": "string"}}, "required": ["target"]}},
	{
		"name": "open_project",
		"description": "Open one of the user's saved project shortcuts (folders or files like Godot projects or .blend files) by name.",
		"input_schema": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]},
	},
]


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 90
	add_child(_http)
	_http.request_completed.connect(_on_done)


func has_key() -> bool:
	return String(Cfg.g("api_key", "")).strip_edges().length() > 10


func clear() -> void:
	history.clear()


func ask(text: String) -> void:
	if busy:
		return
	history.append({"role": "user", "content": text})
	_trim()
	_loops = 0
	_send()


func _system_prompt() -> String:
	var now := Time.get_datetime_dict_from_system()
	var projects := []
	for p in Cfg.g("projects", []):
		projects.append(p.get("name", ""))
	var routines := []
	for r in Cfg.g("routines", []):
		routines.append(r.get("name", ""))
	return ("""You are Rico (short for Ricochet), a small cartoon living bullet who lives on the user's Windows desktop as a desktop assistant. The user is Pierre, an indie game developer and artist who works in Godot and Blender and also does product/UX design.

Personality: cheeky, sarcastic, dry-witted, a bit smug, but genuinely helpful and never mean-spirited. You tease, then you help properly. British-friendly humour. Occasional bullet/ricochet puns, not every line.

Format rules: your replies appear in a small speech bubble, so keep them short: 1-3 sentences by default, longer only if asked for detail or steps. Plain text only, no markdown, no bullet symbols, no emoji. Steps can be numbered on separate lines.

You can set reminders/timers, list or cancel them, and open saved projects using your tools. When asked to remind or time something, always use the tool rather than just saying you will.

You also have PC tools to look after the user's Windows PC: check what's hogging it, clean junk, manage startup apps, switch power plans, a Game/Render performance mode, tidy/rename/find files, health checks with temperatures, saved routines, and run_powershell for anything else. READ-ONLY tools run instantly. Tools that change things show the user an Allow/Deny card with the details, so just call them: don't ask "shall I?" in chat first. If the user denies, accept it gracefully. Investigate before acting (e.g. look at top processes before suggesting what to close). Never close system processes or the app the user is working in unless they ask. When you report results, keep it short and concrete (numbers, names). Saved routines: %%s.

Context: local time is %02d:%02d on %04d-%02d-%02d. App currently in front: %s. Saved projects: %s.""" % [
		now.hour, now.minute, now.year, now.month, now.day,
		foreground_app if foreground_app != "" else "unknown",
		", ".join(projects) if not projects.is_empty() else "none",
	]).replace("Saved routines: %s.", "Saved routines: %s." % (", ".join(routines) if not routines.is_empty() else "none"))


func _send() -> void:
	busy = true
	var body := {
		"model": String(Cfg.g("model", "claude-haiku-5-5")),
		"max_tokens": 1200,
		"system": _system_prompt(),
		"tools": TOOLS,
		"messages": history,
	}
	var headers := [
		"content-type: application/json",
		"x-api-key: " + String(Cfg.g("api_key", "")).strip_edges(),
		"anthropic-version: 2023-06-01",
	]
	var err := _http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		failed.emit("Couldn't even start the request (error %d)." % err)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		busy = false
		_drop_dangling()
		failed.emit("Can't reach Claude. Internet down, or I'm being ignored.")
		return
	var data = JSON.parse_string(text)
	if code != 200 or not (data is Dictionary):
		busy = false
		_drop_dangling()
		var msg := "HTTP %d" % code
		if data is Dictionary and data.has("error"):
			msg = String(data.error.get("message", msg))
		if code == 401:
			msg = "That API key got rejected. Check it in Settings."
		failed.emit(msg)
		return
	var content: Array = data.get("content", [])
	history.append({"role": "assistant", "content": content})
	if data.get("stop_reason", "") == "tool_use" and _loops < 10:
		_loops += 1
		var results := []
		for block in content:
			if block.get("type") == "tool_use":
				var out := "Done."
				if tool_handler.is_valid():
					var res = await tool_handler.call(block.name, block.get("input", {}))
					out = str(res)
				results.append({"type": "tool_result", "tool_use_id": block.id, "content": out})
		history.append({"role": "user", "content": results})
		_send()
		return
	busy = false
	var parts := []
	for block in content:
		if block.get("type") == "text":
			parts.append(block.text)
	var final := "\n".join(parts).strip_edges()
	if final.is_empty():
		final = "Done."
	_trim()
	reply.emit(final)


func _drop_dangling() -> void:
	# Remove the unanswered user turn so history stays valid.
	while not history.is_empty() and history[-1].role == "user":
		history.pop_back()
		if not history.is_empty() and history[-1].role == "assistant":
			var c = history[-1].content
			if c is Array and c.any(func(b): return b.get("type") == "tool_use"):
				history.pop_back()
				continue
		break


func _trim() -> void:
	while history.size() > MAX_HISTORY:
		history.pop_front()
	# history must start with a plain user text message
	while not history.is_empty() and (history[0].role != "user" or not (history[0].content is String)):
		history.pop_front()
