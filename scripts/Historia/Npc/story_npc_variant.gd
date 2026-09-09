@tool
class_name StoryNPCVariant
extends Resource

## Perfil reutilizable de NPC de Historia.
##
## Se crea como .tres y se puede reutilizar en cualquier StoryNPCSpawner.
## La escena se toma del JSON story_npcs_default.json mediante npc_type_id,
## salvo que se asigne scene_override. Los campos se aplican solo cuando su
## override correspondiente está activo, conservando los valores de escena.
##
## npc_type_id, faction_id y weapon_name aparecen como menús desplegables
## generados desde los JSON del juego (ver _get_property_list + StoryDataCatalog).

@export_category("Identidad")
@export var display_name: String = "Nueva variante NPC"
## Tipo de NPC registrado en story_npcs_default.json. Menú desplegable.
var npc_type_id: String = "cuerpo_a_cuerpo"
@export var scene_override: PackedScene = null

@export_category("Facción y apariencia")
## Facción (id) según story_factions.json. Menú desplegable.
var faction_id: int = int(StoryFactionSystem.ENEMY_FACTION)
@export var skin_color: Color = Color("#5fbf4f")

@export_category("Stats opcionales")
@export var override_max_health: bool = false
@export_range(1.0, 100000.0, 1.0) var max_health: float = 55.0
@export var override_movement_speed: bool = false
@export_range(0.1, 20.0, 0.05) var movement_speed: float = 1.65
@export var override_melee_damage: bool = false
@export_range(0.0, 10000.0, 0.5) var melee_damage: float = 10.0

@export_category("IA")
@export var spawn_mode: int = 0
## Combate asaltante independiente del modo base (solo TIRADOR): avanza
## disparando, retrocede si el enemigo se acerca y corre al cadáver de sus bajas.
@export var aggressive_enabled: bool = false
@export_range(1.0, 60.0, 0.5) var vision_range: float = 12.0
@export_range(30.0, 360.0, 10.0) var vision_fov_degrees: float = 120.0
@export_range(0.0, 20.0, 0.5) var wander_radius: float = 6.0
@export_range(0.0, 40.0, 0.5) var guard_radius: float = 10.0

@export_category("Armamento para TIRADOR")
## Arma del arsenal (skill.json). Menú desplegable.
var weapon_name: String = "Glock"
@export_range(-1, 9999, 1) var weapon_mag_override: int = -1
@export_range(-1, 9999, 1) var weapon_reserve_override: int = -1
@export var drop_weapon_on_death: bool = true
@export var tirador_config: TiradorConfig = null


## Menús desplegables data-driven desde los JSON del juego.
func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append({
		"name": "npc_type_id",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.npc_type_hint(),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "faction_id",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.faction_hint(),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "weapon_name",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": StoryDataCatalog.weapon_hint(),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	return props


func _get(property: StringName) -> Variant:
	match property:
		&"npc_type_id":
			return npc_type_id
		&"faction_id":
			return faction_id
		&"weapon_name":
			return weapon_name
	return null


func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"npc_type_id":
			npc_type_id = str(value)
			return true
		&"faction_id":
			faction_id = int(value)
			return true
		&"weapon_name":
			weapon_name = str(value)
			return true
	return false


func resolve_scene() -> PackedScene:
	if scene_override != null:
		return scene_override
	var scene_path: String = StoryNPCConfig.get_npc_scene_path(npc_type_id)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_warning("[StoryNPCVariant] Escena no válida para '%s'." % npc_type_id)
		return null
	return ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene


func build_spawn_config(spawn_position: Vector3) -> Dictionary:
	var cfg: Dictionary = {
		"faction_id": faction_id,
		"spawn_mode": spawn_mode,
		"aggressive_enabled": aggressive_enabled,
		"vision_range": vision_range,
		"vision_fov_degrees": vision_fov_degrees,
		"wander_radius": wander_radius,
		"guard_radius": guard_radius,
		"spawn_position": spawn_position,
		"skin_color": skin_color,
		"weapon_name": weapon_name,
		"weapon_mag_override": weapon_mag_override,
		"weapon_reserve_override": weapon_reserve_override,
		"drop_weapon_on_death": drop_weapon_on_death,
	}
	if override_max_health:
		cfg["max_health"] = max_health
	if override_movement_speed:
		cfg["movement_speed"] = movement_speed
	if override_melee_damage:
		cfg["melee_damage"] = melee_damage
	if tirador_config != null:
		cfg["tirador_config"] = tirador_config
	return cfg
