extends "res://scene/scene_title/Diy_Actor_Skill.gd"

const ATTRIBUTES = [["武", "武力"], ["知", "智力"], ["统", "统率"], ["政", "政治"], ["胆", "胆量"], ["德", "德行"], ["体", "体力"]]
const SKILL_LEVELS = ["LV1", "LV3", "LV5", "LV7"]
const SkillPicker = preload("res://ios_skill_picker.gd")
const PickerPanel = preload("res://ios_picker_panel.gd")

var picker: PopupPanel
var numbers := {}
var fixed_commoner := false
var power_modifier := 0

func _ready() -> void:
	var attributes = PickerPanel.make_button("自选属性")
	attributes.rect_position = Vector2(48, 213)
	attributes.rect_size.x = 112
	attributes.connect("pressed", self, "open_attribute_picker")
	add_child(attributes)

	var skills = PickerPanel.make_button("自选技能")
	skills.rect_position = Vector2(676, 76)
	skills.rect_size.x = 126
	skills.connect("pressed", self, "open_skill_picker")
	$con_Skill.add_child(skills)


func _skill_valid(skill_name: String) -> bool:
	if not skills_pool.has(skill_name):
		return false
	var tags: Array = skills_pool[skill_name]
	var gender: String = ActorHelper.actor(setting.actorId).get_gender()
	if ("男" in tags and gender != "男") or ("女" in tags and gender != "女"):
		return false
	return not (("仙" in tags and setting.mainProperty != "仙体") or ("武" in tags and setting.mainProperty == "仙体"))


func open_attribute_picker() -> void:
	var actor = ActorHelper.actor(setting.actorId)
	var bounds = _attribute_bounds(actor)
	power_modifier = actor.get_power() - actor._get_attr_int_original("武")
	numbers.clear()
	picker = PickerPanel.new()
	add_child(picker)
	picker.connect("applied", self, "_apply_attributes")
	var body = picker.build_layout("自选属性")
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 20)
	grid.add_constant_override("vseparation", 10)
	body.add_child(grid)
	for entry in ATTRIBUTES:
		var key: String = entry[0]
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_constant_override("separation", 8)
		grid.add_child(row)
		var caption = Label.new()
		caption.text = entry[1]
		caption.rect_min_size.x = 72
		row.add_child(caption)
		var lower = PickerPanel.make_button("−", 48)
		row.add_child(lower)
		var number = SpinBox.new()
		number.rect_min_size = Vector2(100, 48)
		number.get_line_edit().align = LineEdit.ALIGN_CENTER
		numbers[key] = number
		row.add_child(number)
		var higher = PickerPanel.make_button("＋", 48)
		row.add_child(higher)
		var range_label = Label.new()
		row.add_child(range_label)
		number.set_meta("bounds_label", range_label)
		var limits: Array = _health_bounds() if key == "体" else bounds[key]
		_set_stat_range(number, limits)
		number.value = actor.get_hp() if key == "体" else actor._get_attr_int_original(key)
		lower.disabled = limits[0] == limits[1]
		higher.disabled = lower.disabled
		number.editable = not lower.disabled
		lower.connect("pressed", self, "_step_attribute", [number, -1])
		higher.connect("pressed", self, "_step_attribute", [number, 1])
	numbers["武"].connect("value_changed", self, "_power_changed")
	var explanation = Label.new()
	explanation.text = "体力范围随武力变化；各项范围由武将类型决定。"
	body.add_child(explanation)
	picker.show_adaptive(Vector2(910, 430))


func _attribute_bounds(actor) -> Dictionary:
	var bounds = {"武": [10, 80], "知": [10, 80], "统": [10, 80], "政": [10, 80], "胆": [10, 80], "德": [10, 90]}
	match setting.mainProperty:
		"文臣":
			bounds.merge({"武": [10, 50], "知": [60, 90], "统": [30, 70], "政": [60, 90]}, true)
		"武将":
			bounds.merge({"武": [60, 90], "知": [30, 70], "统": [60, 90], "政": [10, 50]}, true)
	# The original has a separate all-ones state when first switching to 凡人.
	fixed_commoner = setting.mainProperty == "凡人" and actor.get_hp() == 10
	if fixed_commoner:
		for key in bounds:
			if actor._get_attr_int_original(key) != 1:
				fixed_commoner = false
				break
	if fixed_commoner:
		for key in bounds:
			bounds[key] = [1, 1]
	return bounds


func _health_bounds() -> Array:
	if fixed_commoner:
		return [10, 10]
	var power = int(numbers["武"].value) + power_modifier
	var lower = max(30, power - 10)
	return [lower, max(lower + 10, min(99, power + 10))]


func _set_stat_range(number: SpinBox, limits: Array) -> void:
	number.min_value = limits[0]
	number.max_value = limits[1]
	number.get_meta("bounds_label").text = "%d–%d" % [limits[0], limits[1]]


func _power_changed(_value: float) -> void:
	_set_stat_range(numbers["体"], _health_bounds())


func _step_attribute(number: SpinBox, step: int) -> void:
	_commit_stat_input(number)
	number.value += step


func _commit_stat_input(number: SpinBox) -> void:
	var text = number.get_line_edit().text.strip_edges()
	if number.editable and text.is_valid_integer():
		number.value = int(text)


func _apply_attributes() -> void:
	var actor = ActorHelper.actor(setting.actorId)
	for entry in ATTRIBUTES:
		var key: String = entry[0]
		var number: SpinBox = numbers[key]
		_commit_stat_input(number)
		if key == "体":
			actor.set_hp(number.value)
			actor._set_attr_int("原体力", int(number.value))
		else:
			actor._set_attr_int(key, int(number.value))
	update_actor_property()
	picker.hide()


func open_skill_picker() -> void:
	var actor = ActorHelper.actor(setting.actorId)
	var candidates := []
	for skill_name in skills_pool:
		if _skill_valid(skill_name):
			candidates.append(skill_name)
	var skill_picker = SkillPicker.new()
	add_child(skill_picker)
	skill_picker.set_meta("ios_equipment_actor", setting.actorId)
	skill_picker.connect("selection_applied", self, "_apply_skills")
	skill_picker.open_picker("自选技能", SKILL_LEVELS, actor.get_diy_skills(), candidates)


func _apply_skills(skills: Dictionary, levels: Array) -> void:
	var actor = ActorHelper.actor(setting.actorId)
	for level in levels:
		lock_skill_level(level)
	actor.set_diy_skills(skills)
	update_skill_cache()
	setting.save()
	skillDescription.hide()
	_update_skill_show()
