extends "res://script/Data_Manager.gdc"

var _ios_saved_data_depth := 0
var _ios_personality_epoch := 0


func get_common_path() -> String:
	if is_inside_tree():
		var trial = get_node_or_null("/root/TrialSession")
		if trial != null and trial.active:
			return trial.sandbox_path()
	return .get_common_path()


func loading_version_resource(path: String, version: String = "default", changes: Dictionary = {}):
	var result = .loading_version_resource(path, version, changes)
	# Loading a save and scene-to-scene transfers both reload resources internally.
	# Only the direct new-campaign resource load should consume global defaults.
	if _ios_saved_data_depth == 0 and is_inside_tree():
		_ios_personality_epoch += 1
		var views = get_node_or_null("/root/PrisonViewState")
		if views != null:
			views.reset_campaign()
		var helper = get_node_or_null("/root/SkillHelper")
		if helper != null:
			helper.apply_skill_defaults_to_new_campaign()
	return result


func get_save_data() -> Dictionary:
	if is_inside_tree():
		var personalities = get_node_or_null("/root/RulerPersonalities")
		if personalities != null:
			personalities.prepare_save()
	return .get_save_data()


func set_save_data(data: Dictionary):
	_ios_saved_data_depth += 1
	var result = .set_save_data(data)
	_ios_saved_data_depth -= 1
	return result
