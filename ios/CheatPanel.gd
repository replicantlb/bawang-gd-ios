extends Control

# Preserve the original panel's layout and lifecycle without inheriting its unconditional
# WM_GO_BACK handler. Godot invokes _notification in every script in an inheritance chain.
onready var wd: WindowDialog = $wd
onready var tc: TabContainer = $wd/tc
onready var warTab = get_node("wd/tc/　大战场　")
onready var battleTab = get_node("wd/tc/　小战场　")
onready var soloTab = get_node("wd/tc/　单挑　")
var close_confirmation: ConfirmationDialog
var active_tab := 0
var changing_tab := false


func _ready() -> void:
	tc.set_tab_hidden(1, true)
	tc.set_tab_hidden(2, true)
	tc.set_tab_hidden(3, true)
	match DataManager.get_current_scene_id():
		20000: tc.set_tab_hidden(1, false)
		30000: tc.set_tab_hidden(2, false)
		40000: tc.set_tab_hidden(3, false)
	tc.current_tab = 0
	var close_button = wd.get_close_button()
	if close_button.is_connected("pressed", wd, "_closed"):
		close_button.disconnect("pressed", wd, "_closed")
	close_button.connect("pressed", self, "request_close")


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(wd) and wd.visible:
		request_close()


func _input(event: InputEvent) -> void:
	if not is_instance_valid(wd) or not wd.visible:
		return
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		var modal = get_viewport().get_modal_stack_top()
		if modal != null and modal != wd:
			return
		get_tree().set_input_as_handled()
		request_close()


func start() -> void:
	if SceneManager.portrait_mode:
		reset_layout_portrait()
	else:
		reset_layout_landscape()
	wd.set_as_toplevel(true)
	wd.popup_centered()


func closing() -> void:
	SceneManager.cheater_finished()


func tab_changed(tab: int) -> void:
	if changing_tab:
		return
	if tab != 4:
		active_tab = tab
		return
	changing_tab = true
	tc.current_tab = active_tab
	changing_tab = false
	request_close()


func request_close() -> void:
	if not _has_skill_draft(self):
		wd.hide()
		return
	if is_instance_valid(close_confirmation) and close_confirmation.visible:
		return
	close_confirmation = ConfirmationDialog.new()
	close_confirmation.popup_exclusive = true
	close_confirmation.dialog_text = "技能修改尚未保存。放弃修改并关闭修改器？"
	close_confirmation.get_label().add_font_override("font", Global.get_font(25))
	close_confirmation.get_ok().text = "放弃并关闭"
	close_confirmation.get_cancel().text = "继续编辑"
	close_confirmation.connect("confirmed", self, "_discard_and_close")
	close_confirmation.connect("popup_hide", close_confirmation, "queue_free")
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	layer.add_child(close_confirmation)
	close_confirmation.window_title = "尚未保存"
	close_confirmation.add_font_override("title_font", Global.get_font(25))
	close_confirmation.get_ok().add_font_override("font", Global.get_font(25))
	close_confirmation.get_cancel().add_font_override("font", Global.get_font(25))
	close_confirmation.get_ok().rect_min_size = Vector2(180, 56)
	close_confirmation.get_cancel().rect_min_size = Vector2(180, 56)
	close_confirmation.connect("popup_hide", layer, "queue_free")
	close_confirmation.popup_centered(Vector2(760, 190))


func _has_skill_draft(node: Node) -> bool:
	if node.has_method("_stage_skill_changes"):
		var draft = node.get("skill_draft")
		if draft is Dictionary and not draft.empty():
			return true
	for child in node.get_children():
		if _has_skill_draft(child):
			return true
	return false


func _discard_skill_drafts(node: Node) -> void:
	if node.has_method("_stage_skill_changes"):
		var draft = node.get("skill_draft")
		if draft is Dictionary:
			draft.clear()
	for child in node.get_children():
		_discard_skill_drafts(child)


func _discard_and_close() -> void:
	_discard_skill_drafts(self)
	wd.hide()


func reset_layout_landscape() -> void:
	wd.rect_min_size = Vector2(800, 500)
	wd.rect_size = wd.rect_min_size
	tc.rect_scale = Vector2.ONE
	tc.rect_min_size = Vector2(800, 474)
	tc.rect_position = Vector2.ZERO
	for child in tc.get_children():
		if child.has_method("reset_layout_landscape"):
			child.reset_layout_landscape()


func reset_layout_portrait() -> void:
	wd.rect_min_size = Vector2(980, 1080)
	wd.rect_size = wd.rect_min_size
	tc.rect_scale = Vector2(1.2, 1.2)
	tc.rect_min_size = Vector2(800, 474)
	tc.rect_position = Vector2.ZERO
	for child in tc.get_children():
		if child.has_method("reset_layout_portrait"):
			child.reset_layout_portrait()
