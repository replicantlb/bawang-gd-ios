extends Node

const Badge = preload("res://ios_rating_badge.gd")
const FONT = "res://resource/font/FandolSong-Bold/12.tres"
const COLORS = {"S": "#f4ce66", "A": "#eda27f", "B": "#8fd0ba", "C": "#b9c3d5", "D": "#969696", "?": "#aaaaaa"}
const SCENES = {"大战场": "战场", "小战场": "白刃战", "攻城": "白刃战", "守城": "白刃战"}
var ratings := {}
var primary_scenes := {}
var display_aliases := {}
var header_pattern = RegEx.new()
var decoration_pattern = RegEx.new()
var slot_pattern = RegEx.new()
var elapsed := 0.0


func _init() -> void:
	var file = File.new()
	if file.open("res://ios_skill_ratings.json", File.READ) == OK:
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error == OK and parsed.result is Dictionary:
			ratings = parsed.result.get("skills", {})
			primary_scenes = parsed.result.get("primary_scenes", {})
			display_aliases = parsed.result.get("display_aliases", {})
	header_pattern.compile("【([^】\\n]{1,20})】")
	var part = "\\[color=#[0-9a-fA-F]{6}\\](?:内政|战场|白刃战|单挑)?[SABCD?]\\[/color\\]"
	decoration_pattern.compile("(【[^】\\n]{1,20}】)\\[font=" + FONT.replace(".", "\\.") + "\\] " + part + "(?:/" + part + ")*\\[/font\\]")
	slot_pattern.compile("^(?:LV[1-8]\\s+)?([^＊*\\s:：（）]+)(?:[＊*]|[：:].*|（.*）)?$")


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS


func _canonical_name(text: String) -> String:
	return str(display_aliases.get(text, text))


func facets_for(skill_name: String, category := "全部") -> Array:
	var data: Dictionary = ratings.get(skill_name, {})
	var scene = SCENES.get(category, category)
	if scene in ["内政", "战场", "白刃战", "单挑"]:
		return [scene] if data.has(scene) else []
	var result = []
	for facet in primary_scenes.get(skill_name, []):
		if data.has(facet) and not facet in result:
			result.append(facet)
	if result.empty():
		for facet in ["内政", "战场", "白刃战", "单挑"]:
			if data.has(facet):
				result.append(facet)
	return result


func grade_values(skill_name: String, category := "全部") -> Array:
	var result = []
	for facet in facets_for(skill_name, category):
		result.append(ratings[skill_name][facet].get("grade", "?"))
	return result if not result.empty() else ["?"]


func matches_grade(skill_name: String, category: String, grade: String) -> bool:
	return grade == "全部评级" or grade in grade_values(skill_name, category)


func explanation(skill_name: String) -> String:
	var lines = ["参考评级（按各自场景评价）"]
	for facet in ["内政", "战场", "白刃战", "单挑"]:
		var record = ratings.get(skill_name, {}).get(facet, null)
		if record is Dictionary:
			lines.append("%s %s：%s" % [facet, record.get("grade", "?"), record.get("reason", "尚待评价")])
	if lines.size() == 1:
		lines.append("待评：当前缺少足够依据。")
	return PoolStringArray(lines).join("\n")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.3:
		return
	elapsed = 0.0
	annotate(get_tree().root)


func annotate(node: Node) -> void:
	if node.has_meta("ios_rating_decoration"):
		return
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	_decorate_skill_detail(node)
	if node is RichTextLabel:
		_decorate_rich_text(node)
	elif node is Button or node is Label:
		_decorate_name(node)
	for child in node.get_children():
		annotate(child)


func _skill_name(node: Control) -> String:
	if node.has_meta("ios_rating_exempt") and node.get_meta("ios_rating_exempt"):
		return ""
	if node.has_meta("ios_rating_skill"):
		return str(node.get_meta("ios_rating_skill"))
	var text = node.text.strip_edges()
	if text.begins_with("< "):
		text = text.substr(2)
	if text.ends_with(" >"):
		text = text.substr(0, text.length() - 2)
	if node is Label and not _in_skill_area(node) and not text.begins_with("LV") and text.find("【") < 0:
		return ""
	var canonical = _canonical_name(text)
	if ratings.has(canonical):
		return canonical
	var slot = slot_pattern.search(text)
	if slot != null and ratings.has(_canonical_name(slot.get_string(1))):
		return _canonical_name(slot.get_string(1))
	var headers = header_pattern.search_all(text)
	if headers.size() == 1 and ratings.has(_canonical_name(headers[0].get_string(1))):
		return _canonical_name(headers[0].get_string(1))
	return ""


func _in_skill_area(node: Node) -> bool:
	var ancestor = node
	for _depth in range(8):
		if ancestor == null:
			return false
		var script = ancestor.get_script()
		var path = ancestor.filename + (script.resource_path if script != null else "") + str(ancestor.name)
		if path.to_lower().find("skill") >= 0 or path.find("技能") >= 0:
			return true
		ancestor = ancestor.get_parent()
	return false


func _decorate_name(node: Control) -> void:
	var name = _skill_name(node)
	var badge = node.get_node_or_null("IOSSkillRating")
	if name.empty():
		if badge != null:
			badge.hide()
		if node.has_meta("ios_rating_tooltip"):
			if node.hint_tooltip == node.get_meta("ios_rating_tooltip"):
				node.hint_tooltip = str(node.get_meta("ios_rating_original_tooltip")) if node.has_meta("ios_rating_original_tooltip") else ""
			node.remove_meta("ios_rating_tooltip")
			if node.has_meta("ios_rating_original_tooltip"):
				node.remove_meta("ios_rating_original_tooltip")
		return
	var category = str(node.get_meta("ios_rating_scene")) if node.has_meta("ios_rating_scene") else "全部"
	var values = grade_values(name, category)
	if badge == null:
		badge = Badge.new()
		badge.name = "IOSSkillRating"
		node.add_child(badge)
	badge.visible = node.rect_size.x >= 30 and node.rect_size.y >= 20
	if badge.grades != values:
		badge.show_grades(values)
	var last = str(node.get_meta("ios_rating_tooltip")) if node.has_meta("ios_rating_tooltip") else ""
	if node.hint_tooltip != last:
		node.set_meta("ios_rating_original_tooltip", node.hint_tooltip)
	var original = str(node.get_meta("ios_rating_original_tooltip")) if node.has_meta("ios_rating_original_tooltip") else ""
	var tooltip = (original + "\n\n" if not original.empty() else "") + explanation(name)
	if tooltip != last:
		node.hint_tooltip = tooltip
		node.set_meta("ios_rating_tooltip", tooltip)


func _decorate_rich_text(node: RichTextLabel) -> void:
	if not node.bbcode_enabled:
		return
	var current = node.bbcode_text
	if node.has_meta("ios_rating_rendered") and current == node.get_meta("ios_rating_rendered"):
		return
	# Only decorate named skill headers. Ordinary narrative and numerical text stay intact.
	if current.find("【") < 0:
		return
	var source = decoration_pattern.sub(current, "$1", true)
	var matches = header_pattern.search_all(source)
	if matches.empty():
		return
	var rendered = source
	for index in range(matches.size() - 1, -1, -1):
		var found = matches[index]
		var name = _canonical_name(found.get_string(1))
		if not ratings.has(name):
			continue
		var labels = []
		for facet in facets_for(name):
			var grade = str(ratings[name][facet].get("grade", "?"))
			var multiple = facets_for(name).size() > 1
			labels.append("[color=%s]%s%s[/color]" % [COLORS.get(grade, COLORS["?"]), facet if multiple else "", grade])
		var suffix = "[font=%s] %s[/font]" % [FONT, PoolStringArray(labels).join("/")]
		rendered = rendered.insert(found.get_end(), suffix)
	if rendered != current:
		node.set_meta("ios_rating_rendered", rendered)
		node.bbcode_text = rendered


func _decorate_skill_detail(node: Node) -> void:
	var script = node.get_script()
	if script == null or not script.resource_path in ["res://info/skill_detail.gdc", "res://info/skill_detail.gd"]:
		return
	var skill = node.get("skill")
	if skill == null or not ratings.has(skill.name):
		return
	for section in ["技能效果", "创作背景", "所属武将"]:
		var title = node.get_node_or_null("detail/" + section + "/header/name")
		if title != null:
			title.set_meta("ios_rating_skill", skill.name)
	var effect = node.get_node_or_null("detail/技能效果/effect")
	if not effect is RichTextLabel:
		return
	var previous = str(effect.get_meta("ios_rating_detail")) if effect.has_meta("ios_rating_detail") else ""
	var decorated = str(effect.get_meta("ios_rating_rendered")) if effect.has_meta("ios_rating_rendered") else ""
	if effect.bbcode_text == previous or (not decorated.empty() and effect.bbcode_text == decorated):
		return
	var text = effect.bbcode_text
	var old_suffix = str(effect.get_meta("ios_rating_detail_suffix")) if effect.has_meta("ios_rating_detail_suffix") else ""
	if not old_suffix.empty() and text.ends_with(old_suffix):
		text = text.substr(0, text.length() - old_suffix.length())
	var suffix = "\n\n" + explanation(skill.name) + "\n\nS 极强 · A 强 · B 实用 · C 局限明显 · D 弱或负面\n评级按适用身份和条件判断，组合、等级与装备会改变表现。"
	var rendered = text + suffix
	effect.set_meta("ios_rating_detail_suffix", suffix)
	effect.set_meta("ios_rating_detail", rendered)
	effect.bbcode_text = rendered
