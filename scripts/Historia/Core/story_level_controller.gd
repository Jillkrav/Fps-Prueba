class_name StoryLevelController
extends Node

## Controlador de una misión de Historia.
## Cada mapa instancia uno y expone sus propiedades en el Inspector: spawn,
## checkpoint, arma inicial, objetivo y escena siguiente.
signal level_started(level_id: String)
signal level_completed(level_id: String)
signal player_respawned(player: Player)

@export_category("Level")
@export var level_id: String = "story_test"
@export_multiline var objective_text: String = "Llega a la salida."
@export_file("*.tscn") var next_level_path: String = ""
@export var starting_weapon: String = "Glock"

@export_category("Nodes")
@export var player_path: NodePath = NodePath("../Player")
@export var initial_checkpoint_path: NodePath = NodePath("../Checkpoints/StartCheckpoint/SpawnMarker")

@export_category("Respawn")
@export_range(0.1, 10.0, 0.1) var respawn_delay: float = 2.0

var player: Player = null
var _is_respawning: bool = false
var _is_completing: bool = false


func _ready() -> void:
	add_to_group(&"story_level_controller")
	player = get_node_or_null(player_path) as Player
	GameState.player_team = int(Enums.Equipo.AZUL)
	GameState.friendly_fire = false
	var current_scene: Node = get_tree().current_scene
	var scene_path: String = current_scene.scene_file_path if current_scene != null else ""
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state == null or not story_state.has_method("begin_story"):
		push_error("[StoryLevelController] GameStateSP no está disponible.")
		return
	story_state.call("begin_story", level_id, scene_path)
	if player != null and not player.player_died.is_connected(on_player_died):
		player.player_died.connect(on_player_died)
	call_deferred("_initialize_level")


func _initialize_level() -> void:
	if player == null or not is_instance_valid(player):
		push_error("[StoryLevelController] No se encontró Player en %s." % player_path)
		return
	if not starting_weapon.is_empty():
		player.setup_weapon(starting_weapon)
		if player.weapon_equip_state != null:
			player.weapon_equip_state.equip()
	var initial_checkpoint: Marker3D = get_node_or_null(initial_checkpoint_path) as Marker3D
	if initial_checkpoint != null:
		set_checkpoint(initial_checkpoint.global_position, false)
	_set_objective(objective_text)
	level_started.emit(level_id)


func set_checkpoint(position: Vector3, announce: bool = true) -> void:
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state != null and story_state.has_method("set_checkpoint"):
		story_state.call("set_checkpoint", position)
	if announce:
		_show_message("CHECKPOINT ACTIVADO")


func on_player_died() -> void:
	if _is_respawning:
		return
	_is_respawning = true
	_show_message("HAS MUERTO. REAPARECIENDO...")
	await get_tree().create_timer(respawn_delay).timeout
	if player == null or not is_instance_valid(player):
		return
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	var has_checkpoint: bool = story_state != null and bool(story_state.get("has_checkpoint"))
	var respawn_position: Vector3 = story_state.get("checkpoint_position") as Vector3 if has_checkpoint else player.global_position
	player.respawn_at(respawn_position)
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method("story_player_respawned"):
		hud.story_player_respawned()
	_set_objective(objective_text)
	_is_respawning = false
	player_respawned.emit(player)


func request_level_complete(exit_node: Node) -> void:
	if _is_completing:
		return
	var requires_enemies_defeated: bool = exit_node != null and bool(exit_node.get("require_all_enemies_defeated"))
	if requires_enemies_defeated and not are_required_enemies_defeated():
		_show_message("SALIDA BLOQUEADA: ELIMINA A LOS ENEMIGOS")
		return
	_is_completing = true
	var story_state: Node = get_node_or_null("/root/GameStateSP")
	if story_state != null and story_state.has_method("complete_current_level"):
		story_state.call("complete_current_level")
	_show_message("MISIÓN COMPLETADA")
	level_completed.emit(level_id)
	await get_tree().create_timer(1.5).timeout
	if not next_level_path.is_empty() and ResourceLoader.exists(next_level_path):
		get_tree().change_scene_to_file(next_level_path)
	else:
		get_tree().change_scene_to_file("res://scenes/Compartido/main_menu.tscn")


func are_required_enemies_defeated() -> bool:
	for enemy: Node in get_tree().get_nodes_in_group(&"story_enemy"):
		if is_instance_valid(enemy) and enemy.get("is_dead") != true:
			return false
	return true


func _set_objective(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method("set_story_objective"):
		hud.set_story_objective(text)


func _show_message(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud != null and hud.has_method("set_story_objective"):
		hud.set_story_objective(text)
