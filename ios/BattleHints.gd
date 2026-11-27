extends Control

const WAR_SCENE = 20000
const BATTLE_SCENE = 30000
const WATCH_INTERVAL = 0.25
const SkillCatalog = preload("res://ios_skill_catalog.gd")
const EquipmentInspector = preload("res://ios_equipment_skill_inspector.gd")
const MobileLayout = preload("res://ios_mobile_layout.gd")

var entry: Button
var panel: PopupPanel
var actor_choice: OptionButton
var context_text: RichTextLabel
var skills_text: RichTextLabel
var records_text: RichTextLabel
var observed_scene := -1
var watch_elapsed := 0.0
var actor_ids := []
var was_paused := false
var previous_emu := true
var owns_pause := false
var catalog


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_mode = Node.PAUSE_MODE_PROCESS
	catalog = SkillCatalog.new()
	entry = _button("战况", 82)
	entry.connect("pressed", self, "open_panel")
	add_child(entry)
	entry.hide()
	_build_panel()
	get_viewport().connect("size_changed", self, "_fit_panel")
	var image_menu = SceneManager.get_node_or_null("tool_layer/image_menu")
	if image_menu != null:
		image_menu.connect("visibility_changed", self, "_refresh_entry")
	_refresh_entry()


func _process(delta: float) -> void:
	watch_elapsed += delta
	if watch_elapsed < WATCH_INTERVAL:
		return
	watch_elapsed = 0.0
	_refresh_entry()


func _refresh_entry() -> void:
	var source = get_parent().get_node_or_null("btnShowSkill")
	var scene_id = DataManager.get_current_scene_id()
	var in_combat = scene_id == WAR_SCENE or scene_id == BATTLE_SCENE
	var image_menu = SceneManager.get_node_or_null("tool_layer/image_menu")
	var choosing_formation = image_menu != null and image_menu.is_visible_in_tree() and image_menu.has_method("project_formation") and image_menu.get("_formation_mode") == true
	entry.visible = in_combat and not choosing_formation and source != null and get_parent().is_visible_in_tree() and get_parent().emu_enable
	if source != null:
		entry.rect_position = source.rect_position + Vector2(source.rect_size.x + 8, 0)
		entry.rect_size = Vector2(82, max(48, source.rect_size.y))
	if panel.visible and scene_id != observed_scene:
		panel.hide()


func _button(title: String, width := 100) -> Button:
	var button = Button.new()
	button.text = title
	button.rect_min_size = Vector2(width, 48)
	button.add_font_override("font", Global.get_font(25))
	return button


func _build_panel() -> void:
	panel = PopupPanel.new()
	panel.popup_exclusive = true
	panel.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(panel)
	panel.set_as_toplevel(true)
	panel.connect("popup_hide", self, "_closed")
	var colors = StyleBoxFlat.new()
	colors.bg_color = Color("28231f")
	colors.border_color = Color("b79a6b")
	colors.set_border_width_all(2)
	colors.set_corner_radius_all(8)
	panel.add_stylebox_override("panel", colors)
	var theme = Theme.new()
	theme.default_font = Global.get_font(25)
	panel.theme = theme
	var layout = VBoxContainer.new()
	panel.add_child(layout)
	layout.anchor_right = 1.0
	layout.anchor_bottom = 1.0
	layout.margin_left = 16
	layout.margin_top = 12
	layout.margin_right = -16
	layout.margin_bottom = -12
	layout.add_constant_override("separation", 8)
	var heading = HBoxContainer.new()
	layout.add_child(heading)
	var title = Label.new()
	title.text = "战况与技能"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close = _button("返回战场")
	close.connect("pressed", panel, "hide")
	heading.add_child(close)
	actor_choice = OptionButton.new()
	actor_choice.rect_min_size.y = 48
	actor_choice.connect("item_selected", self, "_actor_selected")
	layout.add_child(actor_choice)
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)
	context_text = _text_page(tabs, "当前战况")
	skills_text = _text_page(tabs, "武将技能")
	records_text = _text_page(tabs, "最近记录")
	records_text.bbcode_enabled = false


func _text_page(tabs: TabContainer, title: String) -> RichTextLabel:
	var scroll = ScrollContainer.new()
	scroll.name = title
	scroll.scroll_horizontal_enabled = false
	scroll.scroll_deadzone = 6
	tabs.add_child(scroll)
	var text = RichTextLabel.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.fit_content_height = true
	text.scroll_active = false
	text.bbcode_enabled = true
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_color_override("default_color", Color("eee4d2"))
	scroll.add_child(text)
	return text


func _fit_panel() -> void:
	if not panel.visible:
		return
	var area = MobileLayout.available_area(get_viewport(), 16.0, false)
	var size = Vector2(min(940, area.size.x), min(550, area.size.y))
	panel.rect_size = size
	panel.rect_position = area.position + (area.size - size) * 0.5


func open_panel() -> void:
	if panel.visible:
		return
	observed_scene = DataManager.get_current_scene_id()
	if not observed_scene in [WAR_SCENE, BATTLE_SCENE]:
		return
	was_paused = get_tree().paused
	previous_emu = get_parent().emu_enable
	get_parent().emu_enable = false
	entry.hide()
	if get_parent().has_method("release_all_touches"):
		get_parent().release_all_touches()
	elif get_parent().has_method("_clear_direction_touches"):
		get_parent()._clear_direction_touches()
	for action in ["ANALOG_UP", "ANALOG_DOWN", "ANALOG_LEFT", "ANALOG_RIGHT", "EMU_A", "EMU_B", "EMU_X", "EMU_Y", "EMU_START", "EMU_SELECT"]:
		Input.action_release(action)
	get_tree().paused = true
	owns_pause = true
	_collect_actors()
	context_text.bbcode_text = _context_description()
	records_text.text = _record_description()
	_actor_selected(actor_choice.selected)
	panel.popup_centered(Vector2(940, 550))
	_fit_panel()


func _closed() -> void:
	if not owns_pause:
		return
	owns_pause = false
	if is_instance_valid(get_parent()):
		get_parent().emu_enable = previous_emu
	get_tree().paused = was_paused


func _exit_tree() -> void:
	_closed()


func _collect_actors() -> void:
	actor_ids.clear()
	actor_choice.clear()
	var candidates := []
	if observed_scene == BATTLE_SCENE:
		var fight = DataManager.get_current_battle_fight()
		if fight != null:
			for wa in [fight.get_attacker(), fight.get_defender()]:
				if wa != null:
					candidates.append(wa)
	else:
		var war = DataManager.get_current_war_fight()
		if war != null:
			candidates = war.get_war_actors(false, true)
	for wa in candidates:
		if wa == null:
			continue
		if observed_scene == WAR_SCENE and (wa.disabled or wa.is_concealed or wa.position.x < 0):
			continue
		if wa.actorId in actor_ids:
			continue
		actor_ids.append(wa.actorId)
		actor_choice.add_item(wa.get_name())
	var selected = actor_ids.find(DataManager.player_choose_actor)
	if selected >= 0:
		actor_choice.select(selected)
	actor_choice.disabled = actor_ids.empty()
	if actor_ids.empty():
		actor_choice.add_item("当前没有可查看的武将")


func _context_description() -> String:
	var text = "查看期间战场暂停，返回后继续。\n\n"
	if observed_scene == WAR_SCENE:
		var war = DataManager.get_current_war_fight()
		if war != null:
			text += "[color=#dfbd7c]大战场　第%d日[/color]\n\n" % war.date
		text += "选择武将查看当前持续效果、技能条件与冷却。\n\n城门与太守府的白刃战规则不同，进入交战后这里会显示对应说明。"
		return text
	var fight = DataManager.get_current_battle_fight()
	if fight == null:
		return text + "当前交战信息尚未就绪。"
	var terrain = fight.get_terrian()
	var terrain_name = fight.get_terrian_cn()
	text += "[color=#dfbd7c]白刃战 · %s[/color]\n" % terrain_name
	text += "攻方：%s　守方：%s\n\n" % [_fighter_name(fight.get_attacker()), _fighter_name(fight.get_defender())]
	if terrain == "walldoor":
		text += "[color=#dfbd7c]城门[/color]\n城门耐久独立结算：普通近身攻击基础减5，射箭或投掷基础减1，象或象将近身基础减15，再计入攻击方的城门增伤。\n\n"
		var war = DataManager.get_current_war_fight()
		if war != null:
			text += "当前城门耐久：%d\n\n" % war.target_city().get_door_hp(fight.get_position())
	elif terrain == "wallcity":
		text += "[color=#dfbd7c]太守府[/color]\n"
		if DataManager.diffculities >= 3:
			text += "当前难度下，守方射击距离超过4格且未处于强弩状态时，射击倍率减半。\n\n"
		else:
			text += "当前难度未启用守方远距离射击倍率减半规则。\n\n"
	if DataManager.diffculities >= 3 and terrain in ["walldoor", "wallcity"]:
		text += "守方近身伤害倍率至少为100%，弓兵贴身时也需要留意。\n\n"
	text += "技能说明中的“你”可能只指武将本人；注明士兵、全军或特定兵种的效果才作用于对应单位。技能有攻守方、主将、地形及阶段条件时，以该项条件为准。"
	return text


func _fighter_name(wa) -> String:
	return "待定" if wa == null else wa.get_name()


func _actor_selected(index: int) -> void:
	if index < 0 or index >= actor_ids.size():
		skills_text.bbcode_text = "当前没有可查看的武将。"
		return
	var actor_id: int = actor_ids[index]
	var wa = DataManager.get_war_actor(actor_id)
	if wa == null:
		skills_text.bbcode_text = "该武将已离开战场。"
		return
	var text = "[color=#dfbd7c]%s[/color]\n" % wa.get_name()
	text += "机动力：%d　战术值：%d\n\n" % [wa.action_point, wa.battle_tactic_point]
	text += "[color=#dfbd7c]持续效果[/color]\n"
	var buffs = wa.get_buff_names()
	if buffs.empty():
		text += "当前没有持续效果。\n"
	for buff_name in buffs:
		var buff = wa.get_buff(buff_name)
		var turns = int(buff.get("回合数", 0))
		if turns <= 0:
			continue
		text += "%s：%s\n" % [buff_name, "持续生效" if turns >= 9999 else "剩余%d回合" % turns]
	text += "\n[color=#dfbd7c]当前场景技能[/color]\n"
	if DataManager.get_game_setting("技能系统") != "是":
		skills_text.bbcode_text = text + "本局未开启技能系统。"
		return
	var names := []
	for item in SkillHelper.get_actor_all_skills(actor_id, observed_scene, false):
		if item is Array and not item.empty():
			var skill = item[0]
			if skill != null and not skill.name in names:
				names.append(skill.name)
	if names.empty():
		text += "本场景没有已解锁技能。\n"
	var interactions = EquipmentInspector.new().inspect(actor_id, names)
	if not interactions.empty():
		text += "\n[color=#dfbd7c]装备与技能[/color]\n" + PoolStringArray(interactions).join("\n\n") + "\n"
	for skill_name in names:
		var skill = StaticManager.get_skill(skill_name)
		if skill == null:
			continue
		text += "\n" + skill.get_runtime_description() + "\n"
		text += catalog.conditions_for(skill_name) + "\n"
		var reasons = SkillHelper.get_actor_skill_disabled_reason(observed_scene, actor_id, skill_name)
		if not reasons.empty():
			text += "[color=#e8a59a]当前受限：%s[/color]\n" % reasons[0]
		var cooldown = 0
		for effect in skill.effects:
			if effect.sceneId == observed_scene:
				cooldown = max(cooldown, SkillHelper.get_skill_cd(observed_scene, effect.id, actor_id, skill_name))
		if cooldown >= 9999:
			text += "[color=#dfbd7c]次数已用，等待重置[/color]\n"
		elif cooldown > 0:
			text += "[color=#dfbd7c]冷却剩余%d回合[/color]\n" % cooldown
	text += "\n持续效果按各自所属场景结算回合。未显示受限或冷却，仅表示没有这些限制，技能仍需满足说明中的发动条件。"
	skills_text.bbcode_text = text


func _record_description() -> String:
	var source = DataManager.war_log
	if observed_scene == BATTLE_SCENE:
		var fight = DataManager.get_current_battle_fight()
		if fight == null:
			return "当前没有交战记录。"
		source = fight.battle_log
	var lines := []
	for item in source:
		if item is String:
			lines.append(item)
		elif item is Dictionary:
			for key in ["文字", "信息", "内容", "text", "msg", "message"]:
				if item.get(key, null) is String and not item[key].empty():
					lines.append(item[key])
					break
	if lines.empty():
		return "当前没有文字记录。可切换到“武将技能”查看当前持续效果、禁用原因与冷却。"
	var recent = PoolStringArray(lines.slice(max(0, lines.size() - 30), lines.size() - 1)).join("\n\n")
	var tags = RegEx.new()
	tags.compile("<[a-zA-Z]([^<>]*)>")
	return tags.sub(recent, "$1", true)
