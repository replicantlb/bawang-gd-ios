extends "res://windows/menu/pnlOthers.gd"

const StorageManager = preload("res://ios_storage_manager.gd")
const StorageService = preload("res://ios_storage_service.gd")
const TrialArena = preload("res://ios_trial_arena.gd")
const PrisonRoster = preload("res://ios_prison_roster.gd")
const RulerPersonalityPanel = preload("res://ios_ruler_personality_panel.gd")
const MobileLayout = preload("res://ios_mobile_layout.gd")
var storage_service = StorageService.new()
var storage_panel: PopupPanel
var trial_panel: PopupPanel
var prisoner_panel: PopupPanel
var personality_panel: PopupPanel
var _input_shield: Control


func _ready() -> void:
	storage_service.ensure_directories()
	var button = $gv/blank
	button.text = "存档与补丁"
	button.disabled = false
	var reference = $gv/btnData
	button.add_font_override("font", reference.get_font("font"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_stylebox_override(state, reference.get_stylebox(state))
	button.add_color_override("font_color", Color.white)
	button.connect("pressed", self, "_open_storage")
	if not button in buttons:
		buttons.push_front(button)
	_add_entry("战斗试炼场", "_open_trial", reference)
	_add_entry("全势力俘虏", "_open_prisoners", reference)
	_add_entry("君主性格", "_open_personalities", reference)
	buttons = []
	for child in $gv.get_children():
		if child is Button:
			buttons.append(child)
	$gv.columns = 3
	$gv.add_constant_override("vseparation", 12)
	$gv.add_constant_override("hseparation", 16)
	$Label.hide()
	_input_shield = Control.new()
	_input_shield.name = "MenuInputShield"
	_input_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_shield.focus_mode = Control.FOCUS_NONE
	add_child(_input_shield)
	move_child(_input_shield, 0)
	connect("visibility_changed", self, "_fit_menu")
	get_viewport().connect("size_changed", self, "_fit_menu")
	_fit_menu()


func _fit_menu() -> void:
	var area = MobileLayout.available_area(get_viewport(), 12, true)
	rect_size = Vector2(min(760, area.size.x), min(240, area.size.y))
	rect_global_position = area.position + (area.size - rect_size) * 0.5
	for edge in ["anchor_left", "anchor_right", "anchor_top", "anchor_bottom"]:
		$gv.set(edge, 0)
	$gv.rect_position = Vector2(24, 24)
	$gv.rect_size = rect_size - Vector2(48, 48)
	if is_instance_valid(_input_shield):
		var visible_area = get_viewport().get_visible_rect()
		_input_shield.rect_global_position = visible_area.position
		_input_shield.rect_size = visible_area.size


func move_up():
	_move_grid(0, -1)


func move_down():
	_move_grid(0, 1)


func move_left():
	_move_grid(-1, 0)


func move_right():
	_move_grid(1, 0)


func _move_grid(dx: int, dy: int) -> void:
	if buttons.empty():
		return
	var columns: int = $gv.columns
	var rows = int(ceil(buttons.size() / float(columns)))
	var current = int(clamp(cursorIndex, 0, buttons.size() - 1))
	var x = current % columns
	var y = int(current / columns)
	for _step in range(buttons.size()):
		x = (x + dx + columns) % columns
		y = (y + dy + rows) % rows
		var index = y * columns + x
		if index < buttons.size() and not buttons[index].disabled:
			cursorIndex = index
			return


func _add_entry(text: String, target: String, reference: Button) -> void:
	var button = Button.new()
	button.text = text
	button.rect_min_size = Vector2(200, 48)
	button.add_font_override("font", reference.get_font("font"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_stylebox_override(state, reference.get_stylebox(state))
	button.add_color_override("font_color", Color.white)
	button.connect("pressed", self, target)
	$gv.add_child(button)
	buttons.append(button)


func _new_layer() -> CanvasLayer:
	var result = CanvasLayer.new()
	result.layer = 120
	result.pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().root.add_child(result)
	return result


func _open_trial() -> void:
	if is_instance_valid(trial_panel):
		return
	var canvas = _new_layer()
	var manager = TrialArena.new()
	trial_panel = manager
	manager.layer = canvas
	canvas.add_child(manager)
	manager.open_manager()


func _open_prisoners() -> void:
	if is_instance_valid(prisoner_panel):
		return
	if not PrisonRoster.can_open():
		_show_notice("请在自己的内政回合查看全势力俘虏。")
		return
	var canvas = _new_layer()
	var manager = PrisonRoster.new()
	prisoner_panel = manager
	manager.layer = canvas
	manager.connect("locate_requested", self, "_prison_located")
	canvas.add_child(manager)
	if not manager.open_manager():
		canvas.queue_free()


func _open_personalities() -> void:
	if is_instance_valid(personality_panel):
		return
	if not RulerPersonalityPanel.can_open():
		_show_notice("请回到战役大地图查看君主性格。")
		return
	var canvas = _new_layer()
	var manager = RulerPersonalityPanel.new()
	personality_panel = manager
	manager.layer = canvas
	canvas.add_child(manager)
	if not manager.open_manager():
		canvas.queue_free()


func _prison_located(_city_id: int, _actor_id: int) -> void:
	var menu = get_parent()
	if menu.has_method("_on_btnBackToGame_pressed"):
		menu.call_deferred("_on_btnBackToGame_pressed")


func _show_notice(text: String) -> void:
	var canvas = _new_layer()
	var notice = AcceptDialog.new()
	canvas.add_child(notice)
	notice.dialog_text = text
	notice.get_label().add_font_override("font", Global.get_font(25))
	notice.get_ok().text = "知道了"
	notice.get_ok().rect_min_size = Vector2(150, 48)
	notice.connect("popup_hide", canvas, "queue_free")
	notice.popup_centered(Vector2(650, 180))


func _open_storage() -> void:
	if is_instance_valid(storage_panel):
		return
	for pad in get_tree().get_nodes_in_group("ios_virtual_pad"):
		pad.release_all_touches()
	var layer = CanvasLayer.new()
	layer.layer = 120
	layer.pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().root.add_child(layer)
	var manager = StorageManager.new()
	storage_panel = manager
	manager.service = storage_service
	manager.layer = layer
	layer.add_child(manager)
	manager.open_manager()
