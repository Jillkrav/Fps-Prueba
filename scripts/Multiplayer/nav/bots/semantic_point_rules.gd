# scripts/semantic_point_rules.gd
# SISTEMA DE REGLAS DE PUNTOS SEMANTICOS
#
# Carga res://config/semantic_points.json y responde consultas
# sobre que roles usan cada punto.
extends RefCounted
class_name SemanticPointRules


const CONFIG_PATH: String = "res://config/Multiplayer/semantic_points.json"

# Mapeo: nombre del punto en JSON -> valor del enum PointType
const POINT_TYPES_BY_NAME: Dictionary = {
	"ASSAULT":   SemanticPoint.PointType.ASSAULT,
	"DEFENSE":   SemanticPoint.PointType.DEFENSE,
	"ALTERNATE": SemanticPoint.PointType.ALTERNATE,
	"PATH":      SemanticPoint.PointType.PATH,
	"VERSATIL":   SemanticPoint.PointType.VERSATIL,
	"OVERWATCH": SemanticPoint.PointType.OVERWATCH,
	"SUPPORT":   SemanticPoint.PointType.SUPPORT,
}

# Inverso
const POINT_NAMES_BY_VALUE: Dictionary = {
	SemanticPoint.PointType.ASSAULT:   "ASSAULT",
	SemanticPoint.PointType.DEFENSE:   "DEFENSE",
	SemanticPoint.PointType.ALTERNATE: "ALTERNATE",
	SemanticPoint.PointType.PATH:      "PATH",
	SemanticPoint.PointType.VERSATIL:   "VERSATIL",
	SemanticPoint.PointType.OVERWATCH: "OVERWATCH",
	SemanticPoint.PointType.SUPPORT:   "SUPPORT",
}

# Mapeo: nombre de rol en JSON -> Roles.Type
const ROLE_NAMES: Dictionary = {
	"VERSATIL":    Roles.Type.VERSATIL,
	"ASALTO":        Roles.Type.ASALTO,
	"FLANQUEADOR":   Roles.Type.FLANQUEADOR,
	"DEFENSOR":      Roles.Type.DEFENSOR,
	"PATRULLADOR":   Roles.Type.PATRULLADOR,
	"FRANCOTIRADOR": Roles.Type.FRANCOTIRADOR,
	"APOYO":         Roles.Type.APOYO,
}

static var _cached_config: Dictionary = {}


static func _load_config() -> Dictionary:
	if not _cached_config.is_empty():
		return _cached_config

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("SemanticPointRules: No se pudo abrir %s" % CONFIG_PATH)
		return {}

	var json_str: String = file.get_as_text()
	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(json_str)
	if parse_err != OK:
		push_error("SemanticPointRules: Error parseando JSON: %s" % json.get_error_message())
		return {}

	_cached_config = json.data
	return _cached_config


## Retorna los Roles.Type que pueden usar este tipo de punto.
static func get_allowed_roles(point_type: int) -> Array[int]:
	var config: Dictionary = _load_config()
	var mapping: Dictionary = config.get("point_mapping", {})
	var type_name: String = POINT_NAMES_BY_VALUE.get(point_type, "")
	if type_name.is_empty():
		return []

	var role_names: Array = mapping.get(type_name, [])
	var result: Array[int] = []
	for r_name in role_names:
		var role_val: Variant = ROLE_NAMES.get(r_name, null)
		if role_val != null:
			result.append(role_val)
	return result


## Verifica si un rol puede usar un tipo de punto especifico.
static func is_role_allowed(point_type: int, role_type: int) -> bool:
	var allowed: Array[int] = get_allowed_roles(point_type)
	return role_type in allowed


## Retorna el cooldown en segundos para un tipo de punto.
static func get_cooldown(point_type: int) -> float:
	var config: Dictionary = _load_config()
	var cooldowns: Dictionary = config.get("cooldowns", {})
	var type_name: String = POINT_NAMES_BY_VALUE.get(point_type, "")
	if type_name.is_empty():
		return 20.0
	return cooldowns.get(type_name, 20.0)


## Retorna el nombre legible de un tipo de punto.
static func get_point_type_name(point_type: int) -> String:
	return POINT_NAMES_BY_VALUE.get(point_type, "UNKNOWN")


## Retorna el tipo de punto semantico que debe usar un rol.
static func get_point_type_for_role(role_type: int) -> int:
	var config: Dictionary = _load_config()
	var mapping: Dictionary = config.get("point_mapping", {})

	for point_name in mapping.keys():
		var role_names: Array = mapping[point_name]
		for r_name in role_names:
			var role_val: Variant = ROLE_NAMES.get(r_name, null)
			if role_val == role_type:
				return POINT_TYPES_BY_NAME.get(point_name, 0)

	return 0  # ASSAULT como fallback
