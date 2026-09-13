@tool
class_name StoryLevelDefinition
extends Resource

## Datos editables de una misión de Historia.
##
## Crea un recurso .tres desde el Inspector y asígnalo al StoryLevelController
## del mapa. Los campos originales del controlador siguen funcionando como
## fallback para no romper mapas existentes.
##
## Los campos level_id, scene_path, next_level_path y starting_weapon aparecen
## como menús desplegables generados desde los JSON del juego (story_map_list.json
## y skill.json) mediante _get_property_list() + StoryDataCatalog.

@export_category("Identidad")
## ID del nivel de campaña. Menú desplegable desde story_map_list.json.
var level_id: String = "new_story_level"
@export var display_name: String = "Nueva misión"
@export_multiline var description: String = ""
## Escena de este nivel. Menú desplegable desde story_map_list.json.
var scene_path: String = ""

@export_category("Objetivo inicial")
@export_multiline var objective_text: String = "Llega a la salida."

@export_category("Flujo")
## Escena del siguiente nivel. Menú desplegable; vacío = volver al menú.
var next_level_path: String = ""
## Arma inicial del jugador. Menú desplegable desde skill.json.
var starting_weapon: String = "Glock"
@export_range(0.1, 10.0, 0.1) var respawn_delay: float = 2.0

@export_category("Presentación")
@export var show_in_campaign_menu: bool = true
@export var sort_order: int = 0


## Menús desplegables data-driven desde los JSON del juego.
func _get_property_list() -> Array[Dictionary]:
    var props: Array[Dictionary] = []
    props.append({
        "name": "level_id",
        "type": TYPE_STRING,
        "hint": PROPERTY_HINT_ENUM,
        "hint_string": StoryDataCatalog.campaign_id_hint(),
        "usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
    })
    props.append({
        "name": "scene_path",
        "type": TYPE_STRING,
        "hint": PROPERTY_HINT_ENUM,
        "hint_string": StoryDataCatalog.campaign_scene_hint(false),
        "usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
    })
    props.append({
        "name": "next_level_path",
        "type": TYPE_STRING,
        "hint": PROPERTY_HINT_ENUM,
        "hint_string": StoryDataCatalog.campaign_scene_hint(true),
        "usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
    })
    props.append({
        "name": "starting_weapon",
        "type": TYPE_STRING,
        "hint": PROPERTY_HINT_ENUM,
        "hint_string": StoryDataCatalog.weapon_hint(),
        "usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
    })
    return props


func _get(property: StringName) -> Variant:
    match property:
        &"level_id":
            return level_id
        &"scene_path":
            return scene_path
        &"next_level_path":
            return next_level_path
        &"starting_weapon":
            return starting_weapon
    return null


func _set(property: StringName, value: Variant) -> bool:
    match property:
        &"level_id":
            level_id = str(value)
            return true
        &"scene_path":
            scene_path = str(value)
            return true
        &"next_level_path":
            next_level_path = str(value)
            return true
        &"starting_weapon":
            starting_weapon = str(value)
            return true
    return false
