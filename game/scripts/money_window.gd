extends Window
## Money: budget overview, transactions, categories, bills and subscriptions, CSV import.
## 100% local. Nothing here is ever sent anywhere.

const UI := preload("res://scripts/ui.gd")

var money: Node
var reminders: Node
var tabs: TabContainer
var _nav_buttons: Array = []
var _overview: VBoxContainer
var _tx_tree: Tree
var _bills_box: VBoxContainer
var _import_status: Label
var _dialog: FileDialog
var _month := ""


func _init() -> void:
	title = "Rico's Money (stays on this PC)"
	size = Vector2i(960, 700)
	min_size = Vector2i(820, 560)
	visible = false
	close_requested.connect(hide)
	files_dropped.connect(func(files):
		for f in files:
			if String(f).get_extension().to_lower() == "csv":
				import_file(f))


func build() -> void:
	theme = UI.theme()
	_month = money.this_month()
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
	brand.text = UI.icon("coin") + "  Money"
	brand.add_theme_font_override("font", UI.bold())
	brand.add_theme_font_size_override("font_size", 21)
	nav.add_child(brand)
	var lock := Label.new()
	lock.text = "Stays on this PC. No AI, no internet."
	lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lock.add_theme_font_size_override("font_size", 12)
	lock.add_theme_color_override("font_color", UI.TEXT_3)
	nav.add_child(lock)
	var sp := Control.new()
	sp.custom_minimum_size.y = 10
	nav.add_child(sp)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + m, 22)
	root.add_child(margin)
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	margin.add_child(tabs)

	_overview = _page("Overview")
	_build_transactions()
	_build_budget()
	_build_bills()
	_build_import()
	var icons := ["activity", "notes", "sliders", "bell", "download"]
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
	tabs.tab_changed.connect(_on_tab)
	_dialog = FileDialog.new()
	_dialog.use_native_dialog = true
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.filters = PackedStringArray(["*.csv ; Bank statement CSV"])
	_dialog.file_selected.connect(import_file)
	add_child(_dialog)
	money.changed.connect(func(): if visible: _on_tab(tabs.current_tab))
	_on_tab(0)


func _on_tab(cur: int) -> void:
	for i in _nav_buttons.size():
		var b: Button = _nav_buttons[i]
		if i == cur:
			b.add_theme_stylebox_override("normal", UI.box(Color(UI.COPPER, 0.9), 10, Color(1, 1, 1, 0.15), 1, 6))
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_color_override("font_color")
	match cur:
		0: _refresh_overview()
		1: _refresh_tx()
		3: _refresh_bills()


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


# ------------------------------------------------------------------ overview

func _refresh_overview() -> void:
	for c in _overview.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	_overview.add_child(head)
	var t := Label.new()
	t.text = _month_label(_month)
	t.add_theme_font_override("font", UI.bold())
	t.add_theme_font_size_override("font_size", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	for d in [[-1, UI.icon("chevron") + " Previous"], [1, "Next " + UI.icon("chevron")]]:
		var b := Button.new()
		b.text = "Previous" if d[0] < 0 else "Next"
		var step: int = d[0]
		b.pressed.connect(func(): _month = _shift_month(_month, step); _refresh_overview())
		head.add_child(b)
	var sp: Dictionary = money.spending(_month)
	var total := 0.0
	for v in sp.values():
		total += v
	var budget := 0.0
	for c in money.data.categories:
		budget += float(c.budget)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	_overview.add_child(cards)
	for card in [["Spent", "£%.2f" % total], ["Budget", "£%.0f" % budget if budget > 0 else "Not set"], ["Left", ("£%.2f" % (budget - total)) if budget > 0 else "-"], ["Money in", "£%.2f" % money.income(_month)]]:
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.05), 14, Color(1, 1, 1, 0.1), 1, 14))
		var v := VBoxContainer.new()
		pc.add_child(v)
		var a := Label.new()
		a.text = card[0]
		a.add_theme_color_override("font_color", UI.TEXT_2)
		v.add_child(a)
		var b := Label.new()
		b.text = card[1]
		b.add_theme_font_override("font", UI.bold())
		b.add_theme_font_size_override("font_size", 24)
		if card[0] == "Left" and budget > 0 and budget - total < 0:
			b.add_theme_color_override("font_color", Color("ff8a7a"))
		v.add_child(b)
		cards.add_child(pc)
	_heading(_overview, "By category")
	var cats = money.data.categories.filter(func(c): return not c.name in ["Income", "Transfers"] and (float(c.budget) > 0 or sp.has(c.name)))
	if cats.is_empty():
		_note(_overview, "Nothing yet. Import a bank CSV, or tell Rico \"spent £12 on lunch\".")
	for c in cats:
		var spent := float(sp.get(c.name, 0.0))
		var b := float(c.budget)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var l := Label.new()
		l.text = "%s   £%.2f%s" % [c.name, spent, (" of £%.0f" % b) if b > 0 else ""]
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		bar.max_value = maxf(b, spent) if b > 0 else maxf(spent, 1.0)
		bar.value = spent
		var over := b > 0 and spent > b
		bar.add_theme_stylebox_override("background", UI.box(Color(1, 1, 1, 0.07), 5, Color(0, 0, 0, 0), 0, 0))
		bar.add_theme_stylebox_override("fill", UI.box(Color("ff8a7a") if over else (UI.COPPER if b > 0 else Color(1, 1, 1, 0.3)), 5, Color(0, 0, 0, 0), 0, 0))
		row.add_child(bar)
		_overview.add_child(row)


static func _month_label(m: String) -> String:
	var names := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	return "%s %s" % [names[int(m.substr(5, 2)) - 1], m.left(4)]


static func _shift_month(m: String, d: int) -> String:
	var y := int(m.left(4))
	var mo := int(m.substr(5, 2)) + d
	while mo < 1:
		mo += 12; y -= 1
	while mo > 12:
		mo -= 12; y += 1
	return "%04d-%02d" % [y, mo]


# ------------------------------------------------------------------ transactions

func _build_transactions() -> void:
	var v := _page("Transactions")
	_heading(v, "Transactions")
	_note(v, "Double-click a category to change it. Rico remembers the merchant for next time.")
	_tx_tree = Tree.new()
	_tx_tree.columns = 4
	_tx_tree.column_titles_visible = true
	_tx_tree.hide_root = true
	_tx_tree.custom_minimum_size = Vector2(0, 480)
	for i in 4:
		_tx_tree.set_column_title(i, ["Date", "Description", "Amount", "Category"][i])
		_tx_tree.set_column_expand(i, i == 1)
		if i != 1: _tx_tree.set_column_custom_minimum_width(i, 120)
	_tx_tree.add_theme_stylebox_override("panel", UI.box(UI.FIELD, 12, Color(1, 1, 1, 0.1), 1, 6))
	_tx_tree.add_theme_color_override("font_color", UI.TEXT)
	_tx_tree.add_theme_stylebox_override("selected", UI.box(Color(UI.COPPER, 0.35), 4, Color(0, 0, 0, 0), 0, 2))
	_tx_tree.add_theme_stylebox_override("selected_focus", UI.box(Color(UI.COPPER, 0.5), 4, Color(0, 0, 0, 0), 0, 2))
	_tx_tree.item_edited.connect(func():
		var it := _tx_tree.get_edited()
		var tx: Dictionary = it.get_metadata(0)
		var cats = money.data.categories.map(func(c): return c.name)
		money.set_category(tx, cats[int(it.get_range(3))]))
	v.add_child(_tx_tree)
	var del := Button.new()
	del.text = "Delete selected"
	del.pressed.connect(func():
		var it := _tx_tree.get_selected()
		if it:
			money.data.tx.erase(it.get_metadata(0))
			money.save())
	v.add_child(del)


func _refresh_tx() -> void:
	_tx_tree.clear()
	var root := _tx_tree.create_item()
	var cats = money.data.categories.map(func(c): return c.name)
	var list: Array = money.data.tx.duplicate()
	list.sort_custom(func(a, b): return String(a.date) > String(b.date))
	for tx in list.slice(0, 600):
		var it := _tx_tree.create_item(root)
		it.set_text(0, String(tx.date))
		it.set_text(1, String(tx.desc))
		it.set_text(2, ("+£%.2f" if float(tx.amount) > 0 else "-£%.2f") % absf(float(tx.amount)))
		it.set_custom_color(2, Color("86dba8") if float(tx.amount) > 0 else UI.TEXT)
		it.set_cell_mode(3, TreeItem.CELL_MODE_RANGE)
		it.set_text(3, ",".join(cats))
		it.set_range(3, maxi(0, cats.find(tx.cat)))
		it.set_editable(3, true)
		it.set_metadata(0, tx)


# ------------------------------------------------------------------ budget

func _build_budget() -> void:
	var v := _page("Budget")
	_heading(v, "Monthly budget")
	_note(v, "Set a monthly limit per category (0 = just track it). Double-click to edit.")
	var tr := Tree.new()
	tr.columns = 2
	tr.column_titles_visible = true
	tr.hide_root = true
	tr.custom_minimum_size = Vector2(0, 460)
	tr.set_column_title(0, "Category")
	tr.set_column_title(1, "£ per month")
	tr.set_column_expand(1, false)
	tr.set_column_custom_minimum_width(1, 140)
	tr.add_theme_stylebox_override("panel", UI.box(UI.FIELD, 12, Color(1, 1, 1, 0.1), 1, 6))
	tr.add_theme_color_override("font_color", UI.TEXT)
	var fill := func():
		tr.clear()
		var root := tr.create_item()
		for c in money.data.categories:
			var it := tr.create_item(root)
			it.set_text(0, String(c.name))
			it.set_text(1, "%.0f" % float(c.budget))
			it.set_editable(0, true)
			it.set_editable(1, true)
			it.set_metadata(0, c)
	fill.call()
	tr.item_edited.connect(func():
		var it := tr.get_edited()
		var c: Dictionary = it.get_metadata(0)
		c.name = it.get_text(0)
		c.budget = it.get_text(1).replace("£", "").to_float()
		money.save())
	v.add_child(tr)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var add := Button.new()
	add.text = "+ Add category"
	add.pressed.connect(func(): money.data.categories.append({"name": "New category", "budget": 0.0}); money.save(); fill.call())
	h.add_child(add)


# ------------------------------------------------------------------ bills

func _build_bills() -> void:
	var v := _page("Bills")
	_heading(v, "Bills and subscriptions")
	_note(v, "Rico reminds you the day before each one is due.")
	_bills_box = VBoxContainer.new()
	_bills_box.add_theme_constant_override("separation", 6)
	v.add_child(_bills_box)
	_heading(v, "Add one")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var n := LineEdit.new()
	n.placeholder_text = "Netflix"
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var a := SpinBox.new()
	a.max_value = 5000
	a.step = 0.01
	a.prefix = "£"
	h.add_child(a)
	var d := SpinBox.new()
	d.min_value = 1
	d.max_value = 28
	d.prefix = "day "
	h.add_child(d)
	var cat := OptionButton.new()
	cat.add_item("Subscriptions")
	cat.add_item("Bills")
	h.add_child(cat)
	var b := Button.new()
	b.text = "Add"
	b.theme_type_variation = "Primary"
	b.pressed.connect(func():
		if n.text.strip_edges() != "":
			money.add_bill(n.text.strip_edges(), a.value, int(d.value), cat.get_item_text(cat.selected))
			n.clear())
	h.add_child(b)


func _refresh_bills() -> void:
	for c in _bills_box.get_children():
		c.queue_free()
	var total := 0.0
	for bill in money.data.bills:
		total += float(bill.amount)
		var h := HBoxContainer.new()
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s  %s   £%.2f a month   ·   next %s" % [UI.icon("bell"), bill.name, float(bill.amount), money.next_due(bill)]
		h.add_child(l)
		var x := Button.new()
		x.text = "Remove"
		x.pressed.connect(func(): money.data.bills.erase(bill); money.save())
		h.add_child(x)
		_bills_box.add_child(h)
	if money.data.bills.is_empty():
		_note(_bills_box, "None yet.")
	else:
		_note(_bills_box, "Total: £%.2f a month (£%.0f a year)." % [total, total * 12])
	var found: Array = money.detect_subscriptions()
	if not found.is_empty():
		_heading(_bills_box, "Looks like regular payments")
		for f in found.slice(0, 10):
			var h := HBoxContainer.new()
			var l := Label.new()
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.text = "%s   about £%.2f a month, seen in %d months" % [f.name, f.amount, f.months]
			l.add_theme_color_override("font_color", UI.TEXT_2)
			h.add_child(l)
			var add := Button.new()
			add.text = "Track it"
			add.pressed.connect(func(): money.add_bill(f.name, f.amount, f.day, "Subscriptions"))
			h.add_child(add)
			_bills_box.add_child(h)


# ------------------------------------------------------------------ import

func _build_import() -> void:
	var v := _page("Import")
	_heading(v, "Import a bank statement")
	_note(v, "Download a CSV statement from your bank's website or app, then drop it on this window (or on Rico). Works with most UK banks. Duplicates are skipped, and nothing leaves your PC.")
	var b := Button.new()
	b.text = UI.icon("folder") + "  Choose CSV file"
	b.theme_type_variation = "Primary"
	b.pressed.connect(func(): _dialog.popup_centered(Vector2i(900, 600)))
	v.add_child(b)
	_import_status = _note(v, "")


func import_file(path: String) -> Dictionary:
	var r: Dictionary = money.import_csv(path)
	if _import_status:
		_import_status.text = ("Imported %d transactions (%d already there)." % [r.added, r.skipped]) if r.ok else String(r.note)
	return r
