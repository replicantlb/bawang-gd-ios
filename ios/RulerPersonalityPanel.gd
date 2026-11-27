extends PopupPanel

const MobileLayout = preload("res://ios_mobile_layout.gd")

var layer: CanvasLayer
var opened := false
var was_paused := false
var pad_states := []
var rows := []
var selected_vstate_id := -1
var selected_lord_id := -1
var tree: Tree
var details: RichTextLabel
var primary_choice: OptionButton
var secondary_choice: OptionButton
var save_button: Button
var reset_button: Button
var enabled_choice: CheckButton
var notice: Label
var discard_dialog: ConfirmationDialog
var service
var _session := ""
var _populating := false
var _drafts := {}
var _last_area := Rect2()
var _refresh_elapsed := 0.0
var _compact := false


static func can_open() -> bool:
	var trial = DataManager.get_node_or_null("/root/TrialSession")
	return DataManager.get_current_scene_id() == 10000 and not DataManager.vstates.empty() and (trial == null or not trial.active)


func open_manager() -> bool:
	service = get_node_or_null("/root/RulerPersonalities")
	if opened or service == null or not can_open():
		return false
	_session = service.session_token()
	pause_mode = Node.PAUSE_MODE_PROCESS
	popup_exclusive = true
	if layer == null and get_parent() is CanvasLayer and get_parent().get_child_count() == 1:
		layer = get_parent()
	_build()
	connect("popup_hide", self, "_closed")
	was_paused = get_tree().paused
	for pad in get_tree().get_nodes_in_group("ios_virtual_pad"):
		pad_states.append([pad, pad.emu_enable])
		pad.release_all_touches()
		pad.emu_enable = false
	get_tree().paused = true
	opened = true
	popup_centered(Vector2(980, 560))
	_fit()
	_refresh()
	set_process(true)
	return true


func _build() -> void:
	var fonts = Theme.new()
	fonts.default_font = _font(23)
	theme = fonts
	var style = StyleBoxFlat.new()
	style.bg_color = Color("28231f")
	style.border_color = Color("b79a6b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_stylebox_override("panel", style)
	var body = VBoxContainer.new()
	add_child(body)
	body.anchor_right = 1
	body.anchor_bottom = 1
	body.margin_left = 14
	body.margin_right = -14
	body.margin_top = 10
	body.margin_bottom = -10
	body.add_constant_override("separation", 8)
	var heading = HBoxContainer.new()
	heading.add_constant_override("separation", 12)
	body.add_child(heading)
	var title = Label.new()
	title.text = "君主性格"
	title.add_font_override("font", _font(28))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	enabled_choice = CheckButton.new()
	enabled_choice.text = "启用 AI 性格"
	enabled_choice.rect_min_size.y = 46
	enabled_choice.connect("toggled", self, "_enabled_changed")
	heading.add_child(enabled_choice)
	_button("关闭", "_request_close", heading, 90)
	var content = HBoxContainer.new()
	content.add_constant_override("separation", 12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	tree = Tree.new()
	tree.hide_root = true
	tree.columns = 3
	tree.select_mode = Tree.SELECT_ROW
	tree.column_titles_visible = true
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.size_flags_stretch_ratio = 0.9
	for index in range(3):
		tree.set_column_title(index, ["势力", "君主", "性格"][index])
		tree.set_column_min_width(index, [95, 95, 140][index])
	tree.connect("item_selected", self, "_selected")
	content.add_child(tree)
	var right = VBoxContainer.new()
	right.add_constant_override("separation", 8)
	right.rect_min_size.x = 390
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.1
	content.add_child(right)
	var detail_panel = PanelContainer.new()
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_panel)
	var scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	scroll.scroll_deadzone = 6
	detail_panel.add_child(scroll)
	details = RichTextLabel.new()
	details.fit_content_height = true
	details.scroll_active = false
	details.bbcode_enabled = false
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_color_override("default_color", Color("eee4d2"))
	scroll.add_child(details)
	var choices = HBoxContainer.new()
	choices.add_constant_override("separation", 12)
	right.add_child(choices)
	primary_choice = _trait_choice(choices, "主性格")
	secondary_choice = _trait_choice(choices, "副性格")
	var actions = HBoxContainer.new()
	actions.add_constant_override("separation", 12)
	right.add_child(actions)
	save_button = _button("保存本局", "_save_draft", actions, 150)
	reset_button = _button("恢复默认", "_reset_profile", actions, 150)
	notice = Label.new()
	notice.autowrap = true
	notice.add_font_override("font", _font(19))
	notice.rect_min_size.y = 44
	body.add_child(notice)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.dialog_text = "还有未保存的性格选择，关闭后将放弃这些选择。"
	discard_dialog.get_label().autowrap = true
	discard_dialog.get_label().add_font_override("font", _font(23))
	discard_dialog.get_ok().text = "放弃并关闭"
	discard_dialog.get_cancel().text = "继续设置"
	discard_dialog.get_ok().rect_min_size = Vector2(150, 48)
	discard_dialog.get_cancel().rect_min_size = Vector2(150, 48)
	discard_dialog.connect("confirmed", self, "hide")
	add_child(discard_dialog)


func _font(size: int):
	var result = Global.get_font(25).duplicate()
	if result is DynamicFont:
		result.size = size
	return result


func _button(text: String, method: String, parent: Node, width: int) -> Button:
	var button = Button.new()
	button.text = text
	button.rect_min_size = Vector2(width, 46)
	button.connect("pressed", self, method)
	parent.add_child(button)
	return button


func _trait_choice(parent: Node, title: String) -> OptionButton:
	var box = HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var label = Label.new()
	label.text = title + "："
	box.add_child(label)
	var choice = OptionButton.new()
	choice.rect_min_size.y = 46
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for trait in service.TRAITS:
		choice.add_item(trait)
	choice.connect("item_selected", self, "_draft_changed")
	box.add_child(choice)
	return choice


func _process(delta: float) -> void:
	if not opened:
		return
	if not can_open() or service.session_token() != _session:
		hide()
		return
	_fit()
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.5:
		_refresh_elapsed = 0.0
		var current: Array = service.current_factions(false)
		if _roster_identity(current) != _roster_identity(rows):
			_refresh()
			notice.text = "君主或势力已发生变化，已更新名单；请确认现任君主后再设置。"


func _roster_identity(records: Array) -> String:
	var identity = ""
	for record in records:
		identity += "%s:%s;" % [record.vstate_id, record.lord_id]
	return identity


func _fit() -> void:
	var area = MobileLayout.available_area(get_viewport(), 12, true)
	if area == _last_area:
		return
	_last_area = area
	rect_size = Vector2(min(980, area.size.x), min(560, area.size.y))
	rect_position = area.position + (area.size - rect_size) * 0.5
	var compact = area.size.y < 430
	if compact != _compact:
		_compact = compact
		for record in rows:
			if record.vstate_id == selected_vstate_id:
				_render_record(record)
				break


func _refresh() -> void:
	_populating = true
	rows = service.current_factions(false)
	var active_lords := []
	for record in rows:
		active_lords.append(str(record.lord_id))
	for actor_key in _drafts.keys():
		if not actor_key in active_lords:
			_drafts.erase(actor_key)
	enabled_choice.set_pressed_no_signal(service.is_enabled())
	enabled_choice.disabled = not service.supported()
	tree.clear()
	var root = tree.create_item()
	var active
	for record in rows:
		var item = tree.create_item(root)
		item.set_metadata(0, record.vstate_id)
		item.set_text(0, str(record.faction_name))
		item.set_text(1, str(record.lord_name))
		item.set_text(2, "%s·%s" % [record.profile.primary, record.profile.secondary])
		if record.vstate_id == selected_vstate_id:
			active = item
	if active == null:
		active = root.get_children()
	if active != null:
		active.select(0)
	_populating = false
	_selected()
	if active != null:
		tree.call_deferred("ensure_cursor_is_visible")


func _selected() -> void:
	if _populating:
		return
	var item = tree.get_selected()
	var record = {}
	if item != null:
		for candidate in rows:
			if candidate.vstate_id == int(item.get_metadata(0)):
				record = candidate
				break
	selected_vstate_id = int(record.get("vstate_id", -1))
	selected_lord_id = int(record.get("lord_id", -1))
	if record.empty():
		details.text = "当前没有可查看的势力。"
		save_button.disabled = true
		reset_button.disabled = true
		primary_choice.disabled = true
		secondary_choice.disabled = true
		_update_notice()
		return
	var profile: Dictionary = record.profile
	_render_record(record)
	var draft: Dictionary = _drafts.get(str(selected_lord_id), profile)
	_populating = true
	primary_choice.select(max(0, service.TRAITS.find(draft.primary)))
	secondary_choice.select(max(0, service.TRAITS.find(draft.secondary)))
	_populating = false
	primary_choice.disabled = not service.supported()
	secondary_choice.disabled = not service.supported()
	reset_button.disabled = not service.supported()
	_update_notice()


func _render_record(record: Dictionary) -> void:
	var profile: Dictionary = record.profile
	var lines = ["%s　君主：%s" % [record.faction_name, record.lord_name], "当前性格：%s · %s" % [profile.primary, profile.secondary], "当前来源：" + str(profile.source)]
	if _compact:
		lines = ["%s · %s" % [record.lord_name, profile.source]]
		if not _drafts.has(str(record.lord_id)):
			lines.append("偏好：" + str(profile.get("preference", "")))
	if int(record.get("previous_lord_id", -1)) >= 0 and not str(record.get("previous_lord_name", "")).empty():
		lines.append("前任君主：" + str(record.previous_lord_name))
	var draft: Dictionary = _drafts.get(str(record.lord_id), {})
	if not draft.empty():
		lines.append("\n待保存性格：%s · %s" % [draft.primary, draft.secondary])
		if draft.primary != draft.secondary:
			var preview = profile.duplicate(true)
			preview.primary = draft.primary
			preview.secondary = draft.secondary
			preview.preference = ""
			lines.append("倾向预览（保存后生效）\n" + service.description(preview))
		else:
			lines.append("主副性格需要不同。")
	else:
		lines.append("\n" + service.description(profile))
	if record.get("is_player", false):
		lines.append("\n玩家势力由你指挥，性格不会限制手动操作。")
	details.text = "\n".join(lines)


func _draft_changed(_index: int) -> void:
	if _populating or selected_lord_id < 0:
		return
	var primary = primary_choice.get_item_text(primary_choice.selected)
	var secondary = secondary_choice.get_item_text(secondary_choice.selected)
	var saved: Dictionary = service.profile_for(selected_lord_id, false)
	if primary == saved.primary and secondary == saved.secondary:
		_drafts.erase(str(selected_lord_id))
	else:
		_drafts[str(selected_lord_id)] = {"primary": primary, "secondary": secondary}
	for record in rows:
		if record.vstate_id == selected_vstate_id and record.lord_id == selected_lord_id:
			_render_record(record)
			break
	_update_notice()


func _update_notice() -> void:
	var valid = selected_lord_id >= 0 and primary_choice.selected != secondary_choice.selected
	save_button.disabled = not service.supported() or not valid or not _drafts.has(str(selected_lord_id))
	if not service.supported():
		notice.text = "当前模组暂不支持君主性格设置。"
	elif not valid and selected_lord_id >= 0:
		notice.text = "主性格与副性格不能相同，请选择两种不同性格。"
	elif not _drafts.empty():
		notice.text = "%d位君主有未保存选择。切换名单会保留选择；点击“保存本局”应用当前君主。" % _drafts.size()
	elif not service.is_enabled():
		notice.text = "君主性格已关闭，AI沿用原有决策；本局性格设置仍保留。"
	else:
		notice.text = "性格随君主本人，继位后按新君主行事；本局设置请通过游戏存档保留。"


func _valid_selection() -> bool:
	if not opened or not can_open() or service.session_token() != _session:
		hide()
		return false
	if not service.supported():
		return false
	for current in service.current_factions(false):
		if current.vstate_id == selected_vstate_id and current.lord_id == selected_lord_id:
			return true
	_refresh()
	notice.text = "君主已更替，请确认现任君主后再保存。"
	return false


func _save_draft() -> void:
	if not _valid_selection() or not _drafts.has(str(selected_lord_id)):
		return
	var draft: Dictionary = _drafts[str(selected_lord_id)]
	if not service.set_manual(selected_lord_id, draft.primary, draft.secondary):
		notice.text = "未能保存，请检查主副性格是否不同。"
		return
	_drafts.erase(str(selected_lord_id))
	_refresh()
	notice.text = "已保存当前君主的本局性格，请通过游戏存档保留。"


func _reset_profile() -> void:
	if not _valid_selection():
		return
	service.reset_profile(selected_lord_id)
	_drafts.erase(str(selected_lord_id))
	_refresh()
	notice.text = "已恢复该武将默认性格，请通过游戏存档保留。"


func _enabled_changed(value: bool) -> void:
	if _populating:
		return
	if not opened or service.session_token() != _session or not service.supported():
		_refresh()
		return
	service.set_enabled(value)
	_update_notice()


func _request_close() -> void:
	if not _drafts.empty():
		discard_dialog.popup_centered(Vector2(min(620, rect_size.x - 32), 180))
		return
	hide()


func _input(event: InputEvent) -> void:
	if opened and visible and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE and get_viewport().get_modal_stack_top() == self:
		get_tree().set_input_as_handled()
		_request_close()


func _restore_state() -> void:
	if not opened:
		return
	opened = false
	var owner = get_focus_owner()
	if owner != null and is_a_parent_of(owner):
		owner.release_focus()
		OS.hide_virtual_keyboard()
	for state in pad_states:
		if is_instance_valid(state[0]):
			state[0].release_all_touches()
			state[0].emu_enable = state[1]
	pad_states.clear()
	if get_tree() != null:
		get_tree().paused = was_paused


func _closed() -> void:
	_restore_state()
	queue_free()
	if is_instance_valid(layer):
		layer.queue_free()


func _exit_tree() -> void:
	_restore_state()
