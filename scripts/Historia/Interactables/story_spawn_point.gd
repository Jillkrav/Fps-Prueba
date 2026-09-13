@tool
class_name StorySpawnPoint
extends Marker3D

## ────────────────────────────────────────────────────────────────────────────
##  StorySpawnPoint — Punto de aparición del jugador controlado por el diseñador.
##
##  Es un Marker3D: la POSICIÓN y ORIENTACIÓN del nodo definen dónde y hacia
##  dónde aparece el jugador. Su función principal es ser el "lugar de llegada"
##  de un StoryExit de OTRO nivel:
##
##    1) En el Inspector eliges, en el menú "source_story_exit", qué StoryExit
##       de otros niveles aterriza en este punto (el menú lista los exits de
##       TODA la campaña, escaneando las escenas).
##    2) Cuando el jugador usa ESE exit, el nivel de destino lo lee
##       (StoryLevelController) y coloca al jugador aquí.
##    3) Opcionalmente el punto define con cuánta VIDA y con qué ARMA aparece
##       el jugador al llegar (vacío / 0 = no tocar lo que traiga).
##
##  Uso en la escena del mapa: añade la instancia bajo el grupo de interactuables
##  y muévela/rota con el gizmo. El cilindro verde es solo una referencia visual
##  de editor (se oculta en runtime).
## ────────────────────────────────────────────────────────────────────────────

@export_category("Spawn")
@export var display_name: String = "SPAWN"
## Vida con la que aparece el jugador al llegar por este punto.
## 0 = no tocar la vida (conserva la que traiga o la del nivel).
@export_range(0.0, 500.0, 1.0) var spawn_health: float = 0.0
## Arma inicial al llegar por este punto. Menú desplegable desde skill.json.
## Vacío = no tocar el arma (conserva la que traiga o la del nivel).
var spawn_weapon: String = ""

@export_category("Origen (StoryExit)")
## StoryExit de OTRO nivel que aterriza en este punto. Menú desplegable generado
## desde las escenas de campaña (ver StoryDataCatalog.story_exit_hint).
## Vacío = este punto no se usa como llegada por exit.
var source_story_exit: String = ""

@onready var debug_mesh: MeshInstance3D = $DebugMesh
@onready var status_label: Label3D = $StatusLabel


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_label()
		return
	add_to_group(&"story_spawn_points")
	if debug_mesh != null:
		debug_mesh.visible = false
	_update_label()


## Expone spawn_weapon y source_story_exit como menús desplegables generados
## desde los JSON / escenas del juego.
func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append({
		"name": "spawn_weapon",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "(No cambiar):," + StoryDataCatalog.weapon_hint(),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "source_story_exit",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.story_exit_hint(_current_scene_path()),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	return props


func _get(property: StringName) -> Variant:
	match property:
		&"spawn_weapon":
			return spawn_weapon
		&"source_story_exit":
			return source_story_exit
	return null


func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"spawn_weapon":
			spawn_weapon = str(value)
			return true
		&"source_story_exit":
			source_story_exit = StoryDataCatalog.clean_exit_key(str(value))
			return true
	return false


## Clave del exit de origen, sin la etiqueta del desplegable (si la tuviera).
func get_source_exit_key() -> String:
	return StoryDataCatalog.clean_exit_key(source_story_exit)


## Clave única de este punto en la campaña: "scene_path|node_path".
## La usa un StoryExit (en «destination_spawn_point») para elegir llegar AQUÍ.
func get_spawn_key() -> String:
	var scene_path: String = _current_scene_path()
	if scene_path.is_empty():
		return ""
	var root: Node = owner as Node
	if root == null and is_inside_tree():
		root = get_tree().current_scene
	if root == null:
		return ""
	return "%s|%s" % [scene_path, root.get_path_to(self)]


## Ruta de escena del mapa donde vive este punto (para excluir sus propios
## exits del menú). "" si no se puede determinar.
func _current_scene_path() -> String:
	if owner != null and owner is Node:
		return owner.scene_file_path
	if get_tree() != null and get_tree().edited_scene_root != null:
		return get_tree().edited_scene_root.scene_file_path
	return ""


func _update_label() -> void:
	if status_label != null:
		status_label.text = display_name
