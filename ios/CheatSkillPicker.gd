extends "res://ios_skill_picker.gd"

signal configuration_applied(changes_by_scope, also_default)

var scope_states := {}
var scopes := []
var current_scope := "default"
var active_scope := "default"
var scope_selector: OptionButton
var default_checkbox: CheckBox


func open_configuration(title: String, actor_scopes: Array, current: Dictionary, originals: Dictionary, candidates: Array, initial_scope: String, pending: Dictionary, also_default: bool, allow_default: bool) -> void:
	scopes = actor_scopes.duplicate()
	current_scope = initial_scope if initial_scope in scopes else scopes[0]
	active_scope = current_scope
	for scope in scopes:
		var initial: Dictionary = current.get(scope, {}).duplicate()
		var native: Dictionary = originals.get(scope, {}).duplicate()
		var draft = initial.duplicate()
		var chosen := {}
		var restored := {}
		for level in pending.get(scope, {}):
			if not level in SkillHelper.LEVELS:
				continue
			var value = pending[scope][level]
			if value == null:
				draft[level] = native.get(level, "")
				restored[level] = true
				chosen[level] = true
			elif value is String:
				draft[level] = value
				if value != initial.get(level, ""):
					chosen[level] = true
		scope_states[scope] = {"initial": initial, "native": native, "draft": draft, "chosen": chosen, "restored": restored}
	var first: Dictionary = scope_states[current_scope]
	set_meta("ios_equipment_side", current_scope)
	open_picker(title, SkillHelper.LEVELS, first.draft, candidates, true, first.native)
	_load_scope_state(current_scope)
	if scopes.size() > 1:
		_build_scope_selector(initial_scope)
	default_checkbox = CheckBox.new()
	default_checkbox.text = "两面另存新局默认" if scopes.size() > 1 else "另存新局默认"
	default_checkbox.add_font_override("font", Global.get_font(18))
	default_checkbox.rect_min_size.y = 44
	default_checkbox.disabled = not allow_default
	default_checkbox.pressed = also_default and allow_default
	default_checkbox.hint_tooltip = "保存本局时，同时将本武将两面技能另存为以后新局的默认配置；不会修改其他旧存档。" if allow_default else "自建武将请使用创建配置，不写入原版武将默认补丁。"
	footer.add_child(default_checkbox)
	footer.move_child(default_checkbox, 1 if save_notice != null else 0)
	if save_notice != null:
		save_notice.text = "确认后在武将页保存，再存档保留。"


func _build_scope_selector(active_scope: String) -> void:
	var effect_body = effect_heading.get_parent()
	var heading_row = HBoxContainer.new()
	effect_body.add_child(heading_row)
	effect_body.move_child(heading_row, 0)
	effect_body.remove_child(effect_heading)
	heading_row.add_child(effect_heading)
	effect_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scope_selector = OptionButton.new()
	scope_selector.rect_min_size = Vector2(142, 40)
	scope_selector.set_meta("ios_rating_exempt", true)
	for scope in scopes:
		var label = scope + "面"
		if scope == active_scope:
			label += "·当前"
		scope_selector.add_item(label)
	scope_selector.select(scopes.find(current_scope))
	scope_selector.connect("item_selected", self, "_scope_selected")
	heading_row.add_child(scope_selector)
	_refresh_scope_labels()


func _draw_skill_slots() -> void:
	._draw_skill_slots()
	_refresh_scope_labels()


func _refresh_scope_labels() -> void:
	if scope_selector == null:
		return
	for index in range(scopes.size()):
		var scope: String = scopes[index]
		var changed = not chosen_levels.empty() if scope == current_scope else not scope_states[scope].chosen.empty()
		var label = scope + "面" + ("＊" if changed else "")
		if scope == active_scope:
			label += "·当前"
		scope_selector.set_item_text(index, label)


func _save_scope_state() -> void:
	scope_states[current_scope] = {"initial": initial_skills.duplicate(), "native": original_skills.duplicate(), "draft": draft_skills.duplicate(), "chosen": chosen_levels.duplicate(), "restored": restored_levels.duplicate()}


func _load_scope_state(scope: String) -> void:
	current_scope = scope
	var state: Dictionary = scope_states[scope]
	initial_skills = state.initial.duplicate()
	original_skills = state.native.duplicate()
	draft_skills = state.draft.duplicate()
	chosen_levels = state.chosen.duplicate()
	restored_levels = state.restored.duplicate()
	set_meta("ios_equipment_side", current_scope)
	_draw_skill_slots()
	_draw_skill_page()
	_show_skill_effect()


func _scope_selected(index: int) -> void:
	if index < 0 or index >= scopes.size() or scopes[index] == current_scope:
		return
	_finish_skill_search("")
	_save_scope_state()
	_load_scope_state(scopes[index])


func configuration_changes() -> Dictionary:
	_save_scope_state()
	var changes := {}
	for scope in scopes:
		var state: Dictionary = scope_states[scope]
		var slots := {}
		for level in state.chosen:
			slots[level] = null if state.restored.has(level) else state.draft.get(level, "")
		if not slots.empty():
			changes[scope] = slots
	return changes


func _confirm_selection() -> void:
	emit_signal("configuration_applied", configuration_changes(), default_checkbox != null and default_checkbox.pressed and not default_checkbox.disabled)
	hide()
