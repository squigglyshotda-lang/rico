extends Node
## Watches a Bambu Lab printer over the local network (read-only MQTT over TLS,
## port 8883, user "bblp", password = the printer's access code).

signal status_changed(state: Dictionary)
signal event(kind: String, info: Dictionary)   # done, failed, attention, connected, disconnected
signal connection(text: String)

const PORT := 8883
const KEEPALIVE := 30

var state := {}                # merged "print" report
var connected := false
var _tcp: StreamPeerTCP
var _tls: StreamPeerTLS
var _buf := PackedByteArray()
var _stage := 0                # 0 idle, 1 tcp, 2 tls, 3 mqtt-connecting, 4 subscribed
var _ping := 0.0
var _retry := 3.0
var _last_state := ""
var _last_error := 0
var _hms_seen := {}
var _run_acc := 0.0


func configured() -> bool:
	return String(Cfg.g("printer_ip", "")) != "" and String(Cfg.g("printer_serial", "")) != "" and String(Cfg.g("printer_code", "")) != ""


func reconnect() -> void:
	_close()
	_retry = 0.1


func _close() -> void:
	if _tls: _tls.disconnect_from_stream()
	if _tcp: _tcp.disconnect_from_host()
	_tls = null
	_tcp = null
	_stage = 0
	_buf.clear()
	if connected:
		connected = false
		event.emit("disconnected", {})


func _process(delta: float) -> void:
	if not configured():
		return
	match _stage:
		0:
			_retry -= delta
			if _retry <= 0:
				_retry = 20.0
				_tcp = StreamPeerTCP.new()
				if _tcp.connect_to_host(String(Cfg.g("printer_ip")), PORT) == OK:
					_stage = 1
					connection.emit("Connecting to the printer...")
		1:
			_tcp.poll()
			match _tcp.get_status():
				StreamPeerTCP.STATUS_CONNECTED:
					_tls = StreamPeerTLS.new()
					if _tls.connect_to_stream(_tcp, "bambu", TLSOptions.client_unsafe()) == OK:
						_stage = 2
					else:
						_fail("TLS wouldn't start.")
				StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
					_fail("Can't reach the printer at %s. Check the IP and that it's on." % Cfg.g("printer_ip"))
		2:
			_tls.poll()
			match _tls.get_status():
				StreamPeerTLS.STATUS_CONNECTED:
					_send_connect()
					_stage = 3
				StreamPeerTLS.STATUS_ERROR, StreamPeerTLS.STATUS_ERROR_HOSTNAME_MISMATCH, StreamPeerTLS.STATUS_DISCONNECTED:
					_fail("Secure connection to the printer failed.")
		3, 4:
			_tls.poll()
			if _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
				_fail("Lost the printer connection.")
				return
			var n := _tls.get_available_bytes()
			if n > 0:
				var r := _tls.get_partial_data(n)
				if r[0] == OK:
					_buf.append_array(r[1])
					_parse()
			_ping -= delta
			if _ping <= 0:
				_ping = KEEPALIVE * 0.7
				_tls.put_data(PackedByteArray([0xC0, 0x00]))   # PINGREQ
	if String(state.get("gcode_state", "")) == "RUNNING":
		_run_acc += delta
		if _run_acc >= 60.0:
			_run_acc = 0.0
			Cfg.s("print_hours", float(Cfg.g("print_hours", 0.0)) + 1.0 / 60.0)


func _fail(msg: String) -> void:
	connection.emit(msg)
	_close()
	_retry = 20.0


# ------------------------------------------------------------------ MQTT 3.1.1

static func _str(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	var out := PackedByteArray([b.size() >> 8, b.size() & 0xFF])
	out.append_array(b)
	return out


static func _remaining(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	while true:
		var d := n % 128
		n = n / 128
		if n > 0: d |= 0x80
		out.append(d)
		if n == 0: break
	return out


func _packet(kind: int, body: PackedByteArray) -> PackedByteArray:
	var p := PackedByteArray([kind])
	p.append_array(_remaining(body.size()))
	p.append_array(body)
	return p


func _send_connect() -> void:
	var body := _str("MQTT")
	body.append_array(PackedByteArray([4, 0xC2, 0, KEEPALIVE]))   # v3.1.1, user+pass+clean session
	body.append_array(_str("rico-%d" % (randi() % 100000)))
	body.append_array(_str("bblp"))
	body.append_array(_str(String(Cfg.g("printer_code"))))
	_tls.put_data(_packet(0x10, body))


func _subscribe() -> void:
	var body := PackedByteArray([0, 1])
	body.append_array(_str("device/%s/report" % String(Cfg.g("printer_serial")).strip_edges()))
	body.append(0)
	_tls.put_data(_packet(0x82, body))
	# ask for a full status (may be ignored when the printer only allows reading)
	var pub := _str("device/%s/request" % String(Cfg.g("printer_serial")).strip_edges())
	pub.append_array(JSON.stringify({"pushing": {"sequence_id": "0", "command": "pushall"}}).to_utf8_buffer())
	_tls.put_data(_packet(0x30, pub))


func _parse() -> void:
	while _buf.size() >= 2:
		var kind := _buf[0] & 0xF0
		var mult := 1
		var length := 0
		var i := 1
		while true:
			if i >= _buf.size():
				return
			var d := _buf[i]
			length += (d & 0x7F) * mult
			mult *= 128
			i += 1
			if d & 0x80 == 0:
				break
		if _buf.size() < i + length:
			return
		var body := _buf.slice(i, i + length)
		_buf = _buf.slice(i + length)
		match kind:
			0x20:   # CONNACK
				if body.size() >= 2 and body[1] == 0:
					_stage = 4
					connected = true
					connection.emit("Connected to your printer.")
					event.emit("connected", {})
					_subscribe()
				else:
					_fail("The printer refused the access code (it changes if LAN mode is toggled).")
					return
			0x30:   # PUBLISH (QoS 0)
				var tl := (body[0] << 8) | body[1]
				var payload := body.slice(2 + tl).get_string_from_utf8()
				var d = JSON.parse_string(payload)
				if d is Dictionary and d.get("print") is Dictionary:
					_merge(d.print)


func _merge(p: Dictionary) -> void:
	for k in p.keys():
		state[k] = p[k]
	var gs := String(state.get("gcode_state", ""))
	var err := int(state.get("print_error", 0))
	var info := summary()
	if gs != _last_state:
		if _last_state != "":
			match gs:
				"FINISH": event.emit("done", info)
				"FAILED": event.emit("failed", info)
				"PAUSE":
					if err != 0:
						event.emit("attention", info)
		_last_state = gs
	elif err != 0 and err != _last_error and gs in ["PAUSE", "RUNNING"]:
		event.emit("attention", info)
	_last_error = err
	for h in state.get("hms", []):
		var key := "%s-%s" % [h.get("attr", 0), h.get("code", 0)]
		if not _hms_seen.has(key):
			_hms_seen[key] = true
			if gs in ["RUNNING", "PAUSE"] and _hms_seen.size() > 0:
				event.emit("attention", info.merged({"hms": key}))
	status_changed.emit(state)


func summary() -> Dictionary:
	return {
		"state": String(state.get("gcode_state", "")),
		"job": String(state.get("subtask_name", "")).get_basename(),
		"percent": int(state.get("mc_percent", 0)),
		"minutes_left": int(state.get("mc_remaining_time", 0)),
		"layer": int(state.get("layer_num", 0)),
		"layers": int(state.get("total_layer_num", 0)),
		"nozzle": float(state.get("nozzle_temper", 0.0)),
		"bed": float(state.get("bed_temper", 0.0)),
		"error": int(state.get("print_error", 0)),
	}


func status_text() -> String:
	if not configured():
		return "I'm not hooked up to your printer yet. Add its IP, serial and access code in Settings > 3D printing."
	if not connected:
		return "I can't reach the printer right now. Is it on and on the same Wi-Fi?"
	var s := summary()
	match s.state:
		"RUNNING", "PREPARE":
			var h = s.minutes_left / 60
			var m = s.minutes_left % 60
			return "%s is %d%% done, layer %d of %d, about %s left. Nozzle %d C, bed %d C." % [s.job if s.job != "" else "Your print", s.percent, s.layer, s.layers, ("%dh %02dm" % [h, m]) if h > 0 else "%d min" % m, s.nozzle, s.bed]
		"PAUSE": return "The print's paused%s." % (" (error %d)" % s.error if s.error != 0 else "")
		"FINISH": return "Last print finished: %s." % (s.job if s.job != "" else "done")
		"FAILED": return "The last print failed%s." % (" (error %d)" % s.error if s.error != 0 else "")
	return "The printer's idle. Waiting for something to make."


func progress() -> float:
	var gs := String(state.get("gcode_state", ""))
	if connected and gs in ["RUNNING", "PREPARE", "PAUSE"]:
		return clampf(float(state.get("mc_percent", 0)) / 100.0, 0.0, 1.0)
	return -1.0
