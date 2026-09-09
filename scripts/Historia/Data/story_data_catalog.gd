class_name StoryDataCatalog
extends RefCounted

## Catálogo data-driven de la campaña (Historia).
##
## Lee los JSON centrales del proyecto (armas, niveles de campaña, tipos de
## NPC y facciones) y expone listas de opciones para construir los menús
## desplegables del Inspector. Así los nodos y recursos de campaña se
## mantienen sincronizados con los archivos de datos SIN escribir a mano:
##
##   - Armas            -> config/Compartido/skill.json
##   - Niveles campaña  -> config/Historia/story_map_list.json
##   - Tipos de NPC     -> config/Historia/npc/story_npcs_default.json
##   - Facciones        -> config/Historia/story_factions.json
##
## Los hints siguen el formato de PROPERTY_HINT_ENUM de Godot:
##   "Etiqueta:valor,Etiqueta2:valor2"   (o "Valor,Valor2" si valor == etiqueta)

const STORY_MAP_LIST_PATH := "res://config/Historia/story_map_list.json"
const WEAPON_CONFIG_PATH := "res://config/Compartido/skill.json"
const NPC_DEFAULTS_PATH := "res://config/Historia/npc/story_npcs_default.json"
const FACTIONS_PATH := "res://config/Historia/story_factions.json"

## Etiqueta y valor de la opción «volver al menú» para next_level_path.
const MENU_OPTION_LABEL := "(Volver al menú / ninguno)"


## Lee un JSON y devuelve su contenido (Dictionary o Array). {} si falla.
static func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[StoryDataCatalog] No se pudo leer %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("[StoryDataCatalog] JSON inválido: %s" % path)
		return {}
	return json.data


# ─── Armas (skill.json) ─────────────────────────────────────────────────

## Nombres de todas las armas definidas en skill.json (orden del JSON).
static func weapon_names() -> Array[String]:
	var names: Array[String] = []
	var data: Variant = _load_json(WEAPON_CONFIG_PATH)
	var armas: Variant = {}
	if data is Dictionary:
		armas = (data as Dictionary).get("ConfiguracionJuego", {}).get("Armas", {})
	if armas is Dictionary:
		for _categoria: Variant in armas:
			var lista: Variant = armas[_categoria]
			if lista is Dictionary:
				for nombre: Variant in lista:
					names.append(str(nombre))
	return names


## Hint desplegable para seleccionar un arma del arsenal.
static func weapon_hint() -> String:
	var names := weapon_names()
	if names.is_empty():
		return "Glock,USP,Deagle"
	return ",".join(names)


# ─── Niveles de campaña (story_map_list.json) ──────────────────────────

## Lista de niveles con {id, display_name, scene_path, enabled}.
static func campaign_levels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data: Variant = _load_json(STORY_MAP_LIST_PATH)
	if data is Array:
		for entry: Variant in data:
			if entry is Dictionary:
				result.append(entry)
	return result


## Hint desplegable para elegir el level_id de un nivel de campaña.
static func campaign_id_hint() -> String:
	var parts: Array[String] = []
	for level: Dictionary in campaign_levels():
		var label: String = str(level.get("display_name", level.get("id", "?")))
		parts.append("%s:%s" % [label, str(level.get("id", ""))])
	return ",".join(parts)


## Devuelve la entrada {id, display_name, description, scene_path, enabled} de un
## nivel por su id ({ } si no existe). Útil para menus y pantallas de carga.
static func campaign_entry_for_id(level_id: String) -> Dictionary:
	for level: Dictionary in campaign_levels():
		if str(level.get("id", "")) == level_id:
			return level
	return {}


## Nombre para mostrar de un nivel por su id (fallback: el propio id).
static func campaign_name_for_id(level_id: String) -> String:
	var entry := campaign_entry_for_id(level_id)
	return str(entry.get("display_name", level_id))


## Nombre para mostrar de un nivel por su scene_path (fallback: nombre del archivo).
static func campaign_name_for_scene(scene_path: String) -> String:
	for level: Dictionary in campaign_levels():
		if str(level.get("scene_path", "")) == scene_path:
			return str(level.get("display_name", "?"))
	return scene_path.get_file().get_basename()


## Hint desplegable para elegir la escena de un nivel de campaña
## (scene_path / next_level_path).
static func campaign_scene_hint(include_menu_option: bool = true) -> String:
	var parts: Array[String] = []
	if include_menu_option:
		parts.append("%s:" % MENU_OPTION_LABEL)
	for level: Dictionary in campaign_levels():
		var label: String = str(level.get("display_name", level.get("id", "?")))
		parts.append("%s:%s" % [label, str(level.get("scene_path", ""))])
	return ",".join(parts)


# ─── Limpieza de valores de menús desplegables ──────────────────────────

## Los menús desplegables del Inspector con hint "Etiqueta:valor" guardan a veces
## la etiqueta completa delante (p. ej. "Mapa de Pruebas 1:res://...").
## Devuelve SOLO la parte de ruta res:// (o "" si no hay ruta válida).
## Ej: "Mapa de Pruebas 1:res://x/y.tscn" -> "res://x/y.tscn"
static func clean_scene_path(value: String) -> String:
	if value.is_empty():
		return ""
	var idx: int = value.find("res://")
	if idx >= 0:
		return value.substr(idx)
	return ""


## Versión para claves de exits (siempre contienen "res://...|ruta"). Si no hay
## res:// se devuelve el valor tal cual (p. ej. una clave escrita a mano).
static func clean_exit_key(value: String) -> String:
	if value.is_empty():
		return ""
	var idx: int = value.find("res://")
	if idx >= 0:
		return value.substr(idx)
	return value


# ─── StoryExits de otros niveles (para StorySpawnPoint) ────────────────

## Cache del hint de exits (solo editor). Se reconstruye si cambia algún .tscn
## de campaña (mtime). Evita re-escancar escenas en cada refresco del Inspector.
static var _story_exit_hint_full: String = ""
static var _story_exit_hint_fingerprint: String = ""

## Huella de mtime de las escenas de campaña (para invalidar la cache).
static func _exit_fingerprint() -> String:
	var parts: Array[String] = []
	for level: Dictionary in campaign_levels():
		var scene_path: String = str(level.get("scene_path", ""))
		if scene_path.is_empty():
			continue
		parts.append("%s:%s" % [scene_path, FileAccess.get_modified_time(scene_path)])
	return ",".join(parts)


## Hint desplegable con TODOS los StoryExit de la campaña. Cada opción vale la
## clave única "scene_path|node_path" del exit. Un StorySpawnPoint usa este menú
## para enlazarse al exit de OTRO nivel que aterriza en él.
## exclude_scene_path: si se pasa, se omiten los exits de ESE mapa (normalmente
## el mapa donde vive el propio spawn point).
static func story_exit_hint(exclude_scene_path: String = "") -> String:
	var fp := _exit_fingerprint()
	if fp != _story_exit_hint_fingerprint:
		_story_exit_hint_full = _build_story_exit_hint()
		_story_exit_hint_fingerprint = fp
	if exclude_scene_path.is_empty():
		return _story_exit_hint_full
	var parts: Array[String] = []
	for item: String in _story_exit_hint_full.split(",", false):
		if item.begins_with("(Ninguno)"):
			parts.append(item)
		elif not item.contains(exclude_scene_path):
			parts.append(item)
	return ",".join(parts)


## Escanea (off-tree) cada escena de campaña y recoge sus StoryExit.
static func _build_story_exit_hint() -> String:
	var parts: Array[String] = ["(Ninguno):"]
	for level: Dictionary in campaign_levels():
		var scene_path: String = str(level.get("scene_path", ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			continue
		var root: Node = packed.instantiate()
		if root == null:
			continue
		var level_label: String = str(level.get("display_name", scene_path.get_file()))
		for node: Node in root.find_children("*", "Area3D", true, false):
			if not node.has_method("get_exit_key"):
				continue
			var exit_label: Variant = node.get("display_name")
			var label_str: String = str(exit_label) if exit_label != null and str(exit_label) != "" else str(node.name)
			var key: String = str(node.get_exit_key())
			if key.is_empty():
				continue
			parts.append("%s — %s:%s" % [level_label, label_str, key])
		root.free()
	return ",".join(parts)


# ─── StorySpawnPoints de un mapa (para StoryExit) ───────────────────────

## Hint desplegable con los StorySpawnPoint de una escena destino (destino = destination_scene del exit). Un StoryExit
## usa este menú («destination_spawn_point») para elegir a QUÉ punto de aparición
## viaja el jugador al salir por él. Cada opción vale la clave "scene_path|node_path".
## scene_path: escena destino que se escanea (se limpia la etiqueta si la trae).
static func story_spawn_point_hint(scene_path: String) -> String:
	var target: String = clean_scene_path(scene_path)
	if target.is_empty() or not ResourceLoader.exists(target):
		return "(Sigue el destino del nivel):"
	var packed: PackedScene = load(target) as PackedScene
	if packed == null:
		return "(Sigue el destino del nivel):"
	var root: Node = packed.instantiate()
	var parts: Array[String] = ["(Sigue el destino del nivel):"]
	if root != null:
		for node: Node in root.find_children("*", "Marker3D", true, false):
			if not node.has_method("get_spawn_key"):
				continue
			var pw: Variant = node.get("display_name")
			var label: String = str(pw) if pw != null and str(pw) != "" else str(node.name)
			var key: String = str(node.get_spawn_key())
			if key.is_empty():
				continue
			parts.append("%s:%s" % [label, key])
		root.free()
	return ",".join(parts)


# ─── Tipos de NPC (story_npcs_default.json) ─────────────────────────────

## Hint desplegable para elegir un tipo de NPC registrado en el JSON.
static func npc_type_hint() -> String:
	var parts: Array[String] = []
	var data: Variant = _load_json(NPC_DEFAULTS_PATH)
	var types: Variant = {}
	if data is Dictionary:
		types = (data as Dictionary).get("npc_types", {})
	if types is Dictionary:
		for type_id: Variant in types:
			var info: Variant = types[type_id]
			var label: String = str(type_id)
			if info is Dictionary:
				label = str((info as Dictionary).get("display_name", type_id))
			parts.append("%s:%s" % [label, str(type_id)])
	return ",".join(parts)


# ─── Facciones (story_factions.json) ────────────────────────────────────

## Hint desplegable para elegir una facción por su id.
static func faction_hint() -> String:
	var parts: Array[String] = []
	var data: Variant = _load_json(FACTIONS_PATH)
	var factions: Variant = []
	if data is Dictionary:
		factions = (data as Dictionary).get("factions", [])
	if factions is Array:
		for f: Variant in factions:
			if f is Dictionary:
				var faction_id: int = int((f as Dictionary).get("id", 0))
				parts.append("%s:%d" % [str((f as Dictionary).get("name", "?")), faction_id])
	return ",".join(parts)
