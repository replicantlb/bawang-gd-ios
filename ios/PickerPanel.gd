extends PopupPanel

signal applied

const MobileLayout = preload("res://ios_mobile_layout.gd")

var preferred_size := Vector2(930, 540)
var content_scroll: ScrollContainer
var apply_button: Button
var _last_available := Rect2()
var modal_canvas: CanvasLayer
var footer: HBoxContainer


static func make_button(title: String, width: float = 100) -> Button:
	var button = Button.new()
	button.text = title
	button.rect_min_size = Vector2(width, 48)
	button.add_font_override("font", Global.get_font(25))
	return button


func build_layout(title: String, scroll_body := true) -> VBoxContainer:
	popup_exclusive = true
	var colors = StyleBoxFlat.new()
	colors.bg_color = Color("28231f")
	colors.border_color = Color("b79a6b")
	colors.set_border_width_all(2)
	colors.set_corner_radius_all(8)
	colors.content_margin_left = 16
	colors.content_margin_right = 16
	colors.content_margin_top = 14
	colors.content_margin_bottom = 14
	add_stylebox_override("panel", colors)
	var fonts = Theme.new()
	fonts.default_font = Global.get_font(25)
	theme = fonts
	connect("popup_hide", self, "_dismiss_keyboard")
	connect("popup_hide", self, "queue_free")
	var layout = VBoxContainer.new()
	layout.add_constant_override("separation", 8)
	add_child(layout)
	layout.anchor_right = 1.0
	layout.anchor_bottom = 1.0
	layout.margin_left = 16
	layout.margin_top = 14
	layout.margin_right = -16
	layout.margin_bottom = -14
	var heading = Label.new()
	heading.text = title
	heading.add_font_override("font", Global.get_font(30))
	layout.add_child(heading)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_constant_override("separation", 8)
	if scroll_body:
		content_scroll = ScrollContainer.new()
		content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content_scroll.scroll_horizontal_enabled = false
		content_scroll.scroll_deadzone = 6
		content_scroll.follow_focus = true
		layout.add_child(content_scroll)
		content_scroll.add_child(body)
	else:
		layout.add_child(body)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGN_END
	footer.add_constant_override("separation", 12)
	layout.add_child(footer)
	var cancel = make_button("取消")
	apply_button = make_button("确认选择", 150)
	footer.add_child(cancel)
	footer.add_child(apply_button)
	cancel.connect("pressed", self, "hide")
	apply_button.connect("pressed", self, "emit_signal", ["applied"])
	return body


func show_adaptive(size: Vector2) -> void:
	preferred_size = size
	if modal_canvas == null:
		var host = get_parent()
		modal_canvas = CanvasLayer.new()
		modal_canvas.layer = 100
		host.add_child(modal_canvas)
		host.remove_child(self)
		modal_canvas.add_child(self)
		connect("popup_hide", modal_canvas, "queue_free")
	popup_centered(size)
	_last_available = Rect2()
	_fit_to_visible_area()
	set_process(true)


func _process(_delta: float) -> void:
	if visible:
		_fit_to_visible_area()


func _fit_to_visible_area() -> void:
	var available = MobileLayout.available_area(get_viewport(), 12.0, true)
	if available.size.x <= 0 or available.size.y <= 0:
		return
	var target_size = Vector2(min(preferred_size.x, available.size.x), min(preferred_size.y, available.size.y))
	var target_position = available.position + Vector2(max(0, (available.size.x - target_size.x) / 2), max(0, (available.size.y - target_size.y) / 2))
	# Containers may briefly grow a popup while wrapped text is first laid out.
	# Re-fit that size once minimums settle, even when the viewport is unchanged.
	if available == _last_available and rect_size.distance_to(target_size) < 0.5 and rect_position.distance_to(target_position) < 0.5:
		return
	_last_available = available
	rect_size = target_size
	rect_position = available.position + Vector2(max(0, (available.size.x - rect_size.x) / 2), max(0, (available.size.y - rect_size.y) / 2))


func _dismiss_keyboard() -> void:
	var owner = get_focus_owner()
	if owner != null:
		if not is_a_parent_of(owner):
			return
		owner.release_focus()
	OS.hide_virtual_keyboard()
