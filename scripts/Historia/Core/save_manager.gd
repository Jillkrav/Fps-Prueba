## AUTOLOAD /root/SaveManager (no usar class_name: el nombre del autoload ya es
## el identificador global y declarar un class_name igual rompe la compilación).
extends Node

## ────────────────────────────────────────────────────────────────────────────
##  SaveManager — Guardado persistente de la campaña (CAPA 3 de la arquitectura).
##  Autoload (/root/SaveManager).
##
##  Escribe JSON en  user://savegames/  (NUNCA toca los .tscn/.tres/.json de
##  configuración del proyecto). Slots:
##    slot 0 -> user://savegames/autosave.json   (checkpoints)
##    slot N -> user://savegames/slot_N.json     (guardado manual / transición)
##
##  Contenido del JSON:
##    meta          -> versión del formato + fecha/hora
##    campaign      -> current_level, completed_levels, checkpoint (GameStateSP)
##    level_states  -> TODO el estado de la Capa 2 (LevelStateManager)
##    player        -> snapshot del jugador (vida, arma, munición)
##
##  Momentos de guardado (los pide el diseño):
##    - Checkpoint activado  -> autosave()  (lo llama StoryCheckpoint)
##    - Transición de mapa   -> save_current_game(1) (lo llama el controlador)
##    - Menú / pausa futuro  -> save_current_game(slot) desde la UI
##
##  El jugador SE RESTAURA al volver a un nivel: el controlador lee
##  get_player_snapshot() y aplica vida/arma/municiones.
## ────────────────────────────────────────────────────────────────────────────

const SAVE_DIR := "user://savegames"
const AUTOSAVE_SLOT := 0
const SAVE_VERSION := 1
## Número de slots disponibles en el menú «cargar partida» (0 = autosave, 1..N-1).
const MAX_SLOTS := 5

## Snapshot del jugador capturado en el último guardado. Se aplica al entrar
## a un nivel (lo lee StoryLevelController) y al cargar una partida.
var last_player_snapshot: Dictionary = {}


func _ready() -> void:
	add_to_group(&"save_manager")
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


# ── Rutas y existencia ───────────────────────────────────────────────────────

func get_save_path(slot: int) -> String:
	if slot == AUTOSAVE_SLOT:
		return SAVE_DIR + "/autosave.json"
	return SAVE_DIR + "/slot_%d.json" % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(get_save_path(slot))


## Slots con guardado existente, ordenados (0 = autosave, 1..MAX_SLOTS-1 manuales).
func get_save_slots() -> Array[int]:
	var slots: Array[int] = []
	for s: int in range(MAX_SLOTS):
		if has_save(s):
			slots.append(s)
	return slots


## Lee SOLO el resumen de un slot (meta + campaña + jugador) sin aplicarlo:
## {slot, level_id, level_path, health, max_health, weapon, ammo_in_mag,
## reserve_ammo, timestamp}. {} si el slot no existe o el JSON es inválido.
func read_save_summary(slot: int) -> Dictionary:
	var path := get_save_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	var summary: Dictionary = {"slot": slot}
	var campaign: Variant = data.get("campaign", {})
	if campaign is Dictionary:
		summary["level_id"] = str((campaign as Dictionary).get("current_level_id", ""))
		summary["level_path"] = str((campaign as Dictionary).get("current_level_path", ""))
	var meta: Variant = data.get("meta", {})
	if meta is Dictionary:
		summary["timestamp"] = str((meta as Dictionary).get("timestamp", ""))
	var player: Variant = data.get("player", {})
	if player is Dictionary:
		var pd: Dictionary = player
		summary["health"] = float(pd.get("health", 0.0))
		summary["max_health"] = float(pd.get("max_health", 100.0))
		summary["weapon"] = str(pd.get("weapon", "-"))
		summary["ammo_in_mag"] = int(pd.get("ammo_in_mag", 0))
		summary["reserve_ammo"] = int(pd.get("reserve_ammo", 0))
	return summary


# ── Guardar ──────────────────────────────────────────────────────────────────

## Guarda el estado actual de la campaña en un slot concreto.
func save_current_game(slot: int = 1) -> void:
	var data: Dictionary = _collect_save_data()
	last_player_snapshot = data.get("player", {}) if data.get("player", {}) is Dictionary else {}
	_write_json(get_save_path(slot), data)


## Autoguardado (checkpoints). Slot 0.
func autosave() -> void:
	save_current_game(AUTOSAVE_SLOT)


## Alias por comodidad para UI/eventos.
func save_now() -> void:
	autosave()


## Reinicia el snapshot del jugador (al empezar una campaña nueva).
func reset_campaign_session() -> void:
	last_player_snapshot = {}


func _collect_save_data() -> Dictionary:
	var data: Dictionary = {}
	data["meta"] = {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
	}

	# Estado de campaña (GameStateSP)
	var campaign: Dictionary = {}
	var gs: Node = get_node_or_null("/root/GameStateSP")
	if gs != null:
		campaign["current_level_id"] = str(gs.get("current_level_id"))
		campaign["current_level_path"] = str(gs.get("current_level_path"))
		campaign["has_checkpoint"] = bool(gs.get("has_checkpoint"))
		campaign["checkpoint_position"] = _vec_to_array(gs.get("checkpoint_position"))
		var completed: Variant = gs.get("completed_levels")
		if completed is Dictionary:
			campaign["completed_levels"] = completed
	data["campaign"] = campaign

	# Estado por nivel (LevelStateManager)
	var lsm: Node = get_node_or_null("/root/LevelStateManager")
	if lsm != null and lsm.has_method("get_all_level_states"):
		data["level_states"] = lsm.get_all_level_states()
	else:
		data["level_states"] = {}

	# Snapshot del jugador
	data["player"] = _capture_player_snapshot()
	return data


## Captura vida/arma/municiones del jugador actual (si existe en la escena).
func _capture_player_snapshot() -> Dictionary:
	var snap: Dictionary = {}
	if get_tree() == null:
		return snap
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return snap
	snap["health"] = player.get("current_health")
	snap["max_health"] = player.get("max_health")
	var weapon: Node = player.get("active_weapon")
	if weapon != null and is_instance_valid(weapon):
		snap["weapon"] = str(weapon.get("weapon_name"))
		snap["ammo_in_mag"] = weapon.get("ammo_in_mag")
		snap["reserve_ammo"] = weapon.get("reserve_ammo")
	return snap


func get_player_snapshot() -> Dictionary:
	return last_player_snapshot


# ── Cargar ───────────────────────────────────────────────────────────────────

## Carga una partida de un slot y deja la memoria (GameStateSP + LevelStateManager
## + snapshot del jugador) lista para entrar al nivel guardado. Devuelve true si
## cargó correctamente.
func load_game(slot: int) -> bool:
	var path := get_save_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[SaveManager] No se pudo abrir %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_error("[SaveManager] JSON inválido en %s" % path)
		return false
	var data: Dictionary = parsed

	# Campaign (GameStateSP)
	var campaign: Variant = data.get("campaign", {})
	var gs: Node = get_node_or_null("/root/GameStateSP")
	if gs != null and campaign is Dictionary:
		var cd: Dictionary = campaign
		if cd.has("current_level_id"):
			gs.set("current_level_id", str(cd["current_level_id"]))
		if cd.has("current_level_path"):
			gs.set("current_level_path", str(cd["current_level_path"]))
		if cd.has("has_checkpoint"):
			gs.set("has_checkpoint", bool(cd["has_checkpoint"]))
		if cd.has("checkpoint_position"):
			var arr: Variant = cd["checkpoint_position"]
			if arr is Array and (arr as Array).size() >= 3:
				gs.set("checkpoint_position", Vector3(float(arr[0]), float(arr[1]), float(arr[2])))
		if cd.has("completed_levels") and (cd["completed_levels"] as Variant) is Dictionary:
			gs.set("completed_levels", cd["completed_levels"])

	# Estado por nivel (LevelStateManager)
	var lsm: Node = get_node_or_null("/root/LevelStateManager")
	if lsm != null and lsm.has_method("load_all_level_states"):
		lsm.load_all_level_states(data.get("level_states", {}))

	# Snapshot del jugador
	var psnap: Variant = data.get("player", {})
	if psnap is Dictionary:
		last_player_snapshot = psnap
	else:
		last_player_snapshot = {}
	return true


# ── Utilidades internas ──────────────────────────────────────────────────────

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] No se pudo escribir %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


## Vector3 -> [x, y, z] para serializar a JSON.
func _vec_to_array(v: Variant) -> Array:
	if v is Vector3:
		return [v.x, v.y, v.z]
	return []
