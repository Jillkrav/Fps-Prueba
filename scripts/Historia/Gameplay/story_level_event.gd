class_name StoryLevelEvent
extends Node

## Evento de nivel para campaña/singleplayer.
##
## Permite construir secuencias sin editar scripts: asigna nodos emisores,
## selecciona sus señales desde listas habituales o escribe una señal propia,
## configura cuántos disparos necesita y define acciones/recompensas. Ejemplos:
## - botón.activated -> actualizar objetivo, activar una oleada y abrir puerta;
## - spawner_enemies_cleared -> entregar loot y abrir salida;
## - checkpoint.activated -> nuevo objetivo;
## - pickup.picked_up -> desbloquear un warp.

signal event_started(level_event: StoryLevelEvent)
signal event_progressed(level_event: StoryLevelEvent, current_count: int, required_count: int)
signal event_completed(level_event: StoryLevelEvent)

enum StartMode {
	ON_READY,
	EXTERNAL,
}

enum SourceSignal {
	ACTIVATED,
	COMPLETED,
	CLEARED,
	PICKED_UP,
	CHECKPOINT_ACTIVATED,
	DOOR_OPENED,
	DOOR_CLOSED,
	WARPED,
	EXIT_REACHED,
	CUSTOM,
}

@export_category("Identidad")
@export var event_id: String = "new_event"
@export var display_name: String = "Nuevo evento"
@export var enabled: bool = true
@export var one_shot: bool = true
@export var start_mode: StartMode = StartMode.ON_READY

@export_category("Condición")
## Rutas relativas al evento. Arrastra nodos desde el árbol al Inspector.
@export var sources: Array[NodePath] = []
@export var source_signal: SourceSignal = SourceSignal.ACTIVATED
@export var custom_signal_name: StringName = &""
@export_range(1, 9999, 1) var required_count: int = 1
@export var count_each_source_once: bool = true

@export_category("Objetivo")
## Recurso StoryObjectiveStep (.tres).
@export var objective_step: Resource = null

@export_category("Resultado")
## Recursos StoryAction (.tres).
@export var actions: Array[Resource] = []
## Rutas de nodos StoryLootSpawner del mismo mapa.
@export var reward_spawners: Array[NodePath] = []

var is_active: bool = false
var is_completed: bool = false
var current_count: int = 0
var _counted_sources: Dictionary[int, bool] = {}


func _ready() -> void:
	if start_mode == StartMode.ON_READY and enabled:
		call_deferred("activate")


func activate() -> void:
	if not enabled or is_active or (one_shot and is_completed):
		return
	is_active = true
	current_count = 0
	_counted_sources.clear()
	_connect_sources()
	_apply_objective_start()
	event_started.emit(self)
	if sources.is_empty():
		_complete()


func deactivate() -> void:
	is_active = false


func reset_event() -> void:
	is_active = false
	is_completed = false
	current_count = 0
	_counted_sources.clear()


func _connect_sources() -> void:
	var signal_name: StringName = _get_signal_name()
	if signal_name == &"":
		push_warning("[StoryLevelEvent] '%s' no tiene señal configurada." % name)
		return
	for source_path: NodePath in sources:
		var source: Node = get_node_or_null(source_path)
		if source == null:
			push_warning("[StoryLevelEvent] '%s' tiene una ruta de fuente inválida: %s." % [name, source_path])
			continue
		if not source.has_signal(signal_name):
			push_warning("[StoryLevelEvent] '%s' no expone la señal '%s'." % [source.name, signal_name])
			continue
		var callback: Callable = _on_source_signal.bind(source)
		if not source.is_connected(signal_name, callback):
			source.connect(signal_name, callback)


func _on_source_signal(source: Node, ..._args: Array) -> void:
	if not is_active or is_completed or source == null or not is_instance_valid(source):
		return
	var source_id: int = source.get_instance_id()
	if count_each_source_once and _counted_sources.has(source_id):
		return
	_counted_sources[source_id] = true
	current_count += 1
	event_progressed.emit(self, current_count, required_count)
	if current_count >= required_count:
		_complete()


func _complete() -> void:
	if is_completed:
		return
	is_completed = true
	is_active = false
	_apply_objective_complete()
	for reward_path: NodePath in reward_spawners:
		var reward_spawner: Node = get_node_or_null(reward_path)
		if reward_spawner != null and reward_spawner.has_method("activate"):
			reward_spawner.call("activate")
	for action: Resource in actions:
		_execute_action(action)
	event_completed.emit(self)


func _execute_action(action: Resource) -> void:
	if action == null:
		return
	var controller: StoryLevelController = get_tree().get_first_node_in_group(&"story_level_controller") as StoryLevelController
	var action_type: int = int(action.get("action_type"))
	match action_type:
		0: # CALL_TARGET_METHOD
			var target: Node = get_node_or_null(action.get("target_node_path") as NodePath)
			var method_name: StringName = action.get("method_name") as StringName
			if target == null or method_name == &"" or not target.has_method(method_name):
				return
			if bool(action.get("pass_bool_argument")):
				target.call(method_name, bool(action.get("bool_argument")))
			else:
				target.call(method_name)
		1: # SET_OBJECTIVE
			if controller != null:
				controller.set_objective(str(action.get("text")))
		2: # SHOW_MESSAGE
			if controller != null:
				controller.show_message(str(action.get("text")))
		3: # GIVE_STARTING_WEAPON
			var weapon_name: String = str(action.get("weapon_name"))
			if controller != null and not weapon_name.is_empty():
				controller.give_player_weapon(weapon_name)
		4: # COMPLETE_LEVEL
			if controller != null:
				controller.request_level_complete(self)


func _apply_objective_start() -> void:
	if objective_step != null and bool(objective_step.get("update_hud_on_start")):
		var objective_text: String = str(objective_step.get("objective_text"))
		var controller: StoryLevelController = get_tree().get_first_node_in_group(&"story_level_controller") as StoryLevelController
		if controller != null and not objective_text.is_empty():
			controller.set_objective(objective_text)


func _apply_objective_complete() -> void:
	if objective_step != null and bool(objective_step.get("update_hud_on_complete")):
		var completion_text: String = str(objective_step.get("completion_text"))
		var controller: StoryLevelController = get_tree().get_first_node_in_group(&"story_level_controller") as StoryLevelController
		if controller != null and not completion_text.is_empty():
			controller.show_message(completion_text)


func _get_signal_name() -> StringName:
	match source_signal:
		SourceSignal.ACTIVATED:
			return &"activated"
		SourceSignal.COMPLETED:
			return &"completed"
		SourceSignal.CLEARED:
			return &"spawner_enemies_cleared"
		SourceSignal.PICKED_UP:
			return &"picked_up"
		SourceSignal.CHECKPOINT_ACTIVATED:
			return &"activated"
		SourceSignal.DOOR_OPENED:
			return &"opened"
		SourceSignal.DOOR_CLOSED:
			return &"closed"
		SourceSignal.WARPED:
			return &"warped"
		SourceSignal.EXIT_REACHED:
			return &"reached"
		SourceSignal.CUSTOM:
			return custom_signal_name
	return &""
