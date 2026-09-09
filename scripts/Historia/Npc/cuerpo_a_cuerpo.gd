class_name CuerpoACuerpo
extends CharacterBody3D

## Zombie lento de Historia. Usa NavigationAgent3D nativo porque las misiones
## necesitan persecución local y precisa, no las rutas tácticas del multijugador.
##
## Todo el comportamiento se configura desde el Spawner vía apply_spawn_config()
## (faction_id, SpawnMode, visión, radius de patrulla/guardia y color de skin).
##
## Activación: cada NPC tiene un switch (activation_mode) para decidir si se
## activa nada más cargar el mapa (START_ON_READY, por defecto) o si se queda
## dormido hasta que un activador externo (pared invisible, puerta, botón...)
## llame a activate()/deactivate() sobre él (EXTERNAL_TRIGGER).
signal died(enemy: CuerpoACuerpo, killer_id: int)

## Modo de comportamiento del NPC:
##  - PATROL: deambula por la zona (wander_radius) y persigue enemigos al verlos.
##  - GUARD : se queda estático en su punto de aparición y solo ataca cuando ve
##            (o siente muy cerca) a un enemigo. Nunca abandona guard_radius.
enum SpawnMode {
	PATROL,
	GUARD,
}

## Modo de activación del NPC:
##  - START_ON_READY : se activa solo nada más cargar el mapa.
##  - EXTERNAL_TRIGGER: queda inactivo hasta que un activador externo (pared
##    invisible, puerta, botón...) llame a activate() sobre este NPC.
enum ActivationMode {
	START_ON_READY,
	EXTERNAL_TRIGGER,
}

@export_category("Stats")
@export var max_health: float = 55.0
@export_range(0.1, 10.0, 0.05) var movement_speed: float = 1.65
@export_range(0.5, 5.0, 0.05) var attack_range: float = 1.5
@export var melee_damage: float = 10.0
@export_range(0.1, 5.0, 0.05) var attack_cooldown: float = 1.1

@export_category("Facción")
## Facción a la que pertenece este NPC (ver config/Historia/story_factions.json).
## Enemistad/alianza se resuelve con StoryFactionSystem.are_hostile().
@export var faction_id: int = int(StoryFactionSystem.ENEMY_FACTION)
## Derivado automáticamente de faction_id para que el daño respete el sistema
## de fuego amigo de GameState (player.take_damage). Variable INTERNA: no se
## edita en el Inspector. No modificar a mano salvo un comportamiento especial.
var equipo_id: int = int(Enums.Equipo.ROJO)

@export_category("Comportamiento")
@export var spawn_mode: SpawnMode = SpawnMode.PATROL
## Distancia máxima a la que el NPC detecta/ve enemigos.
@export_range(1.0, 60.0, 0.5) var vision_range: float = 12.0
## Apertura del cono de visión (grados). 360 = ve en todas direcciones.
@export_range(30.0, 360.0, 10.0) var vision_fov_degrees: float = 120.0
## Radio de deambulación alrededor del punto de aparición (solo PATROL).
@export_range(0.0, 20.0, 0.5) var wander_radius: float = 6.0
## Radio máximo alrededor de su puesto desde el que un guardia persigue al
## objetivo antes de volver a su puesto (solo GUARD).
@export_range(0.0, 40.0, 0.5) var guard_radius: float = 10.0
## Tiempo de "memoria" persiguiendo un enemigo tras perderlo de vista.
@export_range(0.0, 5.0, 0.1) var target_memory_time: float = 1.5
## Cómo se activa este NPC al empezar la partida:
##  - START_ON_READY : actúa nada más cargar el mapa (por defecto).
##  - EXTERNAL_TRIGGER: se queda dormido (estático, no ataca ni percibe) hasta
##    que una pared invisible, una puerta abierta o un botón llame a
##    activate() sobre él.
@export var activation_mode: ActivationMode = ActivationMode.START_ON_READY

@export_category("Navigation")
@export var stop_distance: float = 1.15

@export_category("Rendimiento")
## Espacia las búsquedas de objetivos y raycasts costosos. 0.10 s conserva una
## respuesta inmediata para el jugador y reduce el trabajo de IA en oleadas.
@export_range(0.05, 1.0, 0.01) var perception_interval: float = 0.10

@export_category("Estados (máquina visible)")
## Segundos que dura el estado DETECCIÓN tras adquirir un objetivo nuevo
## (ventana para pedir ayuda antes de considerarse plenamente en combate).
@export_range(0.1, 5.0, 0.1) var state_detection_duration: float = 0.8
## Segundos que dura el estado GANÓ COMBATE tras matar al último enemigo.
@export_range(0.5, 20.0, 0.5) var state_victory_duration: float = 3.0
## Al detectar un enemigo, el NPC grita pidiendo ayuda: publica un estímulo
## ALLY_ALERT que los aliados cercanos oyen (pueden acudir a ayudar).
@export var help_shout_enabled: bool = true
## Radio (m) del grito de ayuda.
@export_range(0.0, 120.0, 1.0) var help_shout_radius: float = 18.0
## Segundos mínimos entre gritos de ayuda (anti-spam).
@export_range(0.0, 60.0, 0.5) var help_shout_cooldown: float = 6.0
## Voz del NPC (líneas por estado; por ahora se muestran en el display de
## debug). Asigna un .tres compartido para tunear las líneas globalmente.
@export var voice: StoryNpcVoice = null

@export_category("IA táctica y depuración")
## Activa un rótulo 3D opcional con estado, schedule, memoria y transición.
## Se usa solo durante desarrollo; desactivado no crea nodos ni añade coste visual.
@export var debug_ai_enabled: bool = false
## Distancia a la que el NPC considera alcanzada su última posición conocida.
@export_range(0.25, 5.0, 0.05) var memory_search_arrival_distance: float = 1.2
## Histéresis de cambio de objetivo: el objetivo ACTUAL cuenta como esta
## fracción más cerca, así un rival solo roba el foco si está claramente más
## cerca (0.3 = 30%). Evita cambios de objetivo nerviosos con varios enemigos.
@export_range(0.0, 0.9, 0.05) var target_switch_hysteresis: float = 0.3
## Segundos tras perder de vista al objetivo actual en los que NO se cambia a
## otro enemigo visible: se persigue la última posición conocida del perdido.
@export_range(0.0, 10.0, 0.1) var target_lost_grace: float = 2.0

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, este NPC FIJO no se recuerda
## (reaparece al volver al mapa). Si se rellena, al morir queda eliminado al
## volver al nivel.
@export var state_id: String = ""

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var current_health: float = 0.0
var is_dead: bool = false
var is_invisible: bool = false
## false = el NPC está inactivo (dormido): no patrulla, no percibe ni ataca,
## esperando un activador externo. true = comportamiento normal.
var is_active: bool = true

var _attack_timer: float = 0.0
var _gravity: float = 9.8
var _spawn_position: Vector3 = Vector3.ZERO

# Máquina de estados visible (derivada del brain táctico; punto de enganche
# para animación, voz y debug).
var _npc_state: StoryNpcStateMachine = StoryNpcStateMachine.new()
## Intención de carrera del frame ("huida"/"apurarse"/"persiguiendo").
var _run_intent: StringName = &""
var _seen_target: Node3D = null
var _target_first_seen_msec: int = 0
var _shouted_for_target: Node3D = null
var _last_shout_msec: int = 0
var _victory_msec: int = 0
# Voz por estado (recurso de fallback si no se asignó ninguno).
var _voice_res: StoryNpcVoice = null
var _voice_line: String = ""
var _voice_line_until_msec: int = 0

# ═══ Skins de color (a falta de modelos reales) ════════════════════════════
# MeshInstance3D no tiene 'modulate' (es una propiedad 2D de CanvasItem).
# Para teñir la malla 3D usamos un StandardMaterial3D propio (duplicado para
# no alterar el material compartido de la escena) y su albedo_color.
var _tint_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE
var _hit_flash_timer: float = 0.0
const HIT_FLASH_TIME: float = 0.12

# ═══ IA interna / táctica ══════════════════════════════════════════════════
var _memory_target: Node3D = null
var _target_memory: float = 0.0
var _last_known_position: Vector3 = Vector3.INF
var _last_known_time_msec: int = 0
var _last_known_confidence: float = 0.0
var _cached_perception_target: Node3D = null
var _perception_timer: float = 0.0
var _heard_stimulus: Dictionary = {}
var _heard_stimulus_timer: float = 0.0
var _tactical_brain: StoryNPCTacticalBrain = StoryNPCTacticalBrain.new()
var _debug_display: StoryNpcDebugDisplay = null
# Wander (PATROL)
var _has_wander_dest: bool = false
var _wander_dest: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _wander_last_dist: float = INF
var _wander_stuck_frames: int = 0

# Seguir al jugador (campaña, tecla Tab). Se activa desde el controlador de
# nivel cuando el jugador pulsa [Tab] en una misión de Historia.
var following: bool = false
var _follow_leader: Node3D = null
var _follow_slot: float = 0.0


func _ready() -> void:
	add_to_group(&"npc")
	add_to_group(&"enemigo")
	current_health = max_health
	if activation_mode == ActivationMode.EXTERNAL_TRIGGER:
		set_active(false)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = stop_distance
	# La facción manda: derivamos el equipo para que GameState.friendly_fire funcione.
	equipo_id = faction_id
	_spawn_position = global_position
	_wander_timer = randf_range(0.5, 1.5)
	_follow_slot = _compute_follow_slot()
	_setup_tint_material()
	_setup_tactical_debug()
	_npc_state.state_changed.connect(_on_npc_state_changed)
	# Overlay de debug (Bot Debug Info del dev menu): se crea solo si ya estaba
	# activado globalmente (los NPCs spawneados más tarde también lo llevan).
	_setup_debug_overlay()
	if not state_id.is_empty():
		LevelStateManager.register(self)
		call_deferred("_restore_persistent_state")


## ── Interfaz de configuración desde el Spawner ─────────────────────────────
## El StoryNPCSpawner construye un Dictionary con estos campos y lo pasa aquí.
## Un NPC que no implemente este método no recibirá la configuración.
func apply_spawn_config(cfg: Dictionary) -> void:
	if cfg.has("faction_id"):
		faction_id = int(cfg["faction_id"])
		equipo_id = faction_id
	if cfg.has("max_health") and float(cfg["max_health"]) > 0.0:
		max_health = float(cfg["max_health"])
		if is_inside_tree():
			current_health = max_health
	if cfg.has("spawn_mode"):
		spawn_mode = int(cfg["spawn_mode"]) as SpawnMode
	if cfg.has("movement_speed"):
		movement_speed = float(cfg["movement_speed"])
	if cfg.has("melee_damage"):
		melee_damage = float(cfg["melee_damage"])
	if cfg.has("vision_range"):
		vision_range = float(cfg["vision_range"])
	if cfg.has("vision_fov_degrees"):
		vision_fov_degrees = float(cfg["vision_fov_degrees"])
	if cfg.has("wander_radius"):
		wander_radius = float(cfg["wander_radius"])
	if cfg.has("guard_radius"):
		guard_radius = float(cfg["guard_radius"])
	if cfg.has("spawn_position"):
		_spawn_position = cfg["spawn_position"] as Vector3
	if cfg.has("skin_color"):
		apply_skin_color(cfg["skin_color"] as Color)
	if cfg.has("activation_mode"):
		activation_mode = int(cfg["activation_mode"]) as ActivationMode
		set_active(activation_mode != ActivationMode.EXTERNAL_TRIGGER)


## Aplica una "skin" de color: cambia el color base del material de la malla.
## Para skins reales en el futuro, este método se sustituiría por la carga del
## modelo correspondiente (p. ej. SkinManager), manteniendo la misma firma.
func apply_skin_color(color: Color) -> void:
	_base_albedo = color
	if _tint_material != null:
		_tint_material.albedo_color = color


## Punto base del NPC (su "puesto" de guardia / centro de deambulación).
func get_spawn_position() -> Vector3:
	return _spawn_position


## ── Interfaz de activación estándar ─────────────────────────────────────────
## Permite conectar este NPC a una StoryInvisibleWall, StoryActionButton o
## StoryDoor (o cualquier trigger) como si fuera un objetivo más: basta con
## poner el path del NPC en "target_nodes" y esos elementos llaman a
## activate()/deactivate() automáticamente.

## Despierta al NPC: empieza a patrullar/perseguir según su spawn_mode.
func activate() -> void:
	set_active(true)


## Duerme al NPC: se queda estático y no percibe ni ataca.
func deactivate() -> void:
	set_active(false)


func toggle() -> void:
	set_active(not is_active)


func set_active(enabled: bool) -> void:
	if is_active == enabled:
		return
	is_active = enabled
	if not enabled:
		_reset_to_idle()


## Abandona cualquier persecución/movimiento y queda pasivo (para dormirse).
func _reset_to_idle() -> void:
	_cached_perception_target = null
	_memory_target = null
	_clear_target_memory()
	_heard_stimulus = {}
	_heard_stimulus_timer = 0.0
	_has_wander_dest = false
	velocity = Vector3.ZERO
	_tactical_brain.deactivate("NPC desactivado")
	_refresh_tactical_debug()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	# Inactivo (esperando un activador externo): el NPC no se mueve, no percibe
	# ni ataca, pero sigue mostrando el flash de daño por si lo golpean.
	if not is_active:
		_update_hit_flash(delta)
		return
	_update_hit_flash(delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_target_memory = maxf(0.0, _target_memory - delta)
	_heard_stimulus_timer = maxf(0.0, _heard_stimulus_timer - delta)
	if _target_memory <= 0.0:
		_memory_target = null
	# Decaimiento de la velocidad horizontal para que el NPC no conserve inercia.
	velocity.x = move_toward(velocity.x, 0.0, movement_speed * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, movement_speed * 2.0 * delta)

	# Intención de carrera del frame (la publican los comportamientos y la
	# consume la máquina de estados visible).
	_run_intent = &""

	var target: Node3D = _get_perception_target(delta)
	var visible_target: Node3D = _get_visible_target()
	# Adquisición de objetivo nuevo: abre la ventana de DETECCIÓN y, si toca,
	# grita pidiendo ayuda a los aliados cercanos (bus de estímulos).
	if visible_target != _seen_target:
		_seen_target = visible_target
		_shouted_for_target = null
		if visible_target != null:
			_target_first_seen_msec = Time.get_ticks_msec()
			_try_help_shout()
		else:
			_target_first_seen_msec = 0
	var heard: Dictionary = _get_best_heard_stimulus()
	var explosive_danger: bool = not heard.is_empty() \
			and int(heard.get("type", -1)) == int(StoryNpcStimulusBus.StimulusType.EXPLOSIVE_DANGER)
	var has_memory: bool = _has_valid_memory()
	var schedule: StoryNPCTacticalBrain.Schedule = _tactical_brain.decide({
		"is_dead": is_dead,
		"is_active": is_active,
		"sees_enemy": visible_target != null,
		"hears_stimulus": not heard.is_empty(),
		"has_target_memory": has_memory,
		"has_explosive_danger": explosive_danger,
		"can_attack_ranged": false,
		"can_patrol": spawn_mode == SpawnMode.PATROL,
		"return_to_post": spawn_mode == SpawnMode.GUARD and global_position.distance_to(_spawn_position) > guard_radius * 0.5,
	})
	match schedule:
		StoryNPCTacticalBrain.Schedule.ATTACK_MELEE:
			if target != null:
				_engage_target(target, delta)
			else:
				_idle_behavior(delta)
		StoryNPCTacticalBrain.Schedule.SEARCH_LAST_KNOWN_POSITION:
			# En modo escolta no se va a investigar estímulos: sigue al jugador.
			if following:
				_idle_behavior(delta)
			else:
				_search_last_known_position(delta)
		StoryNPCTacticalBrain.Schedule.EVADE_EXPLOSIVE:
			_evade_explosive_danger(heard, delta)
		StoryNPCTacticalBrain.Schedule.INVESTIGATE:
			if following:
				_idle_behavior(delta)
			else:
				_investigate_stimulus_or_memory(delta)
		_:
			_idle_behavior(delta)
	_update_npc_state()
	_refresh_tactical_debug()


func take_damage(amount: float, zone: String = "Torso", killer_id: int = -1, from_position: Vector3 = Vector3.INF) -> void:
	if is_dead:
		return
	var multiplier: float = 2.0 if zone == "Cabeza" else 1.0
	current_health = maxf(0.0, current_health - amount * multiplier)
	_hit_flash()
	_turn_to_damage_source(from_position)
	if from_position != Vector3.INF and from_position.is_finite():
		_remember_position(from_position, 0.75)
		var stimulus_bus: Node = get_node_or_null("/root/StoryNpcStimulusBus")
		if stimulus_bus != null:
			stimulus_bus.emit_stimulus(
				StoryNpcStimulusBus.StimulusType.NEAR_IMPACT,
				global_position,
				self
			)
	if current_health <= 0.0:
		die(killer_id)


## Gira de forma suave hacia el origen del daño (si se conoce y hay componente
## StoryNpcDamageTurn "DamageTurn" en la escena).
func _turn_to_damage_source(from_position: Vector3) -> void:
	if from_position == Vector3.INF or not from_position.is_finite():
		return
	var turn: StoryNpcDamageTurn = get_node_or_null("DamageTurn") as StoryNpcDamageTurn
	if turn != null:
		turn.trigger(from_position)


func die(killer_id: int = -1) -> void:
	if is_dead:
		return
	is_dead = true
	_tactical_brain.mark_dead("Salud agotada")
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", true)
	_tint(Color(0.2, 0.2, 0.2))
	following = false
	died.emit(self, killer_id)
	_persist_death()
	await get_tree().create_timer(0.25).timeout
	queue_free()


# ── Persistencia de campaña (NPC fijos) ──────────────────────────────────────

func _restore_persistent_state() -> void:
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	apply_persistent_state(st)


## Elimina el NPC de forma limpia al volver a un nivel donde ya murió.
func _restored_dead() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", true)
	visible = false
	queue_free()


func _persist_death() -> void:
	if state_id.is_empty():
		return
	LevelStateManager.persist_state(self, state_id, {"dead": true})


func get_persistent_state() -> Dictionary:
	return {"dead": is_dead}


func apply_persistent_state(state: Dictionary) -> void:
	if bool(state.get("dead", false)) and not is_dead:
		_restored_dead()


## ── Percepción ──────────────────────────────────────────────────────────────

## Consulta de percepción acelerada: limita el escaneo de grupos y raycasts.
func _get_perception_target(delta: float) -> Node3D:
	_perception_timer = maxf(0.0, _perception_timer - delta)
	if _perception_timer <= 0.0:
		_perception_timer = perception_interval
		var acquired: Node3D = _acquire_visible_target()
		# Gracia de pérdida: si acabamos de perder de vista al objetivo actual
		# (menos de target_lost_grace s), NO cambiar a otro enemigo visible.
		if not _keep_lost_target(acquired):
			_cached_perception_target = acquired
	if is_instance_valid(_cached_perception_target) and not _is_dead(_cached_perception_target) \
			and _is_hostile(_cached_perception_target):
		_remember_target(_cached_perception_target)
		return _cached_perception_target
	if is_instance_valid(_memory_target) and not _is_dead(_memory_target) and _is_hostile(_memory_target) \
			and _has_valid_memory():
		return _memory_target
	return null


## Busca el enemigo hostil visible más cercano. La memoria se mantiene aparte:
## perder visión no renueva el temporizador ni revela la posición actual.
func _acquire_visible_target() -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for group: StringName in [&"player", &"npc"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var cand: Node3D = node as Node3D
			if cand == null or cand == self:
				continue
			if _is_dead(cand) or cand.get("is_invisible") == true:
				continue
			if not _is_hostile(cand):
				continue
			var dist: float = global_position.distance_to(cand.global_position)
			# Histéresis: el objetivo actual "cuenta como" más cerca de lo que es.
			dist = _hysteresis_dist(cand, dist)
			if dist > vision_range or dist >= best_dist:
				continue
			if not _can_see(cand):
				continue
			best = cand
			best_dist = dist
	return best


## Distancia "efectiva" de un candidato a objetivo: el objetivo ACTUAL cuenta
## como target_switch_hysteresis más cerca (histéresis anti-cambio de foco).
## Parte determinista (testable).
func _hysteresis_dist(cand: Node3D, dist: float) -> float:
	if cand == _cached_perception_target and target_switch_hysteresis > 0.0:
		return dist * (1.0 - target_switch_hysteresis)
	return dist


## ¿Mantener el objetivo actual (recién perdido de vista) en vez de cambiar a
## otro enemigo visible? Aplica durante target_lost_grace segundos tras la
## última vez que se vio al objetivo actual. Parte determinista (testable).
func _keep_lost_target(acquired: Node3D) -> bool:
	if acquired == null or acquired == _cached_perception_target:
		return false
	var current: Node3D = _cached_perception_target
	if not is_instance_valid(current) or _is_dead(current) or not _is_hostile(current):
		return false
	if _memory_target != current or not _has_valid_memory():
		return false
	return Time.get_ticks_msec() - _last_known_time_msec < int(target_lost_grace * 1000.0)


## Compatibilidad privada para cualquier herramienta/prueba previa que consultara
## la adquisición de objetivo directamente.
func _acquire_target() -> Node3D:
	return _acquire_visible_target()


func _get_visible_target() -> Node3D:
	if is_instance_valid(_cached_perception_target) and not _is_dead(_cached_perception_target) \
			and _is_hostile(_cached_perception_target) and _can_see(_cached_perception_target):
		return _cached_perception_target
	return null


func _remember_target(target: Node3D) -> void:
	_memory_target = target
	# Escuchar la baja de este objetivo: registra la victoria (máquina de
	# estados: GANO_COMBATE) cuando la baja es nuestra.
	if target.has_signal("died") and not target.died.is_connected(_on_killed_target_died):
		target.died.connect(_on_killed_target_died)
	_remember_position(target.global_position, 1.0)


func _remember_position(known_position: Vector3, confidence: float) -> void:
	if not known_position.is_finite():
		return
	_last_known_position = known_position
	_last_known_time_msec = Time.get_ticks_msec()
	_last_known_confidence = clampf(confidence, 0.0, 1.0)
	_target_memory = target_memory_time


func _has_valid_memory() -> bool:
	return _target_memory > 0.0 and _last_known_position.is_finite()


func _clear_target_memory() -> void:
	_target_memory = 0.0
	_last_known_position = Vector3.INF
	_last_known_time_msec = 0
	_last_known_confidence = 0.0


func _get_best_heard_stimulus() -> Dictionary:
	if _heard_stimulus_timer > 0.0 and not _heard_stimulus.is_empty():
		return _heard_stimulus
	var stimulus_bus: Node = get_node_or_null("/root/StoryNpcStimulusBus")
	if stimulus_bus == null:
		return {}
	_heard_stimulus = stimulus_bus.get_best_stimulus_for(self)
	if _heard_stimulus.is_empty():
		_heard_stimulus_timer = 0.0
		return {}
	var now_msec: int = Time.get_ticks_msec()
	var age_seconds: float = float(now_msec - int(_heard_stimulus.get("time_msec", now_msec))) / 1000.0
	_heard_stimulus_timer = maxf(float(_heard_stimulus.get("duration", 0.0)) - age_seconds, 0.0)
	return _heard_stimulus


func _evade_explosive_danger(stimulus: Dictionary, delta: float) -> void:
	var raw_position: Variant = stimulus.get("position", global_position)
	if not (raw_position is Vector3):
		_idle_behavior(delta)
		return
	var danger_position: Vector3 = raw_position as Vector3
	var away: Vector3 = global_position - danger_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = -global_transform.basis.z
	away = away.normalized()
	var safe_destination: Vector3 = global_position + away * 4.0
	_run_intent = &"huida"
	_navigate_to(safe_destination, delta)


func _search_last_known_position(delta: float) -> void:
	if not _has_valid_memory():
		_idle_behavior(delta)
		return
	if global_position.distance_to(_last_known_position) <= memory_search_arrival_distance:
		_clear_target_memory()
		_idle_behavior(delta)
		return
	_run_intent = &"persiguiendo"
	_navigate_to(_last_known_position, delta)


func _investigate_stimulus_or_memory(delta: float) -> void:
	var stimulus: Dictionary = _get_best_heard_stimulus()
	if not stimulus.is_empty():
		var raw_position: Variant = stimulus.get("position", global_position)
		if raw_position is Vector3:
			var stimulus_position: Vector3 = raw_position as Vector3
			if stimulus_position.is_finite():
				_remember_position(stimulus_position, 0.45)
				# Grito de un aliado → acudir a ayudar; otro estímulo →
				# investigar persiguiendo.
				_run_intent = &"apurarse" if _stimulus_is_ally_alert(stimulus) else &"persiguiendo"
				_navigate_to(stimulus_position, delta)
				return
	_search_last_known_position(delta)


func _is_hostile(other: Node3D) -> bool:
	var other_faction: int
	if other.is_in_group(&"player"):
		other_faction = StoryFactionSystem.PLAYER_FACTION
	elif "faction_id" in other:
		other_faction = int(other.get("faction_id"))
	else:
		other_faction = -1
	return StoryFactionSystem.are_hostile(faction_id, other_faction)


## ¿Puede ver al objetivo? Rango + cono de visión + línea de visión.
## Si el objetivo está pegado (attack_range), se detecta por proximidad aunque
## quede fuera del cono (lo "siente" en el cuerpo a cuerpo).
func _can_see(target: Node3D) -> bool:
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist > vision_range:
		return false
	if dist <= attack_range + 0.2:
		return true
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001 or to_target.length_squared() < 0.0001:
		return true
	if forward.normalized().angle_to(to_target.normalized()) > deg_to_rad(vision_fov_degrees * 0.5):
		return false
	return _has_line_of_sight(target)


## Raycast desde los "ojos" hasta el torso del objetivo. Devuelve true si el
## primer obstáculo es el propio objetivo (línea despejada).
func _has_line_of_sight(target: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 1.5
	var to: Vector3 = target.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return false
	var node: Node = result.get("collider") as Node
	while node != null:
		if node == target:
			return true
		node = node.get_parent()
	return false


## ── Comportamiento ──────────────────────────────────────────────────────────

func _engage_target(target: Node3D, delta: float) -> void:
	var horizontal_to_target: Vector3 = target.global_position - global_position
	horizontal_to_target.y = 0.0
	var target_distance: float = horizontal_to_target.length()
	if target_distance <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		_face_direction(horizontal_to_target, delta)
		_try_attack(target)
		move_and_slide()
		return
	# En modo GUARDIA, si perseguir al objetivo nos alejaría del puesto más allá
	# de lo permitido, el NPC no lo hace: vuelve a su puesto (o se queda).
	if spawn_mode == SpawnMode.GUARD:
		var dist_to_post: float = global_position.distance_to(_spawn_position)
		if dist_to_post > guard_radius:
			_run_intent = &"huida"
			_navigate_to(_spawn_position, delta)
			return
	_run_intent = &"persiguiendo"
	_navigate_to(target.global_position, delta)


## ── Seguir al jugador (campaña, [Tab]) ──────────────────────────────────
## ¿Es aliado del jugador humano?
func is_allied_with_player() -> bool:
	return not StoryFactionSystem.are_hostile(faction_id, StoryFactionSystem.PLAYER_FACTION)


## Activa/desactiva el modo escolta. Lo llama el controlador de nivel cuando
## el jugador pulsa [Tab] en una misión de Historia (solo NPCs aliados).
func set_following(value: bool) -> void:
	if following == value:
		return
	following = value
	if following:
		_follow_leader = get_tree().get_first_node_in_group(&"player")
		_has_wander_dest = false
	else:
		_follow_leader = null
		_wander_timer = randf_range(0.5, 1.5)


func _resolve_follow_leader() -> Node3D:
	if _follow_leader != null and is_instance_valid(_follow_leader) \
			and not _follow_target_is_dead(_follow_leader):
		return _follow_leader
	_follow_leader = get_tree().get_first_node_in_group(&"player")
	if _follow_leader != null and _follow_target_is_dead(_follow_leader):
		return null
	return _follow_leader


func _follow_target_is_dead(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	if target.get("is_dead") is bool:
		return bool(target.get("is_dead"))
	return false


## Asigna a cada aliado un hueco lateral distinto detrás del jugador para que
## no se amontonen (se deriva del instance_id, así cada NPC mantiene su hueco).
func _compute_follow_slot() -> float:
	var slot_id: int = int(get_instance_id() % 7)
	var side: float = 1.0 if slot_id % 2 == 0 else -1.0
	return side * ((slot_id * 0.55) + 0.6)


func _follow_behavior(delta: float) -> void:
	var leader: Node3D = _resolve_follow_leader()
	if leader == null:
		following = false
		_follow_leader = null
		return
	# Punto de formación: detrás del jugador, repartidos lateralmente.
	var behind: Vector3 = leader.global_transform.basis.z
	behind.y = 0.0
	if behind.length_squared() < 0.0001:
		behind = Vector3.BACK
	behind = behind.normalized()
	var side: Vector3 = behind.cross(Vector3.UP).normalized()
	var target_pos: Vector3 = leader.global_position + behind * 2.2 + side * _follow_slot
	target_pos.y = global_position.y
	if global_position.distance_to(target_pos) <= stop_distance:
		velocity.x = move_toward(velocity.x, 0.0, movement_speed * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, movement_speed * 2.0 * delta)
		move_and_slide()
		var face_dir: Vector3 = leader.global_position - global_position
		face_dir.y = 0.0
		if face_dir.length_squared() > 0.0001:
			_face_direction(face_dir.normalized(), delta)
		return
	_navigate_to(target_pos, delta)


func _idle_behavior(delta: float) -> void:
	# En modo escolta, patrulla/guardia se sustituye por seguir al jugador.
	if following:
		_follow_behavior(delta)
		return
	if spawn_mode == SpawnMode.GUARD:
		# Guardia: se mantiene en su puesto. Si fue empujado, regresa.
		var dist_to_post: float = global_position.distance_to(_spawn_position)
		if dist_to_post > guard_radius * 0.5:
			_navigate_to(_spawn_position, delta)
			if global_position.distance_to(_spawn_position) < stop_distance:
				velocity.x = 0.0
				velocity.z = 0.0
				move_and_slide()
			return
		velocity.x = move_toward(velocity.x, 0.0, movement_speed)
		velocity.z = move_toward(velocity.z, 0.0, movement_speed)
		move_and_slide()
		return
	# PATROL: deambula por la zona.
	_patrol(delta)


func _patrol(delta: float) -> void:
	if not _has_wander_dest:
		_wander_timer = maxf(0.0, _wander_timer - delta)
		if _wander_timer <= 0.0:
			_pick_wander_dest()
		else:
			velocity.x = move_toward(velocity.x, 0.0, movement_speed)
			velocity.z = move_toward(velocity.z, 0.0, movement_speed)
			move_and_slide()
		return
	var dist: float = global_position.distance_to(_wander_dest)
	if dist <= stop_distance:
		velocity.x = move_toward(velocity.x, 0.0, movement_speed)
		velocity.z = move_toward(velocity.z, 0.0, movement_speed)
		move_and_slide()
		_has_wander_dest = false
		_wander_timer = randf_range(1.0, 3.0)
		return
	# Anti-bloqueo: si no avanza, descarta el punto y elige otro en breve.
	if dist < _wander_last_dist - 0.05:
		_wander_stuck_frames = 0
	else:
		_wander_stuck_frames += 1
		if _wander_stuck_frames > 90:
			_has_wander_dest = false
			_wander_timer = randf_range(0.25, 0.75)
			return
	_wander_last_dist = dist
	_navigate_to(_wander_dest, delta)


func _pick_wander_dest() -> void:
	var angle: float = randf() * TAU
	var radius: float = randf() * wander_radius
	var point: Vector3 = _spawn_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_wander_dest = point
	_wander_last_dist = INF
	_wander_stuck_frames = 0
	_has_wander_dest = true


## Navega hacia un punto del mundo con la velocidad de movimiento actual.
func _navigate_to(destination: Vector3, delta: float) -> void:
	var direction: Vector3 = _get_navigation_direction(destination)
	velocity.x = direction.x * movement_speed
	velocity.z = direction.z * movement_speed
	_face_direction(direction, delta)
	move_and_slide()


## ── Navegación / orientación ────────────────────────────────────────────────

func _get_navigation_direction(target_position: Vector3) -> Vector3:
	var navigation_map: RID = navigation_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		var direct_direction: Vector3 = target_position - global_position
		direct_direction.y = 0.0
		if direct_direction.length_squared() < 0.0001:
			return Vector3.ZERO
		return direct_direction.normalized()
	navigation_agent.target_position = target_position
	if navigation_agent.is_navigation_finished():
		return Vector3.ZERO
	var next_position: Vector3 = navigation_agent.get_next_path_position()
	var direction: Vector3 = next_position - global_position
	direction.y = 0.0
	return direction.normalized()


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var target_yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 7.0, 1.0))


func _try_attack(target: Node3D) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	if target.has_method("take_damage"):
		# Dificultad global: escala el daño que hacen los NPCs.
		var manager: StoryDifficulty = StoryDifficulty.get_manager()
		var damage: float = melee_damage * (manager.damage_dealt_multiplier() if manager != null else 1.0)
		target.call("take_damage", damage, "Torso", get_instance_id(), global_position)


## Una baja de nuestro objetivo: si fuimos nosotros, registramos la victoria
## (máquina de estados: GANO_COMBATE).
func _on_killed_target_died(_enemy: Node, killer_id: int) -> void:
	if is_dead:
		return
	if killer_id == get_instance_id():
		_victory_msec = Time.get_ticks_msec()


## ── Máquina de estados visible (derivada del brain táctico) ──────────────
## El brain decide QUÉ HACE el NPC; esto deriva QUÉ ESTÁ PASANDO para la
## animación, la voz y el debug. Prioridad: MUERTO > CORRIENDO > DETECCION >
## EN_COMBATE > GANO_COMBATE > PATRULLANDO > QUIETO.
func _update_npc_state() -> void:
	if is_dead:
		_npc_state.set_state(StoryNpcStateMachine.State.MUERTO, &"muerto")
		return
	if _run_intent != &"":
		_npc_state.set_state(StoryNpcStateMachine.State.CORRIENDO, _run_intent)
		return
	var now_msec: int = Time.get_ticks_msec()
	var schedule: StoryNPCTacticalBrain.Schedule = _tactical_brain.current_schedule
	# DETECCIÓN: ventana inicial tras adquirir un objetivo nuevo.
	if _target_first_seen_msec > 0 \
			and now_msec - _target_first_seen_msec <= int(state_detection_duration * 1000.0):
		var detection_sub: StringName = &"pidiendo_ayuda" if _shouted_for_target != null else &"confirmado"
		_npc_state.set_state(StoryNpcStateMachine.State.DETECCION, detection_sub)
		return
	# EN COMBATE (melee): pegando o acercándose al objetivo.
	if schedule == StoryNPCTacticalBrain.Schedule.ATTACK_MELEE:
		var combat_sub: StringName = &"atacando"
		if _memory_target != null and is_instance_valid(_memory_target) \
				and global_position.distance_to(_memory_target.global_position) > attack_range:
			combat_sub = &"acercandose"
		_npc_state.set_state(StoryNpcStateMachine.State.EN_COMBATE, combat_sub)
		return
	# GANÓ EL COMBATE: ventana tras una baja propia sin combate activo.
	if _victory_msec > 0 \
			and now_msec - _victory_msec <= int(state_victory_duration * 1000.0):
		_npc_state.set_state(StoryNpcStateMachine.State.GANO_COMBATE, &"vigilando")
		return
	# PATRULLANDO / QUIETO.
	if schedule in [StoryNPCTacticalBrain.Schedule.PATROL, StoryNPCTacticalBrain.Schedule.RETURN_TO_POST] or following:
		_npc_state.set_state(StoryNpcStateMachine.State.PATRULLANDO, &"")
		return
	_npc_state.set_state(StoryNpcStateMachine.State.QUIETO, &"")


## Grito de ayuda al detectar un enemigo: publica un estímulo ALLY_ALERT por
## el bus de estímulos. Los aliados que lo oyan decidirán si acuden
## (schedule INVESTIGATE). Reutiliza el filtro de bando del bus.
func _try_help_shout() -> void:
	if not help_shout_enabled or not is_inside_tree():
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_shout_msec < int(help_shout_cooldown * 1000.0):
		return
	var stimulus_bus: Node = get_node_or_null("/root/StoryNpcStimulusBus")
	if stimulus_bus == null:
		return
	_last_shout_msec = now_msec
	_shouted_for_target = _seen_target
	stimulus_bus.emit_stimulus(
		StoryNpcStimulusBus.StimulusType.ALLY_ALERT,
		global_position,
		self,
		1.0,
		help_shout_radius
	)


## ¿Es este estímulo un grito de ayuda de un aliado?
func _stimulus_is_ally_alert(stimulus: Dictionary) -> bool:
	return not stimulus.is_empty() \
			and int(stimulus.get("type", -1)) == int(StoryNpcStimulusBus.StimulusType.ALLY_ALERT)


## Recurso de voz activo: el exportado o una COPIA del .tres por defecto
## (copia para que el cooldown de voz no se comparta entre NPCs).
const DEFAULT_VOICE: Resource = preload("res://config/Historia/npc/voz_npc_default.tres")


func _voice() -> StoryNpcVoice:
	if voice != null:
		return voice
	if _voice_res == null:
		_voice_res = (DEFAULT_VOICE as StoryNpcVoice).duplicate()
	return _voice_res


## Cambio de estado visible: el NPC puede "hablar" una línea de su tabla.
func _on_npc_state_changed(_previous_state: int, _new_state: int,
		_previous_sub: StringName, _new_sub: StringName) -> void:
	var spoken: String = _voice().try_speak(_npc_state)
	if not spoken.is_empty():
		_voice_line = spoken
		_voice_line_until_msec = Time.get_ticks_msec() + int(_voice().line_display_time * 1000.0)
		_refresh_tactical_debug()


## ── Skins / tintado ─────────────────────────────────────────────────────────

## Duplica el material de la malla para poder teñirla por instancia sin afectar
## a los zombies hermanos que comparten el mismo recurso StandardMaterial3D.
func _setup_tint_material() -> void:
	if mesh.material_override is StandardMaterial3D:
		_tint_material = (mesh.material_override as StandardMaterial3D).duplicate()
		_base_albedo = _tint_material.albedo_color
		mesh.material_override = _tint_material
	else:
		# No hay material override Standard (o es shader): no podemos teñir albedo.
		_tint_material = null


## Flash rojo al recibir daño: tiñe y programa la vuelta al color de skin.
func _hit_flash() -> void:
	if _tint_material == null:
		return
	_tint_material.albedo_color = Color(1.0, 0.35, 0.35)
	_hit_flash_timer = HIT_FLASH_TIME


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_timer <= 0.0:
		return
	_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
	if _hit_flash_timer == 0.0 and _tint_material != null:
		_tint_material.albedo_color = _base_albedo


## Aplica un color de forma inmediata (usado internamente en die()).
func _tint(color: Color) -> void:
	if _tint_material != null:
		_tint_material.albedo_color = color


## Snapshot estable para herramientas, overlay y pruebas de integración.
func get_tactical_debug_snapshot() -> Dictionary:
	var memory_age: float = 0.0
	if _last_known_time_msec > 0:
		memory_age = float(Time.get_ticks_msec() - _last_known_time_msec) / 1000.0
	return {
		"state": _tactical_brain.get_global_state_name(),
		"schedule": _tactical_brain.get_schedule_name(),
		"npc_state": _npc_state.describe(),
		"task": _tactical_brain.current_task,
		"reason": _tactical_brain.last_transition_reason,
		"conditions": _tactical_brain.get_conditions_summary(),
		"last_known_position": _last_known_position,
		"memory_age": memory_age,
		"memory_confidence": _last_known_confidence,
		"has_memory": _has_valid_memory(),
		"heard_stimulus": _heard_stimulus.duplicate(),
		"voice_line": _voice_line if _voice_line_until_msec > Time.get_ticks_msec() else "",
	}


func _setup_tactical_debug() -> void:
	if not debug_ai_enabled or _debug_display != null:
		return
	_debug_display = StoryNpcDebugDisplay.new()
	_debug_display.name = "AIDebug"
	add_child(_debug_display)
	_debug_display.setup(self)


func _refresh_tactical_debug() -> void:
	if _debug_display != null and is_instance_valid(_debug_display):
		_debug_display.refresh(get_tactical_debug_snapshot())


func _is_dead(body: Node) -> bool:
	return body.get("is_dead") == true


## ── Debug Overlay (Bot Debug Info / Propiedades de unidad) ────────────────
## Mismo patrón que Player, BotBase y Tirador: el dev menu activa/desactiva
## el overlay globalmente y este NPC responde mostrando vida y schedule de IA.
const DEBUG_OVERLAY_SCENE: PackedScene = preload(
	"res://scenes/Multiplayer/objetos/bots/bot_debug_overlay.tscn")

var _debug_overlay: Node3D = null


func _setup_debug_overlay() -> void:
	if BotDebugOverlay.enabled:
		_add_debug_overlay()
	else:
		_remove_debug_overlay()


func _add_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		return
	var overlay: Node3D = DEBUG_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	_debug_overlay = overlay


func _remove_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		_debug_overlay.queue_free()
		_debug_overlay = null
