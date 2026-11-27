extends Node

# Browsing preferences belong to the current in-memory campaign, never a save.
var _generation := 0
var _context := ""
var _view := {}


func reset_campaign() -> void:
	_generation += 1
	_context = ""
	_view.clear()


func generation_token() -> int:
	return _generation


func read_view(context: String) -> Dictionary:
	if context != _context:
		_generation += 1
		_context = context
		_view.clear()
	return _view.duplicate(true)


func write_view(context: String, generation: int, state: Dictionary) -> bool:
	# A closing popup from a previous campaign must not repopulate a reset cache.
	if context != _context or generation != _generation:
		return false
	_view = state.duplicate(true)
	return true
