@tool
class_name StoryLootEntry
extends Resource

## Entrada de loot para StoryLootSpawner y recompensas de StoryLevelEvent.
## Configura qué aparece, en qué cantidad y con qué probabilidad, sin scripts.
##
## weapon_name aparece como menú desplegable generado desde skill.json.

enum LootType {
	WEAPON,
	AMMO,
	MEDKIT,
	PACKED_SCENE,
}

@export_category("Contenido")
@export var loot_type: LootType = LootType.WEAPON
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
@export_range(1, 100, 1) var amount: int = 1
@export var spread_radius: float = 0.7

@export_category("Arma")
## Arma del arsenal (skill.json). Menú desplegable.
var weapon_name: String = "Glock"
@export_range(-1, 9999, 1) var magazine_ammo: int = -1
@export_range(-1, 9999, 1) var reserve_ammo: int = -1
@export var persistent_on_floor: bool = false

@export_category("Consumibles")
@export_range(1, 9999, 1) var ammo_amount: int = 60
@export_range(1.0, 10000.0, 1.0) var heal_amount: float = 50.0

@export_category("Escena personalizada")
@export var packed_scene: PackedScene = null


## Menú desplegable data-driven para el arma (skill.json).
func _get_property_list() -> Array[Dictionary]:
	return [{
		"name": "weapon_name",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.weapon_hint(),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	}]


func _get(property: StringName) -> Variant:
	if property == &"weapon_name":
		return weapon_name
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"weapon_name":
		weapon_name = str(value)
		return true
	return false
