extends Reference

const CATEGORIES = ["全部", "内政", "战场", "白刃战", "单挑", "攻城", "守城", "其他"]
const TAG_FILTERS = ["全部类型", "文系", "武系", "主动", "锁定", "诱发", "光环", "主将", "君主", "专属", "限定", "道术", "仙系"]
const ORIGINAL_TAGS = {"文系": "文", "武系": "武", "主将": "主将", "君主": "君主", "限定": "限定", "道术": "道术", "仙系": "仙"}
const TERRAIN_NAMES = {"wall": "城墙", "wallcity": "太守府", "walldoor": "城门", "plain": "平原", "forest": "树林", "mountain": "山地", "water": "水面", "river": "河流", "hill": "山地", "land": "平原", "desert": "沙漠", "swamp": "沼泽", "flame": "火原"}
const CITY_TERRAINS = ["wall", "wallcity", "walldoor"]
var entries := {}
var scene_overrides := {}


func _init() -> void:
	var file = File.new()
	if file.open("res://packed/data/skill_system/skill.json", File.READ) != OK:
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error == OK and parsed.result is Dictionary:
		entries = parsed.result
	if file.open("res://ios_skill_ratings.json", File.READ) == OK:
		parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error == OK and parsed.result is Dictionary:
			scene_overrides = parsed.result.get("scene_overrides", {})


func categories_for(skill_name: String) -> Array:
	var result := []
	var skill = StaticManager.get_skill(skill_name)
	if skill != null:
		match skill.scene:
			"内政": result.append("内政")
			"大战场": result.append("战场")
			"小战场": result.append("白刃战")
			"单挑": result.append("单挑")
	for effect in entries.get(skill_name, {}).get("效果", []):
		var scene_id = int(effect.get("场景ID", effect.get("ID", 0))) / 10000
		var category = {1: "内政", 2: "战场", 3: "白刃战", 4: "单挑"}.get(scene_id, "")
		if category != "" and not category in result:
			result.append(category)
		var city := false
		for field in ["地形要求", "地形限定"]:
			for terrain in _array(effect.get(field, [])):
				city = city or terrain in CITY_TERRAINS
		for field in ["身份限定", "攻守限定"]:
			var side = str(effect.get(field, ""))
			if city and side in ["攻方", "守方", "攻击方", "防守方"]:
				category = "攻城" if side in ["攻方", "攻击方"] else "守城"
				if not category in result:
					result.append(category)
	if result.empty():
		result.append("其他")
	if scene_overrides.has(skill_name):
		var specialized = []
		for category in result:
			if category in ["攻城", "守城"]:
				specialized.append(category)
		result = scene_overrides[skill_name].duplicate() + specialized
	return result


func tags_for(skill_name: String) -> Array:
	var data: Dictionary = entries.get(skill_name, {})
	var result = []
	var tags = _array(data.get("标签", []))
	for label in ORIGINAL_TAGS:
		if ORIGINAL_TAGS[label] in tags:
			result.append(label)
	var kind = str(data.get("类型", ""))
	if kind in ["主动", "锁定", "诱发"]:
		result.append(kind)
	if not _array(data.get("专属", [])).empty():
		result.append("专属")
	for effect in data.get("效果", []):
		if effect.get("类型", "") == "光环" and not "光环" in result:
			result.append("光环")
		var identity = str(effect.get("身份限定", ""))
		if identity in ["主将", "君主"] and not identity in result:
			result.append(identity)
	return result


func matches(skill_name: String, category: String, query: String, tag := "全部类型") -> bool:
	if category != "全部" and not category in categories_for(skill_name):
		return false
	if tag != "全部类型" and not tag in tags_for(skill_name):
		return false
	if query.empty() or skill_name.findn(query) >= 0:
		return true
	var skill = StaticManager.get_skill(skill_name)
	return skill != null and skill.raw_description.findn(query) >= 0


func conditions_for(skill_name: String) -> String:
	var data: Dictionary = entries.get(skill_name, {})
	var lines := []
	var genders = _array(data.get("性别", []))
	if not genders.empty():
		lines.append("适用性别：" + PoolStringArray(genders).join("、"))
	if not _array(data.get("专属", [])).empty():
		lines.append("专属技能")
	var effects: Array = data.get("效果", [])
	for i in range(effects.size()):
		var effect: Dictionary = effects[i]
		var parts := []
		# Trigger dispatch scope is not the effect's recipient (general vs soldiers).
		# Keep recipients in the original description rather than mislabelling them.
		for field in ["身份限定", "攻守限定"]:
			if effect.has(field):
				parts.append(field + "：" + str(effect[field]))
		for field in ["地形要求", "地形限定", "地形排除"]:
			if effect.has(field):
				var names := []
				for terrain in _array(effect[field]):
					names.append(TERRAIN_NAMES.get(str(terrain), str(terrain)))
				parts.append(field + "：" + PoolStringArray(names).join("、"))
		for field in ["次数", "机动力消耗", "战争天数"]:
			if effect.has(field):
				var value = effect[field]
				parts.append(field + "：" + ("按技能说明计算" if value is int and value < 0 else str(value)))
		if effect.has("触发条件"):
			parts.append("另有发动条件，见技能说明")
		if not parts.empty():
			var line = PoolStringArray(parts).join("；")
			if not line in lines:
				lines.append(line)
	if lines.empty():
		return "具体生效条件见技能说明。"
	return "各项效果的条件\n" + PoolStringArray(lines).join("\n") + "\n其余限制与作用对象以技能说明为准。"


func _array(value) -> Array:
	if value is Array:
		return value
	return [] if value == null or str(value).empty() else [value]


func configuration_notes(skill_names: Array, include_general := true) -> Array:
	var notes := []
	var city_configuration := false
	for skill_name in skill_names:
		var categories = categories_for(str(skill_name))
		city_configuration = city_configuration or "攻城" in categories or "守城" in categories
	if city_configuration:
		for skill_name in skill_names:
			for effect in entries.get(str(skill_name), {}).get("效果", []):
				var excluded = _array(effect.get("地形排除", []))
				if "wall" in excluded and "wallcity" in excluded and "walldoor" in excluded:
					var note = "【%s】有排除城墙、城门和太守府的效果，攻守城时这些效果不会触发。" % skill_name
					if not note in notes:
						notes.append(note)
	# Verified against the original 2.560 effect_30109 and effect_30101 implementations.
	if include_general and "连弩" in skill_names:
		notes.append("【连弩】会把士兵射程设为3，并禁止火矢；不能把相关加成简单相加。")
	if include_general and "玄阵" in skill_names and "精盾" in skill_names:
		notes.append("【玄阵】与【精盾】的格挡率不叠加。")
	return notes
