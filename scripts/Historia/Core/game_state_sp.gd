class_name GameStateSPClass
extends Node

## Estado persistente y aislado del modo Historia.
## Se mantiene separado de GameStateMP para que cargar una misión no inicie
## sistemas de equipos, cores o respawn del modo multijugador.
signal story_started(level_id: String, scene_path: String)
signal checkpoint_changed(position: Vector3)
signal level_completed(level_id: String)
signal story_session_reset()

enum SessionMode {
	NONE,
	HISTORIA,
}

var session_mode: int = SessionMode.NONE
var selected_level_id: String = ""
var selected_level_path: String = ""
var current_level_id: String = ""
var current_level_path: String = ""
var checkpoint_position: Vector3 = Vector3.ZERO
var has_checkpoint: bool = false
var completed_levels: Dictionary[String, bool] = {}


func is_story_active() -> bool:
	return session_mode == SessionMode.HISTORIA


func begin_story(level_id: String, scene_path: String) -> void:
	session_mode = SessionMode.HISTORIA
	selected_level_id = level_id
	selected_level_path = scene_path
	current_level_id = level_id
	current_level_path = scene_path
	has_checkpoint = false
	checkpoint_position = Vector3.ZERO
	story_started.emit(level_id, scene_path)


func set_checkpoint(position: Vector3) -> void:
	checkpoint_position = position
	has_checkpoint = true
	checkpoint_changed.emit(position)


func complete_current_level() -> void:
	if current_level_id.is_empty():
		return
	completed_levels[current_level_id] = true
	level_completed.emit(current_level_id)


func reset_session() -> void:
	session_mode = SessionMode.NONE
	selected_level_id = ""
	selected_level_path = ""
	current_level_id = ""
	current_level_path = ""
	has_checkpoint = false
	checkpoint_position = Vector3.ZERO
	story_session_reset.emit()
