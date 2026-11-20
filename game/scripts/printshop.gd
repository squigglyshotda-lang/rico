extends Node
## Rico's print shop: costs, presets, Royal Mail shipping, selling fees, products,
## reading sliced files and the pricing maths. Saved in %APPDATA%/Rico/printshop.json.

const PATH := "user://printshop.json"

const DEFAULTS := {
	"filaments": [
		{"name": "PLA", "per_kg": 20.0}, {"name": "PLA Matte", "per_kg": 22.0}, {"name": "PETG", "per_kg": 22.0},
		{"name": "ABS", "per_kg": 24.0}, {"name": "ASA", "per_kg": 26.0}, {"name": "TPU", "per_kg": 32.0},
		{"name": "PLA Silk", "per_kg": 24.0}, {"name": "Support", "per_kg": 40.0},
	],
	"kwh_per_hour": 0.22,            # average draw of the H2D while printing (edit to your measurements)
	"pence_per_kwh": 25.0,
	"machine_per_hour": 0.35,        # wear and parts, in pounds
	"failure_buffer": 0.10,          # +10% on materials and machine time
	"labour_per_hour": 15.0,
	"default_labour_min": 10,
	"tiers": [1.8, 2.5, 3.5],        # budget, sweet spot, premium (x true cost)
	"charm": true,                   # round to .99 / .49
	"vat_registered": false,
	"packaging": [
		{"name": "Small box", "cost": 0.45}, {"name": "Mailer bag", "cost": 0.15}, {"name": "Bubble wrap", "cost": 0.10},
		{"name": "Thank-you card", "cost": 0.06}, {"name": "Label and tape", "cost": 0.05},
	],
	"addons": [
		{"name": "Magnet (6x2 mm)", "cost": 0.05}, {"name": "Heat-set insert", "cost": 0.06}, {"name": "Keyring", "cost": 0.12},
	],
	# Royal Mail online prices (edit or ask Rico to refresh). max dims in mm, max weight in g.
	"shipping": [
		{"name": "Royal Mail Tracked 48 Large Letter", "max_g": 750, "dims": [353, 250, 25], "price": 2.85},
		{"name": "Royal Mail Tracked 24 Large Letter", "max_g": 750, "dims": [353, 250, 25], "price": 3.80},
		{"name": "Royal Mail Tracked 48 Small Parcel", "max_g": 2000, "dims": [450, 350, 160], "price": 3.65},
		{"name": "Royal Mail Tracked 24 Small Parcel", "max_g": 2000, "dims": [450, 350, 160], "price": 4.65},
		{"name": "Royal Mail 2nd Class Small Parcel", "max_g": 2000, "dims": [450, 350, 160], "price": 3.95},
		{"name": "Royal Mail 1st Class Small Parcel", "max_g": 2000, "dims": [450, 350, 160], "price": 5.15},
		{"name": "Royal Mail Tracked 48 Medium Parcel (2 kg)", "max_g": 2000, "dims": [610, 460, 460], "price": 5.55},
		{"name": "Royal Mail Tracked 48 Medium Parcel (10 kg)", "max_g": 10000, "dims": [610, 460, 460], "price": 7.35},
		{"name": "Collection / hand delivery", "max_g": 999999, "dims": [9999, 9999, 9999], "price": 0.0},
	],
	"shipping_checked": "Royal Mail online prices, Nov 2026",
	# fee = percent of sale + fixed per order (edit to your plan; rates change)
	"platforms": [
		{"name": "Etsy", "percent": 10.5, "fixed": 0.36},
		{"name": "eBay (business)", "percent": 12.8, "fixed": 0.30},
		{"name": "Shopify", "percent": 2.0, "fixed": 0.25},
		{"name": "In person (card)", "percent": 1.69, "fixed": 0.0},
		{"name": "In person (cash)", "percent": 0.0, "fixed": 0.0},
	],
	"products": [],
}

var data := {}


func _ready() -> void:
	data = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			for k in d.keys():
				data[k] = d[k]


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func per_kg(material: String) -> float:
	var m := material.to_lower()
	var best := -1.0
	for f in data.filaments:
		var n := String(f.name).to_lower()
		if n == m:
			return float(f.per_kg)
		if best < 0 and (m.begins_with(n) or n in m):
			best = float(f.per_kg)
	return best if best >= 0 else float(data.filaments[0].per_kg)


# ------------------------------------------------------------------ reading sliced files

## Returns {name, hours, plates, filaments: [{material, grams}], ok, note}
func read_sliced(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext == "3mf":
		return _read_3mf(path)
	if ext in ["gcode", "gco", "g", "bgcode"]:
		return _read_gcode(path)
	return {"ok": false, "note": "I can read .3mf (sliced) and .gcode files."}


func _read_3mf(path: String) -> Dictionary:
	var out := {"ok": false, "name": path.get_file().get_basename(), "hours": 0.0, "plates": 0, "filaments": []}
	var z := ZIPReader.new()
	if z.open(path) != OK:
		out.note = "Couldn't open that 3MF."
		return out
	var files := z.get_files()
	var info := ""
	for f in files:
		if f.to_lower().ends_with("slice_info.config"):
			info = z.read_file(f).get_string_from_utf8()
	if info == "":
		# unsliced project: look for any embedded gcode
		for f in files:
			if f.to_lower().ends_with(".gcode"):
				var tmp := OS.get_user_data_dir().path_join("tmp_plate.gcode")
				var fa := FileAccess.open(tmp, FileAccess.WRITE)
				fa.store_buffer(z.read_file(f))
				fa.close()
				var g := _read_gcode(tmp)
				g.name = out.name
				z.close()
				return g
		z.close()
		out.note = "That 3MF isn't sliced yet. Slice it in Bambu Studio and save (or export the plate), then drop it on me."
		return out
	z.close()
	var seconds := 0.0
	var by_mat := {}
	var p := XMLParser.new()
	p.open_buffer(info.to_utf8_buffer())
	while p.read() == OK:
		if p.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var tag := p.get_node_name()
		if tag == "plate":
			out.plates += 1
		elif tag == "metadata" and p.has_attribute("key"):
			if p.get_named_attribute_value("key") == "prediction":
				seconds += float(p.get_named_attribute_value("value"))
		elif tag == "filament":
			var mat := p.get_named_attribute_value_safe("type")
			var g := float(p.get_named_attribute_value_safe("used_g"))
			if mat == "": mat = "PLA"
			by_mat[mat] = float(by_mat.get(mat, 0.0)) + g
	out.hours = seconds / 3600.0
	for m in by_mat.keys():
		out.filaments.append({"material": m, "grams": snappedf(by_mat[m], 0.1)})
	out.ok = out.hours > 0 or not out.filaments.is_empty()
	if not out.ok:
		out.note = "I couldn't find print time or filament in that file."
	return out


func _read_gcode(path: String) -> Dictionary:
	var out := {"ok": false, "name": path.get_file().get_basename(), "hours": 0.0, "plates": 1, "filaments": []}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out.note = "Couldn't open that file."
		return out
	var head := f.get_buffer(mini(f.get_length(), 300000)).get_string_from_utf8()
	var tail := ""
	if f.get_length() > 300000:
		f.seek(f.get_length() - 200000)
		tail = f.get_buffer(200000).get_string_from_utf8()
	f.close()
	var text := head + "\n" + tail
	var re := RegEx.new()
	# time: "; total estimated time: 1h 2m 3s" / "; estimated printing time (normal mode) = 1d 2h 3m 4s" / ";TIME:3723"
	re.compile("(?im)^;\\s*(?:total estimated time|estimated printing time[^=:]*|model printing time)\\s*[:=]\\s*(.+)$")
	var m := re.search(text)
	if m:
		out.hours = _parse_duration(m.get_string(1))
	else:
		re.compile("(?m)^;TIME:(\\d+)")
		m = re.search(text)
		if m: out.hours = float(m.get_string(1)) / 3600.0
	# grams (possibly per filament, comma separated)
	re.compile("(?im)^;\\s*(?:total filament weight \\[g\\]|filament used \\[g\\]|total filament used \\[g\\])\\s*[:=]\\s*([\\d.,\\s]+)$")
	m = re.search(text)
	var grams: Array = []
	if m:
		for g in m.get_string(1).split(","):
			if g.strip_edges() != "":
				grams.append(float(g.strip_edges()))
	re.compile("(?im)^;\\s*filament_type\\s*=\\s*(.+)$")
	m = re.search(text)
	var types: Array = []
	if m:
		for t in m.get_string(1).split(";"):
			types.append(t.strip_edges())
	for i in grams.size():
		if grams[i] > 0:
			out.filaments.append({"material": types[i] if i < types.size() else (types[0] if not types.is_empty() else "PLA"), "grams": snappedf(grams[i], 0.1)})
	out.ok = out.hours > 0 or not out.filaments.is_empty()
	if not out.ok:
		out.note = "I couldn't find print time or filament in that G-code's header."
	return out


static func _parse_duration(s: String) -> float:
	var total := 0.0
	var re := RegEx.new()
	re.compile("(\\d+(?:\\.\\d+)?)\\s*([dhms])")
	for m in re.search_all(s):
		var v := float(m.get_string(1))
		match m.get_string(2):
			"d": total += v * 24.0
			"h": total += v
			"m": total += v / 60.0
			"s": total += v / 3600.0
	return total


# ------------------------------------------------------------------ pricing

## job: {filaments:[{material, grams}], hours, labour_min, packaging:[names], addons:[[name, qty]],
##       shipping: name, include_shipping: bool, platform: name, quantity}
func quote(job: Dictionary) -> Dictionary:
	var qty := maxi(1, int(job.get("quantity", 1)))
	var material := 0.0
	var grams := 0.0
	for f in job.get("filaments", []):
		material += float(f.grams) / 1000.0 * per_kg(String(f.material))
		grams += float(f.grams)
	var hours := float(job.get("hours", 0.0))
	var power := hours * float(data.kwh_per_hour) * float(data.pence_per_kwh) / 100.0
	var machine := hours * float(data.machine_per_hour)
	var buffer := (material + power + machine) * float(data.failure_buffer)
	var labour := float(job.get("labour_min", data.default_labour_min)) / 60.0 * float(data.labour_per_hour)
	var pack := 0.0
	for p in data.packaging:
		if p.name in job.get("packaging", []):
			pack += float(p.cost)
	var addons := 0.0
	for a in job.get("addons", []):
		for preset in data.addons:
			if preset.name == a[0]:
				addons += float(preset.cost) * int(a[1])
	var ship := 0.0
	for s in data.shipping:
		if s.name == String(job.get("shipping", "")):
			ship = float(s.price)
	var include_ship := bool(job.get("include_shipping", false))
	var unit_cost := material + power + machine + buffer + labour + addons
	var order_cost := pack + (ship if include_ship else 0.0)
	var cost := unit_cost + order_cost / qty
	var plat := {"name": "None", "percent": 0.0, "fixed": 0.0}
	for p in data.platforms:
		if p.name == String(job.get("platform", "")):
			plat = p
	var vat := 0.2 if data.vat_registered else 0.0
	var tiers := []
	var names := ["Budget", "Sweet spot", "Premium"]
	for i in 3:
		var price := _charm(cost * float(data.tiers[i]) * (1.0 + vat))
		var net := price / (1.0 + vat)
		var fees := price * float(plat.percent) / 100.0 + float(plat.fixed) / qty
		var profit := net - fees - cost
		tiers.append({"name": names[i], "price": price, "fees": fees, "profit": profit, "margin": profit / maxf(net, 0.01)})
	return {
		"grams": grams, "hours": hours, "quantity": qty,
		"breakdown": {"Filament": material, "Electricity": power, "Machine wear": machine, "Failure buffer": buffer,
			"Your time": labour, "Add-ons": addons, "Packaging": pack / qty, "Postage": (ship / qty) if include_ship else 0.0},
		"cost": cost, "shipping": ship, "shipping_included": include_ship, "platform": plat.name, "tiers": tiers,
	}


func _charm(p: float) -> float:
	if not data.charm:
		return snappedf(p, 0.01)
	if p < 5.0:
		return ceilf(p * 2.0) / 2.0 - 0.01   # .49 / .99
	return ceilf(p) - 0.01


func auto_shipping(grams: float, dims: Vector3 = Vector3.ZERO) -> String:
	var packed := grams * 1.15 + 60.0   # rough allowance for packaging
	var best := ""
	var best_price := INF
	for s in data.shipping:
		if float(s.price) <= 0.0:
			continue
		if packed > float(s.max_g):
			continue
		if dims != Vector3.ZERO:
			var d := [dims.x, dims.y, dims.z]
			d.sort()
			var m: Array = s.dims.duplicate()
			m.sort()
			if d[0] > m[0] or d[1] > m[1] or d[2] > m[2]:
				continue
		if "Tracked 48" in String(s.name) and float(s.price) < best_price:
			best_price = float(s.price)
			best = s.name
	return best


func text_summary(q: Dictionary) -> String:
	var t: Array = q.tiers
	return "Costs you %s (%.0f g, %s). Budget %s, sweet spot %s, premium %s%s." % [
		money(q.cost), q.grams, _hrs(q.hours), money(t[0].price), money(t[1].price), money(t[2].price),
		(" plus %s postage" % money(q.shipping)) if q.shipping > 0 and not q.shipping_included else ""]


static func money(v: float) -> String:
	return ("-£%.2f" % -v) if v < 0 else "£%.2f" % v


static func _hrs(h: float) -> String:
	var hh := int(h)
	var mm := int(round((h - hh) * 60.0))
	return ("%dh %02dm" % [hh, mm]) if hh > 0 else "%d min" % mm


# ------------------------------------------------------------------ products

func save_product(p: Dictionary) -> void:
	var list: Array = data.products
	for i in list.size():
		if String(list[i].name).to_lower() == String(p.name).to_lower():
			list[i] = p
			save()
			return
	list.append(p)
	save()


func find_product(q: String) -> Dictionary:
	var ql := q.to_lower().strip_edges()
	for p in data.products:
		if String(p.name).to_lower() == ql:
			return p
	for p in data.products:
		if ql in String(p.name).to_lower():
			return p
	return {}
