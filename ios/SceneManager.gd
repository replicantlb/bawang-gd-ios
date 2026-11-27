extends "res://scene/manager/Scene_Manager.gdc"


func go_to_scene(path: String):
	var trial = get_node_or_null("/root/TrialSession")
	if trial != null and trial.active and trial.intercept_scene_change(path):
		return
	return .go_to_scene(path)


func save_current_scene(no: int) -> String:
	var trial = get_node_or_null("/root/TrialSession")
	if trial != null and (trial.active or trial.restoring):
		return ""
	return .save_current_scene(no)


func _rpc_save_current_scene(no: int) -> String:
	var trial = get_node_or_null("/root/TrialSession")
	if trial != null and (trial.active or trial.restoring):
		return ""
	return ._rpc_save_current_scene(no)
