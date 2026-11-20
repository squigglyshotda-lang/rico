extends Control
## Rico's speech bubble: shows lines with a typewriter effect, and doubles as the chat box.

signal submitted(text: String)
signal mic_pressed
signal closed
signal action(id: String)

const INK := Color("2a1a10")
const PAPER := Color("fffaf0")
const ACCENT := Color("d06d3c")

var panel: PanelContainer
var title_label: Label
var text_label: RichTextLabel
var scroll: ScrollContainer
var actions_box: HBoxContainer
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
var tail_down := true        # tail points down (bubble above Rico)
var _full_text := ""
var _shown := 0.0
var _hide_timer := -1.0
var _cps := 55.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 16
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	title_label = Label.new()
	title_label.text = "RICO"
	title_label.add_theme_color_override("font_color", ACCENT)
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close := Button.new()
	close.text = "x"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.add_theme_color_override("font_color", INK)
	close.add_theme_font_size_override("font_size", 16)
	close.custom_minimum_size = Vector2(26, 22)
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
	text_label.custom_minimum_size = Vector2(300, 0)
	text_label.add_theme_color_override("default_color", INK)
	text_label.add_theme_font_size_override("normal_font_size", 17)
	scroll.add_child(text_label)

	meta_label = Label.new()
	meta_label.add_theme_font_size_override("font_size", 11)
	meta_label.add_theme_color_override("font_color", Color(INK, 0.45))
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta_label.visible = false
	v.add_child(meta_label)

	checks_box = VBoxContainer.new()
	checks_box.add_theme_constant_override("separation", 2)
	checks_box.visible = false
	v.add_child(checks_box)

	details_scroll = ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.visible = false
	var dbg := StyleBoxFlat.new()
	dbg.bg_color = Color("2a1a10")
	dbg.set_corner_radius_all(8)
	dbg.set_content_margin_all(8)
	details_scroll.add_theme_stylebox_override("panel", dbg)
	v.add_child(details_scroll)
	details_label = RichTextLabel.new()
	details_label.fit_content = true
	details_label.scroll_active = false
	details_label.selection_enabled = true
	details_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_label.add_theme_color_override("default_color", Color("ffe9c7"))
	details_label.add_theme_font_size_override("normal_font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "monospace"])
	details_label.add_theme_font_override("normal_font", mono)
	details_scroll.add_child(details_label)

	actions_box = HBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 8)
	v.add_child(actions_box)

	input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	v.add_child(input_row)
	input = LineEdit.new()
	input.placeholder_text = "Say something to Rico..."
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(200, 36)
	input.add_theme_font_size_override("font_size", 16)
	input.add_theme_stylebox_override("normal", _field_box(Color("f3e6cf")))
	input.add_theme_stylebox_override("focus", _field_box(Color("f3e6cf"), ACCENT))
	input.add_theme_color_override("font_color", INK)
	input.add_theme_color_override("font_placeholder_color", Color(INK, 0.45))
	input.add_theme_color_override("caret_color", INK)
	input.text_submitted.connect(_on_submit)
	input_row.add_child(input)
	mic_btn = _button("Mic", "Talk instead of typing (Ctrl+Alt+Space)")
	mic_btn.pressed.connect(func(): mic_pressed.emit())
	input_row.add_child(mic_btn)
	send_btn = _button("Send", "Send (Enter)")
	send_btn.pressed.connect(func(): _on_submit(input.text))
	input_row.add_child(send_btn)

	tail = Control.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.draw.connect(_draw_tail)
	add_child(tail)
	visible = false


func _field_box(bg: Color, border := Color("c9b48f")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 10
	s.content_margin_right = 10
	return s


func _button(label: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(54, 36)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_color_override("font_pressed_color", PAPER)
	b.add_theme_color_override("font_focus_color", PAPER)
	var n := _field_box(ACCENT, INK)
	var hv := _field_box(Color("e2834f"), INK)
	var pr := _field_box(Color("9e4826"), INK)
	var fc := _field_box(ACCENT, Color("ffcf3a"))
	fc.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", fc)
	return b


func _draw_tail() -> void:
	var w := 26.0
	var h := 18.0
	var base_y := 0.0
	var tip_y := h if tail_down else -h
	var pts := PackedVector2Array([Vector2(-w / 2, base_y), Vector2(w / 2, base_y), Vector2(4, tip_y)])
	tail.draw_colored_polygon(pts, PAPER)
	tail.draw_line(Vector2(-w / 2, base_y), Vector2(4, tip_y), INK, 3.0, true)
	tail.draw_line(Vector2(w / 2, base_y), Vector2(4, tip_y), INK, 3.0, true)


## Show a line. timeout <= 0 keeps it up until closed.
func say(text: String, timeout := 6.0, buttons: Array = [], details := "", checklist: Array = []) -> void:
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
		cb.add_theme_color_override("font_color", INK)
		cb.add_theme_color_override("font_hover_color", ACCENT)
		cb.add_theme_color_override("font_pressed_color", INK)
		cb.add_theme_color_override("font_focus_color", INK)
		cb.add_theme_font_size_override("font_size", 15)
		checks_box.add_child(cb)
	_full_text = text
	_shown = 0.0
	text_label.text = text
	text_label.visible_characters = 0
	typing = true
	_cps = clampf(text.length() / 2.5, 45.0, 140.0)
	_set_buttons(buttons)
	input_row.visible = chat_mode
	visible = true
	_hide_timer = timeout if timeout > 0 else -1.0
	_relayout()


func open_chat(prompt_text := "") -> void:
	chat_mode = true
	input_row.visible = true
	if prompt_text != "":
		say(prompt_text, -1)
	elif not visible:
		say("What do you want?", -1)
	_hide_timer = -1.0
	visible = true
	input.grab_focus()
	_relayout()


func set_listening(on: bool) -> void:
	mic_btn.text = "Stop" if on else "Mic"


func hide_bubble() -> void:
	visible = false
	chat_mode = false
	typing = false
	_set_buttons([])
	input.release_focus()


func set_meta_text(t: String) -> void:
	meta_label.text = t
	meta_label.visible = t != ""
	_relayout()


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
			b.text = "Hide details" if details_scroll.visible else "Show details"
	_relayout()


func is_busy_with_user() -> bool:
	return visible and (chat_mode or not actions_box.get_children().is_empty())


func _set_buttons(buttons: Array) -> void:
	for c in actions_box.get_children():
		c.queue_free()
	actions_box.visible = not buttons.is_empty()
	var first: Button = null
	for b in buttons:
		var btn := _button(b[1], "")
		var id: String = b[0]
		btn.set_meta("id", id)
		btn.pressed.connect(func(): action.emit(id))
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
	if Input.is_action_just_pressed("ui_cancel") and visible:
		hide_bubble()
		closed.emit()


func _relayout() -> void:
	var content_h := text_label.get_content_height()
	scroll.custom_minimum_size = Vector2(300, minf(content_h, 280.0))
	if details_scroll.visible:
		details_scroll.custom_minimum_size = Vector2(300, minf(details_label.get_content_height() + 16, 220.0))
	panel.reset_size()
	size = panel.size


## Place the bubble near Rico (anchor = top of his head in window coords).
func place(anchor_top: Vector2, anchor_bottom: Vector2, area: Rect2) -> void:
	_relayout()
	var s := panel.size
	var gap := 22.0
	var pos := Vector2(anchor_top.x - s.x * 0.5 + 40, anchor_top.y - gap - s.y)
	tail_down = true
	if pos.y < area.position.y + 4:
		pos.y = anchor_bottom.y + gap
		tail_down = false
	pos.x = clampf(pos.x, area.position.x + 6, area.end.x - s.x - 6)
	pos.y = clampf(pos.y, area.position.y + 4, area.end.y - s.y - 4)
	position = pos.round()
	tail_x = clampf(anchor_top.x - pos.x, 28.0, s.x - 28.0)
	tail.position = Vector2(tail_x, s.y - 1.5 if tail_down else 1.5)
	tail.queue_redraw()


func rect_with_tail() -> Rect2:
	return Rect2(position - Vector2(10, 24), size + Vector2(20, 48))
