extends PopupPanel

const MobileLayout = preload("res://ios_mobile_layout.gd")
const PickerPanel = preload("res://ios_picker_panel.gd")
const SkillPicker = preload("res://ios_skill_picker.gd")
const LEVELS = ["LV1", "LV2", "LV3", "LV4", "LV5", "LV6", "LV7", "LV8"]
const SLOTS = ["武器", "防具", "道具", "坐骑"]
const MODES = ["war", "plain", "walldoor", "wallcity", "solo"]

var layer: CanvasLayer
var opened := false
var was_paused := false
var profiles := []
var actor_buttons := []
var side_choices := []
var level_inputs := []
var soldier_inputs := []
var equipment_buttons := []
var summaries := []
var mode_choice: OptionButton
var status: Label
var equipment_rows := {}


func open_manager() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	popup_exclusive = true
	for pad in get_tree().get_nodes_in_group("ios_virtual_pad"):
		pad.release_all_touches()
	profiles = [_make_profile(2), _make_profile(25)]
	_build()
	was_paused = get_tree().paused
	get_tree().paused = true
	opened = true
	connect("popup_hide", self, "_closed")
	popup_centered(Vector2(960, 560))
	_fit()
	_refresh_side(0)
	_refresh_side(1)
	set_process(true)


func _make_profile(actor_id: int) -> Dictionary:
	var actor = ActorHelper.actor(actor_id)
	var scopes: Array = SkillHelper.actor_skill_scopes(actor_id)
	var skills = {}
	for scope in scopes:
		skills[scope] = SkillHelper._raw_actor_skill_configuration(actor_id, scope, true)
	var equipment = {}
	for slot in SLOTS:
		equipment[slot] = actor.get_equip(slot).id
	var side: String = SkillHelper.actor_skill_scope(actor_id)
	if not side in scopes:
		side = scopes[0]
	return {"actor_id": actor_id, "side": side, "level": 8, "soldiers": 1000, "skills_by_scope": skills, "equipment": equipment}


func _button(text: String, parent: Node, target: String, arguments := []) -> Button:
	var result = PickerPanel.make_button(text, 0)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.clip_text = true
	result.connect("pressed", self, target, arguments)
	parent.add_child(result)
	return result


func _build() -> void:
	var fonts = Theme.new()
	fonts.default_font = Global.get_font(25)
	theme = fonts
	var style = StyleBoxFlat.new()
	style.bg_color = Color("28231f")
	style.border_color = Color("b79a6b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_stylebox_override("panel", style)
	var body = VBoxContainer.new()
	add_child(body)
	body.anchor_right = 1
	body.anchor_bottom = 1
	body.margin_left = 16
	body.margin_top = 12
	body.margin_right = -16
	body.margin_bottom = -12
	body.add_constant_override("separation", 8)
	var heading = HBoxContainer.new()
	body.add_child(heading)
	var title = Label.new()
	title.text = "战斗试炼场"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close = _button("关闭", heading, "hide")
	close.rect_min_size.x = 90
	close.size_flags_horizontal = 0
	mode_choice = OptionButton.new()
	mode_choice.rect_min_size.y = 48
	for text in ["大战场 · 谋略与移动", "白刃战 · 野战", "白刃战 · 城门", "白刃战 · 太守府", "单挑"]:
		mode_choice.add_item(text)
	mode_choice.select(1)
	mode_choice.connect("item_selected", self, "_mode_changed")
	body.add_child(mode_choice)
	var scrolling = ScrollContainer.new()
	scrolling.scroll_horizontal_enabled = false
	scrolling.scroll_deadzone = 6
	scrolling.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scrolling)
	var sides = HBoxContainer.new()
	sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_constant_override("separation", 16)
	scrolling.add_child(sides)
	for index in range(2):
		var side = VBoxContainer.new()
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.add_constant_override("separation", 6)
		sides.add_child(side)
		actor_buttons.append(_button("", side, "_open_actor_picker", [index]))
		var settings = HBoxContainer.new()
		side.add_child(settings)
		var scope = OptionButton.new()
		scope.rect_min_size = Vector2(114, 48)
		scope.connect("item_selected", self, "_side_changed", [index])
		settings.add_child(scope)
		side_choices.append(scope)
		var label = Label.new()
		label.text = "等级"
		settings.add_child(label)
		var level = SpinBox.new()
		level.min_value = 1
		level.max_value = 8
		level.rect_min_size = Vector2(96, 48)
		level.connect("value_changed", self, "_level_changed", [index])
		settings.add_child(level)
		level_inputs.append(level)
		var soldiers = settings
		var soldier_label = Label.new()
		soldier_label.text = "兵力"
		soldiers.add_child(soldier_label)
		var number = SpinBox.new()
		number.min_value = 1
		number.max_value = 9999
		number.step = 100
		number.rect_min_size = Vector2(80, 48)
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		number.connect("value_changed", self, "_soldiers_changed", [index])
		soldiers.add_child(number)
		soldier_inputs.append(number)
		_button("配置技能", side, "_open_skills", [index])
		var summary = Label.new()
		summary.autowrap = true
		summary.rect_min_size.y = 42
		summary.add_font_override("font", Global.get_font(18))
		side.add_child(summary)
		summaries.append(summary)
		var equipment = GridContainer.new()
		equipment.columns = 2
		side.add_child(equipment)
		var buttons = {}
		for slot in SLOTS:
			buttons[slot] = _button(slot, equipment, "_open_equipment", [index, slot])
			buttons[slot].add_font_override("font", Global.get_font(22))
		equipment_buttons.append(buttons)
	status = Label.new()
	status.text = "试炼使用独立战局；结束后返回原战役。攻守双方请选择不同武将。"
	status.autowrap = true
	status.rect_min_size.y = 50
	status.add_font_override("font", Global.get_font(18))
	body.add_child(status)
	var footer = HBoxContainer.new()
	body.add_child(footer)
	_button("交换攻守", footer, "_swap")
	_button("开始试炼", footer, "_start")


func _process(_delta: float) -> void:
	if visible:
		_fit()


func _fit() -> void:
	var available = MobileLayout.available_area(get_viewport(), 12, true)
	rect_size = Vector2(min(960, available.size.x), min(560, available.size.y))
	rect_position = available.position + (available.size - rect_size) * 0.5


func _refresh_side(index: int) -> void:
	var profile: Dictionary = profiles[index]
	var actor = ActorHelper.actor(profile.actor_id)
	actor_buttons[index].text = ("攻方 · " if index == 0 else "守方 · ") + actor.get_name()
	var choices: OptionButton = side_choices[index]
	choices.clear()
	var scopes: Array = SkillHelper.actor_skill_scopes(profile.actor_id)
	for scope in scopes:
		choices.add_item("普通" if scope == "default" else scope + "面")
	choices.select(max(0, scopes.find(profile.side)))
	choices.disabled = scopes.size() == 1
	level_inputs[index].value = profile.level
	soldier_inputs[index].value = profile.soldiers
	var names = []
	for level in LEVELS:
		var name: String = profile.skills_by_scope[profile.side].get(level, "")
		if not name.empty():
			names.append("%s %s" % [level, name])
	summaries[index].text = PoolStringArray(names).join("、") if not names.empty() else "当前面未配置技能。"
	for slot in SLOTS:
		var equip = actor.get_equip(slot).get_script().new(int(profile.equipment[slot]), slot)
		equipment_buttons[index][slot].text = slot + " · " + equip.name()
	_mode_changed(mode_choice.selected)


func _mode_changed(_mode: int) -> void:
	for number in soldier_inputs:
		number.editable = MODES[mode_choice.selected] != "solo"


func _side_changed(choice: int, index: int) -> void:
	if not _commit_numbers():
		side_choices[index].select(SkillHelper.actor_skill_scopes(profiles[index].actor_id).find(profiles[index].side))
		return
	profiles[index].side = SkillHelper.actor_skill_scopes(profiles[index].actor_id)[choice]
	_refresh_side(index)


func _level_changed(value: float, index: int) -> void:
	profiles[index].level = int(value)


func _soldiers_changed(value: float, index: int) -> void:
	profiles[index].soldiers = int(value)


func _swap() -> void:
	if not _commit_numbers():
		return
	profiles.invert()
	_refresh_side(0)
	_refresh_side(1)


func _open_actor_picker(index: int) -> void:
	if not _commit_numbers():
		return
	var picker = PickerPanel.new()
	add_child(picker)
	var body = picker.build_layout("选择试炼武将", false)
	var query = LineEdit.new()
	query.placeholder_text = "搜索姓名"
	query.clear_button_enabled = true
	query.rect_min_size.y = 48
	body.add_child(query)
	var list = ItemList.new()
	list.rect_min_size.y = 80
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_constant_override("vseparation", 14)
	body.add_child(list)
	query.connect("text_changed", self, "_filter_actors", [list])
	picker.connect("applied", self, "_actor_chosen", [index, list, picker])
	picker.apply_button.text = "选择武将"
	_filter_actors("", list)
	picker.show_adaptive(Vector2(760, 520))
	picker.modal_canvas.layer = 140


func _filter_actors(query: String, list: ItemList) -> void:
	list.clear()
	for actor_id in range(min(StaticManager.actors.size(), DataManager.actors.size())):
		var actor = ActorHelper.actor(actor_id)
		var name: String = actor.get_name()
		if not query.empty() and name.findn(query.strip_edges()) < 0:
			continue
		list.add_item("%s　武%d 知%d 统%d" % [name, actor.get_power(), actor.get_wisdom(), actor.get_leadership()])
		list.set_item_metadata(list.get_item_count() - 1, actor_id)
	if list.get_item_count() > 0:
		list.select(0)


func _actor_chosen(index: int, list: ItemList, picker: PopupPanel) -> void:
	var selected = list.get_selected_items()
	if selected.empty():
		return
	profiles[index] = _make_profile(int(list.get_item_metadata(selected[0])))
	_refresh_side(index)
	picker.hide()


func _open_skills(index: int) -> void:
	if not _commit_numbers():
		return
	var profile: Dictionary = profiles[index]
	var actor = ActorHelper.actor(profile.actor_id)
	var candidates = []
	for skill in StaticManager.skillDict.values():
		if skill.visible() and skill.exclusive_valid_for_actor(profile.actor_id) and (skill._gendersOnly.empty() or actor.get_gender() in skill._gendersOnly):
			candidates.append(skill.name)
	var picker = SkillPicker.new()
	add_child(picker)
	picker.connect("selection_applied", self, "_skills_chosen", [index, profile.side])
	var original = SkillHelper._raw_actor_skill_configuration(profile.actor_id, profile.side, false)
	picker.open_picker("试炼技能 · " + actor.get_name(), LEVELS, profile.skills_by_scope[profile.side], candidates, true, original)
	picker.save_notice.text = "只用于本次试炼；实际发动仍须满足技能条件。"
	picker.preset_menu.hide()
	picker.modal_canvas.layer = 140


func _skills_chosen(selection: Dictionary, levels: Array, index: int, scope: String) -> void:
	var native = SkillHelper._raw_actor_skill_configuration(profiles[index].actor_id, scope, false)
	for level in levels:
		profiles[index].skills_by_scope[scope][level] = native.get(level, "") if selection[level] == null else selection[level]
	_refresh_side(index)


func _equipments(slot: String) -> Array:
	if equipment_rows.has(slot):
		return equipment_rows[slot]
	var rows = []
	for equip in load("res://script/objects/clEquip.gd").all_equips(slot, true):
		rows.append(equip.id)
	equipment_rows[slot] = rows
	return rows


func _open_equipment(index: int, slot: String) -> void:
	if not _commit_numbers():
		return
	var picker = PickerPanel.new()
	add_child(picker)
	var body = picker.build_layout("试炼装备 · " + slot, false)
	var list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_constant_override("vseparation", 14)
	body.add_child(list)
	var description_scroll = ScrollContainer.new()
	description_scroll.rect_min_size.y = 100
	description_scroll.scroll_horizontal_enabled = false
	description_scroll.scroll_deadzone = 6
	body.add_child(description_scroll)
	var description = RichTextLabel.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.fit_content_height = true
	description.scroll_active = false
	description.bbcode_enabled = true
	description.add_font_override("normal_font", Global.get_font(18))
	description_scroll.add_child(description)
	var actor = ActorHelper.actor(profiles[index].actor_id)
	for value in _equipments(slot):
		var equip = actor.get_equip(slot).get_script().new(value, slot)
		list.add_item(equip.name())
		list.set_item_metadata(list.get_item_count() - 1, value)
		if value == profiles[index].equipment[slot]:
			list.select(list.get_item_count() - 1)
	list.connect("item_selected", self, "_equipment_highlighted", [list, index, slot, description])
	picker.connect("applied", self, "_equipment_chosen", [list, index, slot, picker])
	picker.apply_button.text = "选择装备"
	if not list.get_selected_items().empty():
		_equipment_highlighted(list.get_selected_items()[0], list, index, slot, description)
	picker.show_adaptive(Vector2(760, 520))
	picker.modal_canvas.layer = 140


func _equipment_highlighted(selected: int, list: ItemList, index: int, slot: String, description: RichTextLabel) -> void:
	var actor = ActorHelper.actor(profiles[index].actor_id)
	var equip = actor.get_equip(slot).get_script().new(int(list.get_item_metadata(selected)), slot)
	var details: Dictionary = StaticManager.get_equip_data(equip.id, slot)
	description.bbcode_text = "攻击＋%s　防御＋%s　重量%s\n%s" % [details.get("攻击力", 0), details.get("防御力", 0), details.get("重量", 0), equip.get_features_description()]


func _equipment_chosen(list: ItemList, index: int, slot: String, picker: PopupPanel) -> void:
	if list.get_selected_items().empty():
		return
	profiles[index].equipment[slot] = int(list.get_item_metadata(list.get_selected_items()[0]))
	_refresh_side(index)
	picker.hide()


func configuration() -> Dictionary:
	var result = {"mode": MODES[mode_choice.selected]}
	for index in range(2):
		var profile = profiles[index].duplicate(true)
		profile.skills = profile.skills_by_scope[profile.side].duplicate()
		result["left" if index == 0 else "right"] = profile
	return result


func _commit_numbers() -> bool:
	for index in range(2):
		for entry in [[level_inputs[index], "level", 1, 8], [soldier_inputs[index], "soldiers", 1, 9999]]:
			var text: String = entry[0].get_line_edit().text.strip_edges()
			if not text.is_valid_integer() or int(text) < entry[2] or int(text) > entry[3]:
				status.text = "等级请填写1～8，兵力请填写1～9999。"
				return false
			entry[0].value = int(text)
			profiles[index][entry[1]] = int(entry[0].value)
	return true


func _start() -> void:
	if not _commit_numbers():
		return
	if profiles[0].actor_id == profiles[1].actor_id:
		status.text = "双方请选择不同武将。"
		return
	var session = get_node_or_null("/root/TrialSession")
	if session == null:
		status.text = "试炼暂时无法启动，请重新打开游戏。"
		return
	get_tree().paused = was_paused
	var error: String = session.start_trial(configuration())
	if not error.empty():
		get_tree().paused = true
		status.text = error
		return
	opened = false
	hide()


func _closed() -> void:
	if opened:
		get_tree().paused = was_paused
		opened = false
	queue_free()
	if is_instance_valid(layer):
		layer.queue_free()


func _exit_tree() -> void:
	if opened and get_tree() != null:
		get_tree().paused = was_paused
