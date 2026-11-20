extends Control
## Rico's speech bubble in the smoked-glass style: lines type out, cards for
## approvals and alerts, a typing indicator, and pop-in / pop-out motion.

const UI := preload("res://scripts/ui.gd")

signal submitted(text: String)
signal mic_pressed
signal closed
signal action(id: String)

const WIDTH := 330.0
const BUTTON_ICONS := {"allow": "check", "deny": "x", "details": "chevron", "done": "check", "snooze5": "clock", "snooze15": "clock",
	"brain_dl": "download", "temps_admin": "cpu", "dismiss": "", "close": "x"}

var panel: PanelContainer
var head_icon: Label
var title_label: Label
var text_label: RichTextLabel
var scroll: ScrollContainer
var dots: Control
var actions_box: HFlowContainer
var meta_label: Label
var checks_box: VBoxContainer
var details_label: RichTextLabel
var details_scroll: ScrollContainer
var input_row: HBoxContainer
var input: LineEdit
var mic_btn: Button
var send_btn: Button
var tail: Control

var chat_mode := false
var typing := false
var tail_x := 40.0
var tail_down := true
var _full_text := ""
var _shown := 0.0
var _hide_timer := -1.0
var _cps := 55.0
var _hiding := false
var _out_tween: Tween
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.theme()
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.glass_panel(18, 14))
	UI.add_sheen(panel)
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head_icon = Label.new()
	head_icon.add_theme_color_override("font_color", UI.COPPER)
	head_icon.add_theme_font_size_override("font_size", 16)
	head.add_child(head_icon)
	title_label = Label.new()
	title_label.add_theme_color_override("font_color", UI.TEXT_2)
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close := Button.new()
	close.text = UI.icon("x")
	close.theme_type_variation = "Ghost"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.add_theme_font_size_override("font_size", 15)
	close.custom_minimum_size = Vector2(26, 24)
	close.pressed.connect(func(): hide_bubble(); closed.emit())
	head.add_child(close)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	text_label = RichTextLabel.new()
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.selection_enabled = true
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.custom_minimum_size = Vector2(WIDTH, 0)
	text_label.add_theme_color_override("default_color", UI.TEXT)
	text_label.add_theme_font_size_override("normal_font_size", 17)
	text_label.add_theme_constant_override("line_separation", 3)
	scroll.add_child(text_label)

	dots = Control.new()
	dots.custom_minimum_size = Vector2(64, 22)
	dots.draw.connect(_draw_dots)
	dots.visible = false
	v.add_child(dots)

	checks_box = VBoxContainer.new()
	checks_box.add_theme_constant_override("separation", 2)
	checks_box.visible = false
	v.add_child(checks_box)

	details_scroll = ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.visible = false
	details_scroll.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.35), 10, Color(1, 1, 1, 0.08), 1, 10))
	v.add_child(details_scroll)
	details_label = RichTextLabel.new()
	details_label.fit_content = true
	details_label.scroll_active = false
	details_label.selection_enabled = true
	details_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_label.add_theme_color_override("default_color", UI.BRASS)
	details_label.add_theme_font_size_override("normal_font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "monospace"])
	details_label.add_theme_font_override("normal_font", mono)
	details_scroll.add_child(details_label)

	actions_box = HFlowContainer.new()
	actions_box.add_theme_constant_override("h_separation", 8)
	actions_box.add_theme_constant_override("v_separation", 8)
	v.add_child(actions_box)

	meta_label = Label.new()
	meta_label.add_theme_font_size_override("font_size", 11)
	meta_label.add_theme_color_override("font_color", UI.TEXT_3)
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta_label.visible = false
	v.add_child(meta_label)

	input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	v.add_child(input_row)
	input = LineEdit.new()
	input.placeholder_text = "Ask Rico anything..."
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(200, 40)
	input.add_theme_font_size_override("font_size", 16)
	input.text_submitted.connect(_on_submit)
	input_row.add_child(input)
	mic_btn = _icon_button("mic", "Talk instead of typing (Ctrl+Alt+Space)")
	mic_btn.pressed.connect(func(): mic_pressed.emit())
	input_row.add_child(mic_btn)
	send_btn = _icon_button("send", "Send (Enter)", true)
	send_btn.pressed.connect(func(): _on_submit(input.text))
	input_row.add_child(send_btn)

	tail = Control.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.draw.connect(_draw_tail)
	add_child(tail)
	visible = false


func _icon_button(icon_name: String, tip: String, primary := false) -> Button:
	var b := Button.new()
	b.text = UI.icon(icon_name)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(40, 40)
	b.add_theme_font_size_override("font_size", 19)
	if primary:
		b.theme_type_variation = "Primary"
	UI.juice(b)
	return b


func _draw_tail() -> void:
	var w := 24.0
	var h := 14.0
	var tip_y := h if tail_down else -h
	var pts := PackedVector2Array([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(2, tip_y)])
	tail.draw_colored_polygon(pts, UI.GLASS)
	tail.draw_line(Vector2(-w / 2, 0), Vector2(2, tip_y), UI.EDGE, 1.0, true)
	tail.draw_line(Vector2(w / 2, 0), Vector2(2, tip_y), UI.EDGE, 1.0, true)


func _draw_dots() -> void:
	for i in 3:
		var ph := _t * 7.0 - i * 0.7
		var y := 11.0 - maxf(0.0, sin(ph)) * 6.0
		var a := 0.45 + 0.55 * maxf(0.0, sin(ph))
		dots.draw_circle(Vector2(14 + i * 17, y), 4.5, Color(UI.COPPER_HI, a), true, -1.0, true)


## Show a line. timeout <= 0 keeps it up until closed.
func say(text: String, timeout := 6.0, buttons: Array = [], details := "", checklist: Array = []) -> void:
	var was_open := is_open()
	if _out_tween and _out_tween.is_valid():
		_out_tween.kill()
	_hiding = false
	modulate.a = 1.0
	scale = Vector2.ONE
	details_label.text = details
	details_scroll.visible = false
	meta_label.visible = false
	for c in checks_box.get_children():
		c.queue_free()
	checks_box.visible = not checklist.is_empty()
	for item in checklist:
		var cb := CheckBox.new()
		cb.text = item[1]
		cb.button_pressed = item[2]
		cb.add_theme_font_size_override("font_size", 15)
		checks_box.add_child(cb)
	_set_header(buttons)
	var thinking := text == "..."
	dots.visible = thinking
	scroll.visible = not thinking
	_full_text = text
	_shown = 0.0
	text_label.text = text
	text_label.visible_characters = 0
	typing = not thinking
	_cps = clampf(text.length() / 2.5, 45.0, 140.0)
	_set_buttons(buttons)
	input_row.visible = chat_mode
	visible = true
	_hide_timer = timeout if timeout > 0 else -1.0
	_relayout()
	if not was_open:
		pivot_offset = Vector2(tail_x, size.y if tail_down else 0.0)
		UI.pop_in(self)


func _set_header(buttons: Array) -> void:
	var ids := buttons.map(func(b): return b[0])
	if "allow" in ids:
		head_icon.text = UI.icon("shield")
		head_icon.add_theme_color_override("font_color", UI.BRASS)
		title_label.text = "Rico needs your OK"
	elif "done" in ids:
		head_icon.text = UI.icon("bell")
		head_icon.add_theme_color_override("font_color", UI.BRASS)
		title_label.text = "Reminder"
	else:
		head_icon.text = UI.icon("sparkles")
		head_icon.add_theme_color_override("font_color", UI.COPPER)
		title_label.text = "Rico"


func open_chat(prompt_text := "") -> void:
	chat_mode = true
	input_row.visible = true
	if prompt_text != "":
		say(prompt_text, -1)
	elif not is_open():
		say("What do you want?", -1)
	_hide_timer = -1.0
	input.grab_focus()
	_relayout()


func set_listening(on: bool) -> void:
	mic_btn.text = UI.icon("stop") if on else UI.icon("mic")
	mic_btn.theme_type_variation = "Primary" if on else ""


func set_meta_text(t: String) -> void:
	meta_label.text = t
	meta_label.visible = t != ""
	_relayout()


func is_open() -> bool:
	return visible and not _hiding


func hide_bubble() -> void:
	chat_mode = false
	typing = false
	input.release_focus()
	if not visible or _hiding:
		return
	_hiding = true
	pivot_offset = Vector2(tail_x, size.y if tail_down else 0.0)
	_out_tween = create_tween().set_parallel(true)
	_out_tween.tween_property(self, "modulate:a", 0.0, 0.13)
	_out_tween.tween_property(self, "scale", Vector2.ONE * 0.9, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_out_tween.chain().tween_callback(func():
		visible = false
		_hiding = false
		modulate.a = 1.0
		scale = Vector2.ONE
		_set_buttons([]))


func is_busy_with_user() -> bool:
	return is_open() and (chat_mode or not actions_box.get_children().is_empty())


func get_checks() -> Array:
	var out := []
	for c in checks_box.get_children():
		if not c.is_queued_for_deletion():
			out.append(c.button_pressed)
	return out


func toggle_details() -> void:
	details_scroll.visible = not details_scroll.visible
	for b in actions_box.get_children():
		if b is Button and b.get_meta("id", "") == "details":
			b.text = ("Hide details " if details_scroll.visible else "Details ") + UI.icon("chevron")
	_relayout()


func _set_buttons(buttons: Array) -> void:
	for c in actions_box.get_children():
		c.queue_free()
	actions_box.visible = not buttons.is_empty()
	var first: Button = null
	for i in buttons.size():
		var b: Array = buttons[i]
		var id: String = b[0]
		var btn := Button.new()
		var ic: String = BUTTON_ICONS.get(id, "x" if id.begins_with("close:") else "")
		if id == "details":
			btn.text = "Details " + UI.icon("chevron")
			btn.theme_type_variation = "Ghost"
		else:
			btn.text = (UI.icon(ic) + "  " if ic != "" else "") + String(b[1])
			if i == 0:
				btn.theme_type_variation = "Primary"
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size.y = 38
		btn.set_meta("id", id)
		btn.pressed.connect(func(): action.emit(id))
		UI.juice(btn)
		actions_box.add_child(btn)
		if first == null:
			first = btn
	if first:
		first.call_deferred("grab_focus")


func _on_submit(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	input.clear()
	submitted.emit(text)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if dots.visible:
		dots.queue_redraw()
	if typing:
		_shown += delta * _cps
		text_label.visible_characters = int(_shown)
		if _shown >= _full_text.length():
			typing = false
			text_label.visible_characters = -1
		_relayout()
	elif _hide_timer > 0 and not chat_mode:
		_hide_timer -= delta
		if _hide_timer <= 0:
			hide_bubble()
	if Input.is_action_just_pressed("ui_cancel") and is_open():
		hide_bubble()
		closed.emit()


func _relayout() -> void:
	var w := 96.0 if dots.visible and not chat_mode and actions_box.get_child_count() == 0 else WIDTH
	text_label.custom_minimum_size.x = w
	var content_h := text_label.get_content_height()
	scroll.custom_minimum_size = Vector2(w, minf(content_h, 300.0))
	if details_scroll.visible:
		details_scroll.custom_minimum_size = Vector2(w, minf(details_label.get_content_height() + 20, 220.0))
	title_label.visible = w > 100
	panel.reset_size()
	size = panel.size


## Place the bubble near Rico (anchor = top of his head in window coords).
func place(anchor_top: Vector2, anchor_bottom: Vector2, area: Rect2) -> void:
	_relayout()
	var s := panel.size
	var gap := 20.0
	var pos := Vector2(anchor_top.x - s.x * 0.5 + 40, anchor_top.y - gap - s.y)
	tail_down = true
	if pos.y < area.position.y + 4:
		pos.y = anchor_bottom.y + gap
		tail_down = false
	pos.x = clampf(pos.x, area.position.x + 8, area.end.x - s.x - 8)
	pos.y = clampf(pos.y, area.position.y + 4, area.end.y - s.y - 4)
	position = pos.round()
	tail_x = clampf(anchor_top.x - pos.x, 28.0, s.x - 28.0)
	tail.position = Vector2(tail_x, s.y - 1.0 if tail_down else 1.0)
	tail.queue_redraw()


func rect_with_tail() -> Rect2:
	return Rect2(position - Vector2(24, 24), size + Vector2(48, 56))
