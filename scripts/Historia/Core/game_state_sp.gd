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
## Clave del StoryExit por el que se salió del nivel anterior
## ("scene_path|node_path"). La consume StoryLevelController del nivel de destino
## para colocar al jugador en su StorySpawnPoint correspondiente.
var entry_exit_key: String = ""


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


## Reanuda una partida guardada (menú «continuar»): activa la sesión de Historia
## conservando el checkpoint y el nivel que ya cargó SaveManager.load_game().
## A diferencia de begin_story(), NO borra el checkpoint ni la posición.
func resume_story() -> void:
	session_mode = SessionMode.HISTORIA
	selected_level_id = current_level_id
	selected_level_path = current_level_path


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
	entry_exit_key = ""
	story_session_reset.emit()
