extends Reference

# These are presentation checks against the original 2.560 rules. They never
# equip items, change a side, apply a skill, or run a combat effect.
# Sources inside resource/bwdl.pck: effects 20380/40002 (龙魂), 40004
# (无前, also present in 无双), 30101/30170 (玄阵/精盾), 30109 (连弩),
# 30024/30029 (藤甲/巨象); packed/data/equip/*.json and description/skills.json.
# Equipment previews use independent native clEquip instances so modded item
# data and scene equipment restrictions are handled by the original accessors.
const SLOTS = ["武器", "防具", "道具", "坐骑"]
const YANYUE_ID = 15
const JIEZISHU_ID = 12
const WUZI_ID = 15
const SIMA_STUDENTS = ["司马师", "司马昭"]
const PERSONAL_SHOOTING = ["烈弓", "漫射"]


func inspect(actor_id: int, skill_names: Array, side := "", equipment_overrides := {}) -> Array:
	if actor_id < 0 or actor_id >= DataManager.actors.size():
		return []
	var actor = ActorHelper.actor(actor_id)
	var names = []
	for value in skill_names:
		if value is String and not value.empty() and not value in names:
			names.append(value)
	var notes = []
	var equipment = equipment_for(actor_id, equipment_overrides)
	if equipment.empty():
		return notes
	for slot in SLOTS:
		var item: Dictionary = equipment[slot]
		if item.get("preview_invalid", false):
			notes.append("预览提示：%s的候选装备无效，按已保存装备检查。" % slot)
		if item.disabled:
			notes.append("当前限制：%s「%s」已被禁用，不按其装备词条取得收益；按装备编号判断的技能仍须看各自条件。" % [slot, item.name])
	var weapon: Dictionary = equipment["武器"]
	var jewelry: Dictionary = equipment["道具"]
	var steed: Dictionary = equipment["坐骑"]
	if "龙魂" in names:
		if weapon.id != YANYUE_ID:
			notes.append("条件收益：【龙魂】未持青龙偃月刀时，提供单挑暴击率＋20%；此分支不附加【神武】。")
		else:
			var phase = _current_five_phase(actor_id, side)
			var state = "须在战场满足金或水五行"
			if phase == "金" or phase == "水":
				state = "当前战场五行为%s，已满足五行条件" % phase
			elif not phase.empty():
				state = "当前战场五行为%s，尚未满足金或水条件" % phase
			notes.append("分支切换：持青龙偃月刀时，【龙魂】自身的单挑＋20%%暴击分支关闭，改为附加【神武】；%s。青龙刀自带的暴击词条另行结算。" % state)
	if "无双" in names and "无前" in names:
		notes.append("效果重合：【无双】已带【无前】效果，免疫暴击这一部分重复；不能把重复的免暴击当成额外收益，也不把回复数值直接相加。")
	if "玄阵" in names and "精盾" in names:
		notes.append("不叠加：【玄阵】与【精盾】的士兵格挡率取较强的30%，不会相加成50%；【玄阵】的增伤仍按原条件生效。")
	if "连弩" in names:
		notes.append("发动后覆盖：【连弩】把所属士兵射程设为3、远近伤害倍率设为0.7，并禁用火矢；这些是设置值，不能和原士兵数值直接相加。武将本人不在此次改写名单内。")
		if _feature_value(jewelry, "白兵射程") > 0:
			notes.append("对象区分：「%s」的白兵射程词条用于武将射箭；【连弩】改写的是士兵，不能把这件道具的武将射程当作全军额外射程。" % jewelry.name)
	var elephant_leader = _current_elephant_leader(actor_id, side)
	if "藤甲" in names or elephant_leader:
		var prefix = "当前白刃状态" if elephant_leader else "按此配置发动后"
		notes.append("%s：本人骑象时，白刃单位的武器攻击特性列表会被清空，刀、剑、枪、斧等攻击特性不能照常发挥；这不代表武器基础攻击或所有装备词条归零，也不据此判定单挑词条失效。" % prefix)
		if "藤甲" in names:
			notes.append("兵种区分：【藤甲】的藤甲兵仍属步兵，步兵类效果可按各自条件生效；站在骑兵位置不等于骑兵。")
	if "巨象" in names and "铁骑" in names:
		notes.append("兵种不匹配：【巨象】把骑兵转为象兵，象兵不算骑兵；【铁骑】对骑兵的三动与减伤不能直接套给这些象兵。")
	if jewelry.id == JIEZISHU_ID and _feature_value(jewelry, "学习折扣") == 80:
		if "劝学" in names:
			notes.append("不叠加：诫子书与【劝学】同时满足条件时，学习经验仍为原来的80%，不会连乘成64%；【劝学】另有太守、君主及月份条件。")
		if "同槽" in names:
			if actor.get_name() in SIMA_STUDENTS:
				notes.append("不叠加：本人属于【同槽】的指定受益者，条件满足时与诫子书合用，学习经验仍为80%，不会连乘。")
			else:
				notes.append("对象限制：【同槽】只给同城司马师、司马昭学习折扣；不能把它当成持有者本人诫子书之外的第二份折扣。")
	if _feature_value(jewelry, "强制统系") > 0:
		notes.append("成长覆盖：「%s」在升级时、统未达90的条件下优先成长统；这影响以后升级路线，不会把当前基础统立即设为90。白兵附加统词条另在白刃战结算。" % jewelry.name)
	if jewelry.id == WUZI_ID and _has_wuzi_features(jewelry):
		notes.append("条件收益：吴子兵法仅在白刃攻方按入场机动力的一半增加战术值、最多6；攻方获胜后按结算战术值的五分之一恢复机动力、最多3，不能保证每战都取得上限。")
		if "骁勇" in names or "破势" in names or "连袭" in names:
			notes.append("连续作战配合：吴子兵法可在上述攻方获胜条件下补回部分机动，有利连战；发动连战技能并不保证这次交战有足够战术值返还机动。")
	if _feature_value(steed, "避免白刃战") > 0:
		notes.append("对象限制：「%s」的避免白刃战让武将本人不出现在白刃战，并非整支部队免战；不能因此认定所有士兵技能都失效。" % steed.name)
		for name in PERSONAL_SHOOTING:
			if name in names:
				notes.append("条件冲突：【%s】依赖武将本人射箭；本人不出场时，不能按正常武将射击发挥此效果。" % name)
	return notes


func equipment_for(actor_id: int, overrides := {}) -> Dictionary:
	if actor_id < 0 or actor_id >= DataManager.actors.size():
		return {}
	var actor = ActorHelper.actor(actor_id)
	var result = {}
	var restrictions = actor.get_disabled_equip_types()
	for slot in SLOTS:
		var equip = actor.get_equip(slot)
		var invalid = false
		if overrides.has(slot):
			var value = overrides[slot]
			if typeof(value) in [TYPE_INT, TYPE_REAL] and value >= 0 and int(value) == value and _known_equipment(slot, int(value)):
				var preview = equip.get_script().new(int(value), slot)
				var slot_disabled = slot in restrictions
				var item_disabled = slot + "|" + str(int(value)) in restrictions
				preview.disabled = slot_disabled or item_disabled
				preview.disabledEquipOnly = item_disabled and not slot_disabled
				preview.battleTemporary = equip.battleTemporary
				equip = preview
			else:
				invalid = true
		result[slot] = {"id": equip.id, "name": equip.name(), "features": equip.features().duplicate(true), "disabled": equip.disabled or equip.type_disabled(), "preview_invalid": invalid}
	return result


func _known_equipment(slot: String, equip_id: int) -> bool:
	return not StaticManager.get_equip_data(equip_id, slot).empty()


func _feature_value(item: Dictionary, tag: String) -> float:
	if item.disabled:
		return 0.0
	var value = 0.0
	for feature in item.features:
		if feature is Dictionary and typeof(feature.get(tag)) in [TYPE_INT, TYPE_REAL]:
			value = max(value, float(feature[tag]))
	return value


func _has_wuzi_features(item: Dictionary) -> bool:
	var entry = false
	var victory = false
	for feature in item.features:
		entry = entry or (feature.get("公式", "") == "min(6, get_war_ap()/2)" and feature.get("条件", "") == "is_battle_attacker()")
		victory = victory or (feature.get("公式", "") == "min(3, get_battle_tp()/5)" and feature.get("条件", "") == "is_battle_attacker() and is_battle_winner()")
	return entry and victory and not item.disabled


func _current_five_phase(actor_id: int, side: String) -> String:
	if DataManager.get_current_scene_id() < 20000:
		return ""
	# Another side is only a skill preview: its effects have not been applied.
	if not side.empty() and side != str(ActorHelper.actor(actor_id).get_side()):
		return ""
	var wa = DataManager.get_war_actor(actor_id)
	if wa == null or wa.disabled:
		return ""
	return War_Character.get_five_phases_string(wa.five_phases)


func _current_elephant_leader(actor_id: int, side := "") -> bool:
	if DataManager.get_current_scene_id() != 30000:
		return false
	if not side.empty() and side != str(ActorHelper.actor(actor_id).get_side()):
		return false
	var wa = DataManager.get_war_actor(actor_id)
	if wa == null or wa.disabled:
		return false
	var unit = wa.battle_actor_unit()
	return unit != null and str(unit.get("Type")) == "将(象)"
