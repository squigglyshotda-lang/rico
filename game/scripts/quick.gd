extends Node
## Instant answers for the search bar: maths, unit conversions, live currency rates
## and time-zone lookups (the time lookups are answered by the search server).

const RATES_PATH := "user://rates.json"
const RATE_URLS := ["https://api.frankfurter.dev/v1/latest", "https://api.frankfurter.app/latest"]

var rates := {}          # code -> units per 1 EUR
var rates_date := ""
var _http: HTTPRequest
var _url_i := 0

const UNITS := {
	# length (metres)
	"mm": ["length", 0.001], "cm": ["length", 0.01], "m": ["length", 1.0], "metre": ["length", 1.0], "metres": ["length", 1.0], "meter": ["length", 1.0], "meters": ["length", 1.0],
	"km": ["length", 1000.0], "in": ["length", 0.0254], "inch": ["length", 0.0254], "inches": ["length", 0.0254], "\"": ["length", 0.0254],
	"ft": ["length", 0.3048], "foot": ["length", 0.3048], "feet": ["length", 0.3048], "'": ["length", 0.3048], "yd": ["length", 0.9144], "yard": ["length", 0.9144], "yards": ["length", 0.9144],
	"mi": ["length", 1609.344], "mile": ["length", 1609.344], "miles": ["length", 1609.344], "nmi": ["length", 1852.0],
	# mass (kg)
	"mg": ["mass", 0.000001], "g": ["mass", 0.001], "gram": ["mass", 0.001], "grams": ["mass", 0.001], "kg": ["mass", 1.0], "kgs": ["mass", 1.0],
	"t": ["mass", 1000.0], "tonne": ["mass", 1000.0], "tonnes": ["mass", 1000.0], "oz": ["mass", 0.028349523125], "ounce": ["mass", 0.028349523125], "ounces": ["mass", 0.028349523125],
	"lb": ["mass", 0.45359237], "lbs": ["mass", 0.45359237], "pound": ["mass", 0.45359237], "pounds": ["mass", 0.45359237], "st": ["mass", 6.35029318], "stone": ["mass", 6.35029318],
	# volume (litres; pints/gallons are UK)
	"ml": ["volume", 0.001], "cl": ["volume", 0.01], "l": ["volume", 1.0], "litre": ["volume", 1.0], "litres": ["volume", 1.0], "liter": ["volume", 1.0], "liters": ["volume", 1.0],
	"tsp": ["volume", 0.00492892], "tbsp": ["volume", 0.0147868], "cup": ["volume", 0.2365882365], "cups": ["volume", 0.2365882365], "floz": ["volume", 0.0284130625],
	"pint": ["volume", 0.56826125], "pints": ["volume", 0.56826125], "gal": ["volume", 4.54609], "gallon": ["volume", 4.54609], "gallons": ["volume", 4.54609], "usgal": ["volume", 3.785411784],
	# data (bytes)
	"b": ["data", 1.0], "byte": ["data", 1.0], "bytes": ["data", 1.0], "kb": ["data", 1000.0], "mb": ["data", 1e6], "gb": ["data", 1e9], "tb": ["data", 1e12],
	"kib": ["data", 1024.0], "mib": ["data", 1048576.0], "gib": ["data", 1073741824.0], "tib": ["data", 1099511627776.0],
	# speed (m/s)
	"mps": ["speed", 1.0], "m/s": ["speed", 1.0], "kph": ["speed", 0.2777778], "kmh": ["speed", 0.2777778], "km/h": ["speed", 0.2777778], "mph": ["speed", 0.44704], "knot": ["speed", 0.514444], "knots": ["speed", 0.514444],
	# time (s)
	"ms": ["time", 0.001], "s": ["time", 1.0], "sec": ["time", 1.0], "secs": ["time", 1.0], "seconds": ["time", 1.0], "min": ["time", 60.0], "mins": ["time", 60.0], "minutes": ["time", 60.0],
	"h": ["time", 3600.0], "hr": ["time", 3600.0], "hrs": ["time", 3600.0], "hour": ["time", 3600.0], "hours": ["time", 3600.0], "day": ["time", 86400.0], "days": ["time", 86400.0], "week": ["time", 604800.0], "weeks": ["time", 604800.0],
	# area (m2)
	"m2": ["area", 1.0], "sqm": ["area", 1.0], "km2": ["area", 1e6], "ft2": ["area", 0.09290304], "sqft": ["area", 0.09290304], "acre": ["area", 4046.8564224], "acres": ["area", 4046.8564224], "ha": ["area", 10000.0], "hectare": ["area", 10000.0], "hectares": ["area", 10000.0],
}
const TEMPS := {"c": "C", "celsius": "C", "°c": "C", "f": "F", "fahrenheit": "F", "°f": "F", "k": "K", "kelvin": "K"}
const SYMBOLS := {"£": "GBP", "$": "USD", "€": "EUR", "¥": "JPY"}
const CURRENCY_NAMES := {"pound": "GBP", "pounds": "GBP", "quid": "GBP", "dollar": "USD", "dollars": "USD", "euro": "EUR", "euros": "EUR", "yen": "JPY", "rupee": "INR", "rupees": "INR", "xcd": "XCD"}

const CITIES := {
	"london": "GMT Standard Time", "uk": "GMT Standard Time", "dublin": "GMT Standard Time", "lisbon": "GMT Standard Time", "edinburgh": "GMT Standard Time",
	"paris": "Romance Standard Time", "madrid": "Romance Standard Time", "brussels": "Romance Standard Time",
	"berlin": "W. Europe Standard Time", "amsterdam": "W. Europe Standard Time", "rome": "W. Europe Standard Time", "stockholm": "W. Europe Standard Time", "oslo": "W. Europe Standard Time", "vienna": "W. Europe Standard Time", "zurich": "W. Europe Standard Time",
	"helsinki": "FLE Standard Time", "kyiv": "FLE Standard Time", "athens": "GTB Standard Time", "istanbul": "Turkey Standard Time", "moscow": "Russian Standard Time",
	"cairo": "Egypt Standard Time", "johannesburg": "South Africa Standard Time", "lagos": "W. Central Africa Standard Time", "nairobi": "E. Africa Standard Time",
	"dubai": "Arabian Standard Time", "mumbai": "India Standard Time", "delhi": "India Standard Time", "india": "India Standard Time",
	"bangkok": "SE Asia Standard Time", "jakarta": "SE Asia Standard Time", "singapore": "Singapore Standard Time", "manila": "Singapore Standard Time",
	"beijing": "China Standard Time", "shanghai": "China Standard Time", "hong kong": "China Standard Time", "taipei": "Taipei Standard Time",
	"tokyo": "Tokyo Standard Time", "japan": "Tokyo Standard Time", "seoul": "Korea Standard Time",
	"sydney": "AUS Eastern Standard Time", "melbourne": "AUS Eastern Standard Time", "brisbane": "E. Australia Standard Time", "perth": "W. Australia Standard Time", "auckland": "New Zealand Standard Time",
	"new york": "Eastern Standard Time", "nyc": "Eastern Standard Time", "toronto": "Eastern Standard Time", "miami": "Eastern Standard Time", "boston": "Eastern Standard Time",
	"chicago": "Central Standard Time", "texas": "Central Standard Time", "dallas": "Central Standard Time", "denver": "Mountain Standard Time",
	"los angeles": "Pacific Standard Time", "la": "Pacific Standard Time", "san francisco": "Pacific Standard Time", "seattle": "Pacific Standard Time", "vancouver": "Pacific Standard Time",
	"honolulu": "Hawaiian Standard Time", "mexico city": "Central Standard Time (Mexico)", "sao paulo": "E. South America Standard Time", "buenos aires": "Argentina Standard Time",
	"st lucia": "SA Western Standard Time", "saint lucia": "SA Western Standard Time", "castries": "SA Western Standard Time", "barbados": "SA Western Standard Time", "trinidad": "SA Western Standard Time",
	"jamaica": "SA Pacific Standard Time", "kingston": "SA Pacific Standard Time", "utc": "UTC", "gmt": "UTC",
}


func _ready() -> void:
	if FileAccess.file_exists(RATES_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(RATES_PATH))
		if d is Dictionary:
			rates = d.get("rates", {})
			rates_date = String(d.get("date", ""))
	_http = HTTPRequest.new()
	_http.timeout = 15
	add_child(_http)
	_http.request_completed.connect(_on_rates)


## Refresh currency rates at most once a day.
func refresh_rates() -> void:
	var today := Time.get_date_string_from_system()
	if rates_date == today or _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_http.request(RATE_URLS[_url_i])


func _on_rates(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var d = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if d is Dictionary and d.has("rates"):
		rates = d.rates
		rates["EUR"] = 1.0
		rates_date = Time.get_date_string_from_system()
		var f := FileAccess.open(RATES_PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify({"rates": rates, "date": rates_date, "source_date": d.get("date", "")}))
	elif _url_i + 1 < RATE_URLS.size():
		_url_i += 1
		_http.request(RATE_URLS[_url_i])


static func fmt(v: float) -> String:
	if absf(v) >= 1e15 or (absf(v) < 1e-6 and v != 0.0):
		return String.num_scientific(v)
	var s := String.num(v, 6 if absf(v) < 1 else 4)
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	# thousands separators for big whole parts
	var neg := s.begins_with("-")
	if neg: s = s.substr(1)
	var parts := s.split(".")
	var whole := parts[0]
	var grouped := ""
	while whole.length() > 3:
		grouped = "," + whole.right(3) + grouped
		whole = whole.left(whole.length() - 3)
	grouped = whole + grouped
	return ("-" if neg else "") + grouped + ("." + parts[1] if parts.size() > 1 else "")


func _num(s: String) -> float:
	return s.replace(",", "").to_float()


## Returns {title, subtitle, copy} or {} when the text isn't something we can answer.
func answer(q: String) -> Dictionary:
	var t := q.strip_edges().to_lower()
	if t.is_empty():
		return {}
	var r := _currency(t)
	if r.is_empty(): r = _units(t)
	if r.is_empty(): r = _percent(t)
	if r.is_empty(): r = _math(t, q)
	return r


func _math(t: String, q := "") -> Dictionary:
	var re := RegEx.new()
	re.compile("^[0-9\\s\\.\\,\\+\\-\\*\\/\\(\\)\\^x×÷%a-z]+$")
	if not re.search(t):
		return {}
	var e := t.replace("×", "*").replace("÷", "/").replace("^", "**").replace(",", "")
	var x := RegEx.new()
	x.compile("(?<=[0-9\\)])\\s*x\\s*(?=[0-9\\(])")
	e = x.sub(e, "*", true)
	# words allowed: maths functions only
	var words := RegEx.new()
	words.compile("[a-z_]+")
	var allowed := ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "exp", "abs", "round", "floor", "ceil", "pow", "min", "max", "pi", "PI", "tau"]
	for m in words.search_all(e):
		if not m.get_string() in allowed:
			return {}
	e = e.replace("pi", "PI").replace("tau", "TAU")
	var ints := RegEx.new()
	ints.compile("(?<![\\d.])(\\d+)(?![\\d.])")
	e = ints.sub(e, "$1.0", true)   # float maths, so 1200/7 isn't integer division
	var op := RegEx.new()
	op.compile("[\\+\\-\\*\\/%]|\\b[a-z]+\\(")
	if not op.search(e.substr(1)):   # needs at least one operator or function (not just "42" or "-3")
		return {}
	var ex := Expression.new()
	if ex.parse(e) != OK:
		return {}
	var v = ex.execute([], null, false)
	if ex.has_execute_failed() or not (v is float or v is int):
		return {}
	if is_nan(float(v)) or is_inf(float(v)):
		return {}
	var s := fmt(float(v))
	return {"title": "= " + s, "subtitle": q.strip_edges(), "copy": s.replace(",", "")}


func _percent(t: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("^([\\d.,]+)\\s*%\\s*of\\s*([\\d.,]+)$")
	var m := re.search(t)
	if not m:
		return {}
	var v := _num(m.get_string(1)) / 100.0 * _num(m.get_string(2))
	return {"title": "= " + fmt(v), "subtitle": t, "copy": str(v)}


func _units(t: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("^(-?[\\d.,]+)\\s*([a-z°\"'/0-9]+(?: [a-z]+)?)\\s+(?:in|to|as|into)\\s+([a-z°\"'/0-9]+)$")
	var m := re.search(t)
	if not m:
		return {}
	var v := _num(m.get_string(1))
	var a := m.get_string(2).strip_edges()
	var b := m.get_string(3).strip_edges()
	if TEMPS.has(a) and TEMPS.has(b):
		var c := v
		match TEMPS[a]:
			"F": c = (v - 32.0) * 5.0 / 9.0
			"K": c = v - 273.15
		var out := c
		match TEMPS[b]:
			"F": out = c * 9.0 / 5.0 + 32.0
			"K": out = c + 273.15
		var s := fmt(snappedf(out, 0.01))
		return {"title": "%s °%s" % [s, TEMPS[b]], "subtitle": "%s °%s" % [fmt(v), TEMPS[a]], "copy": s}
	if UNITS.has(a) and UNITS.has(b) and UNITS[a][0] == UNITS[b][0]:
		var out: float = v * float(UNITS[a][1]) / float(UNITS[b][1])
		var s := fmt(out)
		var bl := b.to_upper() if UNITS[b][0] == "data" else b
		var al := a.to_upper() if UNITS[a][0] == "data" else a
		return {"title": "%s %s" % [s, bl], "subtitle": "%s %s (%s)" % [fmt(v), al, UNITS[a][0]], "copy": s.replace(",", "")}
	return {}


func _code(s: String) -> String:
	s = s.strip_edges()
	if SYMBOLS.has(s): return SYMBOLS[s]
	if CURRENCY_NAMES.has(s): return CURRENCY_NAMES[s]
	return s.to_upper()


func _currency(t: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("^([£$€¥])?\\s*([\\d.,]+)\\s*([a-z]{3}|pounds?|quid|dollars?|euros?|yen|rupees?)?\\s+(?:in|to|as)\\s+([£$€¥]|[a-z]{3}|pounds?|dollars?|euros?|yen|rupees?)$")
	var m := re.search(t)
	if not m:
		return {}
	var from := _code(m.get_string(1) if m.get_string(1) != "" else m.get_string(3))
	var to := _code(m.get_string(4))
	if from == "" or from == to:
		return {}
	if UNITS.has(from.to_lower()) or UNITS.has(to.to_lower()):
		return {}
	refresh_rates()
	if rates.is_empty():
		return {"title": "Fetching exchange rates...", "subtitle": "%s to %s" % [from, to], "copy": ""}
	if not rates.has(from) or not rates.has(to):
		return {}
	var v := _num(m.get_string(2)) / float(rates[from]) * float(rates[to])
	var s := String.num(v, 2)
	return {"title": "%s %s" % [fmt(snappedf(v, 0.01)), to], "subtitle": "%s %s · rates from %s" % [fmt(_num(m.get_string(2))), from, rates_date], "copy": s}


## Parse "time in tokyo" / "3pm london in new york" / "15:30 in la".
## Returns {tz_to, tz_from (may be ""), hour (-1 = now), minute, label} or {}.
func time_query(q: String) -> Dictionary:
	var t := q.strip_edges().to_lower()
	var re := RegEx.new()
	re.compile("^(?:what(?:'s| is) the )?time (?:is it )?in (.+?)\\??$")
	var m := re.search(t)
	if m and CITIES.has(m.get_string(1)):
		return {"tz_to": CITIES[m.get_string(1)], "tz_from": "", "hour": -1, "minute": 0, "label": m.get_string(1).capitalize()}
	re.compile("^(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\s*(?:(.+?)\\s+)?(?:in|to)\\s+(.+)$")
	m = re.search(t)
	if m and CITIES.has(m.get_string(5)):
		var src := m.get_string(4).strip_edges()
		if src != "" and not CITIES.has(src):
			return {}
		var h := int(m.get_string(1))
		var ap := m.get_string(3)
		if ap == "pm" and h < 12: h += 12
		if ap == "am" and h == 12: h = 0
		if h > 23:
			return {}
		return {"tz_to": CITIES[m.get_string(5)], "tz_from": CITIES.get(src, ""), "hour": h, "minute": int(m.get_string(2)), "label": "%s%s in %s" % [m.get_string(1) + (":" + m.get_string(2) if m.get_string(2) != "" else "") + ap, (" " + src.capitalize()) if src != "" else "", m.get_string(5).capitalize()]}
	return {}
