extends Window
## Print Shop: quotes, products, costs, packaging, Royal Mail shipping, selling fees, printer.

const UI := preload("res://scripts/ui.gd")
const PS := preload("res://scripts/printshop.gd")

signal refresh_rates_requested(kind: String)   # "shipping" | "fees"
signal printer_settings_changed
signal sold(name: String, price: float)

var shop: Node
var bambu: Node
var tabs: TabContainer
var _nav_buttons: Array = []
var _dialog: FileDialog

# quote widgets
var _q_name: LineEdit
var _fil_box: VBoxContainer
var _hours: SpinBox
var _labour: SpinBox
var _qty: SpinBox
var _pack_checks: Dictionary = {}
var _addon_spins: Dictionary = {}
var _ship: OptionButton
var _ship_include: CheckBox
var _platform: OptionButton
var _breakdown: Label
var _tier_box: HBoxContainer
var _q_status: Label
var _last_quote := {}
var _products: ItemList
var _printer_status: Label
var _maint_box: VBoxContainer
var _quiet := false


func _init() -> void:
	title = "Rico's Print Shop"
	size = Vector2i(1160, 820)
	min_size = Vector2i(1000, 640)
	visible = false
	close_requested.connect(hide)
	files_dropped.connect(func(files): if not files.is_empty(): load_file(files[0]))


func build() -> void:
	theme = UI.theme()
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", UI.box(Color(0.085, 0.08, 0.095), 0, Color(0, 0, 0, 0), 0, 0))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 210
	side.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.25), 0, Color(0, 0, 0, 0), 0, 14))
	root.add_child(side)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	side.add_child(nav)
	var brand := Label.new()
	brand.text = UI.icon("cube") + "  Print Shop"
	brand.add_theme_font_override("font", UI.bold())
	brand.add_theme_font_size_override("font_size", 21)
	nav.add_child(brand)
	var sp := Control.new()
	sp.custom_minimum_size.y = 12
	nav.add_child(sp)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + m, 22)
	root.add_child(margin)
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	margin.add_child(tabs)

	_build_quote()
	_build_products()
	_build_costs()
	_build_presets()
	_build_shipping()
	_build_fees()
	_build_printer()

	var icons := ["coin", "grid", "sliders", "zip", "send", "activity", "cube"]
	for i in tabs.get_tab_count():
		var b := Button.new()
		b.text = UI.icon(icons[i]) + "   " + tabs.get_tab_title(i)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "Ghost"
		b.custom_minimum_size.y = 40
		var idx := i
		b.pressed.connect(func(): tabs.current_tab = idx)
		nav.add_child(b)
		_nav_buttons.append(b)
	tabs.tab_changed.connect(_mark_nav)
	_mark_nav(0)

	_dialog = FileDialog.new()
	_dialog.use_native_dialog = true
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.filters = PackedStringArray(["*.3mf, *.gcode ; Sliced prints"])
	_dialog.file_selected.connect(load_file)
	add_child(_dialog)
	_requote()


func _mark_nav(cur: int) -> void:
	for i in _nav_buttons.size():
		var b: Button = _nav_buttons[i]
		if i == cur:
			b.add_theme_stylebox_override("normal", UI.box(Color(UI.COPPER, 0.9), 10, Color(1, 1, 1, 0.15), 1, 6))
			b.add_theme_stylebox_override("hover", UI.box(UI.COPPER_HI, 10, Color(1, 1, 1, 0.2), 1, 6))
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_stylebox_override("hover")
			b.remove_theme_color_override("font_color")
			b.remove_theme_color_override("font_hover_color")
	if cur == 1: refresh_products()
	if cur == 6: refresh_printer()


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


func _heading(parent: Node, text: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		parent.add_child(gap)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI.bold())
	l.add_theme_font_size_override("font_size", 19)
	parent.add_child(l)


func _note(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UI.TEXT_2)
	parent.add_child(l)
	return l


func _row(parent: Node, label: String, ctrl: Control, width := 230) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = width
	h.add_child(l)
	h.add_child(ctrl)


func _spin(lo: float, hi: float, step: float, val: float, prefix := "", suffix := "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.prefix = prefix
	s.suffix = suffix
	s.custom_minimum_size.x = 130
	return s


# ------------------------------------------------------------------ quote

func _build_quote() -> void:
	var v := _page("Quote")
	_heading(v, "Quick quote")
	_note(v, "Drop a sliced .3mf or .gcode on this window (or on Rico), open one, or fill it in by hand.")
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	v.add_child(bh)
	var open := Button.new()
	open.text = UI.icon("folder") + "  Open sliced file"
	open.pressed.connect(func(): _dialog.popup_centered(Vector2i(900, 600)))
	bh.add_child(open)
	var last := Button.new()
	last.text = UI.icon("cube") + "  Use last H2D print time"
	last.pressed.connect(_use_last_print)
	bh.add_child(last)
	_q_status = Label.new()
	_q_status.add_theme_color_override("font_color", UI.TEXT_2)
	_q_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_q_status)

	_q_name = LineEdit.new()
	_q_name.placeholder_text = "Product name, e.g. Brio crossing"
	v.add_child(_q_name)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)

	var fl := Label.new()
	fl.text = "Filament"
	fl.add_theme_color_override("font_color", UI.TEXT_2)
	left.add_child(fl)
	_fil_box = VBoxContainer.new()
	left.add_child(_fil_box)
	var addf := Button.new()
	addf.text = "+ Add filament"
	addf.theme_type_variation = "Ghost"
	addf.pressed.connect(func(): _add_filament_row("PLA", 0.0); _requote())
	left.add_child(addf)
	_hours = _spin(0, 500, 0.05, 0, "", " h")
	_row(left, "Print time", _hours, 130)
	_labour = _spin(0, 600, 1, float(shop.data.default_labour_min), "", " min")
	_row(left, "Your time", _labour, 130)
	_qty = _spin(1, 500, 1, 1, "", " per order")
	_row(left, "Quantity", _qty, 130)
	for s in [_hours, _labour, _qty]:
		s.value_changed.connect(func(_v): _requote())

	var pl := Label.new()
	pl.text = "Packaging"
	pl.add_theme_color_override("font_color", UI.TEXT_2)
	right.add_child(pl)
	var pflow := HFlowContainer.new()
	right.add_child(pflow)
	for p in shop.data.packaging:
		var cb := CheckBox.new()
		cb.text = "%s (%s)" % [p.name, PS.money(float(p.cost))]
		cb.toggled.connect(func(_on): _requote())
		pflow.add_child(cb)
		_pack_checks[p.name] = cb
	var al := Label.new()
	al.text = "Add-ons (each)"
	al.add_theme_color_override("font_color", UI.TEXT_2)
	right.add_child(al)
	for a in shop.data.addons:
		var s := _spin(0, 99, 1, 0)
		s.custom_minimum_size.x = 100
		s.value_changed.connect(func(_v): _requote())
		_row(right, "%s (%s)" % [a.name, PS.money(float(a.cost))], s, 190)
		_addon_spins[a.name] = s
	_ship = OptionButton.new()
	for s in shop.data.shipping:
		_ship.add_item("%s  %s" % [s.name, PS.money(float(s.price))])
	_ship.item_selected.connect(func(_i): _requote())
	_row(right, "Postage", _ship, 90)
	_ship_include = CheckBox.new()
	_ship_include.text = "Include postage in the price (free shipping)"
	_ship_include.toggled.connect(func(_on): _requote())
	right.add_child(_ship_include)
	_platform = OptionButton.new()
	for p in shop.data.platforms:
		_platform.add_item(p.name)
	_platform.item_selected.connect(func(_i): _requote())
	_row(right, "Selling on", _platform, 90)

	_heading(v, "Price")
	_tier_box = HBoxContainer.new()
	_tier_box.add_theme_constant_override("separation", 12)
	v.add_child(_tier_box)
	_breakdown = _note(v, "")
	var save := Button.new()
	save.text = UI.icon("check") + "  Save as product"
	save.theme_type_variation = "Primary"
	save.pressed.connect(_save_product)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 8)
	v.add_child(sh)
	save.reparent(sh)
	var sell := Button.new()
	sell.text = UI.icon("coin") + "  Log a sale (sweet-spot price)"
	sell.pressed.connect(func():
		if _last_quote.is_empty(): return
		var nm := _q_name.text.strip_edges() if _q_name.text.strip_edges() != "" else "3D print"
		sold.emit(nm, float(_last_quote.tiers[1].price) * int(_qty.value))
		_q_status.text = "Logged the sale in Money.")
	sh.add_child(sell)
	_add_filament_row("PLA", 0.0)


func _add_filament_row(material: String, grams: float) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var o := OptionButton.new()
	var sel := 0
	for i in shop.data.filaments.size():
		var f: Dictionary = shop.data.filaments[i]
		o.add_item("%s  %s/kg" % [f.name, PS.money(float(f.per_kg))])
		o.set_item_metadata(i, f.name)
		if String(f.name).to_lower() == material.to_lower():
			sel = i
	if sel == 0 and material != "" and String(shop.data.filaments[0].name).to_lower() != material.to_lower():
		for i in shop.data.filaments.size():
			if String(shop.data.filaments[i].name).to_lower() in material.to_lower():
				sel = i
	o.selected = sel
	o.item_selected.connect(func(_i): _requote())
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(o)
	var g := _spin(0, 20000, 0.1, grams, "", " g")
	g.value_changed.connect(func(_v): _requote())
	h.add_child(g)
	var x := Button.new()
	x.text = UI.icon("x")
	x.theme_type_variation = "Ghost"
	x.pressed.connect(func(): h.queue_free(); await get_tree().process_frame; _requote())
	h.add_child(x)
	_fil_box.add_child(h)


func _job() -> Dictionary:
	var fils := []
	for h in _fil_box.get_children():
		if h.is_queued_for_deletion():
			continue
		var o: OptionButton = h.get_child(0)
		var g: SpinBox = h.get_child(1)
		if g.value > 0:
			fils.append({"material": String(o.get_item_metadata(o.selected)), "grams": g.value})
	var packs := []
	for k in _pack_checks.keys():
		if _pack_checks[k].button_pressed:
			packs.append(k)
	var adds := []
	for k in _addon_spins.keys():
		if _addon_spins[k].value > 0:
			adds.append([k, int(_addon_spins[k].value)])
	return {"name": _q_name.text.strip_edges(), "filaments": fils, "hours": _hours.value, "labour_min": _labour.value,
		"quantity": int(_qty.value), "packaging": packs, "addons": adds,
		"shipping": String(shop.data.shipping[_ship.selected].name) if _ship.selected >= 0 else "",
		"include_shipping": _ship_include.button_pressed,
		"platform": String(shop.data.platforms[_platform.selected].name) if _platform.selected >= 0 else ""}


func _requote() -> void:
	if _quiet or _tier_box == null:
		return
	var q: Dictionary = shop.quote(_job())
	_last_quote = q
	for c in _tier_box.get_children():
		c.queue_free()
	for i in 3:
		var t: Dictionary = q.tiers[i]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UI.box(Color(UI.COPPER, 0.22) if i == 1 else Color(1, 1, 1, 0.05), 14, UI.COPPER if i == 1 else Color(1, 1, 1, 0.1), 1, 14))
		var cv := VBoxContainer.new()
		card.add_child(cv)
		var n := Label.new()
		n.text = t.name + ("  " + UI.icon("sparkles") if i == 1 else "")
		n.add_theme_color_override("font_color", UI.TEXT_2)
		cv.add_child(n)
		var p := Label.new()
		p.text = PS.money(t.price)
		p.add_theme_font_override("font", UI.bold())
		p.add_theme_font_size_override("font_size", 30)
		cv.add_child(p)
		var pr := Label.new()
		pr.text = "Profit %s  (%d%%)" % [PS.money(t.profit), int(round(t.margin * 100))]
		pr.add_theme_color_override("font_color", Color("86dba8") if t.profit > 0 else Color("ff8a7a"))
		cv.add_child(pr)
		var fe := Label.new()
		fe.text = "Fees %s" % PS.money(t.fees)
		fe.add_theme_font_size_override("font_size", 12)
		fe.add_theme_color_override("font_color", UI.TEXT_3)
		cv.add_child(fe)
		_tier_box.add_child(card)
	var lines := ["True cost per item: %s" % PS.money(q.cost)]
	var parts := []
	for k in q.breakdown.keys():
		if float(q.breakdown[k]) > 0.0005:
			parts.append("%s %s" % [k, PS.money(q.breakdown[k])])
	lines.append("  ".join(parts))
	if q.shipping > 0 and not q.shipping_included:
		lines.append("Customer pays postage on top: %s" % PS.money(q.shipping))
	_breakdown.text = "\n".join(lines)


## Fill the quote from a sliced file. Returns the read result.
func load_file(path: String) -> Dictionary:
	var r: Dictionary = shop.read_sliced(path)
	if not r.get("ok", false):
		_q_status.text = String(r.get("note", "Couldn't read that."))
		return r
	_quiet = true
	_q_name.text = String(r.name).replace("_", " ")
	for c in _fil_box.get_children():
		c.queue_free()
	for f in r.filaments:
		_add_filament_row(String(f.material), float(f.grams))
	_hours.value = float(r.hours)
	var grams := 0.0
	for f in r.filaments:
		grams += float(f.grams)
	var auto: String = shop.auto_shipping(grams)
	for i in shop.data.shipping.size():
		if shop.data.shipping[i].name == auto:
			_ship.selected = i
	_quiet = false
	_q_status.text = "Read %s: %.0f g, %s%s." % [path.get_file(), grams, PS._hrs(r.hours), (", %d plates" % r.plates) if int(r.plates) > 1 else ""]
	await get_tree().process_frame
	_requote()
	return r


func set_manual(material: String, grams: float, hours: float, name := "") -> void:
	_quiet = true
	for c in _fil_box.get_children():
		c.queue_free()
	_add_filament_row(material, grams)
	_hours.value = hours
	if name != "": _q_name.text = name
	_quiet = false
	await get_tree().process_frame
	_requote()


func _use_last_print() -> void:
	var mins := float(Cfg.g("last_print_minutes", 0.0))
	if mins <= 0:
		_q_status.text = "I haven't watched a finished print yet."
		return
	_hours.value = mins / 60.0
	if _q_name.text == "": _q_name.text = String(Cfg.g("last_print_name", ""))
	_q_status.text = "Used the last print's time (%s). Add the grams from the slicer." % PS._hrs(mins / 60.0)


func _save_product() -> void:
	var j := _job()
	if j.name == "":
		_q_status.text = "Give it a name first."
		return
	j.price = _last_quote.tiers[1].price if not _last_quote.is_empty() else 0.0
	j.saved = Time.get_date_string_from_system()
	shop.save_product(j)
	_q_status.text = "Saved \"%s\" at %s." % [j.name, PS.money(j.price)]


# ------------------------------------------------------------------ products

func _build_products() -> void:
	var v := _page("Products")
	_heading(v, "Products")
	_note(v, "Prices are recalculated with your current costs. The saved price is the one you chose when saving.")
	_products = ItemList.new()
	_products.custom_minimum_size = Vector2(0, 420)
	v.add_child(_products)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var load := Button.new()
	load.text = "Open in quote"
	load.pressed.connect(func():
		var sel := _products.get_selected_items()
		if not sel.is_empty(): load_product(shop.data.products[sel[0]]))
	h.add_child(load)
	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func():
		var sel := _products.get_selected_items()
		if not sel.is_empty():
			shop.data.products.remove_at(sel[0])
			shop.save()
			refresh_products())
	h.add_child(del)


func refresh_products() -> void:
	if _products == null:
		return
	_products.clear()
	for p in shop.data.products:
		var q: Dictionary = shop.quote(p)
		_products.add_item("%s   ·   saved %s   ·   now: cost %s, sweet spot %s" % [p.name, PS.money(float(p.get("price", 0))), PS.money(q.cost), PS.money(q.tiers[1].price)])


func load_product(p: Dictionary) -> void:
	_quiet = true
	_q_name.text = String(p.name)
	for c in _fil_box.get_children():
		c.queue_free()
	for f in p.get("filaments", []):
		_add_filament_row(String(f.material), float(f.grams))
	_hours.value = float(p.get("hours", 0))
	_labour.value = float(p.get("labour_min", 10))
	_qty.value = int(p.get("quantity", 1))
	for k in _pack_checks.keys():
		_pack_checks[k].button_pressed = k in p.get("packaging", [])
	for k in _addon_spins.keys():
		_addon_spins[k].value = 0
	for a in p.get("addons", []):
		if _addon_spins.has(a[0]): _addon_spins[a[0]].value = int(a[1])
	for i in shop.data.shipping.size():
		if shop.data.shipping[i].name == p.get("shipping", ""): _ship.selected = i
	_ship_include.button_pressed = bool(p.get("include_shipping", false))
	for i in shop.data.platforms.size():
		if shop.data.platforms[i].name == p.get("platform", ""): _platform.selected = i
	_quiet = false
	tabs.current_tab = 0
	await get_tree().process_frame
	_requote()


# ------------------------------------------------------------------ editable tables

func _table(parent: Node, key: String, cols: Array, height := 220) -> Tree:
	# cols: [[field, title, "text"|"num"], ...]
	var tr := Tree.new()
	tr.columns = cols.size()
	tr.column_titles_visible = true
	tr.hide_root = true
	tr.custom_minimum_size = Vector2(0, height)
	tr.add_theme_color_override("font_color", UI.TEXT)
	tr.add_theme_color_override("title_button_color", UI.TEXT_2)
	tr.add_theme_stylebox_override("panel", UI.box(UI.FIELD, 12, Color(1, 1, 1, 0.1), 1, 6))
	tr.add_theme_stylebox_override("title_button_normal", UI.box(Color(1, 1, 1, 0.04), 6, Color(0, 0, 0, 0), 0, 6))
	tr.add_theme_stylebox_override("selected", UI.box(Color(UI.COPPER, 0.35), 4, Color(0, 0, 0, 0), 0, 2))
	tr.add_theme_stylebox_override("selected_focus", UI.box(Color(UI.COPPER, 0.5), 4, Color(0, 0, 0, 0), 0, 2))
	for i in cols.size():
		tr.set_column_title(i, cols[i][1])
		tr.set_column_expand(i, i == 0)
		if i > 0: tr.set_column_custom_minimum_width(i, 110)
	var fill := func():
		tr.clear()
		var root := tr.create_item()
		for row in shop.data[key]:
			var it := tr.create_item(root)
			for i in cols.size():
				var f: String = cols[i][0]
				var val = row.get(f, "")
				it.set_text(i, str(val) if not (val is Array) else "x".join(val.map(func(x): return str(x))))
				it.set_editable(i, true)
			it.set_metadata(0, row)
	fill.call()
	tr.item_edited.connect(func():
		var it := tr.get_edited()
		var col := tr.get_edited_column()
		var row: Dictionary = it.get_metadata(0)
		var f: String = cols[col][0]
		match cols[col][2]:
			"num": row[f] = it.get_text(col).replace("£", "").replace("%", "").to_float()
			"dims": row[f] = Array(it.get_text(col).split("x")).map(func(x): return int(x))
			_: row[f] = it.get_text(col)
		shop.save()
		_requote())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var add := Button.new()
	add.text = "+ Add"
	add.pressed.connect(func():
		var row := {}
		for c in cols:
			row[c[0]] = 0.0 if c[2] == "num" else ([100, 100, 100] if c[2] == "dims" else "New")
		shop.data[key].append(row)
		shop.save()
		fill.call())
	h.add_child(add)
	var rem := Button.new()
	rem.text = "Remove selected"
	rem.pressed.connect(func():
		var it := tr.get_selected()
		if it:
			shop.data[key].erase(it.get_metadata(0))
			shop.save()
			fill.call())
	h.add_child(rem)
	parent.add_child(tr)
	parent.add_child(h)
	return tr


func _build_costs() -> void:
	var v := _page("Costs")
	_heading(v, "Filament prices")
	_note(v, "What you pay per kilo. Double-click a cell to edit.")
	_table(v, "filaments", [["name", "Filament", "text"], ["per_kg", "£ per kg", "num"]], 240)
	_heading(v, "Running costs")
	var d: Dictionary = shop.data
	var fields := [["pence_per_kwh", "Electricity (p per kWh)", 0, 100, 0.1], ["kwh_per_hour", "Printer power (kWh per hour)", 0, 3, 0.01],
		["machine_per_hour", "Machine wear (£ per hour)", 0, 10, 0.01], ["labour_per_hour", "Your time (£ per hour)", 0, 200, 0.5],
		["default_labour_min", "Default prep and finishing (min)", 0, 600, 1]]
	for fd in fields:
		var s := _spin(fd[2], fd[3], fd[4], float(d[fd[0]]))
		var key: String = fd[0]
		s.value_changed.connect(func(val): d[key] = val; shop.save(); _requote())
		_row(v, fd[1], s, 300)
	var fb := _spin(0, 100, 1, float(d.failure_buffer) * 100.0, "", " %")
	fb.value_changed.connect(func(val): d.failure_buffer = val / 100.0; shop.save(); _requote())
	_row(v, "Failed-print buffer", fb, 300)
	_heading(v, "Price tiers (times your true cost)")
	var names := ["Budget", "Sweet spot", "Premium"]
	for i in 3:
		var s := _spin(1, 20, 0.05, float(d.tiers[i]), "", "x")
		var idx := i
		s.value_changed.connect(func(val): d.tiers[idx] = val; shop.save(); _requote())
		_row(v, names[i], s, 300)
	var charm := CheckBox.new()
	charm.text = "Charm pricing (end prices in .99 / .49)"
	charm.button_pressed = bool(d.charm)
	charm.toggled.connect(func(on): d.charm = on; shop.save(); _requote())
	v.add_child(charm)
	var vat := CheckBox.new()
	vat.text = "I'm VAT registered (add 20% VAT to prices)"
	vat.button_pressed = bool(d.vat_registered)
	vat.toggled.connect(func(on): d.vat_registered = on; shop.save(); _requote())
	v.add_child(vat)


func _build_presets() -> void:
	var v := _page("Packaging")
	_heading(v, "Packaging presets")
	_note(v, "Changes show up in the Quote tab next time the Print Shop opens.")
	_table(v, "packaging", [["name", "Item", "text"], ["cost", "£ each", "num"]], 200)
	_heading(v, "Add-ons")
	_table(v, "addons", [["name", "Add-on", "text"], ["cost", "£ each", "num"]], 180)


func _build_shipping() -> void:
	var v := _page("Shipping")
	_heading(v, "Royal Mail services")
	_note(v, "Prices: %s. Royal Mail changes them a few times a year, so double-check at royalmail.com/prices or ask me to look." % shop.data.get("shipping_checked", ""))
	_table(v, "shipping", [["name", "Service", "text"], ["max_g", "Max g", "num"], ["dims", "Max mm (LxWxH)", "dims"], ["price", "£", "num"]], 340)
	var b := Button.new()
	b.text = UI.icon("web") + "  Ask Rico to check today's Royal Mail prices"
	b.pressed.connect(func(): refresh_rates_requested.emit("shipping"))
	v.add_child(b)


func _build_fees() -> void:
	var v := _page("Selling fees")
	_heading(v, "Where you sell")
	_note(v, "Fees are a % of the sale plus a fixed amount per order. Defaults are rough; check your actual plan, or ask me to look them up.")
	_table(v, "platforms", [["name", "Platform", "text"], ["percent", "% of sale", "num"], ["fixed", "£ per order", "num"]], 260)
	var b := Button.new()
	b.text = UI.icon("web") + "  Ask Rico to check current UK selling fees"
	b.pressed.connect(func(): refresh_rates_requested.emit("fees"))
	v.add_child(b)


# ------------------------------------------------------------------ printer

func _build_printer() -> void:
	var v := _page("Printer")
	_heading(v, "Your Bambu Lab H2D")
	_note(v, "Rico watches prints on your local network (read-only, no cloud). On the printer: Settings > WLAN shows the IP and Access Code; the serial number is under Settings > Device. LAN mode doesn't need to stay on, but the access code changes if you toggle it.")
	for f in [["printer_ip", "Printer IP", "192.168.1.50"], ["printer_serial", "Serial number", "0948..."], ["printer_code", "Access code", "8 digits"]]:
		var e := LineEdit.new()
		e.placeholder_text = f[2]
		e.text = String(Cfg.g(f[0], ""))
		e.custom_minimum_size.x = 260
		if f[0] == "printer_code": e.secret = true
		var key: String = f[0]
		e.text_changed.connect(func(t): Cfg.s(key, t.strip_edges()))
		_row(v, f[1], e, 200)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var c := Button.new()
	c.text = "Connect"
	c.theme_type_variation = "Primary"
	c.pressed.connect(func(): printer_settings_changed.emit())
	h.add_child(c)
	_printer_status = Label.new()
	_printer_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_printer_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_printer_status.add_theme_color_override("font_color", UI.TEXT_2)
	h.add_child(_printer_status)
	_heading(v, "Maintenance")
	_maint_box = VBoxContainer.new()
	_maint_box.add_theme_constant_override("separation", 6)
	v.add_child(_maint_box)


func set_printer_status(t: String) -> void:
	if _printer_status: _printer_status.text = t


func refresh_printer() -> void:
	if _maint_box == null:
		return
	for ch in _maint_box.get_children():
		ch.queue_free()
	var hours := float(Cfg.g("print_hours", 0.0))
	_note(_maint_box, "Total print time Rico has watched: %s" % PS._hrs(hours))
	var done: Dictionary = Cfg.g("maint_done", {})
	for m in MAINTENANCE:
		var since := hours - float(done.get(m.id, 0.0))
		var h := HBoxContainer.new()
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var due := since >= float(m.every)
		l.text = "%s%s   ·   every %d h, %s since" % [UI.icon("alert") + "  " if due else "", m.name, int(m.every), PS._hrs(since)]
		l.add_theme_color_override("font_color", UI.BRASS if due else UI.TEXT)
		h.add_child(l)
		var b := Button.new()
		b.text = "Done"
		var id: String = m.id
		b.pressed.connect(func():
			var d2: Dictionary = Cfg.g("maint_done", {}).duplicate()
			d2[id] = float(Cfg.g("print_hours", 0.0))
			Cfg.s("maint_done", d2)
			refresh_printer())
		h.add_child(b)
		_maint_box.add_child(h)


const MAINTENANCE := [
	{"id": "plate", "name": "Wash the build plate (warm water and dish soap)", "every": 30},
	{"id": "wiper", "name": "Clear the purge chute and check the nozzle wiper", "every": 50},
	{"id": "nozzle", "name": "Inspect the nozzles and hotends for clogs or wear", "every": 150},
	{"id": "rails", "name": "Clean and lubricate the motion rods/rails", "every": 250},
	{"id": "ams", "name": "Dust the AMS feeders and check the PTFE tubes", "every": 300},
	{"id": "belts", "name": "Check belt tension and run calibration", "every": 400},
]
