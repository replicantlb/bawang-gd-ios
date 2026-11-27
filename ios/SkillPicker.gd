extends "res://ios_picker_panel.gd"

signal selection_applied(skills, changed_levels)

const Catalog = preload("res://ios_skill_catalog.gd")
const EquipmentInspector = preload("res://ios_equipment_skill_inspector.gd")
const PRESETS_PATH = "user://ios_skill_presets.json"
var catalog = Catalog.new()
var draft_skills := {}
var initial_skills := {}
var original_skills := {}
var chosen_levels := {}
var restored_levels := {}
var level_keys: Array
var selected_level: String
var choices_per_page: int
var slot_buttons := {}
var eligible_skills := []
var skill_query: LineEdit
var category_filter: OptionButton
var selected_category := "全部"
var category_buttons := {}
var grade_filter: OptionButton
var skill_grid: GridContainer
var skill_effect_scroll: ScrollContainer
var skill_effect_text: RichTextLabel
var page_label: Label
var previous_page: Button
var next_page: Button
var skill_page := 0
var clear_skill: Button
var preset_menu: MenuButton
var preset_actions := {}
var presets := []
var slot_row: HBoxContainer
var category_grid: GridContainer
var main_split: HBoxContainer
var skill_list_scroll: ScrollContainer
var effect_heading: Label
var save_notice: Label


func open_picker(title: String, levels: Array, current: Dictionary, candidates: Array, allow_clear := false, originals := {}) -> void:
	level_keys = levels
	selected_level = level_keys[0]
	draft_skills = current.duplicate()
	initial_skills = current.duplicate()
	original_skills = originals.duplicate()
	eligible_skills = candidates.duplicate()
	eligible_skills.sort()
	choices_per_page = 8
	connect("applied", self, "_confirm_selection")
	var body = build_layout(title, false)
	body.add_constant_override("separation", 6)
	slot_row = HBoxContainer.new()
	body.add_child(slot_row)
	for level in level_keys:
		var slot = make_button("", 0)
		slot.rect_min_size.y = 60
		slot.clip_text = true
		slot.toggle_mode = true
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.connect("pressed", self, "_select_skill_slot", [level])
		slot_buttons[level] = slot
		slot_row.add_child(slot)
		var slot_content = VBoxContainer.new()
		slot_content.name = "Content"
		slot_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_content.alignment = BoxContainer.ALIGN_CENTER
		slot_content.add_constant_override("separation", 0)
		slot.add_child(slot_content)
		slot_content.anchor_right = 1
		slot_content.anchor_bottom = 1
		slot_content.margin_left = 4
		slot_content.margin_right = -4
		slot_content.margin_top = 2
		slot_content.margin_bottom = -2
		var level_label = Label.new()
		level_label.text = level
		level_label.align = Label.ALIGN_CENTER
		level_label.add_font_override("font", Global.get_font(18))
		level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		level_label.set_meta("ios_rating_exempt", true)
		slot_content.add_child(level_label)
		var skill_label = Label.new()
		skill_label.name = "SkillName"
		skill_label.align = Label.ALIGN_CENTER
		skill_label.clip_text = true
		skill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_label.set_meta("ios_rating_exempt", true)
		slot_content.add_child(skill_label)
	main_split = HBoxContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_constant_override("separation", 12)
	body.add_child(main_split)
	var browser = VBoxContainer.new()
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser.size_flags_stretch_ratio = 1.5
	browser.add_constant_override("separation", 6)
	main_split.add_child(browser)
	category_grid = GridContainer.new()
	category_grid.columns = 4
	browser.add_child(category_grid)
	for category in Catalog.CATEGORIES:
		var category_button = make_button(category, 0)
		category_button.rect_min_size.y = 40
		category_button.toggle_mode = true
		category_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_button.set_meta("ios_rating_exempt", true)
		category_button.set_pressed_no_signal(category == selected_category)
		category_button.connect("pressed", self, "_select_category", [category])
		category_grid.add_child(category_button)
		category_buttons[category] = category_button
	var search_row = HBoxContainer.new()
	browser.add_child(search_row)
	category_filter = OptionButton.new()
	category_filter.rect_min_size = Vector2(125, 44)
	for tag in Catalog.TAG_FILTERS:
		category_filter.add_item(tag)
	category_filter.connect("item_selected", self, "_category_changed")
	search_row.add_child(category_filter)
	grade_filter = OptionButton.new()
	grade_filter.rect_min_size = Vector2(120, 44)
	for grade in ["全部评级", "S", "A", "B", "C", "D"]:
		grade_filter.add_item(grade)
	grade_filter.connect("item_selected", self, "_category_changed")
	search_row.add_child(grade_filter)
	skill_query = LineEdit.new()
	skill_query.placeholder_text = "技能名或效果"
	skill_query.clear_button_enabled = true
	skill_query.rect_min_size = Vector2(80, 44)
	skill_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_query.connect("text_changed", self, "_filter_skills")
	skill_query.connect("text_entered", self, "_finish_skill_search")
	search_row.add_child(skill_query)
	skill_list_scroll = ScrollContainer.new()
	skill_list_scroll.scroll_horizontal_enabled = false
	skill_list_scroll.scroll_deadzone = 6
	skill_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.add_child(skill_list_scroll)
	skill_grid = GridContainer.new()
	skill_grid.columns = 4
	skill_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_list_scroll.add_child(skill_grid)
	var paging = HBoxContainer.new()
	browser.add_child(paging)
	previous_page = make_button("‹", 44)
	next_page = make_button("›", 44)
	previous_page.rect_min_size.y = 44
	next_page.rect_min_size.y = 44
	previous_page.hint_tooltip = "上一页"
	next_page.hint_tooltip = "下一页"
	page_label = Label.new()
	page_label.add_font_override("font", Global.get_font(18))
	page_label.align = Label.ALIGN_CENTER
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paging.add_child(previous_page)
	paging.add_child(page_label)
	paging.add_child(next_page)
	if allow_clear:
		clear_skill = make_button("清空", 64)
		clear_skill.rect_min_size.y = 44
		clear_skill.connect("pressed", self, "_choose_skill", [""])
		paging.add_child(clear_skill)
		if not original_skills.empty():
			var restore = MenuButton.new()
			restore.text = "恢复"
			restore.rect_min_size = Vector2(64, 44)
			restore.get_popup().add_item("恢复本栏原版技能", 0)
			restore.get_popup().add_item("恢复全部原版技能", 1)
			restore.get_popup().connect("id_pressed", self, "_restore_original")
			paging.add_child(restore)
	previous_page.connect("pressed", self, "_change_skill_page", [-1])
	next_page.connect("pressed", self, "_change_skill_page", [1])
	preset_menu = MenuButton.new()
	preset_menu.text = "配置"
	preset_menu.rect_min_size = Vector2(64, 44)
	preset_menu.get_popup().connect("id_pressed", self, "_preset_action")
	paging.add_child(preset_menu)
	_load_presets()
	_refresh_preset_menu()
	var effect_panel = PanelContainer.new()
	effect_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_panel.rect_min_size.x = 300
	var effect_style = StyleBoxFlat.new()
	effect_style.bg_color = Color("352e27")
	effect_style.set_corner_radius_all(4)
	effect_style.content_margin_left = 12
	effect_style.content_margin_right = 12
	effect_style.content_margin_top = 8
	effect_style.content_margin_bottom = 8
	effect_panel.add_stylebox_override("panel", effect_style)
	main_split.add_child(effect_panel)
	var effect_body = VBoxContainer.new()
	effect_panel.add_child(effect_body)
	effect_heading = Label.new()
	effect_heading.text = "技能说明"
	effect_body.add_child(effect_heading)
	skill_effect_scroll = ScrollContainer.new()
	skill_effect_scroll.rect_min_size.y = 180
	skill_effect_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_effect_scroll.scroll_horizontal_enabled = false
	skill_effect_scroll.scroll_deadzone = 6
	effect_body.add_child(skill_effect_scroll)
	skill_effect_text = RichTextLabel.new()
	skill_effect_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_effect_text.fit_content_height = true
	skill_effect_text.scroll_active = false
	skill_effect_text.bbcode_enabled = true
	skill_effect_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_effect_text.add_color_override("default_color", Color("eee4d2"))
	skill_effect_scroll.add_child(skill_effect_text)
	if allow_clear:
		save_notice = Label.new()
		save_notice.text = "确认后，还需在武将页保存并存档。"
		save_notice.add_font_override("font", Global.get_font(18))
		save_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(save_notice)
		footer.move_child(save_notice, 0)
	_draw_skill_slots()
	_draw_skill_page()
	_show_skill_effect()
	show_adaptive(Vector2(960, 560))


func _fit_to_visible_area() -> void:
	if is_instance_valid(slot_row):
		var available = MobileLayout.available_area(get_viewport(), 12.0, true)
		set_compact_layout(available.size.y < 450)
	._fit_to_visible_area()


func set_compact_layout(compact: bool) -> void:
	slot_row.visible = not compact
	category_grid.visible = not compact
	effect_heading.visible = not compact
	skill_effect_scroll.rect_min_size.y = 72 if compact else 180
	if save_notice != null:
		save_notice.visible = not compact


func _draw_skill_slots() -> void:
	for level in level_keys:
		var slot: Button = slot_buttons[level]
		var current: String = draft_skills.get(level, "")
		slot.get_node("Content/SkillName").text = "%s%s" % [current if current != "" else "无技能", "＊" if chosen_levels.has(level) else ""]
		slot.set_meta("ios_rating_skill", current)
		slot.set_meta("ios_rating_scene", selected_category if catalog.matches(current, selected_category, "") else "全部")
		slot.set_pressed_no_signal(level == selected_level)
	if clear_skill != null:
		clear_skill.disabled = draft_skills.get(selected_level, "").empty()


func _select_skill_slot(level: String) -> void:
	selected_level = level
	_draw_skill_slots()
	_draw_skill_page()
	_show_skill_effect()


func _show_skill_effect() -> void:
	var skill_name: String = draft_skills.get(selected_level, "")
	var skill = StaticManager.get_skill(skill_name)
	var before: String = initial_skills.get(selected_level, "")
	var change = "原：%s → 选：%s" % [before if not before.empty() else "无技能", skill_name if not skill_name.empty() else "无技能"]
	if restored_levels.has(selected_level):
		change += "（恢复原版默认）"
	var lines = [change]
	if skill_name.empty():
		lines.append("本栏无技能。清空与恢复原版默认不同。")
	elif skill == null:
		lines.append("【%s】暂无效果说明" % skill_name)
	else:
		lines.append(skill.get_runtime_description())
		lines.append(MobileSkillRatings.explanation(skill_name))
		lines.append(catalog.conditions_for(skill_name))
	var notes = catalog.configuration_notes(draft_skills.values(), not has_meta("ios_equipment_actor"))
	if not notes.empty():
		lines.append("组合提醒\n" + PoolStringArray(notes).join("\n"))
	if has_meta("ios_equipment_actor"):
		var inspector = EquipmentInspector.new()
		var actor_id = int(get_meta("ios_equipment_actor"))
		var equipment = get_meta("ios_equipment_overrides") if has_meta("ios_equipment_overrides") else {}
		var side = str(get_meta("ios_equipment_side")) if has_meta("ios_equipment_side") else ""
		if side == "default":
			side = ""
		var interactions = inspector.inspect(actor_id, draft_skills.values(), side, equipment)
		var heading = "装备与技能（按所选配置，含未解锁栏位）"
		if equipment.empty():
			heading += "\n按当前已保存装备检查。"
		else:
			heading += "\n按武将页待保存装备预览。"
		if interactions.empty():
			interactions.append("已核对的规则中，暂未发现重合或冲突；其他效果仍需满足各自条件。")
		lines.append(heading + "\n" + PoolStringArray(interactions).join("\n\n"))
	skill_effect_text.bbcode_text = PoolStringArray(lines).join("\n\n")
	skill_effect_scroll.scroll_vertical = 0


func _filter_skills(_text: String) -> void:
	skill_page = 0
	_draw_skill_page()


func _category_changed(_index: int) -> void:
	_filter_skills(skill_query.text)


func _select_category(category: String) -> void:
	selected_category = category
	for name in category_buttons:
		category_buttons[name].set_pressed_no_signal(name == category)
	_draw_skill_slots()
	_filter_skills(skill_query.text)


func _finish_skill_search(_text: String) -> void:
	skill_query.release_focus()
	OS.hide_virtual_keyboard()


func _change_skill_page(step: int) -> void:
	skill_page += step
	_draw_skill_page()


func _draw_skill_page() -> void:
	for item in skill_grid.get_children():
		skill_grid.remove_child(item)
		item.queue_free()
	var occupied = draft_skills.duplicate()
	var selected = occupied.get(selected_level, "")
	occupied.erase(selected_level)
	var taken = occupied.values()
	var query = skill_query.text.strip_edges()
	var tag = category_filter.get_item_text(category_filter.selected)
	var grade = grade_filter.get_item_text(grade_filter.selected)
	var matches := []
	for skill_name in eligible_skills:
		if not skill_name in taken and catalog.matches(skill_name, selected_category, query, tag) and MobileSkillRatings.matches_grade(skill_name, selected_category, grade):
			matches.append(skill_name)
	var last_page = max(0, int(ceil(float(matches.size()) / choices_per_page)) - 1)
	skill_page = int(clamp(skill_page, 0, last_page))
	var start = skill_page * choices_per_page
	for i in range(start, min(start + choices_per_page, matches.size())):
		var skill_name = matches[i]
		var choice = make_button(skill_name, 0)
		choice.rect_min_size.y = 44
		choice.clip_text = true
		choice.toggle_mode = true
		choice.pressed = skill_name == selected
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.set_meta("ios_rating_skill", skill_name)
		choice.set_meta("ios_rating_scene", selected_category)
		choice.connect("pressed", self, "_choose_skill", [skill_name])
		skill_grid.add_child(choice)
	page_label.text = "无匹配" if matches.empty() else "%d/%d页 %d项" % [skill_page + 1, last_page + 1, matches.size()]
	skill_list_scroll.scroll_vertical = 0
	previous_page.disabled = skill_page == 0
	next_page.disabled = skill_page == last_page


func _choose_skill(skill_name: String) -> void:
	_finish_skill_search("")
	if not skill_name.empty() and not skill_name in eligible_skills:
		return
	draft_skills[selected_level] = skill_name
	restored_levels.erase(selected_level)
	if skill_name == initial_skills.get(selected_level, ""):
		chosen_levels.erase(selected_level)
	else:
		chosen_levels[selected_level] = true
	_draw_skill_slots()
	_draw_skill_page()
	_show_skill_effect()


func _restore_original(mode: int) -> void:
	_finish_skill_search("")
	var restore_keys = level_keys if mode == 1 else [selected_level]
	for level in restore_keys:
		draft_skills[level] = original_skills.get(level, "")
		restored_levels[level] = true
		chosen_levels[level] = true
	_draw_skill_slots()
	_draw_skill_page()
	_show_skill_effect()


func _load_presets() -> void:
	var file = File.new()
	if file.open(PRESETS_PATH, File.READ) != OK:
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error == OK and parsed.result is Dictionary and parsed.result.get("presets", null) is Array:
		for preset in parsed.result.presets:
			if preset is Dictionary and preset.get("skills", null) is Array and preset.get("name", null) is String:
				presets.append(preset)
				if presets.size() >= 12:
					break


func _refresh_preset_menu() -> void:
	var menu = preset_menu.get_popup()
	menu.clear()
	preset_actions.clear()
	menu.add_item("收藏当前配置", 0)
	menu.set_item_disabled(0, presets.size() >= 12)
	for index in range(presets.size()):
		var preset: Dictionary = presets[index]
		var title = str(preset.name) + "（" + str(preset.skills.size()) + "栏）"
		var load_id = 10 + index
		var delete_id = 100 + index
		menu.add_item("载入 " + title, load_id)
		menu.add_item("删除 " + title, delete_id)
		preset_actions[load_id] = ["load", index]
		preset_actions[delete_id] = ["delete", index]


func _preset_action(id: int) -> void:
	_finish_skill_search("")
	if id == 0:
		var skills := []
		for level in level_keys:
			skills.append(draft_skills.get(level, ""))
		var serial = 1
		var names := []
		for preset in presets:
			names.append(preset.name)
		while "方案%d" % serial in names:
			serial += 1
		presets.append({"name": "方案%d" % serial, "skills": skills})
		if not _save_presets():
			presets.pop_back()
			return
	elif preset_actions.has(id):
		var action: Array = preset_actions[id]
		if action[0] == "delete":
			var previous = presets.duplicate(true)
			presets.remove(action[1])
			if not _save_presets():
				presets = previous
				return
		else:
			_apply_preset(presets[action[1]])
	_refresh_preset_menu()


func _save_presets() -> bool:
	var file = File.new()
	var temporary = PRESETS_PATH + ".tmp"
	if file.open(temporary, File.WRITE) != OK:
		_show_message("收藏保存失败，请稍后重试。")
		return false
	file.store_string(JSON.print({"version": 1, "presets": presets}))
	var written = file.get_error() == OK
	file.close()
	if not written or Directory.new().rename(temporary, PRESETS_PATH) != OK:
		_show_message("收藏保存失败，原配置已保留。")
		return false
	return true


func _apply_preset(preset: Dictionary) -> bool:
	var skills: Array = preset.skills
	if skills.size() != level_keys.size():
		_show_message("此配置栏位数量不同，不能载入。")
		return false
	var used := []
	for skill_name in skills:
		if not skill_name is String or (not skill_name.empty() and (not skill_name in eligible_skills or skill_name in used)):
			_show_message("此配置包含当前武将不可选或重复的技能，未做修改。")
			return false
		if not skill_name.empty():
			used.append(skill_name)
	for index in range(level_keys.size()):
		var level = level_keys[index]
		draft_skills[level] = skills[index]
		restored_levels.erase(level)
		if skills[index] == initial_skills.get(level, ""):
			chosen_levels.erase(level)
		else:
			chosen_levels[level] = true
	_draw_skill_slots()
	_draw_skill_page()
	_show_skill_effect()
	return true


func _show_message(message: String) -> void:
	skill_effect_text.bbcode_text = message
	skill_effect_scroll.scroll_vertical = 0


func _confirm_selection() -> void:
	var result = draft_skills.duplicate()
	for level in restored_levels:
		result[level] = null
	emit_signal("selection_applied", result, chosen_levels.keys())
	hide()
