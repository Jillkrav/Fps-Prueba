class_name StoryNPCTacticalBrain
extends RefCounted

## Núcleo liviano y reutilizable de decisión para los NPCs de Historia.
##
## Separa el estado global, las condiciones observadas y el schedule elegido sin
## sustituir los controladores de movimiento/combate que ya usan CuerpoACuerpo y
## Tirador. Los NPCs publican esta información en el Inspector y, opcionalmente,
## con StoryNpcDebugDisplay durante el desarrollo.

signal transitioned(previous_state: GlobalState, current_state: GlobalState, schedule: Schedule, reason: String)

enum GlobalState {
	INACTIVE,
	IDLE,
	ALERT,
	COMBAT,
	SEARCH,
	SCRIPTED,
	DEAD,
}

enum Schedule {
	NONE,
	IDLE,
	PATROL,
	DISCOVER_ENEMY,
	ATTACK_MELEE,
	ATTACK_RANGED,
	SEEK_COVER,
	RELOAD,
	EVADE_EXPLOSIVE,
	INVESTIGATE,
	SEARCH_LAST_KNOWN_POSITION,
	RETURN_TO_POST,
	RECOVER_NAVIGATION,
	DEAD,
}

var global_state: GlobalState = GlobalState.IDLE
var current_schedule: Schedule = Schedule.IDLE
var current_task: String = "Esperar"
var last_transition_reason: String = "Inicializado"
var last_transition_time_msec: int = 0

var sees_enemy: bool = false
var hears_stimulus: bool = false
var has_target_memory: bool = false
var has_clear_shot: bool = false
var has_friendly_fire_risk: bool = false
var has_low_ammo: bool = false
var has_explosive_danger: bool = false
var has_heavy_damage: bool = false
var has_navigation_failure: bool = false


func reset(reason: String = "Reinicio") -> void:
	sees_enemy = false
	hears_stimulus = false
	has_target_memory = false
	has_clear_shot = false
	has_friendly_fire_risk = false
	has_low_ammo = false
	has_explosive_danger = false
	has_heavy_damage = false
	has_navigation_failure = false
	_transition(GlobalState.IDLE, Schedule.IDLE, "Esperar", reason)


func deactivate(reason: String = "Desactivado") -> void:
	_transition(GlobalState.INACTIVE, Schedule.NONE, "Sin actividad", reason)


func mark_dead(reason: String = "Muerto") -> void:
	_transition(GlobalState.DEAD, Schedule.DEAD, "Liberar recursos", reason)


func update_context(context: Dictionary) -> void:
	sees_enemy = bool(context.get("sees_enemy", false))
	hears_stimulus = bool(context.get("hears_stimulus", false))
	has_target_memory = bool(context.get("has_target_memory", false))
	has_clear_shot = bool(context.get("has_clear_shot", false))
	has_friendly_fire_risk = bool(context.get("has_friendly_fire_risk", false))
	has_low_ammo = bool(context.get("has_low_ammo", false))
	has_explosive_danger = bool(context.get("has_explosive_danger", false))
	has_heavy_damage = bool(context.get("has_heavy_damage", false))
	has_navigation_failure = bool(context.get("has_navigation_failure", false))


func decide(context: Dictionary) -> Schedule:
	update_context(context)
	if bool(context.get("is_dead", false)):
		mark_dead("Muerte confirmada")
		return current_schedule
	if not bool(context.get("is_active", true)):
		deactivate("NPC desactivado")
		return current_schedule
	if has_explosive_danger:
		_transition(GlobalState.COMBAT, Schedule.EVADE_EXPLOSIVE, "Evitar peligro explosivo", "Peligro explosivo prioritario")
		return current_schedule
	if has_navigation_failure:
		_transition(GlobalState.ALERT, Schedule.RECOVER_NAVIGATION, "Replanificar ruta", "Destino inaccesible o sin progreso")
		return current_schedule
	if sees_enemy:
		if bool(context.get("seek_cover", false)):
			_transition(GlobalState.COMBAT, Schedule.SEEK_COVER, "Buscar cobertura", "Salud baja o daño grave")
		elif has_low_ammo:
			_transition(GlobalState.COMBAT, Schedule.RELOAD, "Recargar", "Cargador vacío con reserva")
		elif bool(context.get("can_attack_ranged", false)):
			if has_clear_shot and not has_friendly_fire_risk:
				_transition(GlobalState.COMBAT, Schedule.ATTACK_RANGED, "Disparar ráfaga", "Objetivo visible y tiro seguro")
			else:
				_transition(GlobalState.COMBAT, Schedule.INVESTIGATE, "Buscar ángulo de tiro", "Sin tiro seguro")
		else:
			_transition(GlobalState.COMBAT, Schedule.ATTACK_MELEE, "Perseguir y atacar", "Objetivo visible")
		return current_schedule
	if has_target_memory:
		_transition(GlobalState.SEARCH, Schedule.SEARCH_LAST_KNOWN_POSITION, "Investigar última posición", "Objetivo perdido con memoria vigente")
		return current_schedule
	if hears_stimulus:
		_transition(GlobalState.ALERT, Schedule.INVESTIGATE, "Investigar estímulo", "Estímulo auditivo recibido")
		return current_schedule
	if bool(context.get("return_to_post", false)):
		_transition(GlobalState.IDLE, Schedule.RETURN_TO_POST, "Volver al puesto", "Sin amenaza fuera del puesto")
		return current_schedule
	if bool(context.get("can_patrol", false)):
		_transition(GlobalState.IDLE, Schedule.PATROL, "Patrullar", "Sin amenaza")
	else:
		_transition(GlobalState.IDLE, Schedule.IDLE, "Esperar", "Sin amenaza")
	return current_schedule


func get_global_state_name() -> String:
	return _enum_name(GlobalState, global_state).capitalize()


func get_schedule_name() -> String:
	return _enum_name(Schedule, current_schedule).replace("_", " ").capitalize()


func get_conditions_summary() -> String:
	var active: Array[String] = []
	if sees_enemy:
		active.append("ve enemigo")
	if hears_stimulus:
		active.append("oye estímulo")
	if has_target_memory:
		active.append("memoria")
	if has_clear_shot:
		active.append("tiro claro")
	if has_friendly_fire_risk:
		active.append("riesgo aliado")
	if has_low_ammo:
		active.append("munición baja")
	if has_explosive_danger:
		active.append("peligro explosivo")
	if has_heavy_damage:
		active.append("daño grave")
	if has_navigation_failure:
		active.append("ruta fallida")
	return ", ".join(active) if not active.is_empty() else "sin condiciones activas"


func _enum_name(values: Dictionary, value: int) -> String:
	for key: String in values:
		if int(values[key]) == value:
			return key
	return "UNKNOWN"


func _transition(next_state: GlobalState, next_schedule: Schedule, next_task: String, reason: String) -> void:
	var previous_state: GlobalState = global_state
	var changed: bool = global_state != next_state or current_schedule != next_schedule \
			or current_task != next_task or last_transition_reason != reason
	global_state = next_state
	current_schedule = next_schedule
	current_task = next_task
	last_transition_reason = reason
	if changed:
		last_transition_time_msec = Time.get_ticks_msec()
		transitioned.emit(previous_state, global_state, current_schedule, reason)
