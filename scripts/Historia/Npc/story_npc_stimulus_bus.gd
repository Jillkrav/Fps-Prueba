extends Node

## Bus local de estímulos para la IA de Historia.
##
## No reproduce audio ni requiere recursos finales. Cualquier gameplay puede
## publicar un evento lógico (disparo, pasos, explosión, impacto...) y los NPCs
## cercanos lo consumen como información auditiva limitada y con caducidad.

signal stimulus_emitted(stimulus: Dictionary)

enum StimulusType {
	EXPLOSIVE_DANGER,
	COMBAT,
	GUNSHOT,
	NEAR_IMPACT,
	SURFACE_IMPACT,
	PLAYER_MOVEMENT,
	ALLY_ALERT,
	WORLD,
	DECOY,
}

const DEFAULT_CONFIG_PATH: String = "res://config/Historia/npc/story_npc_stimuli.json"
const MAX_RECENT_STIMULI: int = 64

var _recent_stimuli: Array[Dictionary] = []
var _config_cache: Dictionary = {}


func _ready() -> void:
	_load_config()
	set_process(true)


func emit_stimulus(
	type: StimulusType,
	position: Vector3,
	source: Node3D = null,
	intensity: float = 1.0,
	override_radius: float = -1.0,
	override_duration: float = -1.0
) -> Dictionary:
	var profile: Dictionary = get_stimulus_profile(type)
	var now_msec: int = Time.get_ticks_msec()
	var stimulus: Dictionary = {
		"id": now_msec,
		"type": int(type),
		"position": position,
		"source_id": source.get_instance_id() if is_instance_valid(source) else 0,
		"intensity": maxf(intensity, 0.0),
		"radius": override_radius if override_radius >= 0.0 else float(profile.get("radius", 0.0)),
		"duration": override_duration if override_duration >= 0.0 else float(profile.get("duration", 0.0)),
		"priority": int(profile.get("priority", 0)),
		"time_msec": now_msec,
	}
	_recent_stimuli.append(stimulus)
	if _recent_stimuli.size() > MAX_RECENT_STIMULI:
		_recent_stimuli.pop_front()
	stimulus_emitted.emit(stimulus.duplicate())
	return stimulus


func get_best_stimulus_for(listener: Node3D, min_priority: int = 0) -> Dictionary:
	if listener == null or not is_instance_valid(listener):
		return {}
	var now_msec: int = Time.get_ticks_msec()
	var best: Dictionary = {}
	var best_score: float = -INF
	for stimulus: Dictionary in _recent_stimuli:
		if int(stimulus.get("priority", 0)) < min_priority:
			continue
		var age_seconds: float = float(now_msec - int(stimulus.get("time_msec", 0))) / 1000.0
		var duration: float = float(stimulus.get("duration", 0.0))
		if age_seconds > duration:
			continue
		var raw_position: Variant = stimulus.get("position", Vector3.INF)
		if not (raw_position is Vector3):
			continue
		var position: Vector3 = raw_position as Vector3
		if not position.is_finite():
			continue
		var radius: float = float(stimulus.get("radius", 0.0)) * float(stimulus.get("intensity", 1.0))
		var distance: float = listener.global_position.distance_to(position)
		if distance > radius:
			continue
		# ── Filtros sociales del oído ──
		# 1) Nadie reacciona a un estímulo que él mismo originó (auto-exclusión).
		# 2) El fuego del PROPIO bando no alarma: GUNSHOT y SURFACE_IMPACT provienen
		#    del arma del emisor; si emisor y oyente están aliados, se ignoran.
		#    NEAR_IMPACT proviene de la VÍCTIMA, así que NO se filtra (un aliado
		#    herido debe alarmar al grupo).
		var source_id: int = int(stimulus.get("source_id", 0))
		if source_id > 0:
			var source: Object = instance_from_id(source_id)
			if source == listener:
				continue
			var stype: int = int(stimulus.get("type", -1))
			if (stype == int(StimulusType.GUNSHOT) or stype == int(StimulusType.SURFACE_IMPACT)) \
					and _is_same_side(source, listener):
				continue
		var freshness: float = clampf(1.0 - age_seconds / maxf(duration, 0.01), 0.0, 1.0)
		var proximity: float = clampf(1.0 - distance / maxf(radius, 0.01), 0.0, 1.0)
		var score: float = float(stimulus.get("priority", 0)) * 100.0 + freshness * 10.0 + proximity
		if score > best_score:
			best_score = score
			best = stimulus
	return best.duplicate()


func get_stimulus_profile(type: StimulusType) -> Dictionary:
	if _config_cache.is_empty():
		_load_config()
	var entries: Dictionary = _config_cache.get("stimuli", {}) as Dictionary
	var key: String = stimulus_type_key(type)
	return entries.get(key, {}) as Dictionary


static func stimulus_type_key(type: StimulusType) -> String:
	for key: String in StimulusType:
		if int(StimulusType[key]) == int(type):
			return key.to_lower()
	return "world"


func _process(_delta: float) -> void:
	_prune_expired()


func _prune_expired() -> void:
	var now_msec: int = Time.get_ticks_msec()
	var kept: Array[Dictionary] = []
	for stimulus: Dictionary in _recent_stimuli:
		var age_seconds: float = float(now_msec - int(stimulus.get("time_msec", 0))) / 1000.0
		if age_seconds <= float(stimulus.get("duration", 0.0)):
			kept.append(stimulus)
	_recent_stimuli = kept


func _load_config() -> void:
	_config_cache = {}
	if not FileAccess.file_exists(DEFAULT_CONFIG_PATH):
		push_warning("StoryNpcStimulusBus: falta %s; los estímulos usarán valores vacíos." % DEFAULT_CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_CONFIG_PATH))
	if parsed is Dictionary:
		_config_cache = parsed as Dictionary
	else:
		push_warning("StoryNpcStimulusBus: JSON inválido en %s." % DEFAULT_CONFIG_PATH)


## Facción de un nodo (player → facción del jugador; NPC → su faction_id).
## -1 si es desconocida.
static func _faction_of(node: Object) -> int:
	if node == null or not is_instance_valid(node):
		return -1
	if node.is_in_group(&"player"):
		return StoryFactionSystem.PLAYER_FACTION
	if "faction_id" in node:
		return int(node.get("faction_id"))
	return -1


## true si emisor y oyente pertenecen al mismo bando (aliados entre sí según
## StoryFactionSystem). Facción desconocida (-1) en cualquiera de los dos
## devuelve false para no filtrar (comportamiento conservador).
static func _is_same_side(source: Object, listener: Node) -> bool:
	var source_faction: int = _faction_of(source)
	var listener_faction: int = _faction_of(listener)
	if source_faction < 0 or listener_faction < 0:
		return false
	return StoryFactionSystem.are_allied(source_faction, listener_faction)
