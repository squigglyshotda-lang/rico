extends Node
## Talks to the Claude API as cheaply as possible:
##  - only the tool groups a message needs are sent
##  - Rico's instructions + tools are prompt-cached (cache reads cost ~10%)
##  - history is short and text-only, older turns become a one-line summary
##  - context (time, app, relevant memory) rides along in the latest message only

signal reply(text: String, meta: Dictionary)
signal failed(message: String, details: String)

const URL := "https://api.anthropic.com/v1/messages"
const KEEP_MESSAGES := 6
const HAIKU := "claude-haiku-5-5"
const SONNET := "claude-sonnet-5-5"

var history: Array = []        # text-only [{role, content}]
var earlier: Array = []        # short notes about dropped turns
var busy := false
var foreground_app := ""
var tool_handler: Callable     # async func(name, input) -> String
var mem: Node                  # memory.gd

var _http: HTTPRequest
var _loops := 0
var _turn: Array = []          # full messages for the turn in progress (with tool blocks)
var _model := HAIKU
var _tools: Array = []
var _max_tokens := 350
var _cost := 0.0
var _used_tools := false
var _question := ""

const TOOLS := [
	{"name": "remember_fact", "description": "Save a lasting fact about the user, their PC or preferences to Rico's local memory (e.g. 'uses Blender 4.2', 'prefers dark UI'). Use when the user tells you something worth knowing next time.",
		"input_schema": {"type": "object", "properties": {"fact": {"type": "string"}}, "required": ["fact"]}},
	{"name": "forget_fact", "description": "Remove facts from Rico's local memory that match the given words.",
		"input_schema": {"type": "object", "properties": {"about": {"type": "string"}}, "required": ["about"]}},
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

const GROUPS := {
	"core": ["set_reminder", "list_reminders", "cancel_reminder", "open_project", "open_app_or_file", "remember_fact", "forget_fact"],
	"perf": ["get_top_processes", "close_apps", "scan_junk", "clean_junk", "list_startup_apps", "set_startup_app", "list_power_plans", "set_power_plan", "performance_mode", "system_health"],
	"files": ["find_files", "tidy_folder", "rename_files", "undo_last_file_change", "recycle_files"],
	"power": ["run_powershell", "save_routine", "run_routine", "get_activity_log"],
}
const TRIGGERS := {
	"perf": ["slow", "lag", "cpu", "ram", "memory", "gpu", "hog", "close", "kill", "quit", "junk", "clean", "space", "disk", "storage", "startup", "boot", "power", "battery", "perf", "game mode", "render mode", "fps", "temp", "hot", "heat", "health", "update", "driver", "fan", "speed up", "optimi", "process", "running"],
	"files": ["file", "folder", "download", "desktop", "document", "picture", "photo", "image", "tidy", "organi", "rename", "duplicate", "biggest", "large", "delete", "recycle", "undo", "move", "sort"],
	"power": ["command", "powershell", "script", "install", "uninstall", "setting", "routine", "registry", "network", "wifi", "bluetooth", "printer", "volume", "display", "monitor", "resolution", "activity", "log", "what did you do", "windows", "service", "schedule"],
	"_pc": ["pc", "computer", "laptop", "machine", "system"],
}
const HARD := ["think hard", "think carefully", "in depth", "step by step", "detailed", "debug", "refactor", "algorithm", "architecture", "gdscript", "shader", "write a script", "write code", "code review", "traceback", "error:", "exception", "stack trace", "```", "compare", "pros and cons", "plan out", "design a"]

const STATIC_PROMPT := """You are Rico (short for Ricochet), a small cartoon living bullet who lives on the user's Windows desktop as a desktop assistant. The user is Pierre, an indie game developer and artist (Godot, Blender) who also does product/UX design.

Personality: cheeky, sarcastic, dry-witted, a bit smug, but genuinely helpful and never mean. Tease, then help properly. British-friendly humour. Occasional bullet puns, not every line.

Replies appear in a small speech bubble and every token costs money: be brief. 1-2 sentences by default; only go longer if asked for detail or steps (then number short steps on separate lines). Plain text only: no markdown, no bullet symbols, no emoji.

Use tools instead of promising: reminders/timers, opening projects/apps, remembering facts the user tells you (remember_fact). PC tools (when provided) can check what's hogging the PC, clean junk, manage startup apps and power plans, toggle Game/Render mode, tidy/rename/find files, run health checks and run PowerShell. Read-only tools run instantly; tools that change things show the user an Allow/Deny card, so call them directly instead of asking first. Investigate before acting, never close system processes or the app the user is working in unless asked, accept a denial gracefully, and report results briefly with numbers and names.

Each user message starts with a [context] line (time, app in front, relevant memory, earlier chat). Use it silently; don't repeat it back."""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 90
	add_child(_http)
	_http.request_completed.connect(_on_done)


func has_key() -> bool:
	return String(Cfg.g("api_key", "")).strip_edges().length() > 10


func clear() -> void:
	history.clear()
	earlier.clear()


static func _has_any(t: String, list: Array) -> bool:
	for k in list:
		if k in t:
			return true
	return false


## Which tool groups a message needs (core is always included).
static func groups_for(text: String) -> Array:
	var t := " " + text.to_lower() + " "
	var g := ["core"]
	for k in ["perf", "files", "power"]:
		if _has_any(t, TRIGGERS[k]):
			g.append(k)
	if _has_any(t, TRIGGERS["_pc"]):
		for k in ["perf", "power"]:
			if not k in g: g.append(k)
	return g


static func needs_tools(text: String) -> bool:
	return groups_for(text).size() > 1


static func is_hard(text: String) -> bool:
	return text.length() > 350 or _has_any(text.to_lower(), HARD)


func _tool_defs(groups: Array) -> Array:
	var names := []
	for g in groups:
		names.append_array(GROUPS[g])
	var out := []
	for t in TOOLS:
		if t.name in names:
			out.append(t.duplicate(true))
	return out


func _context(text: String, groups: Array) -> String:
	var now := Time.get_datetime_dict_from_system()
	var parts := ["time %02d:%02d %04d-%02d-%02d" % [now.hour, now.minute, now.year, now.month, now.day]]
	if foreground_app != "":
		parts.append("app in front: " + foreground_app.left(80))
	var projects := []
	for p in Cfg.g("projects", []):
		projects.append(p.get("name", ""))
	if not projects.is_empty() and ("core" in groups):
		parts.append("projects: " + ", ".join(projects))
	var routines := []
	for r in Cfg.g("routines", []):
		routines.append(r.get("name", ""))
	if not routines.is_empty() and "power" in groups:
		parts.append("routines: " + ", ".join(routines))
	if mem:
		var facts: Array = mem.relevant(text, 5, ["pc"] if groups.size() > 1 else [])
		if not facts.is_empty():
			parts.append("memory: " + "; ".join(facts))
	if not earlier.is_empty():
		parts.append("earlier: " + " | ".join(earlier.slice(-4)))
	return "[context: " + ". ".join(parts) + "]"


## Ask Claude. Model escalates to Sonnet automatically for hard questions.
func ask(text: String) -> void:
	if busy:
		return
	_question = text
	var groups := groups_for(text)
	_tools = _tool_defs(groups)
	if not _tools.is_empty():
		_tools[-1]["cache_control"] = {"type": "ephemeral"}
	_model = SONNET if is_hard(text) else String(Cfg.g("model", HAIKU))
	var lt := text.to_lower()
	_max_tokens = 900 if (_model == SONNET or _has_any(lt, ["detail", "explain", "steps", "how do", "how to", "list", "write"])) else 350
	_cost = 0.0
	_retried = false
	_used_tools = false
	_loops = 0
	_turn = history.duplicate(true)
	_turn.append({"role": "user", "content": _context(text, groups) + "\n" + text})
	_send()


var _retried := false


## Plain-English versions of API errors (the raw text goes under "Show details").
static func friendly_error(code: int, raw: String) -> String:
	var r := raw.to_lower()
	if code == 401:
		return "Claude rejected my API key. Check it in Settings > Chat."
	if "credit" in r or "billing" in r or "balance" in r:
		return "Your Claude account is out of credit. Top up at platform.claude.com, under Billing."
	if code == 404 or "model" in r and "not" in r and "found" in r:
		return "That model name doesn't exist. Reset it in Settings > Chat (claude-haiku-5-5)."
	if code == 403:
		return "Your API key isn't allowed to do that. Check its permissions on platform.claude.com."
	if code == 429:
		return "Claude says I'm asking too often. Give it a minute and try again."
	if code == 529 or code >= 500 or "overloaded" in r:
		return "Claude's servers are swamped right now. Try again in a bit."
	if code == 413 or "too long" in r or "too large" in r:
		return "That was too much for one message. Try something shorter."
	return "Claude didn't like that request. I've reset our chat, so try asking again."


func _send() -> void:
	busy = true
	var body := {
		"model": _model,
		"max_tokens": _max_tokens,
		"system": [{"type": "text", "text": STATIC_PROMPT, "cache_control": {"type": "ephemeral"}}],
		"messages": _turn,
	}
	if not _tools.is_empty():
		body["tools"] = _tools
	var headers := [
		"content-type: application/json",
		"x-api-key: " + String(Cfg.g("api_key", "")).strip_edges(),
		"anthropic-version: 2023-06-01",
	]
	var err := _http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		failed.emit("I couldn't send that to Claude. Try again in a moment.", "HTTPRequest error %d" % err)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		busy = false
		failed.emit("I can't reach Claude. Is the internet down?", "Network result code %d" % result)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if code != 200 or not (data is Dictionary):
		var raw := "HTTP %d" % code
		if data is Dictionary and data.has("error"):
			raw = "HTTP %d: %s" % [code, String(data.error.get("message", ""))]
		# A stale conversation can trip Claude up: forget it and try once more, silently.
		if code == 400 and not _retried and ("messages" in raw or "signature" in raw or "thinking" in raw or "tool_use" in raw):
			_retried = true
			clear()
			_turn = [{"role": "user", "content": _turn[-1].content if _loops == 0 else _question}]
			_loops = 0
			_send()
			return
		busy = false
		failed.emit(friendly_error(code, raw), raw)
		return
	if mem and data.has("usage"):
		_cost += mem.add_usage(_model, data.usage)
	var content: Array = data.get("content", [])
	_turn.append({"role": "assistant", "content": content})
	if data.get("stop_reason", "") == "tool_use" and _loops < 10:
		_loops += 1
		_used_tools = true
		var results := []
		for block in content:
			if block.get("type") == "tool_use":
				var out := "Done."
				if tool_handler.is_valid():
					var res = await tool_handler.call(block.name, block.get("input", {}))
					out = str(res)
				results.append({"type": "tool_result", "tool_use_id": block.id, "content": out.left(4000)})
		_turn.append({"role": "user", "content": results})
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
	_commit(final)
	reply.emit(final, {"model": _model, "cost": _cost, "tools": _used_tools})


## Keep history short and text-only; squash older turns into tiny notes.
func _commit(answer: String) -> void:
	history.append({"role": "user", "content": _question})
	history.append({"role": "assistant", "content": answer.left(600)})
	while history.size() > KEEP_MESSAGES:
		var u: Dictionary = history.pop_front()
		var a: Dictionary = history.pop_front() if not history.is_empty() else {}
		earlier.append("asked \"%s\"%s" % [String(u.content).left(60), (" -> " + String(a.get("content", "")).left(50)) if not a.is_empty() else ""])
	while earlier.size() > 6:
		earlier.pop_front()


## Add an exchange that happened elsewhere (offline brain, local command) so Claude has the thread.
func note_exchange(question: String, answer: String) -> void:
	_question = question
	_commit(answer)
