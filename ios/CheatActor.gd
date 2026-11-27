extends "res://cheat/actor.gd"

const SkillPicker = preload("res://ios_cheat_skill_picker.gd")
const PickerPanel = preload("res://ios_picker_panel.gd")
const DEFAULT_REQUEST_KEY = "__also_default__"

var edit_skills: Button
var skill_draft := {}
var skill_scope := ""
var discard_dialog: ConfirmationDialog


func _ready() -> void:
	edit_skills = PickerPanel.make_button("修改技能", 112)
	edit_skills.rect_position = Vector2(480, 336)
	edit_skills.connect("pressed", self, "_open_skill_editor")
	edit_skills.hide()
	add_child(edit_skills)
	$cancel.disconnect("pressed", self, "cancel")
	$cancel.connect("pressed", self, "_request_cancel")


func reload_data(_actorId: int = -1) -> void:
	if not skill_draft.empty() and _actorId >= 0 and _actorId != actorId:
		_ask_discard("技能修改尚未保存。放弃修改并切换武将？", "_discard_and_reload", [_actorId])
		return
	.reload_data(_actorId)
	skill_draft.clear()
	skill_scope = ""
	var show_editor: bool = SkillHelper.can_edit_actor_skills(actorId) and not SkillHelper.actor_skill_scope(actorId).empty()
	edit_skills.visible = show_editor
	edit_skills.text = "修改技能"
	$save.text = "保存"
	_layout_actions(show_editor)


func _layout_actions(reserve_skill_button: bool) -> void:
	var actions = [$save, $reset, $cancel, $status]
	for index in range(actions.size()):
		var button: Button = actions[index]
		var is_status: bool = button == $status
		var position = 8 + 94 * index if reserve_skill_button else 20 + 120 * index
		var width = (180 if is_status else 88) if reserve_skill_button else (200 if is_status else 100)
		button.rect_min_size.x = width
		button.rect_size.x = width
		button.rect_position.x = position
		button.clip_text = reserve_skill_button


func _open_skill_editor() -> void:
	skill_scope = SkillHelper.actor_skill_scope(actorId)
	if skill_scope.empty():
		return
	var scopes: Array = SkillHelper.actor_skill_scopes(actorId)
	var selection := {}
	var originals := {}
	for scope in scopes:
		selection[scope] = SkillHelper.get_actor_default_skill_names(actorId, "" if scope == "default" else scope)
		originals[scope] = SkillHelper.get_actor_original_skill_names(actorId, "" if scope == "default" else scope)
	var gender = _edited_gender()
	var candidates := []
	for skill in StaticManager.skillDict.values():
		if skill.visible() and _can_select_skill(skill, gender):
			candidates.append(skill.name)
	var actor = ActorHelper.actor(actorId)
	var title = "修改技能 · " + actor.get_name()
	var picker = SkillPicker.new()
	add_child(picker)
	picker.set_as_toplevel(true)
	picker.set_meta("ios_equipment_actor", actorId)
	var equipment = {}
	for slot in ["武器", "防具", "道具", "坐骑"]:
		equipment[slot] = int(attrs.get_node(slot).editor_description)
	picker.set_meta("ios_equipment_overrides", equipment)
	picker.connect("configuration_applied", self, "_stage_skill_configuration")
	picker.open_configuration(title, scopes, selection, originals, candidates, skill_scope, _scope_changes(), skill_draft.get(DEFAULT_REQUEST_KEY, false), actorId != StaticManager.ACTOR_ID_DIY)


func _edited_gender() -> String:
	for gender in ["男", "女", "无"]:
		if basics.get_node(gender).disabled:
			return gender
	return ActorHelper.actor(actorId).get_gender()


func _can_select_skill(skill, gender: String) -> bool:
	if skill == null or not skill.exclusive_valid_for_actor(actorId):
		return false
	return skill._gendersOnly.empty() or gender in skill._gendersOnly


func _stage_skill_changes(selection: Dictionary, levels: Array) -> void:
	# Keep the existing single-scope entry point for callers outside the picker.
	if skill_scope.empty():
		skill_scope = SkillHelper.actor_skill_scope(actorId)
	var slots: Dictionary = skill_draft.get(skill_scope, {})
	for level in levels:
		slots[level] = selection[level]
	if not slots.empty():
		skill_draft[skill_scope] = slots
	_update_skill_pending_notice()


func _stage_skill_configuration(changes: Dictionary, also_default: bool) -> void:
	skill_draft = changes.duplicate(true)
	if also_default:
		skill_draft[DEFAULT_REQUEST_KEY] = true
	_update_skill_pending_notice()


func _scope_changes() -> Dictionary:
	var changes = skill_draft.duplicate(true)
	changes.erase(DEFAULT_REQUEST_KEY)
	return changes


func _update_skill_pending_notice() -> void:
	if not skill_draft.empty():
		edit_skills.text = "技能待保存"
		$save.text = "保存修改"
	else:
		edit_skills.text = "修改技能"
		$save.text = "保存"


func save_data() -> void:
	var gender = _edited_gender()
	var changes = _scope_changes()
	for slots in changes.values():
		for skill_name in slots.values():
			if skill_name != null and not skill_name.empty() and not _can_select_skill(StaticManager.get_skill(skill_name), gender):
				_show_invalid_skill(skill_name)
				return
	var error: String = SkillHelper.save_actor_skill_configuration(actorId, changes, skill_draft.get(DEFAULT_REQUEST_KEY, false), gender)
	if not error.empty():
		_show_skill_error(error)
		return
	.save_data()
	skill_draft.clear()
	edit_skills.text = "修改技能"
	$save.text = "保存"


func _show_invalid_skill(skill_name: String) -> void:
	_show_skill_error("「%s」不适用于当前武将，请重新选择技能。" % skill_name)


func _show_skill_error(message: String) -> void:
	var notice = AcceptDialog.new()
	notice.dialog_text = message
	notice.get_label().add_font_override("font", Global.get_font(25))
	notice.get_ok().add_font_override("font", Global.get_font(25))
	notice.get_ok().text = "确定"
	notice.connect("popup_hide", notice, "queue_free")
	_present_skill_dialog(notice, "技能提示")


func cancel() -> void:
	_request_cancel()


func _request_cancel() -> void:
	if skill_draft.empty():
		.cancel()
		return
	_ask_discard("技能修改尚未保存。放弃这次修改并返回？", "_discard_skill_changes")


func _ask_discard(message: String, method: String, arguments := []) -> void:
	if is_instance_valid(discard_dialog) and discard_dialog.visible:
		return
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.dialog_text = message
	discard_dialog.popup_exclusive = true
	discard_dialog.get_label().add_font_override("font", Global.get_font(25))
	discard_dialog.get_ok().text = "放弃修改"
	discard_dialog.get_cancel().text = "继续编辑"
	discard_dialog.connect("confirmed", self, method, arguments)
	discard_dialog.connect("popup_hide", discard_dialog, "queue_free")
	_present_skill_dialog(discard_dialog, "尚未保存")


func _discard_and_reload(target_actor_id: int) -> void:
	skill_draft.clear()
	reload_data(target_actor_id)


func _discard_skill_changes() -> void:
	skill_draft.clear()
	.cancel()


func _present_skill_dialog(dialog: AcceptDialog, title: String) -> void:
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	layer.add_child(dialog)
	dialog.popup_exclusive = true
	dialog.window_title = title
	dialog.add_font_override("title_font", Global.get_font(25))
	dialog.get_label().add_font_override("font", Global.get_font(25))
	dialog.get_ok().add_font_override("font", Global.get_font(25))
	dialog.get_ok().rect_min_size = Vector2(180, 56)
	if dialog is ConfirmationDialog:
		dialog.get_cancel().add_font_override("font", Global.get_font(25))
		dialog.get_cancel().rect_min_size = Vector2(180, 56)
	dialog.connect("popup_hide", layer, "queue_free")
	dialog.popup_centered(Vector2(760, 190))
