extends Node

const STATE_KEY = "iOS.君主性格"
const SourcePatches = preload("res://ios_personality_ai_patches.gd")
const TRAITS = ["进取", "守成", "谋略", "重才", "好战", "机会"]
const ACTIONS = ["发展", "策略", "战争"]
const POLICIES = ["rescue", "envoy", "ally", "wedge", "canvass", "incite"]
const ACTION_WEIGHTS = {"进取": [2, 2, 5], "守成": [5, 3, 1], "谋略": [2, 5, 2], "重才": [4, 5, 1], "好战": [2, 1, 6], "机会": [2, 3, 4]}
const POLICY_WEIGHTS = {"进取": [1, 1, 2, 3, 2, 3], "守成": [2, 4, 4, 1, 2, 1], "谋略": [1, 2, 2, 5, 3, 5], "重才": [5, 3, 2, 1, 5, 2], "好战": [2, 1, 1, 2, 2, 1], "机会": [1, 2, 3, 4, 3, 4]}
const TRAIT_TEXT = {"进取": "主动争取领土与战略空间", "守成": "重视发展、留守与领地安全", "谋略": "偏好外交削弱、离间与策反", "重才": "重视招募、招降与营救人才", "好战": "更愿意集结兵力争取战果", "机会": "偏好薄弱目标与局部胜机"}
var _presets := {}
var _support_session := ""
var _sources_supported := false


func _ready() -> void:
	var file = File.new()
	if file.open("res://ios_ruler_personalities.json", File.READ) == OK:
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error == OK and parsed.result is Dictionary and parsed.result.get("presets") is Dictionary:
			_presets = parsed.result.presets


func supported() -> bool:
	if DataManager.mod_path != DataManager.DEFAULT_MOD_PATH or DataManager.is_developer():
		return false
	var token = session_token()
	if token != _support_session:
		_support_session = token
		_sources_supported = true
		for path in SourcePatches.SOURCE_HASHES:
			if not SourcePatches.supports(path, Global.get_file_text(path)):
				_sources_supported = false
				break
	return _sources_supported


func session_token() -> String:
	return "%s:%s:%s" % [DataManager.get("_ios_personality_epoch"), DataManager.mod_path, DataManager.drama_path]


func _state() -> Dictionary:
	var state = DataManager.get_env_dict(STATE_KEY).duplicate(true)
	if state.get("format", 1) != 1:
		return {}
	return state


func _write(state: Dictionary) -> void:
	state.format = 1
	DataManager.set_env(STATE_KEY, state)


func is_enabled() -> bool:
	return bool(_state().get("enabled", true))


func set_enabled(value: bool) -> void:
	var state = _state()
	state.enabled = value
	if not value:
		state.goals = {}
	_write(state)


func _actor_valid(actor_id: int) -> bool:
	return actor_id >= 0 and actor_id < DataManager.actors.size()


func _valid_profile(profile) -> bool:
	return profile is Dictionary and profile.get("primary") in TRAITS and profile.get("secondary") in TRAITS and profile.primary != profile.secondary and profile.get("source") in ["人物预设", "自动性格", "手动设置"]


func _actor_name(actor_id: int) -> String:
	return ActorHelper.actor(actor_id).get_name() if _actor_valid(actor_id) else "无"


func _default_profile(actor_id: int) -> Dictionary:
	if not _actor_valid(actor_id):
		return {}
	var data = {"actor_id": actor_id}
	if _presets.has(str(actor_id)) and actor_id != StaticManager.ACTOR_ID_DIY:
		data.merge(_presets[str(actor_id)].duplicate(true))
		data.source = "人物预设"
	else:
		# Native actors use the immutable base table. The custom actor's creation
		# data is frozen on first persistence; equipment and later levels are ignored.
		var base = StaticManager.actors[actor_id] if actor_id < StaticManager.actors.size() and actor_id != StaticManager.ACTOR_ID_DIY else DataManager.actors[actor_id]
		var courage = clamp(Global.intval(base.get("胆"), 50), 0, 100)
		var moral = clamp(Global.intval(base.get("德"), 50), 0, 100)
		var power = clamp(Global.intval(base.get("武"), 50), 0, 100)
		var wisdom = clamp(Global.intval(base.get("知"), 50), 0, 100)
		var politics = clamp(Global.intval(base.get("政"), 50), 0, 100)
		var lead = clamp(Global.intval(base.get("统"), 50), 0, 100)
		var scores = [courage * 0.55 + lead * 0.30 + power * 0.15, (100 - courage) * 0.45 + politics * 0.35 + moral * 0.20, wisdom * 0.60 + politics * 0.25 + (100 - courage) * 0.15, moral * 0.55 + politics * 0.30 + lead * 0.15, power * 0.45 + courage * 0.45 + lead * 0.10, wisdom * 0.40 + (100 - moral) * 0.30 + courage * 0.30]
		var ranked = []
		for index in range(TRAITS.size()):
			# A stable actor-specific tiebreaker never consumes combat RNG.
			ranked.append({"trait": TRAITS[index], "score": scores[index] + ((actor_id + 17) * (index + 11) % 13)})
		ranked.sort_custom(self, "_score_greater")
		data.primary = ranked[0].trait
		data.secondary = ranked[1].trait
		data.preference = "%s；%s" % [TRAIT_TEXT[data.primary], TRAIT_TEXT[data.secondary]]
		data.focus = "balanced"
		data.source = "自动性格"
	data.default_primary = data.primary
	data.default_secondary = data.secondary
	data.default_source = data.source
	data.default_preference = data.preference
	data.default_focus = data.focus
	return data


func _score_greater(left: Dictionary, right: Dictionary) -> bool:
	return left.score > right.score


func profile_for(actor_id: int, persist := true) -> Dictionary:
	if not _actor_valid(actor_id):
		return {}
	var state = _state()
	var profiles = state.get("profiles", {})
	if not profiles is Dictionary:
		profiles = {}
	var existing = profiles.get(str(actor_id), {})
	var result = existing.duplicate(true) if _valid_profile(existing) else _default_profile(actor_id)
	result.actor_id = actor_id
	result.name = _actor_name(actor_id)
	if persist and (not _valid_profile(existing) or existing.get("actor_id", -1) != actor_id):
		profiles[str(actor_id)] = result.duplicate(true)
		state.profiles = profiles
		_write(state)
	return result


func set_manual(actor_id: int, primary: String, secondary: String) -> bool:
	if not _actor_valid(actor_id) or not primary in TRAITS or not secondary in TRAITS or primary == secondary:
		return false
	var profile = profile_for(actor_id)
	profile.primary = primary
	profile.secondary = secondary
	profile.source = "手动设置"
	profile.focus = "balanced"
	profile.preference = "%s；%s" % [TRAIT_TEXT[primary], TRAIT_TEXT[secondary]]
	var state = _state()
	state.profiles[str(actor_id)] = profile
	_invalidate_decisions(state, actor_id)
	_write(state)
	return true


func reset_profile(actor_id: int) -> void:
	var profile = profile_for(actor_id)
	if profile.empty():
		return
	var defaults = _default_profile(actor_id)
	for field in ["primary", "secondary", "source", "preference", "focus"]:
		profile[field] = profile.get("default_" + field, defaults[field])
	var state = _state()
	state.profiles[str(actor_id)] = profile
	_invalidate_decisions(state, actor_id)
	_write(state)


func _invalidate_decisions(state: Dictionary, actor_id: int) -> void:
	var goals = state.get("goals", {})
	if goals is Dictionary:
		for vstate_id in range(DataManager.vstates.size()):
			var faction = _live_faction(vstate_id)
			if faction != null and faction.get_lord_id() == actor_id:
				goals.erase(str(vstate_id))
		state.goals = goals
	if DataManager.get_env_int("内政.AI性格君主", -1) == actor_id:
		DataManager.unset_env("内政.AI性格君主")


func description(profile: Dictionary) -> String:
	if not _valid_profile(profile):
		return "暂无性格资料。"
	var preference = str(profile.get("preference", ""))
	if preference.empty():
		preference = "%s；%s" % [TRAIT_TEXT[profile.primary], TRAIT_TEXT[profile.secondary]]
	return "主性格：%s——%s\n副性格：%s——%s\n\n偏好：%s\n\n性格影响内政行动、外交偏好、前线留守与选城取舍。局势不利时仍会调整，已有盟约与出征条件继续生效。" % [profile.primary, TRAIT_TEXT[profile.primary], profile.secondary, TRAIT_TEXT[profile.secondary], preference]


func _live_faction(vstate_id: int):
	if vstate_id < 0 or vstate_id >= DataManager.vstates.size():
		return null
	var faction = clVState.vstate(vstate_id)
	if faction == null or faction.is_perished() or not _actor_valid(faction.get_lord_id()):
		return null
	return faction


func _sync_leader(vstate_id: int, lord_id: int, persist: bool) -> int:
	var state = _state()
	var leaders = state.get("leaders", {})
	if not leaders is Dictionary:
		leaders = {}
	var record = leaders.get(str(vstate_id), {})
	if not record is Dictionary:
		record = {}
	var previous = int(record.get("previous", -1))
	if int(record.get("current", lord_id)) != lord_id:
		previous = int(record.get("current", -1))
		if persist:
			var goals = state.get("goals", {})
			if goals is Dictionary:
				goals.erase(str(vstate_id))
				state.goals = goals
	if persist and (record.empty() or int(record.get("current", -1)) != lord_id):
		leaders[str(vstate_id)] = {"current": lord_id, "previous": previous}
		state.leaders = leaders
		_write(state)
	return previous


func current_factions(persist := true) -> Array:
	var result = []
	for vstate_id in range(DataManager.vstates.size()):
		var faction = _live_faction(vstate_id)
		if faction == null:
			continue
		var lord_id = faction.get_lord_id()
		var previous = _sync_leader(vstate_id, lord_id, persist)
		result.append({"vstate_id": vstate_id, "faction_name": faction.get_dynasty_title_or_lord_name(), "lord_id": lord_id, "lord_name": _actor_name(lord_id), "previous_lord_id": previous, "previous_lord_name": _actor_name(previous), "profile": profile_for(lord_id, persist), "enabled": is_enabled(), "is_player": DataManager.get_actor_controlNo(lord_id) >= 0})
	return result


func prepare_save() -> void:
	if supported() and not DataManager.actors.empty() and not DataManager.vstates.empty():
		current_factions(true)


func affects_faction(vstate_id: int) -> bool:
	var faction = _live_faction(vstate_id)
	if not supported() or not is_enabled() or faction == null or DataManager.get_actor_controlNo(faction.get_lord_id()) >= 0:
		return false
	_sync_leader(vstate_id, faction.get_lord_id(), true)
	profile_for(faction.get_lord_id(), true)
	return true


func _faction_profile(vstate_id: int) -> Dictionary:
	var faction = _live_faction(vstate_id)
	return profile_for(faction.get_lord_id()) if faction != null else {}


func _weights(profile: Dictionary, table: Dictionary) -> Array:
	var result = []
	for index in range(table[profile.primary].size()):
		result.append(int(table[profile.primary][index]) * 2 + int(table[profile.secondary][index]))
	return result


func _pool(names: Array, weights: Array) -> Array:
	var result = []
	for index in range(names.size()):
		for _repeat in range(max(1, int(weights[index]))):
			result.append(names[index])
	return result


func action_pool(vstate_id: int) -> Array:
	var profile = _faction_profile(vstate_id)
	if profile.empty():
		return ["策略", "发展", "战争", "发展", "策略"]
	var weights = _weights(profile, ACTION_WEIGHTS)
	var rice = 0
	var actors = 0
	for city in clCity.all_cities([vstate_id]):
		rice += city.get_rice()
		actors += city.get_actors_count()
	if rice < actors * 40:
		weights[0] += 8
		weights[2] = max(1, int(weights[2] / 2))
	# Keep the native five-action cycle: its end-of-war command adjustment uses
	# the remaining pool length. Expanding a weighted pool would grant commands.
	var result = ACTIONS.duplicate()
	var total = int(weights[0] + weights[1] + weights[2])
	for _slot in range(2):
		var roll = Global.get_random(1, total)
		for index in range(ACTIONS.size()):
			roll -= int(weights[index])
			if roll <= 0:
				result.append(ACTIONS[index])
				break
	return result


func policy_methods(vstate_id: int) -> Array:
	var profile = _faction_profile(vstate_id)
	return _pool(POLICIES, _weights(profile, POLICY_WEIGHTS)) if not profile.empty() else POLICIES.duplicate()


func reserve_count(vstate_id: int, base_count: int, enemy_count: int) -> int:
	if enemy_count <= 0:
		return 1
	var profile = _faction_profile(vstate_id)
	var extra = 0
	if not profile.empty():
		extra = (2 if profile.primary == "守成" else 1 if profile.primary in ["谋略", "重才"] else 0) + (1 if profile.secondary == "守成" else 0)
	return int(max(base_count, min(10, base_count + extra)))


func _city_power(city_id: int) -> float:
	var city = clCity.city(city_id)
	var total = 0.0
	for id in city.get_actor_ids():
		if not _actor_valid(id):
			continue
		var actor = ActorHelper.actor(id)
		total += float(actor.get_power() + actor.get_wisdom() + actor.get_leadership()) / 3.0 * actor.get_soldiers() / 10.0
	return total


func _regions(vstate_id: int) -> Dictionary:
	var regions = {}
	var group = 0
	for city in clCity.all_cities([vstate_id]):
		if regions.has(city.ID):
			continue
		var pending = [city.ID]
		while not pending.empty():
			var id = pending.pop_back()
			if regions.has(id):
				continue
			regions[id] = group
			for next in clCity.city(id).get_connected_city_ids([vstate_id]):
				if not regions.has(next):
					pending.append(next)
		group += 1
	return regions


func choose_target(vstate_id: int, candidate_ids: Array, native_target := -1) -> int:
	if not affects_faction(vstate_id) or native_target < 0:
		return native_target
	var profile = _faction_profile(vstate_id)
	var faction = clVState.vstate(vstate_id)
	var regions = _regions(vstate_id)
	var scored = {}
	for id in candidate_ids:
		if not id is int or id < 0 or id >= DataManager.citys.size():
			continue
		var city = clCity.city(id)
		var owner = city.get_vstate_id()
		if owner == vstate_id or owner >= 0 and clVState.get_alliance_month(vstate_id, owner) > 0:
			continue
		var friends = city.get_connected_city_ids([vstate_id])
		if friends.empty():
			continue
		var best_power = 0.0
		for friend in friends:
			best_power = max(best_power, _city_power(friend))
		var strength = _city_power(id)
		if id != native_target and strength > best_power * 1.5 and strength > 0:
			continue
		var pieces = []
		for friend in friends:
			if regions.has(friend) and not regions[friend] in pieces:
				pieces.append(regions[friend])
		var connect_gain = max(0, pieces.size() - 1)
		var weak = clamp((best_power + 1000.0) / (strength + 1000.0), 0, 4)
		var enemy_edges = city.get_connected_city_ids([], [-1, vstate_id]).size()
		var score = 500.0 if owner < 0 else 0.0
		for trait in [profile.primary, profile.primary, profile.secondary]:
			match trait:
				"进取": score += connect_gain * 45 + friends.size() * 9 + weak * 5
				"守成": score += connect_gain * 20 + friends.size() * 10 + weak * 10 - enemy_edges * 10
				"谋略": score += connect_gain * 20 + friends.size() * 6 + weak * 14
				"重才": score += friends.size() * 6 + weak * 12 - enemy_edges * 5
				"好战": score += friends.size() * 6 + min(3, weak) * 5
				"机会": score += weak * 22 + friends.size() * 5 - city.get_actors_count() * 2
		match profile.get("focus", "balanced"):
			"connect": score += connect_gain * 25
			"resources": score += min(25, float(city.get_gold() + city.get_rice()) / 100.0)
			"fortify", "frontier", "region": score += friends.size() * 5 - enemy_edges * 4
			"planning", "alliance": score += weak * 5 - enemy_edges * 4
			"opportunity": score += weak * 6
			"decisive", "advance": score += friends.size() * 5
		if id == native_target:
			score += 12
		scored[str(id)] = score
	if scored.empty():
		return native_target
	var best = native_target if scored.has(str(native_target)) else int(scored.keys()[0])
	for key in scored:
		if float(scored[key]) > float(scored[str(best)]):
			best = int(key)
	var state = _state()
	var goals = state.get("goals", {})
	if not goals is Dictionary:
		goals = {}
	var goal = goals.get(str(vstate_id), {})
	var month = DataManager.year * 12 + DataManager.month
	if goal is Dictionary and goal.get("lord", -1) == faction.get_lord_id() and month - int(goal.get("since", -100)) >= 0 and month - int(goal.get("since", -100)) < 3:
		var target = int(goal.get("city", -1))
		if scored.has(str(target)) and float(scored[str(target)]) >= float(scored[str(best)]) - 20:
			return target
	goals[str(vstate_id)] = {"lord": faction.get_lord_id(), "city": best, "since": month}
	state.goals = goals
	_write(state)
	return best
