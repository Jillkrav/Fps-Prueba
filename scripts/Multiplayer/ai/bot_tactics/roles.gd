# scripts/roles.gd
# SISTEMA DE ROLES UNIFICADO
#
# Los datos de comportamiento estan en res://config/roles.json.
# Edita el JSON para cambiar stats de cada rol.
#
# USO:
#   Roles.Type.ASALTO
#   Roles.get_config(Roles.Type.VERSATIL)
extends RefCounted
class_name Roles


# ENUM - TIPOS DE ROL

enum Type {
	VERSATIL    = 0,
	ASALTO        = 1,
	FLANQUEADOR   = 2,
	DEFENSOR      = 3,
	PATRULLADOR   = 4,
	FRANCOTIRADOR = 5,
	APOYO         = 6,
}


# ENUM - PERFIL DE MOVIMIENTO

enum MovementProfile {
	AGGRESSIVE = 0,
	DEFENSIVE  = 1,
	FLANKING   = 2,
	PATROL     = 3,
}


# ENUM - TIPOS DE RUTA

enum RouteType {
	DIRECT     = 0,
	LEFT       = 1,
	RIGHT      = 2,
	WIDE_LEFT  = 3,
	WIDE_RIGHT = 4,
}


# CARGA DESDE JSON

const CONFIG_PATH: String = "res://config/Multiplayer/roles.json"

const ROLE_KEYS: Array[String] = [
	"VERSATIL",    # 0
	"ASALTO",        # 1
	"FLANQUEADOR",   # 2
	"DEFENSOR",      # 3
	"PATRULLADOR",   # 4
	"FRANCOTIRADOR", # 5
	"APOYO",         # 6,
]

static var _cached_config: Dictionary = {}


static func _load_config() -> Dictionary:
	if not _cached_config.is_empty():
		return _cached_config

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Roles: No se pudo abrir %s" % CONFIG_PATH)
		return {}

	var json_str: String = file.get_as_text()
	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(json_str)
	if parse_err != OK:
		push_error("Roles: Error parseando JSON: %s" % json.get_error_message())
		return {}

	_cached_config = json.data
	return _cached_config


static func _key_for(role_type: int) -> String:
	if role_type < 0 or role_type >= ROLE_KEYS.size():
		return "ASALTO"
	return ROLE_KEYS[role_type]


static func _movement_profile_from_string(s: String) -> int:
	match s:
		"AGGRESSIVE": return MovementProfile.AGGRESSIVE
		"DEFENSIVE": return MovementProfile.DEFENSIVE
		"FLANKING": return MovementProfile.FLANKING
		"PATROL": return MovementProfile.PATROL
	return MovementProfile.AGGRESSIVE


static func _cfg_for(role_type: int) -> Dictionary:
	var config: Dictionary = _load_config()
	var raw: Dictionary = config.get(_key_for(role_type), config.get("ASALTO", {}))
	if raw.is_empty():
		return {}

	var result: Dictionary = raw.duplicate()
	if result.has("movement_profile") and result["movement_profile"] is String:
		result["movement_profile"] = _movement_profile_from_string(result["movement_profile"])
	return result


## Obtiene la configuracion completa de un rol por su tipo.
static func get_config(role_type: int) -> Dictionary:
	return _cfg_for(role_type)
