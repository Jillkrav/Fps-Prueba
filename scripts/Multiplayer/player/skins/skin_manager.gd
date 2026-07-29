# skin_manager.gd
# ─────────────────────────────────────────────────────────────────────────────
# Autoload global que gestiona las skins disponibles y la skin activa.
# Escanea automáticamente las subcarpetas de res://scenes/Multiplayer/objetos/skins/
# buscando archivos .tres de tipo SkinData.
#
# Señales:
#   skin_changed(skin_id: String)  — Se emite al cambiar de skin.
#
# Métodos principales:
#   get_skins() -> Array[SkinData]     — Lista todas las skins descubiertas.
#   get_skin(id: String) -> SkinData   — Obtiene una skin por su ID.
#   select_skin(id: String)            — Cambia la skin activa.
#   get_selected_skin() -> SkinData    — Retorna la skin activa.
#   apply_skin(node: Node)             — Aplica la skin activa a un Player/NPC.
# ─────────────────────────────────────────────────────────────────────────────
extends Node

signal skin_changed(skin_id: String)

## Ruta base donde se buscan las skins (escanea recursivamente subcarpetas).
const SKINS_BASE_PATH: String = "res://scenes/Multiplayer/objetos/skins/"
const CHARACTERS_CONFIG_PATH: String = "res://config/Multiplayer/characters.json"
const TEAMS_CONFIG_PATH: String = "res://config/teams_skins.json"
var _character_config: Dictionary = {}

## Nombre de la clave en ProjectSettings para persistir la selección (opcional por ahora).
const SAVE_KEY: String = "player/skins/selected"

# ─── Estado interno ────────────────────────────────────────────────────────
var _skins: Dictionary = {}        # skin_id -> SkinData
var _skin_list: Array[SkinData] = []
var _current_skin_id: String = ""

# ═══════════════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_load_character_config()
	_discover_skins()
	_load_selected_skin()


# ═══════════════════════════════════════════════════════════════════════════
# DESUBRIMIENTO DE SKINS
# ═══════════════════════════════════════════════════════════════════════════

## Escanea recursivamente SKINS_BASE_PATH buscando archivos .tres de tipo SkinData.
func _load_character_config() -> void:
	if not FileAccess.file_exists(CHARACTERS_CONFIG_PATH):
		return
	var file: FileAccess = FileAccess.open(CHARACTERS_CONFIG_PATH, FileAccess.READ)
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	if error == OK and parser.data is Dictionary:
		for entry: Variant in parser.data.get("characters", []):
			if entry is Dictionary and bool(entry.get("enabled", true)):
				_character_config[str(entry.get("id", ""))] = entry

func get_camera_config(skin_id: String = "") -> Dictionary:
	var id: String = skin_id if not skin_id.is_empty() else _current_skin_id
	return _character_config.get(id, {}).get("camera", {}) as Dictionary

func _discover_skins() -> void:
	_skins.clear()
	_skin_list.clear()
	
	var dir: DirAccess = DirAccess.open(SKINS_BASE_PATH)
	if not dir:
		push_warning("SkinManager: No se encontró el directorio: ", SKINS_BASE_PATH)
		return
	
	_scan_directory(dir, SKINS_BASE_PATH)
	
	if _skins.is_empty():
		push_warning("SkinManager: No se encontraron archivos de skin en: ", SKINS_BASE_PATH)
	else:
		print("SkinManager: Descubiertas ", _skins.size(), " skins: ", _skins.keys())


## Escanea recursivamente un directorio buscando archivos .tres.
func _scan_directory(dir: DirAccess, path: String) -> void:
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	
	while entry != "":
		var full_path: String = path.path_join(entry)
		
		if dir.current_is_dir() and not entry.begins_with("."):
			# Escanear subdirectorio
			var sub_dir: DirAccess = DirAccess.open(full_path)
			if sub_dir:
				_scan_directory(sub_dir, full_path)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			# Cargar recurso
			var skin: SkinData = load(full_path) as SkinData
			if skin and skin.id != "" and (_character_config.is_empty() or _character_config.has(skin.id)):
				if _character_config.has(skin.id):
					skin.runtime_camera_config = _character_config[skin.id].get("camera", {}) as Dictionary
				_skins[skin.id] = skin
				_skin_list.append(skin)
				print("SkinManager: Cargada skin '", skin.id, "' -> ", skin.name)
		
		entry = dir.get_next()
	
	dir.list_dir_end()


# ═══════════════════════════════════════════════════════════════════════════
# SELECCIÓN / PERSISTENCIA
# ═══════════════════════════════════════════════════════════════════════════

## Carga la skin previamente seleccionada (desde ProjectSettings).
func _load_selected_skin() -> void:
	var saved_id: String = ProjectSettings.get_setting(SAVE_KEY, "")
	
	if saved_id.is_empty() or not _skins.has(saved_id):
		# Fallback: usar la primera skin disponible o "teddy"
		if _skins.has("teddy"):
			saved_id = "teddy"
		elif not _skin_list.is_empty():
			saved_id = _skin_list[0].id
		else:
			return
	
	_current_skin_id = saved_id
	print("SkinManager: Skin activa -> ", _current_skin_id)


## Guarda la skin seleccionada en ProjectSettings.
func _save_selected_skin() -> void:
	if SAVE_KEY.is_empty():
		return
	if not ProjectSettings.has_setting(SAVE_KEY):
		ProjectSettings.set_setting(SAVE_KEY, _current_skin_id)
	else:
		ProjectSettings.set_setting(SAVE_KEY, _current_skin_id)


# ═══════════════════════════════════════════════════════════════════════════
# API PÚBLICA
# ═══════════════════════════════════════════════════════════════════════════

## Retorna la lista completa de skins descubiertas.
func get_skins() -> Array[SkinData]:
	return _skin_list.duplicate()


## Obtiene un SkinData por su ID. Retorna null si no existe.
func get_skin(skin_id: String) -> SkinData:
	return _skins.get(skin_id, null)


## Retorna la skin activa actualmente.
func get_selected_skin() -> SkinData:
	return _skins.get(_current_skin_id, null)


## Retorna el ID de la skin activa.
func get_selected_skin_id() -> String:
	return _current_skin_id


## Cambia la skin activa. Emite skin_changed.
func select_skin(skin_id: String) -> bool:
	if not _skins.has(skin_id):
		push_warning("SkinManager: Skin no encontrada: ", skin_id)
		return false
	
	if _current_skin_id == skin_id:
		return true
	
	_current_skin_id = skin_id
	_save_selected_skin()
	skin_changed.emit(skin_id)
	print("SkinManager: Skin cambiada a: ", skin_id)
	return true


## Aplica la skin activa al nodo objetivo (Player o BotBase).
## Reemplaza cualquier modelo visual existente bajo el nodo "SkinModel".
##
## El nodo objetivo debe tener un método _on_skin_applied(skin_data: SkinData)
## para finalizar la configuración (animaciones, texturas, etc.).
func apply_skin(target_node: Node, skin_id: String = "") -> bool:
	var skin: SkinData = null
	if skin_id.is_empty():
		skin = get_selected_skin()
	else:
		skin = get_skin(skin_id)
	
	if not skin:
		push_warning("SkinManager: No hay skin para aplicar")
		return false
	if not skin.model_scene:
		push_warning("SkinManager: La skin '", skin.id, "' no tiene model_scene")
		return false
	
	# Eliminar modelo anterior (si existe)
	var old_model: Node = target_node.get_node_or_null("SkinModel")
	if old_model:
		old_model.queue_free()
	
	# Instanciar nuevo modelo
	var model_instance: Node3D = skin.model_scene.instantiate() as Node3D
	if not model_instance:
		push_warning("SkinManager: model_scene.instantiate() devolvió null")
		return false
	
	model_instance.name = "SkinModel"
	target_node.add_child(model_instance)
	model_instance.owner = target_node.owner if target_node.owner else target_node
	
	# Notificar al nodo objetivo para que configure animaciones y texturas
	if target_node.has_method("_on_skin_applied"):
		target_node.call("_on_skin_applied", skin, model_instance)
	
	return true


## Obtiene la skin asignada por defecto para un equipo.
## Lee `teams_skins.json` y mapea el equipo_id (Enums.Equipo) a la skin
## correspondiente. Si el JSON no existe, no encuentra la skin, o el equipo
## no está configurado, devuelve la skin activa global como fallback.
func get_skin_for_team(team_id: int) -> SkinData:
	var file: FileAccess = FileAccess.open(TEAMS_CONFIG_PATH, FileAccess.READ)
	if not file:
		# Si el JSON no existe, fallback a skin activa global
		return get_selected_skin()

	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()

	if error != OK or not (parser.data is Dictionary):
		return get_selected_skin()

	# Mapear Enums.Equipo a clave del JSON
	var team_key: String = ""
	match team_id:
		Enums.Equipo.ROJO:
			team_key = "rojo"
		Enums.Equipo.AZUL:
			team_key = "azul"
		Enums.Equipo.ESPECTADOR, _:
			# Espectador o valor desconocido → fallback
			return get_selected_skin()

	var teams: Dictionary = parser.data.get("teams", {})
	var team_config: Dictionary = teams.get(team_key, {})
	var default_skin_id: String = team_config.get("default_skin", "")

	if default_skin_id.is_empty():
		return get_selected_skin()

	var skin: SkinData = get_skin(default_skin_id)
	if skin:
		return skin

	# Skin ID del JSON no encontrada en las skins cargadas
	return get_selected_skin()
