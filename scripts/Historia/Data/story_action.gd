@tool
class_name StoryAction
extends Resource

## Acción reutilizable ejecutada por StoryLevelEvent.
## Arrastra un nodo destino y elige un método público: activate, deactivate,
## toggle, set_open, set_active, request_level_complete u otro propio.
##
## method_name y weapon_name aparecen como menús desplegables en el Inspector.

enum ActionType {
	CALL_TARGET_METHOD,
	SET_OBJECTIVE,
	SHOW_MESSAGE,
	GIVE_STARTING_WEAPON,
	COMPLETE_LEVEL,
}

## Métodos públicos más habituales de los interactuables de Historia, para el
## desplegable de method_name. Cualquier otro método propio también vale.
const COMMON_METHODS := "activate,deactivate,toggle,set_open,set_active,request_level_complete"

@export_category("Acción")
@export var action_type: ActionType = ActionType.CALL_TARGET_METHOD
## Ruta relativa al StoryLevelEvent. Se puede arrastrar desde el árbol al Inspector.
@export var target_node_path: NodePath
## Método público a llamar. Menú desplegable con los métodos más comunes.
var method_name: StringName = &"activate"

@export_category("Parámetro opcional")
@export var pass_bool_argument: bool = false
@export var bool_argument: bool = true

@export_category("Texto / arma")
@export_multiline var text: String = ""
## Arma del arsenal (skill.json). Menú desplegable (GIVE_STARTING_WEAPON).
var weapon_name: String = ""


## Menús desplegables data-driven en el Inspector.
func _get_property_list() -> Array[Dictionary]:
	return [
		{
			"name": "method_name",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": COMMON_METHODS,
			"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
		},
		{
			"name": "weapon_name",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": StoryDataCatalog.weapon_hint(),
			"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
		},
	]


func _get(property: StringName) -> Variant:
	match property:
		&"method_name":
			return String(method_name)
		&"weapon_name":
			return weapon_name
	return null


func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"method_name":
			method_name = StringName(str(value))
			return true
		&"weapon_name":
			weapon_name = str(value)
			return true
	return false
