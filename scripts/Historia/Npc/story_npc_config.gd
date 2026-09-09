class_name StoryNPCConfig
extends RefCounted

## Cargador de la configuracion por defecto de TODOS los NPCs de Historia
## (res://config/Historia/npc/story_npcs_default.json).
##
## Es el equivalente para NPCs de lo que ConfigManager es para skill.json
## (armas/items): un unico archivo JSON centraliza los defaults de cada tipo
## de NPC, de modo que anadir un NPC nuevo en el futuro es SOLO anadir una
## entrada en 'npc_types' sin tocar el codigo de este loader.
##
## Uso (estatico, sin instancia):
##     var ids: Array = StoryNPCConfig.get_npc_type_ids()
##     var defaults: Dictionary = StoryNPCConfig.get_npc_defaults("cuerpo_a_cuerpo")
##     var cfg: TiradorConfig = StoryNPCConfig.make_tirador_config("tirador")
##
## NOTA: por ahora este loader solo LEE y expone la config (los scripts de los
## NPCs aun usan sus @export por defecto). La integracion de estos valores en
## el runtime del spawner/NPCs es trabajo futuro (ver StoryNPCSpawner).

const CONFIG_PATH := "res://config/Historia/npc/story_npcs_default.json"
const DEFAULT_NPC_TYPE := "cuerpo_a_cuerpo"

## Cache de la config ya parseada. Se recarga con reload() si editas el JSON
## en caliente.
static var _cache: Dictionary = {}


## Devuelve el JSON completo parseado como Dictionary.
static func get_data() -> Dictionary:
	if _cache.is_empty():
		_load()
	return _cache


## Fuerza la recarga del JSON (util en runtime tras editar el archivo).
static func reload() -> void:
	_load()


static func _load() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("StoryNPCConfig: No se encontro %s" % CONFIG_PATH)
		_cache = {}
		return
	var text: String = FileAccess.get_file_as_string(CONFIG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_cache = parsed
	else:
		push_error("StoryNPCConfig: JSON invalido en %s" % CONFIG_PATH)
		_cache = {}


## Ids (claves) de todos los tipos de NPC registrados: ["cuerpo_a_cuerpo", ...].
static func get_npc_type_ids() -> Array:
	var types: Dictionary = get_data().get("npc_types", {})
	return types.keys()


## Comprueba si existe un tipo de NPC con ese id.
static func npc_type_exists(type_id: String) -> bool:
	var types: Dictionary = get_data().get("npc_types", {})
	return types.has(type_id)


## Devuelve la entrada completa de un tipo de NPC (diccionario vacio si no existe).
static func get_npc_data(type_id: String) -> Dictionary:
	var types: Dictionary = get_data().get("npc_types", {})
	return types.get(type_id, {})


## Ruta a la escena del NPC ("scene_path"). Vacia si no existe.
static func get_npc_scene_path(type_id: String) -> String:
	return str(get_npc_data(type_id).get("scene_path", ""))


## Faccion por defecto del NPC ("faction_id"). Ver story_factions.json.
static func get_npc_faction_id(type_id: String) -> int:
	return int(get_npc_data(type_id).get("faction_id", 2))


## Stats por defecto del NPC (seccion "defaults"). Diccionario vacio si no hay.
static func get_npc_defaults(type_id: String) -> Dictionary:
	return get_npc_data(type_id).get("defaults", {})


## Seccion "tirador_config" (solo la tienen los soldados armados).
static func get_tirador_config_data(type_id: String) -> Dictionary:
	return get_npc_data(type_id).get("tirador_config", {})


## Reconstruye un TiradorConfig real a partir de la seccion 'tirador_config'
## del JSON. Sustituye al antiguo .tres de configuración. Si el tipo no
## tiene seccion, devuelve un TiradorConfig con sus valores por defecto.
static func make_tirador_config(type_id: String) -> TiradorConfig:
	var cfg := TiradorConfig.new()
	var data := get_tirador_config_data(type_id)
	for key: String in data:
		if key in cfg:  # 'in' sobre Object comprueba si la propiedad existe.
			cfg.set(key, data[key])
	return cfg
