extends Node
## Personal budget, bills and subscriptions. Everything lives in %APPDATA%/Rico/money.json
## and never leaves the PC: no AI, no internet, just local maths.

const PATH := "user://money.json"

const DEFAULT_CATEGORIES := [
	{"name": "Groceries", "budget": 300.0}, {"name": "Eating out", "budget": 80.0}, {"name": "Transport", "budget": 100.0},
	{"name": "Bills", "budget": 0.0}, {"name": "Subscriptions", "budget": 40.0}, {"name": "Games", "budget": 40.0},
	{"name": "Art & hobbies", "budget": 60.0}, {"name": "3D printing", "budget": 60.0}, {"name": "Shopping", "budget": 100.0},
	{"name": "Health", "budget": 0.0}, {"name": "Kids & family", "budget": 0.0}, {"name": "Other", "budget": 0.0},
	{"name": "Income", "budget": 0.0}, {"name": "Transfers", "budget": 0.0},
]

## keyword -> category (lower-case, matched inside the description)
const DEFAULT_RULES := {
	"tesco": "Groceries", "sainsbury": "Groceries", "asda": "Groceries", "aldi": "Groceries", "lidl": "Groceries", "morrisons": "Groceries",
	"waitrose": "Groceries", "co-op": "Groceries", "ocado": "Groceries", "iceland": "Groceries", "m&s food": "Groceries",
	"deliveroo": "Eating out", "just eat": "Eating out", "uber eats": "Eating out", "mcdonald": "Eating out", "greggs": "Eating out",
	"nando": "Eating out", "costa": "Eating out", "starbucks": "Eating out", "pret": "Eating out", "kfc": "Eating out", "domino": "Eating out",
	"tfl": "Transport", "trainline": "Transport", "uber": "Transport", "shell": "Transport", "bp ": "Transport", "esso": "Transport",
	"national rail": "Transport", "parking": "Transport", "dvla": "Transport",
	"netflix": "Subscriptions", "spotify": "Subscriptions", "disney": "Subscriptions", "amazon prime": "Subscriptions", "prime video": "Subscriptions",
	"youtube": "Subscriptions", "apple.com": "Subscriptions", "icloud": "Subscriptions", "google": "Subscriptions", "adobe": "Subscriptions",
	"anthropic": "Subscriptions", "claude": "Subscriptions", "openai": "Subscriptions", "patreon": "Subscriptions", "dropbox": "Subscriptions",
	"now tv": "Subscriptions", "paramount": "Subscriptions", "audible": "Subscriptions", "xbox game pass": "Subscriptions", "ps plus": "Subscriptions",
	"steam": "Games", "playstation": "Games", "xbox": "Games", "nintendo": "Games", "epic games": "Games", "humble": "Games", "gog.com": "Games",
	"blizzard": "Games", "battle.net": "Games",
	"bambu": "3D printing", "petg": "3D printing", "pla": "3D printing", "filament": "3D printing", "resin": "3D printing", "nozzle": "3D printing", "sunlu": "3D printing", "printables": "3D printing", "polymaker": "3D printing", "elegoo": "3D printing",
	"clip studio": "Art & hobbies", "procreate": "Art & hobbies", "hobbycraft": "Art & hobbies", "cass art": "Art & hobbies", "wacom": "Art & hobbies",
	"council tax": "Bills", "british gas": "Bills", "octopus": "Bills", "edf": "Bills", "e.on": "Bills", "ovo": "Bills", "thames water": "Bills",
	"water": "Bills", "virgin media": "Bills", "bt group": "Bills", "sky ": "Bills", "ee ": "Bills", "vodafone": "Bills", "o2": "Bills",
	"three": "Bills", "tv licen": "Bills", "insurance": "Bills", "mortgage": "Bills", "rent": "Bills",
	"amazon": "Shopping", "argos": "Shopping", "ebay": "Shopping", "ikea": "Shopping", "john lewis": "Shopping", "currys": "Shopping",
	"boots": "Health", "pharmacy": "Health", "dentist": "Health", "gym": "Health", "puregym": "Health",
	"salary": "Income", "payroll": "Income", "etsy payout": "Income", "refund": "Income",
	"transfer": "Transfers", "to savings": "Transfers", "pot": "Transfers",
}

var data := {}   # {categories, rules, tx: [{id, date, desc, amount, cat, source}], bills: [{name, amount, day, cat, remind}], next_id}

signal changed


func _ready() -> void:
	data = {"categories": DEFAULT_CATEGORIES.duplicate(true), "rules": DEFAULT_RULES.duplicate(), "tx": [], "bills": [], "next_id": 1}
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			for k in d.keys():
				data[k] = d[k]


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	changed.emit()


# ------------------------------------------------------------------ categories

func categorise(desc: String) -> String:
	var d := " " + desc.to_lower() + " "
	var best := ""
	var best_len := 0
	for k in data.rules.keys():
		if String(k) in d and String(k).length() > best_len:
			best = data.rules[k]
			best_len = String(k).length()
	return best if best != "" else "Other"


## Recategorise a transaction and remember the merchant for next time.
func set_category(tx: Dictionary, cat: String, learn := true) -> void:
	tx.cat = cat
	if learn:
		var key := merchant(String(tx.desc))
		if key.length() >= 3:
			data.rules[key] = cat
			for t in data.tx:
				if merchant(String(t.desc)) == key:
					t.cat = cat
	save()


static func merchant(desc: String) -> String:
	var d := desc.to_lower()
	var re := RegEx.new()
	re.compile("[^a-z& ]")
	d = re.sub(d, " ", true)
	var words := Array(d.split(" ", false)).filter(func(w): return not w in ["card", "payment", "to", "from", "ltd", "limited", "uk", "gb", "london", "www", "com", "co", "pos", "contactless", "dd", "so", "fp", "bgc", "vis", "cpt"])
	return " ".join(words.slice(0, 2))


# ------------------------------------------------------------------ transactions

func add(desc: String, amount: float, date := "", cat := "", source := "manual") -> Dictionary:
	if date == "":
		date = Time.get_date_string_from_system()
	var tx := {"id": int(data.next_id), "date": date, "desc": desc, "amount": amount, "cat": cat if cat != "" else (categorise(desc) if amount < 0 else "Income"), "source": source}
	data.next_id = int(data.next_id) + 1
	data.tx.append(tx)
	save()
	return tx


## Import a bank statement CSV. Handles most UK banks (Monzo, Starling, Barclays, HSBC, Lloyds,
## Nationwide, Santander, Revolut...) by finding the date, description and amount columns.
func import_csv(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "note": "Couldn't open that file."}
	var rows := []
	while not f.eof_reached():
		var r := f.get_csv_line()
		if r.size() > 1:
			rows.append(r)
	f.close()
	if rows.size() < 2:
		return {"ok": false, "note": "That CSV looks empty."}
	# find the header row (first row containing a date-ish column name)
	var hi := 0
	for i in mini(rows.size(), 10):
		var joined := ",".join(rows[i]).to_lower()
		if "date" in joined:
			hi = i
			break
	var head: PackedStringArray = rows[hi]
	var c_date := -1; var c_desc := -1; var c_amt := -1; var c_in := -1; var c_out := -1; var c_name := -1
	for i in head.size():
		var h := head[i].to_lower().strip_edges()
		if c_date < 0 and "date" in h: c_date = i
		elif h in ["description", "memo", "details", "transaction description", "reference", "narrative", "payee"] and c_desc < 0: c_desc = i
		elif h in ["name", "counter party", "counterparty", "merchant"] and c_name < 0: c_name = i
		elif h in ["amount", "amount (gbp)", "value", "transaction amount"] and c_amt < 0: c_amt = i
		elif ("paid in" in h or "credit" in h or "money in" in h) and c_in < 0: c_in = i
		elif ("paid out" in h or "debit" in h or "money out" in h) and c_out < 0: c_out = i
	if c_desc < 0: c_desc = c_name
	if c_date < 0 or c_desc < 0 or (c_amt < 0 and c_in < 0 and c_out < 0):
		return {"ok": false, "note": "I couldn't spot the date, description and amount columns in that CSV."}
	var added := 0
	var skipped := 0
	var seen := {}
	for t in data.tx:
		seen["%s|%s|%.2f" % [t.date, t.desc, float(t.amount)]] = true
	for r in rows.slice(hi + 1):
		if r.size() <= maxi(c_date, c_desc):
			continue
		var date := _norm_date(r[c_date])
		if date == "":
			continue
		var desc = r[c_desc].strip_edges()
		if c_name >= 0 and c_name != c_desc and r.size() > c_name and r[c_name].strip_edges() != "":
			desc = r[c_name].strip_edges()
		var amt := 0.0
		if c_amt >= 0 and r.size() > c_amt and r[c_amt].strip_edges() != "":
			amt = _num(r[c_amt])
		else:
			var inn := _num(r[c_in]) if c_in >= 0 and r.size() > c_in else 0.0
			var out := _num(r[c_out]) if c_out >= 0 and r.size() > c_out else 0.0
			amt = absf(inn) - absf(out)
		if amt == 0.0:
			continue
		var key := "%s|%s|%.2f" % [date, desc, amt]
		if seen.has(key):
			skipped += 1
			continue
		seen[key] = true
		data.tx.append({"id": int(data.next_id), "date": date, "desc": desc, "amount": amt, "cat": categorise(desc) if amt < 0 else (categorise(desc) if categorise(desc) == "Transfers" else "Income"), "source": "csv"})
		data.next_id = int(data.next_id) + 1
		added += 1
	save()
	return {"ok": true, "added": added, "skipped": skipped}


static func _num(s: String) -> float:
	var t := s.strip_edges().replace("£", "").replace(",", "").replace(" ", "")
	var neg := t.begins_with("(") and t.ends_with(")")
	t = t.trim_prefix("(").trim_suffix(")")
	var v := t.to_float()
	return -v if neg else v


static func _norm_date(s: String) -> String:
	var t := s.strip_edges()
	var re := RegEx.new()
	re.compile("^(\\d{4})-(\\d{2})-(\\d{2})")
	var m := re.search(t)
	if m:
		return "%s-%s-%s" % [m.get_string(1), m.get_string(2), m.get_string(3)]
	re.compile("^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2,4})")
	m = re.search(t)
	if m:
		var y := int(m.get_string(3))
		if y < 100: y += 2000
		return "%04d-%02d-%02d" % [y, int(m.get_string(2)), int(m.get_string(1))]   # UK day/month order
	re.compile("^(\\d{1,2}) ([A-Za-z]{3})[a-z]* (\\d{4})")
	m = re.search(t)
	if m:
		var months := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
		var mi := months.find(m.get_string(2).to_lower())
		if mi >= 0:
			return "%s-%02d-%02d" % [m.get_string(3), mi + 1, int(m.get_string(1))]
	return ""


# ------------------------------------------------------------------ reports

static func this_month() -> String:
	return Time.get_date_string_from_system().left(7)


func month_tx(month := "") -> Array:
	if month == "": month = this_month()
	return data.tx.filter(func(t): return String(t.date).begins_with(month))


## {category: spent (positive)} for a month, excluding income and transfers
func spending(month := "") -> Dictionary:
	var out := {}
	for t in month_tx(month):
		if float(t.amount) < 0 and not t.cat in ["Income", "Transfers"]:
			out[t.cat] = float(out.get(t.cat, 0.0)) - float(t.amount)
	return out


func income(month := "") -> float:
	var s := 0.0
	for t in month_tx(month):
		if float(t.amount) > 0 and t.cat == "Income":
			s += float(t.amount)
	return s


func budget_for(cat: String) -> float:
	for c in data.categories:
		if String(c.name).to_lower() == cat.to_lower():
			return float(c.budget)
	return 0.0


func find_category(q: String) -> String:
	var ql := q.to_lower().strip_edges()
	for c in data.categories:
		if String(c.name).to_lower() == ql or String(c.name).to_lower().begins_with(ql) or ql in String(c.name).to_lower():
			return c.name
	return ""


func month_summary() -> String:
	var sp := spending()
	var total := 0.0
	for v in sp.values():
		total += v
	var budget := 0.0
	for c in data.categories:
		budget += float(c.budget)
	var over := []
	for c in data.categories:
		var b := float(c.budget)
		if b > 0 and float(sp.get(c.name, 0.0)) > b:
			over.append("%s (£%.0f over)" % [c.name, float(sp[c.name]) - b])
	var top := sp.keys()
	top.sort_custom(func(a, b): return sp[a] > sp[b])
	var lines := ["This month: £%.2f spent%s." % [total, (" of £%.0f budgeted" % budget) if budget > 0 else ""]]
	if not top.is_empty():
		lines.append("Biggest: " + ", ".join(top.slice(0, 3).map(func(k): return "%s £%.0f" % [k, sp[k]])))
	if not over.is_empty():
		lines.append("Over budget: " + ", ".join(over))
	return "\n".join(lines)


func category_left(cat: String) -> String:
	var b := budget_for(cat)
	var s := float(spending().get(cat, 0.0))
	if b <= 0:
		return "%s: £%.2f spent this month (no budget set)." % [cat, s]
	var left := b - s
	return ("%s: £%.2f left of £%.0f." % [cat, left, b]) if left >= 0 else ("%s: £%.2f OVER the £%.0f budget." % [cat, -left, b])


# ------------------------------------------------------------------ bills and subscriptions

func add_bill(name: String, amount: float, day: int, cat := "Bills") -> Dictionary:
	var b := {"name": name, "amount": amount, "day": clampi(day, 1, 28), "cat": cat}
	data.bills.append(b)
	save()
	return b


func next_due(b: Dictionary) -> String:
	var d := Time.get_date_dict_from_system()
	var day := int(b.day)
	var m := int(d.month)
	var y := int(d.year)
	if int(d.day) > day:
		m += 1
		if m > 12:
			m = 1
			y += 1
	return "%04d-%02d-%02d" % [y, m, day]


func due_within(days: int) -> Array:
	var now := Time.get_unix_time_from_system()
	var out := []
	for b in data.bills:
		var due := Time.get_unix_time_from_datetime_string(next_due(b) + "T09:00:00")
		if due - now <= days * 86400:
			out.append(b)
	return out


## Spot repeating payments: same merchant, similar amount, in 2+ different months.
func detect_subscriptions() -> Array:
	var by := {}
	for t in data.tx:
		if float(t.amount) >= 0:
			continue
		var k := merchant(String(t.desc))
		if k == "":
			continue
		if not by.has(k):
			by[k] = []
		by[k].append(t)
	var known = data.bills.map(func(b): return String(b.name).to_lower())
	var out := []
	for k in by.keys():
		var list: Array = by[k]
		var months := {}
		var amounts := []
		var last_day := 1
		for t in list:
			months[String(t.date).left(7)] = true
			amounts.append(-float(t.amount))
			last_day = int(String(t.date).substr(8, 2))
		if months.size() < 2:
			continue
		amounts.sort()
		var med: float = amounts[amounts.size() / 2]
		var steady := amounts.filter(func(a): return absf(a - med) <= maxf(1.0, med * 0.15)).size() >= 2
		if steady and not k in known:
			out.append({"name": k.capitalize(), "amount": snappedf(med, 0.01), "day": clampi(last_day, 1, 28), "months": months.size()})
	out.sort_custom(func(a, b): return a.amount > b.amount)
	return out


func subscriptions_total() -> float:
	var s := 0.0
	for b in data.bills:
		if String(b.cat) == "Subscriptions":
			s += float(b.amount)
	return s
