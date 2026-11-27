extends PopupPanel

signal locate_requested(city_id, actor_id)

const MobileLayout = preload("res://ios_mobile_layout.gd")
const SORT_FIELDS = [["忠诚", "忠"], ["武力", "武"], ["智力", "知"], ["政治", "政"], ["统率", "统"], ["等级", "等级"]]
const HEADERS = ["武将", "关押城", "忠", "武", "知", "政", "统", "级"]
const ROW_FIELDS = ["name", "city_name", "忠", "武", "知", "政", "统", "等级"]

var records := []
var filtered := []
var owner_id := -1
var selected_actor_id := -1
var opened := false
var was_paused := false
var pad_states := []
var layer: CanvasLayer
var search: LineEdit
var city_filter: OptionButton
var origin_filter: OptionButton
var sort_filter: OptionButton
var sort_direction: Button
var descending := false
var tree: Tree
var details: RichTextLabel
var count_label: Label
var notice: Label
var locate_button: Button
var _last_area := Rect2()
var _view_context := ""
var _view_generation := -1


static func current_owner_id() -> int:
	if DataManager.get_current_scene_id() != 10000 or FlowManager.controlNo != AutoLoad.playerNo:
		return -1
	if DataManager.vstate_no < 0 or DataManager.vstate_no >= DataManager.vstates_sort.size():
		return -1
	var current = int(DataManager.vstates_sort[DataManager.vstate_no])
	if current < 0 or current >= DataManager.vstates.size() or AutoLoad.playerNo < 0 or AutoLoad.playerNo >= DataManager.players.size():
		return -1
	# Host control number can also be zero while AI runs. Confirm that the local
	# player's actual controllable cities belong to the active faction as well.
	var player = DataManager.players[AutoLoad.playerNo]
	for city_id in player.get_control_citys():
		if city_id >= 0 and city_id < DataManager.citys.size() and clCity.city(city_id).get_vstate_id() == current:
			return current
	return -1


static func can_open() -> bool:
	return current_owner_id() >= 0


func open_manager() -> bool:
	if opened or not can_open():
		return false
	owner_id = current_owner_id()
	_view_context = _current_view_context()
	var saved_view := {}
	var cache = _view_cache()
	if cache != null:
		saved_view = cache.read_view(_view_context)
		_view_generation = cache.generation_token()
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
	_apply_saved_view(saved_view)
	set_process(true)
	return true


func _view_cache():
	return get_node_or_null("/root/PrisonViewState")


func _current_view_context() -> String:
	var player_no = AutoLoad.playerNo
	var actor_id = -1
	if player_no >= 0 and player_no < DataManager.players.size():
		actor_id = DataManager.players[player_no].actorId
	return "%s:%s:%s:%s" % [player_no, FlowManager.controlNo, actor_id, current_owner_id()]


func _apply_saved_view(state: Dictionary) -> void:
	if state.empty():
		return
	search.text = str(state.get("search", ""))
	_select_id(city_filter, int(state.get("city_id", -2)))
	_select_id(origin_filter, int(state.get("origin_id", -2)))
	for index in range(SORT_FIELDS.size()):
		if SORT_FIELDS[index][1] == state.get("sort_key", "忠"):
			sort_filter.select(index)
			break
	descending = bool(state.get("descending", false))
	selected_actor_id = int(state.get("actor_id", -1))
	_apply_filters()


func _remember_view() -> void:
	var cache = _view_cache()
	if not opened or cache == null or _view_context != _current_view_context():
		return
	cache.write_view(_view_context, _view_generation, {
		"search": search.text,
		"city_id": city_filter.get_selected_id(),
		"origin_id": _selected_origin_id(),
		"sort_key": SORT_FIELDS[sort_filter.selected][1],
		"descending": descending,
		"actor_id": selected_actor_id,
	})


func _build() -> void:
	var font_theme = Theme.new()
	font_theme.default_font = Global.get_font(25)
	theme = font_theme
	var style = StyleBoxFlat.new()
	style.bg_color = Color("28231f")
	style.border_color = Color("b79a6b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
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
	body.add_child(heading)
	var title = Label.new()
	title.text = "全势力俘虏"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	count_label = Label.new()
	heading.add_child(count_label)
	_button("刷新", "_refresh", heading, 90)
	_button("关闭", "hide", heading, 90)
	var filters = HBoxContainer.new()
	body.add_child(filters)
	search = LineEdit.new()
	search.placeholder_text = "搜索姓名或字"
	search.clear_button_enabled = true
	search.rect_min_size = Vector2(160, 48)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.connect("text_changed", self, "_filters_changed")
	search.connect("text_entered", self, "_finish_search")
	filters.add_child(search)
	city_filter = _option(filters, 160)
	origin_filter = _option(filters, 180)
	sort_filter = _option(filters, 140)
	for entry in SORT_FIELDS:
		sort_filter.add_item(entry[0] + "排序")
	sort_direction = _button("从低到高", "_reverse_sort", filters, 130)
	var content = HBoxContainer.new()
	content.add_constant_override("separation", 10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	tree = Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.columns = HEADERS.size()
	tree.column_titles_visible = true
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for index in range(HEADERS.size()):
		tree.set_column_title(index, HEADERS[index])
		tree.set_column_min_width(index, 95 if index < 2 else 43)
		tree.set_column_expand(index, index < 2)
	tree.connect("item_selected", self, "_selected")
	content.add_child(tree)
	var detail_panel = PanelContainer.new()
	detail_panel.rect_min_size.x = 295
	content.add_child(detail_panel)
	var scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	scroll.scroll_deadzone = 6
	detail_panel.add_child(scroll)
	details = RichTextLabel.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.fit_content_height = true
	details.scroll_active = false
	details.bbcode_enabled = false
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_color_override("default_color", Color("eee4d2"))
	scroll.add_child(details)
	var footer = HBoxContainer.new()
	body.add_child(footer)
	notice = Label.new()
	notice.autowrap = true
	notice.rect_min_size.y = 56
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(notice)
	locate_button = _button("定位关押城", "_locate_selected", footer, 180)


func _button(text: String, method: String, parent: Node, width: int) -> Button:
	var button = Button.new()
	button.text = text
	button.rect_min_size = Vector2(width, 48)
	button.connect("pressed", self, method)
	parent.add_child(button)
	return button


func _option(parent: Node, width: int) -> OptionButton:
	var option = OptionButton.new()
	option.rect_min_size = Vector2(width, 48)
	option.clip_text = true
	option.connect("item_selected", self, "_filter_selected", [option])
	parent.add_child(option)
	return option


func _process(_delta: float) -> void:
	if not opened:
		return
	if current_owner_id() != owner_id or _current_view_context() != _view_context:
		hide()
		return
	var cache = _view_cache()
	if cache != null and cache.generation_token() != _view_generation:
		hide()
		return
	_fit()
	_update_navigation()


func _fit() -> void:
	var available = MobileLayout.available_area(get_viewport(), 12.0, true)
	if available == _last_area:
		return
	_last_area = available
	rect_size = Vector2(min(980, available.size.x), min(560, available.size.y))
	rect_position = available.position + (available.size - rect_size) * 0.5


func _refresh() -> void:
	var selected_city = city_filter.get_selected_id() if city_filter.get_item_count() > 0 else -2
	var selected_origin = _selected_origin_id() if origin_filter.get_item_count() > 0 else -2
	records = _collect_records(owner_id)
	city_filter.clear()
	origin_filter.clear()
	city_filter.add_item("全部关押城", -2)
	origin_filter.add_item("全部原势力", -2)
	var cities = {}
	var origins = {}
	for record in records:
		cities[record.city_id] = record.city_name
		origins[record.origin_id] = record.origin_name
	var city_ids = cities.keys()
	var origin_ids = origins.keys()
	city_ids.sort()
	origin_ids.sort()
	for city_id in city_ids:
		city_filter.add_item(cities[city_id], city_id)
	for origin_id in origin_ids:
		# OptionButton reserves -1 for automatically assigned item IDs.
		origin_filter.add_item(origins[origin_id], -3 if origin_id == -1 else origin_id)
	_select_id(city_filter, selected_city)
	_select_id(origin_filter, selected_origin)
	_apply_filters()


func _collect_records(vstate_id: int) -> Array:
	var result = []
	if vstate_id < 0 or vstate_id != current_owner_id():
		return result
	var seen = {}
	for city in clCity.all_cities([vstate_id]):
		for actor_id in city.get_ceil_actor_ids():
			if actor_id < 0 or actor_id >= DataManager.actors.size() or seen.has(actor_id):
				continue
			seen[actor_id] = true
			var actor = ActorHelper.actor(actor_id)
			var origin_id = max(-1, actor.get_prev_vstate_id())
			var record = {"actor_id": actor_id, "city_id": city.ID, "city_name": city.get_name(), "name": actor.get_name(), "nick": str(DataManager.actors[actor_id].get("字", "")), "origin_id": origin_id, "origin_name": _vstate_name(origin_id), "忠": actor.get_loyalty(), "等级": actor.get_level()}
			for attribute in ["武", "知", "政", "统", "胆", "德"]:
				record[attribute] = actor._get_attr_int_original(attribute)
			result.append(record)
	return result


func _vstate_name(vstate_id: int) -> String:
	if vstate_id < 0 or vstate_id >= DataManager.vstates.size():
		return "无原势力记录"
	var record: Dictionary = DataManager.vstates[vstate_id]
	var lord_id = int(record.get("君主", -1))
	var name = ActorHelper.actor(lord_id).get_name() + "军" if lord_id >= 0 and lord_id < DataManager.actors.size() else "势力%d" % vstate_id
	if record.get("状态", "") == "灭亡":
		name += "（已灭亡）"
	return name


func _select_id(option: OptionButton, id: int) -> void:
	if option == origin_filter and id == -1:
		id = -3
	option.select(0)
	for index in range(option.get_item_count()):
		if option.get_item_id(index) == id:
			option.select(index)
			return


func _selected_origin_id() -> int:
	var id = origin_filter.get_selected_id()
	return -1 if id == -3 else id


func _filters_changed(_text: String) -> void:
	_apply_filters()


func _filter_selected(_index: int, option: OptionButton) -> void:
	if option == sort_filter:
		descending = sort_filter.selected != 0
	_apply_filters()


func _reverse_sort() -> void:
	descending = not descending
	_apply_filters()


func _finish_search(_text: String) -> void:
	search.release_focus()
	OS.hide_virtual_keyboard()


func _apply_filters() -> void:
	filtered.clear()
	var query = search.text.strip_edges()
	for record in records:
		if not query.empty() and record.name.findn(query) < 0 and record.nick.findn(query) < 0:
			continue
		if city_filter.get_selected_id() != -2 and record.city_id != city_filter.get_selected_id():
			continue
		if _selected_origin_id() != -2 and record.origin_id != _selected_origin_id():
			continue
		filtered.append(record)
	filtered.sort_custom(self, "_compare_records")
	sort_direction.text = "从高到低" if descending else "从低到高"
	count_label.text = "%d / %d 人" % [filtered.size(), records.size()]
	tree.clear()
	var root = tree.create_item()
	var active_item: TreeItem
	for index in range(filtered.size()):
		var record: Dictionary = filtered[index]
		var item = tree.create_item(root)
		item.set_metadata(0, index)
		item.set_custom_minimum_height(48)
		for column in range(ROW_FIELDS.size()):
			item.set_text(column, str(record[ROW_FIELDS[column]]))
			item.set_text_align(column, TreeItem.ALIGN_LEFT if column < 2 else TreeItem.ALIGN_CENTER)
		if record.actor_id == selected_actor_id:
			active_item = item
	if active_item == null and filtered.size() > 0:
		active_item = root.get_children()
	if active_item != null:
		active_item.select(0)
		_selected()
		tree.call_deferred("ensure_cursor_is_visible")
	else:
		selected_actor_id = -1
		details.text = "本方城池目前没有关押武将。" if records.empty() else "没有符合筛选条件的俘虏。"
	_update_navigation()


func _compare_records(a: Dictionary, b: Dictionary) -> bool:
	var key: String = SORT_FIELDS[sort_filter.selected][1]
	if a[key] == b[key]:
		return a.actor_id < b.actor_id
	return a[key] > b[key] if descending else a[key] < b[key]


func _selected() -> void:
	var item = tree.get_selected()
	if item == null:
		return
	var index = int(item.get_metadata(0))
	if index < 0 or index >= filtered.size():
		return
	var record: Dictionary = filtered[index]
	selected_actor_id = record.actor_id
	var actor = ActorHelper.actor(selected_actor_id)
	var lines = [record.name + ("　字" + record.nick if not record.nick.empty() else ""), "关押城：" + record.city_name, "原势力：" + record.origin_name, "忠诚：%d　等级：%d" % [record["忠"], record["等级"]], "", "基础属性", "武 %d　知 %d　统 %d" % [record["武"], record["知"], record["统"]], "政 %d　胆 %d　德 %d" % [record["政"], record["胆"], record["德"]], "体力：%d　经验：%d" % [actor.get_hp(), actor.get_exp()], "军种：" + str(DataManager.actors[selected_actor_id].get("军种", "")), "", "当前已解锁技能"]
	var names = []
	for skill_name in SkillHelper.get_actor_unlocked_skill_names(selected_actor_id).values():
		if skill_name is String and not skill_name.empty() and not skill_name in names:
			names.append(skill_name)
	lines.append("、".join(names) if not names.empty() else "无")
	details.text = "\n".join(lines)
	_update_navigation()


func _can_locate() -> bool:
	return opened and owner_id == current_owner_id() and DataManager.get_env_int("内政-玩家-步骤", -1) == 1 and selected_actor_id >= 0


func _update_navigation() -> void:
	if locate_button == null:
		return
	locate_button.disabled = not _can_locate()
	notice.text = "定位只移动大地图选城光标；处置俘虏请进入所在城的监狱。" if DataManager.get_env_int("内政-玩家-步骤", -1) == 1 else "返回大地图选城后可定位；当前只查看，不中断正在进行的内政操作。"


func _locate_selected() -> void:
	if not _can_locate():
		return
	var chosen = {}
	for record in filtered:
		if record.actor_id == selected_actor_id:
			chosen = record
			break
	if chosen.empty():
		return
	var city = clCity.city(chosen.city_id)
	if city.get_vstate_id() != owner_id or not selected_actor_id in city.get_ceil_actor_ids():
		_refresh()
		return
	var scene = SceneManager.current_scene()
	if scene == null or not scene.has_method("set_city_cursor_position"):
		return
	_finish_search("")
	DataManager.player_choose_city = chosen.city_id
	scene.set_city_cursor_position(chosen.city_id)
	scene.cursor.show()
	var actor_id = selected_actor_id
	var city_id = chosen.city_id
	hide()
	emit_signal("locate_requested", city_id, actor_id)


func _input(event: InputEvent) -> void:
	if opened and visible and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		if get_viewport().get_modal_stack_top() != self:
			return
		get_tree().set_input_as_handled()
		hide()


func _restore_state() -> void:
	if not opened:
		return
	_remember_view()
	opened = false
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
