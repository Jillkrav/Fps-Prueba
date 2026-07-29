# scripts/role_weapons.gd
# ──────────────────────────────────────────────────────────────────
# ASIGNACIÓN DE ARMAS POR ROL
#
# Los datos de configuración están en res://config/role_weapons.json
# Edita el JSON para cambiar armas preferidas de cada rol.
#
# ── USO ──
#   RoleWeapons.get_preferred_categories(Roles.Type.SOLDADO)
#   RoleWeapons.pick_weapon_for_role(Roles.Type.EXPLORADOR, armas)
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name RoleWeapons


# ══════════════════════════════════════════════════════════════════
# CARGA DESDE JSON
# ══════════════════════════════════════════════════════════════════

const CONFIG_PATH: String = "res://config/Multiplayer/role_weapons.json"

## Mapeo interno: Roles.Type int → string key del JSON
const ROLE_KEYS: Array[String] = [
	"VERSATIL",    # 0
	"ASALTO",        # 1
	"FLANQUEADOR",   # 2
	"DEFENSOR",      # 3
	"PATRULLADOR",   # 4
	"FRANCOTIRADOR", # 5
	"APOYO",         # 6
]

## Config cargada (caché).
static var _cached_config: Dictionary = {}


static func _load_config() -> Dictionary:
	if not _cached_config.is_empty():
		return _cached_config

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("RoleWeapons: No se pudo abrir %s" % CONFIG_PATH)
		return {}

	var json_str: String = file.get_as_text()
	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(json_str)
	if parse_err != OK:
		push_error("RoleWeapons: Error parseando JSON: %s" % json.get_error_message())
		return {}

	_cached_config = json.data
	return _cached_config


## Convierte Roles.Type (int) a la key string del JSON.
static func _key_for(role_type: int) -> String:
	if role_type < 0 or role_type >= ROLE_KEYS.size():
		return "ASALTO"
	return ROLE_KEYS[role_type]


## Retorna la configuración de un rol desde el JSON, o fallback SOLDADO.
static func _cfg_for(role_type: int) -> Dictionary:
	var config: Dictionary = _load_config()
	return config.get(_key_for(role_type), config.get("ASALTO", {}))


# ══════════════════════════════════════════════════════════════════
# MÉTODOS PÚBLICOS
# ══════════════════════════════════════════════════════════════════

## Retorna las categorías preferidas para un rol.
static func get_preferred_categories(role_type: int) -> Array[String]:
	var cfg: Dictionary = _cfg_for(role_type)
	return cfg.get("preferred_categories", [])


## Retorna las armas específicas preferidas para un rol.
static func get_preferred_weapons(role_type: int) -> Array[String]:
	var cfg: Dictionary = _cfg_for(role_type)
	var raw: Variant = cfg.get("preferred_weapons", [])
	var result: Array[String] = []
	if typeof(raw) == TYPE_ARRAY:
		for item in raw:
			result.append(str(item))
	return result


## Retorna el multiplicador de rating para armas que coinciden
## con las preferencias del rol. 1.0 = neutro.
static func get_category_bonus(role_type: int) -> float:
	var cfg: Dictionary = _cfg_for(role_type)
	return cfg.get("category_bonus", 1.0)


## Verifica si un arma (por su nombre o categoría) es preferida
## para este rol.
static func is_weapon_preferred(role_type: int, weapon_name: String, category: String) -> bool:
	var cfg: Dictionary = _cfg_for(role_type)
	var preferred_categories: Array = cfg.get("preferred_categories", [])
	var preferred_weapons: Array = cfg.get("preferred_weapons", [])

	if preferred_weapons.has(weapon_name):
		return true
	if preferred_categories.has(category):
		return true
	return false


## Elige un arma para el rol, a partir de la lista completa de
## nombres de armas disponibles. Prioriza las armas preferidas
## del rol; si no hay ninguna disponible, elige una aleatoria
## de la lista completa.
static func pick_weapon_for_role(role_type: int, all_weapons: Array[String]) -> String:
	if all_weapons.is_empty():
		return ""

	var preferred: Array[String] = get_preferred_weapons(role_type)

	var available_preferred: Array[String] = []
	for weapon_name in preferred:
		if all_weapons.has(weapon_name):
			available_preferred.append(weapon_name)

	if not available_preferred.is_empty():
		return available_preferred[randi() % available_preferred.size()]

	return all_weapons[randi() % all_weapons.size()]
