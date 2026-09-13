@tool
class_name StoryExit
extends Area3D

## Salida de misión con destino configurable por Inspector.
##
## Cada StoryExit puede saltar a un nivel distinto (avanzar, volver o desviarse)
## eligiendo el mapa desde un menú desplegable generado desde story_map_list.json
## (ver _get_property_list y StoryDataCatalog).
##
## - destination_scene vacío -> usa el "next_level_path" del StoryLevelController
##   (comportamiento clásico: siguiente nivel o menú principal).
## - completes_level=false  -> salidas de regreso/desvío que solo cambian de escena,
##   sin marcar la misión actual como completada.
signal reached(exit: StoryExit, player: Player)

## Etiqueta visible sobre la salida (p. ej. "SALIDA", "VOLVER A LA BASE").
@export var display_name: String = "SALIDA"
## Si es true (clásico), al usarla se marca la misión actual como completada.
## Ponlo en false para salidas de regreso/desvío que solo viajan.
@export var completes_level: bool = true

## Destino del viaje. Menú desplegable desde story_map_list.json.
## Vacío = usar el siguiente nivel del controlador (next_level_path).
var destination_scene: String = ""

## Punto de aparición dentro del nivel DESTINO. Menú desplegable que escanea los
## StorySpawnPoint de destination_scene. Vacío = el destino usa su propia lógica
## (el spawn point enlazado por «source_story_exit», checkpoint o arma inicial).
var destination_spawn_point: String = ""

@onready var status_label: Label3D = get_node_or_null("StatusLabel") as Label3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_label()
		return
	body_entered.connect(_on_body_entered)
	_update_label()


## Expone destination_scene como menú desplegable generado desde los JSON del juego.
func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append({
		"name": "Viaje entre niveles",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_CATEGORY,
	})
	props.append({
		"name": "destination_scene",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "(Siguiente nivel del controlador):," + StoryDataCatalog.campaign_scene_hint(false),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "destination_spawn_point",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.story_spawn_point_hint(destination_scene),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	return props


func _get(property: StringName) -> Variant:
	match property:
		&"destination_scene":
			return destination_scene
		&"destination_spawn_point":
			return destination_spawn_point
	return null


func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"destination_scene":
			destination_scene = str(value)
			return true
		&"destination_spawn_point":
			destination_spawn_point = StoryDataCatalog.clean_exit_key(str(value))
			return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player or body.is_in_group(&"player")):
		return
	var controller: Node = get_tree().get_first_node_in_group(&"story_level_controller")
	if controller == null or not controller.has_method("request_level_complete"):
		push_warning("[StoryExit] No se encontró StoryLevelController.")
		return
	reached.emit(self, body as Player)
	# Limpiamos la etiqueta del desplegable ("Mapa X:res://...") para que el
	# controlador reciba la ruta de escena limpia.
	controller.call("request_level_complete", self, StoryDataCatalog.clean_scene_path(destination_scene))


## Clave única de esta salida dentro de la campaña: "scene_path|node_path".
## La usan los StorySpawnPoint para enlazarse («este exit aterriza aquí») y el
## controlador del nivel de destino para colocar al jugador en ese punto.
func get_exit_key() -> String:
	var scene_path: String = _scene_path()
	if scene_path.is_empty():
		return ""
	var root: Node = owner as Node
	if root == null and is_inside_tree():
		root = get_tree().current_scene
	if root == null:
		return ""
	return "%s|%s" % [scene_path, root.get_path_to(self)]


## Clave que debe consumir el nivel de destino:
## - Si el diseñador eligió point «destination_spawn_point», esa clave (el
##   destino colocará al jugador en ESE punto).
## - Si no, la de esta salida (el destino usa el spawn point que se enlaza por
##   «source_story_exit», o su lógica clásica).
func get_entry_key() -> String:
	var sp_key: String = StoryDataCatalog.clean_exit_key(destination_spawn_point)
	if not sp_key.is_empty():
		return sp_key
	return get_exit_key()


func _scene_path() -> String:
	if owner != null and owner is Node:
		return owner.scene_file_path
	if is_inside_tree() and get_tree().current_scene != null:
		return get_tree().current_scene.scene_file_path
	return ""


func _update_label() -> void:
	if status_label != null:
		status_label.text = display_name
