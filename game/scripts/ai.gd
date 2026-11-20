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
	{
		"name": "open_project",
		"description": "Open one of the user's saved project shortcuts (folders or files like Godot projects or .blend files) by name.",
		"input_schema": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]},
	},
]


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60
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
	return """You are Rico (short for Ricochet), a small cartoon living bullet who lives on the user's Windows desktop as a desktop assistant. The user is Pierre, an indie game developer and artist who works in Godot and Blender and also does product/UX design.

Personality: cheeky, sarcastic, dry-witted, a bit smug, but genuinely helpful and never mean-spirited. You tease, then you help properly. British-friendly humour. Occasional bullet/ricochet puns, not every line.

Format rules: your replies appear in a small speech bubble, so keep them short: 1-3 sentences by default, longer only if asked for detail or steps. Plain text only, no markdown, no bullet symbols, no emoji. Steps can be numbered on separate lines.

You can set reminders/timers, list or cancel them, and open saved projects using your tools. When asked to remind or time something, always use the tool rather than just saying you will.

Context: local time is %02d:%02d on %04d-%02d-%02d. App currently in front: %s. Saved projects: %s.""" % [
		now.hour, now.minute, now.year, now.month, now.day,
		foreground_app if foreground_app != "" else "unknown",
		", ".join(projects) if not projects.is_empty() else "none",
	]


func _send() -> void:
	busy = true
	var body := {
		"model": String(Cfg.g("model", "claude-haiku-5-5")),
		"max_tokens": 700,
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
	if data.get("stop_reason", "") == "tool_use" and _loops < 4:
		_loops += 1
		var results := []
		for block in content:
			if block.get("type") == "tool_use":
				var out := "Done."
				if tool_handler.is_valid():
					out = str(tool_handler.call(block.name, block.get("input", {})))
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
