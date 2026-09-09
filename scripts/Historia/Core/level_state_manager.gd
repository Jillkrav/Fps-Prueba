## AUTOLOAD /root/LevelStateManager (NO usar class_name: el nombre del autoload
## ya es el identificador global; declarar un class_name con el mismo nombre
## colisiona con el autoload y rompe la compilación).
extends Node

## ────────────────────────────────────────────────────────────────────────────
##  LevelStateManager — Estado de campaña por nivel, en MEMORIA.
##  Autoload (/root/LevelStateManager). Vive entre cambios de escena.
##
##  SEPARACIÓN DE CAPAS (arquitectura data-driven de la campaña):
##    Capa 1  Config base          -> .tscn del mapa + StoryLevelDefinition (.tres)
##                                   + JSON (story_map_list.json, skill.json...).
##                                   NUNCA se escribe.
##    Capa 2  Estado en memoria    -> ESTE MANAGER. { level_id: { state_id: {...} } }
##                                   Se captura al salir del nivel y se aplica
##                                   al volver a entrar. No toca disco por evento.
##    Capa 3  Guardado persistente -> SaveManager (user://savegames/*.json).
##
##  CONTRATO DE ENTIDAD PERSISTENTE (duck-typing, extensible):
##    Cualquier nodo de un mapa de campaña es persistente si:
##      1) Tiene  @export var state_id: String = ""   (vacío = NO se persiste).
##      2) En _ready() llama a  LevelStateManager.register(self)  y a
##         call_deferred("_restore_persistent_state")  (para restaurarse).
##      3) Implementa  func get_persistent_state() -> Dictionary
##      4) Implementa  func apply_persistent_state(state: Dictionary) -> void
##
##    Para AÑADIR un interactuable nuevo en el futuro basta con copiar ese
##    patrón: register + _restore_persistent_state + get/apply. El manager y el
##    SaveManager lo tratan automáticamente (nada más que tocar).
##
##  FLUJO:
##    - Captura:  StoryLevelController (o un checkpoint) llama a
##                capture_level_state(level_id) justo antes de cambiar de escena
##                o de guardar. Recorre el grupo "story_persistent" y guarda el
##                estado actual de cada entidad con state_id.
##    - Restaura: cada entidad, al cargar el mapa (call_deferred en _ready),
##                lee get_entity_state(level_id, state_id) y se restaura sola.
## ────────────────────────────────────────────────────────────────────────────

## Grupo donde se auto-registran las entidades persistentes.
const PERSISTENT_GROUP := "story_persistent"
## state_id reservado para el controlador de nivel (objetivo actual).
const CONTROLLER_STATE_ID := "__controller__"
## Prefijo de state_id para armas soltadas por NPCs en runtime (dinámicas).
## Estas no existen en el .tscn, así que al volver al mapa el controlador las
## re-crea a partir del estado guardado (ver collect_dynamic_drops).
const DYNAMIC_DROP_PREFIX := "dyn_drop_"

## Nivel que se está jugando ahora mismo. Lo fija StoryLevelController en su
## _ready() ANTES de que corran los call_deferred de restauración de entidades.
var current_level_id: String = ""

## { level_id: { state_id: Dictionary } }
var level_states: Dictionary = {}


func _ready() -> void:
	add_to_group(&"level_state_manager")


# ── API para el controlador ──────────────────────────────────────────────────

## Fija el nivel actual (lo llama StoryLevelController en _ready).
func set_current_level(level_id: String) -> void:
	current_level_id = level_id


## Recorre todas las entidades persistentes del mapa actual y captura su estado.
func capture_level_state(level_id: String) -> void:
	if level_id.is_empty():
		return
	if not level_states.has(level_id):
		level_states[level_id] = {}
	var bag: Dictionary = level_states[level_id]
	for node in get_tree().get_nodes_in_group(PERSISTENT_GROUP):
		if not is_instance_valid(node):
			continue
		var sid: String = str(node.get("state_id"))
		if sid.is_empty():
			continue
		if node.has_method("get_persistent_state"):
			bag[sid] = node.get_persistent_state()


## Captura el estado del nivel actual (conveniencia).
func capture_current_level() -> void:
	capture_level_state(current_level_id)


## true si el nivel ya tiene algo guardado en memoria.
func has_level_state(level_id: String) -> bool:
	if level_id.is_empty() or not level_states.has(level_id):
		return false
	return (level_states[level_id] as Dictionary).size() > 0


## true si una entidad concreta tiene estado guardado.
func has_entity_state(level_id: String, state_id: String) -> bool:
	return not get_entity_state(level_id, state_id).is_empty()


## Estado guardado de una entidad ({} si no hay).
func get_entity_state(level_id: String, state_id: String) -> Dictionary:
	if level_id.is_empty() or state_id.is_empty():
		return {}
	var bag: Variant = level_states.get(level_id, {})
	if bag is Dictionary:
		var st: Variant = (bag as Dictionary).get(state_id, {})
		if st is Dictionary:
			return st
	return {}


## Guarda (o sobrescribe) el estado de una entidad concreta.
func set_entity_state(level_id: String, state_id: String, state: Dictionary) -> void:
	if level_id.is_empty() or state_id.is_empty():
		return
	if not level_states.has(level_id):
		level_states[level_id] = {}
	(level_states[level_id] as Dictionary)[state_id] = state


## Borra el estado de un nivel (p. ej. al empezar campaña nueva).
func clear_level_state(level_id: String) -> void:
	level_states.erase(level_id)


func clear_all_level_states() -> void:
	level_states.clear()


## Devuelve TODO el estado en memoria (para SaveManager).
func get_all_level_states() -> Dictionary:
	return level_states


## Remplaza el estado en memoria desde un guardado (para SaveManager).
func load_all_level_states(data: Variant) -> void:
	if data is Dictionary:
		level_states = data


# ── Helpers para las entidades (uso recomendado) ─────────────────────────────
# Como ESTE script ES el autoload /root/LevelStateManager, las entidades llaman
# a estos métodos como  LevelStateManager.register(self)  /
# LevelStateManager.get_state_for(self, state_id)  (métodos de instancia del
# autoload; el primer argumento es el nodo de la entidad, se conserva por
# compatibilidad con las llamadas existentes).

## Devuelve el level_id actual (el primer argumento se ignora; se conserva por
## compatibilidad con LevelStateManager.get_current_level_id(self)).
func get_current_level_id(_node: Node = null) -> String:
	return current_level_id


## Lee el estado persistido de una entidad ({ } si no hay / no es persistente).
func get_state_for(_node: Node = null, state_id: String = "") -> Dictionary:
	if state_id.is_empty():
		return {}
	return get_entity_state(current_level_id, state_id)


## Escribe el estado persistido de una entidad (no-op si no es persistente).
func persist_state(_node: Node = null, state_id: String = "", state: Dictionary = {}) -> void:
	if state_id.is_empty():
		return
	set_entity_state(current_level_id, state_id, state)


## Registra una entidad en el grupo de persistentes (llamarlo en _ready).
func register(node: Node) -> void:
	node.add_to_group(PERSISTENT_GROUP)


## Devuelve las armas soltadas por NPCs (dinámicas) que siguen en el suelo en
## un nivel: [{ key, transform, weapon_data }]. Solo claves con el prefijo
## DYNAMIC_DROP_PREFIX y estado no "collected". El StoryLevelController las
## re-crea al volver al mapa.
func collect_dynamic_drops(level_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if level_id.is_empty() or not level_states.has(level_id):
		return result
	var bag: Variant = level_states[level_id]
	if not bag is Dictionary:
		return result
	for key: Variant in (bag as Dictionary):
		var k: String = str(key)
		if not k.begins_with(DYNAMIC_DROP_PREFIX):
			continue
		var st: Variant = (bag as Dictionary)[key]
		if st is Dictionary and not bool((st as Dictionary).get("collected", false)):
			result.append({
				"key": k,
				"transform": (st as Dictionary).get("transform", []),
				"weapon_data": (st as Dictionary).get("weapon_data", {}),
			})
	return result
