class_name Tirador
extends CharacterBody3D

## Soldado armado de Historia. Misma configuración desde el Spawner que
## CuerpoACuerpo (facción, modo patrulla/guardia, visión, radios y skin),
## pero en lugar de solo golpear defiende/dispara con el arma que el diseñador
## elige del arsenal (ver export `weapon_name`).
##
## ── Extraas respecto al melee ────────────────────────────────────────────
##   * Elige TODAS las armas del arsenal (skill.json) desde el Inspector.
##   * Dispara de forma realista usando el sistema Weapon existente
##     (proyectiles / hit-scan / melee), respetando el fuego amigo.
##   * Al morir suelta el arma (WeaponPickup) que el jugador puede recoger.
##   * INTERCAMBIO estilo Halo: si es ALIADO y lleva un arma distinta, el
##     jugador puede pulsar [E] cerca para intercambiar armas con él.
##   * Configuración especial reutilizable (TiradorConfig) para el futuro:
##     lanzar granadas sin cambiar de arma y tomar cobertura (compatible con
##     los props pack one_way_low_wall a través de sus CoverPoint).
##   * ACTIVACIÓN: switch (activation_mode) para activarse nada más cargar el
##     mapa (START_ON_READY, por defecto) o quedarse dormido hasta que un
##     activador externo (pared invisible, puerta, botón...) llame a
##     activate()/deactivate() sobre él (EXTERNAL_TRIGGER).
signal died(enemy: Tirador, killer_id: int)

## Modo de comportamiento BASE del NPC (igual que CuerpoACuerpo).
## Determina el comportamiento OCIOSO y la disciplina de movimiento:
##  - PATROL: deambula por el mapa (sin límite de radio) y persigue al ver enemigos.
##  - GUARD : patrulla acotada alrededor del puesto y no se aleja de él.
## El COMBATE puede volverse "asaltante" con el flag independiente
## `aggressive_enabled` (aplica tanto a PATROL como a GUARD).
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

const DROPPED_WEAPON: PackedScene = preload("res://scenes/Compartido/pickups/dropped_weapon.tscn")
const WEAPON_SCENE_PATH: String = "res://scenes/Compartido/weapons/weapon_placeholder.tscn"

@export_category("Stats")
@export var max_health: float = 75.0
@export_range(0.1, 10.0, 0.05) var movement_speed: float = 2.4
@export_range(0.5, 5.0, 0.05) var attack_range: float = 1.5
## Golpe cuerpo a cuerpo de DEFENSA: por diseño es más débil que el de un NPC
## especializado en melee (CuerpoACuerpo usa 10.0). El tirador solo lo usa
## cuando un enemigo se le acerca mucho (ver _engage_target / _should_melee).
@export var melee_damage: float = 6.0
@export_range(0.1, 5.0, 0.05) var attack_cooldown: float = 1.1

@export_category("Facción")
## Facción a la que pertenece este NPC (ver config/Historia/story_factions.json).
## Enemistad/alianza se resuelve con StoryFactionSystem.are_hostile().
@export var faction_id: int = int(StoryFactionSystem.ENEMY_FACTION)
## Derivado automáticamente de faction_id para que el daño respete el sistema
## de fuego amigo de GameState. Variable INTERNA: no se edita en el Inspector.
var equipo_id: int = int(Enums.Equipo.ROJO)

@export_category("Armamento")
## Arma del arsenal que lleva este NPC (ver config/Compartido/skill.json ->
## "Armas"). Todas las del arsenal están disponibles.
@export_enum("USP", "Glock", "Deagle", "M3", "Spas12", "Recortada", "EscopetaAutomatica", "MP7", "MP5", "AUG", "M4", "G36", "Scout", "AWP", "Crowbar", "Tonfa", "Machete", "Cuchillo", "Granada", "Ballesta", "LanzaGranadas", "Bazooka", "RiflePlasma", "PistolaPlasma") var weapon_name: String = "Glock"
## Si true, al morir el NPC suelta un arma recogible con su munición actual.
@export var drop_weapon_on_death: bool = true
## Munición inicial en el cargador (-1 = la normal del arma, llena).
@export_range(-1, 9999, 1) var weapon_mag_override: int = -1
## Munición inicial en reserva (-1 = la normal del arma, llena).
@export_range(-1, 9999, 1) var weapon_reserve_override: int = -1

@export_category("Comportamiento")
@export var spawn_mode: SpawnMode = SpawnMode.PATROL
@export_range(1.0, 60.0, 0.5) var vision_range: float = 16.0
@export_range(30.0, 360.0, 10.0) var vision_fov_degrees: float = 120.0
@export_range(0.0, 20.0, 0.5) var wander_radius: float = 6.0
@export_range(0.0, 40.0, 0.5) var guard_radius: float = 10.0
@export_range(0.0, 5.0, 0.1) var target_memory_time: float = 1.5
## Distancia de formación al seguir al jugador ([C] global / menú de órdenes):
## el aliado se coloca DETRÁS del jugador a esta distancia (más su hueco
## lateral). Subirla evita que el aliado se pegue durante la escolta.
@export_range(1.5, 10.0, 0.1) var follow_distance: float = 3.5
## Cómo se activa este NPC al empezar la partida:
##  - START_ON_READY : actúa nada más cargar el mapa (por defecto).
##  - EXTERNAL_TRIGGER: se queda dormido (estático, no ataca ni percibe) hasta
##    que una pared invisible, una puerta abierta o un botón llame a
##    activate() sobre él.
@export var activation_mode: ActivationMode = ActivationMode.START_ON_READY

@export_category("Navigation")
@export var stop_distance: float = 1.15

@export_category("Rendimiento")
## Espacia búsquedas de grupos y raycasts sin cambiar la lógica de combate.
@export_range(0.05, 1.0, 0.01) var perception_interval: float = 0.10

@export_category("Agresivo")
## Combate ASALTANTE (independiente del modo base `spawn_mode`). Si está
## activado, el tirador avanza disparando hacia el enemigo hasta agotar un
## umbral de cargador, retrocede si el enemigo se acerca demasiado y tras
## matar a un objetivo corre a su posición. Aplica tanto a PATROL como a GUARD
## (en GUARD el ocioso sigue siendo la patrulla acotada del puesto).
@export var aggressive_enabled: bool = false
## Distancia (metros) a la que un agresivo deja de acercarse al enemigo.
## Solo aplica si aggressive_enabled = true.
@export_range(1.0, 30.0, 0.5) var aggressive_stop_distance: float = 6.0
## Si un enemigo se acerca por debajo de esta distancia, el agresivo retrocede
## para reposicionarse (evita que el melee le llegue).
@export_range(0.5, 20.0, 0.5) var aggressive_back_off_distance: float = 4.0
## Fracción del cargador a la que el agresivo deja de avanzar (ej. 0.5 = 50%).
@export_range(0.1, 1.0, 0.05) var aggressive_stop_mag_fraction: float = 0.5
## SUELO de balas: aunque el 50% del cargador sea menor, no se deja de avanzar
## por la regla del cargador hasta tener estas balas (evita que armas de
## cargador pequeño se detengan al primer disparo).
@export_range(1, 99, 1) var aggressive_min_mag_bullets: int = 6
## SUELO de metros: el agresivo siempre avanza al menos esta distancia hacia el
## objetivo antes de detenerse por la regla del cargador.
@export_range(1.0, 60.0, 1.0) var aggressive_min_advance_metres: float = 10.0
## Segundos máximos corriendo hacia el cadáver de un enemigo al que mató (luego
## se cancela por si la posición quedó inalcanzable).
@export_range(1.0, 60.0, 1.0) var corpse_rush_timeout: float = 12.0
## PUSH ON RELOAD (solo agresivo): si el enemigo desaparece de vista con
## NUESTRO cargador sano, avanzar unos metros hacia su última posición
## (castiga al enemigo que recarga en campo abierto).
@export var push_on_reload_enabled: bool = true
## Fracción del cargador por encima de la cual se considera sano para empujar.
@export_range(0.1, 1.0, 0.05) var push_on_reload_mag_fraction: float = 0.8
## Metros máximos de avance del push.
@export_range(1.0, 30.0, 0.5) var push_distance: float = 4.0
## Ventana (s) tras perder la visión en la que se considera que recarga.
@export_range(0.2, 5.0, 0.1) var push_lost_grace: float = 1.5

@export_category("Retroceso (kiting) y combate pasivo")
## Combate PASIVO (tiradores NO agresivos): mantienen la posición — no avanzan
## hacia el enemigo, no lo persiguen al perderlo de vista ni investigan sus
## disparos; disparan desde donde están cuando el objetivo entra en rango. Si
## false, recuperan el comportamiento antiguo de acercarse y buscar.
@export var passive_holds_ground: bool = true
## El tirador DISPARA mientras retrocede (kiting) en vez de darse la vuelta y
## huir sin defenderse.
@export var retreat_fire_while_backing: bool = true
## Longitud (m) del raycast de escape: si hay pared o geometría a menos de esta
## distancia en la dirección de huida, se prueba la esquiva lateral.
@export_range(0.5, 10.0, 0.25) var retreat_wall_check_distance: float = 2.5
## Si la huida directa está bloqueada por una pared, probar escape lateral
## (strafe). Si también está bloqueado, el tirador se planta y pelea.
@export var retreat_allow_strafe: bool = true
## Histéresis del retroceso: se retrocede hasta aggressive_back_off_distance
## por este factor antes de reanudar el combate, para no oscilar entre
## retroceder y pararse a disparar.
@export_range(1.0, 3.0, 0.1) var retreat_hysteresis: float = 1.5
## Segundos máximos de un retroceso antes de abortarlo por atasco (pared,
## esquina o enemigo igual de rápido) y plantarse a pelear.
@export_range(0.5, 10.0, 0.25) var retreat_stuck_timeout: float = 2.0
## Segundos que el tirador se queda plantado peleando tras abortar un
## retroceso atascado, antes de volver a intentar retroceder.
@export_range(0.5, 10.0, 0.25) var retreat_recover_time: float = 3.0

@export_category("Strafe de combate")
## Mientras dispara parado en su banda de distancia, el tirador camina LENTO
## de lado (nunca corre): se mueve lateralmente cada cierto tiempo para no ser
## un blanco fijo. Solo aplica disparando; nunca al avanzar/retroceder.
@export var combat_strafe_enabled: bool = true
## Segundos entre cambios de lado (con ±20% aleatorio).
@export_range(0.25, 5.0, 0.05) var combat_strafe_interval: float = 1.5
## Velocidad del strafe como fracción de movement_speed (lento: caminar).
@export_range(0.05, 1.0, 0.05) var combat_strafe_speed_mult: float = 0.35

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

@export_category("Config Especial")
## Configuración especial reutilizable del soldado (granadas, cobertura...).
## Si se deja vacío se usa un perfil base por defecto (Ver TiradorConfig).
@export var tirador_config: TiradorConfig = null

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, este NPC FIJO no se recuerda
## (reaparece al volver al mapa). Si se rellena, al morir queda eliminado al
## volver al nivel.
@export var state_id: String = ""

# ═══ Nodos ═════════════════════════════════════════════════════════════
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var weapon_holder: Node3D = $WeaponHolder
@onready var trade_area: Area3D = $TradeArea
@onready var prompt_label: Label3D = $PromptLabel

# ═══ Estado ════════════════════════════════════════════════════════════
var current_health: float = 0.0
var is_dead: bool = false
var is_invisible: bool = false
## false = el NPC está inactivo (dormido): no patrulla, no percibe ni ataca,
## esperando un activador externo. true = comportamiento normal.
var is_active: bool = true

var _weapon: Weapon = null
## Total de munición (cargador + reserva) con el que partió el soldado. Es el
## "default" al que vuelve automáticamente cada vez que se queda sin balas.
var _default_total_ammo: int = 0

var _attack_timer: float = 0.0
var _reaction_timer: float = 0.0
var _reaction_armed: bool = false
var _gravity: float = 9.8
var _spawn_position: Vector3 = Vector3.ZERO

# Skins / tintado (igual que CuerpoACuerpo).
var _tint_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE
var _hit_flash_timer: float = 0.0
const HIT_FLASH_TIME: float = 0.12

# IA interna / táctica.
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
var _has_wander_dest: bool = false
var _wander_dest: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _wander_last_dist: float = INF
var _wander_stuck_frames: int = 0

# Granadas.
var _grenade_timer: float = 0.0
var _last_grenade_decision: String = "Sin evaluar"

# Cobertura.
var _cover_point: CoverPoint = null
var _cover_timer: float = 0.0
var _cover_destination: Vector3 = Vector3.INF
var _cover_last_distance: float = INF
var _cover_stuck_frames: int = 0
# Cobertura por fuego recibido sostenido.
var _recent_hits_msec: Array[int] = []
var _sustained_fire_cover_request: bool = false
var _last_cover_exit_msec: int = -1000000

# Agresivo (asaltante).
var _agg_active: bool = false
var _agg_start_dist: float = INF
var _corpse_rush_position: Vector3 = Vector3.INF
var _corpse_rush_timer: float = 0.0
## Destino del push on reload en curso (INF = sin push).
var _push_destination: Vector3 = Vector3.INF

# Retroceso (kiting) con anti-atasco.
var _retreat_active: bool = false
var _retreat_timer: float = 0.0
var _retreat_dir: Vector3 = Vector3.ZERO
var _no_retreat_until_msec: int = 0

# Strafe de combate (caminar lento de lado mientras dispara).
var _strafe_side: int = 1
var _strafe_timer: float = 0.0

# Máquina de estados visible (derivada del brain táctico; punto de enganche
# para animación, voz y debug).
var _npc_state: StoryNpcStateMachine = StoryNpcStateMachine.new()
## Intención de carrera del frame (la publican los comportamientos: "huida",
## "apurarse", "persiguiendo"). Se resetea cada frame.
var _run_intent: StringName = &""
var _seen_target: Node3D = null
var _target_first_seen_msec: int = 0
var _shouted_for_target: Node3D = null
var _last_shout_msec: int = 0
var _victory_msec: int = 0
# Cadencia ajustada por dificultad (instante del último disparo del NPC).
var _last_npc_fire_msec: int = -1000000
# Voz por estado (recurso de fallback si no se asignó ninguno).
var _voice_res: StoryNpcVoice = null
var _voice_line: String = ""
var _voice_line_until_msec: int = 0

# Intercambio (Halo).
var _player_in_trade: Player = null

# Seguir al jugador (campaña, tecla Tab). Se activa desde el controlador de
# nivel cuando el jugador pulsa [Tab] en una misión de Historia.
var following: bool = false
var _follow_leader: Node3D = null
var _follow_slot: float = 0.0

## Perfil base por defecto si el diseñador no asignó tirador_config.
func _config() -> TiradorConfig:
	if tirador_config == null:
		tirador_config = TiradorConfig.new()
	return tirador_config


func _ready() -> void:
	add_to_group(&"npc")
	add_to_group(&"enemigo")
	add_to_group(&"tirador")
	current_health = max_health
	if activation_mode == ActivationMode.EXTERNAL_TRIGGER:
		set_active(false)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = stop_distance
	equipo_id = faction_id
	_spawn_position = global_position
	_wander_timer = randf_range(0.5, 1.5)
	_follow_slot = _compute_follow_slot()
	_setup_tint_material()
	_setup_tactical_debug()
	_npc_state.state_changed.connect(_on_npc_state_changed)
	trade_area.body_entered.connect(_on_trade_body_entered)
	trade_area.body_exited.connect(_on_trade_body_exited)
	_equip_weapon(weapon_name)
	prompt_label.visible = false
	# Overlay de debug (Bot Debug Info del dev menu): se crea solo si ya estaba
	# activado globalmente (los NPCs spawneados más tarde también lo llevan).
	_setup_debug_overlay()
	if not state_id.is_empty():
		LevelStateManager.register(self)
		call_deferred("_restore_persistent_state")


## ── Configuración desde el Spawner ──────────────────────────────────────
func apply_spawn_config(cfg: Dictionary) -> void:
	if cfg.has("faction_id"):
		faction_id = int(cfg["faction_id"])
		equipo_id = faction_id
	if cfg.has("spawn_mode"):
		spawn_mode = int(cfg["spawn_mode"]) as SpawnMode
	if cfg.has("aggressive_enabled"):
		aggressive_enabled = bool(cfg["aggressive_enabled"])
	if cfg.has("max_health") and float(cfg["max_health"]) > 0.0:
		max_health = float(cfg["max_health"])
		if is_inside_tree():
			current_health = max_health
	if cfg.has("drop_weapon_on_death"):
		drop_weapon_on_death = bool(cfg["drop_weapon_on_death"])
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
	# Armas (consumido solo por este tipo de NPC).
	if cfg.has("weapon_name"):
		weapon_name = String(cfg["weapon_name"])
	if cfg.has("weapon_mag_override"):
		weapon_mag_override = int(cfg["weapon_mag_override"])
	if cfg.has("weapon_reserve_override"):
		weapon_reserve_override = int(cfg["weapon_reserve_override"])
	if cfg.get("tirador_config") is TiradorConfig:
		tirador_config = cfg["tirador_config"] as TiradorConfig
	if cfg.has("activation_mode"):
		activation_mode = int(cfg["activation_mode"]) as ActivationMode
		set_active(activation_mode != ActivationMode.EXTERNAL_TRIGGER)
	_equip_weapon(weapon_name)


func apply_skin_color(color: Color) -> void:
	_base_albedo = color
	if _tint_material != null:
		_tint_material.albedo_color = color


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
	_reaction_armed = false
	_release_cover()
	_agg_active = false
	_agg_start_dist = INF
	_corpse_rush_position = Vector3.INF
	_corpse_rush_timer = 0.0
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
	_grenade_timer = maxf(0.0, _grenade_timer - delta)
	velocity.x = move_toward(velocity.x, 0.0, movement_speed * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, movement_speed * 2.0 * delta)
	_update_swap_prompt(delta)

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
	var clear_shot: bool = visible_target != null and _has_line_of_sight(visible_target)
	var friendly_fire_risk: bool = visible_target != null and _has_friendly_fire_risk(visible_target)
	var low_ammo: bool = _weapon != null and is_instance_valid(_weapon) \
			and _weapon.ammo_in_mag <= 0 and _weapon.reserve_ammo > 0
	var schedule: StoryNPCTacticalBrain.Schedule = _tactical_brain.decide({
		"is_dead": is_dead,
		"is_active": is_active,
		"sees_enemy": visible_target != null,
		"hears_stimulus": not heard.is_empty(),
		"has_target_memory": has_memory,
		"can_attack_ranged": true,
		"has_clear_shot": clear_shot,
		"has_friendly_fire_risk": friendly_fire_risk,
		"has_explosive_danger": explosive_danger,
		"has_low_ammo": low_ammo,
		"seek_cover": _should_seek_cover(),
		"can_patrol": spawn_mode == SpawnMode.PATROL,
		"return_to_post": spawn_mode == SpawnMode.GUARD and global_position.distance_to(_spawn_position) > guard_radius * 0.5,
	})
	# Granada anti-cobertura: el enemigo acaba de esconderse junto a un
	# CoverPoint (se evalúa solo con memoria reciente y en rango).
	_try_anti_cover_grenade()
	# Rush al cadáver (agresivo): cuando no hay combate/estímulo (schedule idle o
	# patrulla), el soldado corre a la posición del enemigo al que acaba de matar.
	# Cualquier combate o estímulo (ATTACK_*, SEEK_COVER, INVESTIGATE, ...) tiene
	# prioridad y lo interrumpe automáticamente.
	if aggressive_enabled and _corpse_rush_position.is_finite() \
			and not following \
			and schedule in [StoryNPCTacticalBrain.Schedule.IDLE, StoryNPCTacticalBrain.Schedule.PATROL]:
		_run_intent = &"apurarse"
		_rush_to_corpse(delta)
		_update_npc_state()
		_refresh_tactical_debug()
		return
	# El retroceso (kiting) solo tiene sentido en combate activo: resetearlo en
	# cualquier otro estado para no arrastrar velocidades ni direcciones viejas.
	if schedule not in [StoryNPCTacticalBrain.Schedule.ATTACK_RANGED, StoryNPCTacticalBrain.Schedule.ATTACK_MELEE]:
		_end_retreat()
	match schedule:
		StoryNPCTacticalBrain.Schedule.SEEK_COVER:
			if target != null:
				_seek_cover(target, delta)
			else:
				_idle_behavior(delta)
		StoryNPCTacticalBrain.Schedule.ATTACK_RANGED, StoryNPCTacticalBrain.Schedule.ATTACK_MELEE:
			if target != null:
				if not _reaction_armed or _memory_target != target:
					_reaction_timer = _config().effective_reaction_time()
					_reaction_armed = true
				_release_cover()
				_engage_target(target, delta)
			else:
				_idle_behavior(delta)
		StoryNPCTacticalBrain.Schedule.RELOAD:
			_reload_or_seek_cover(target, delta)
		StoryNPCTacticalBrain.Schedule.EVADE_EXPLOSIVE:
			_evade_explosive_danger(heard, delta)
		StoryNPCTacticalBrain.Schedule.INVESTIGATE:
			# En modo escolta o pasivo (passive_holds_ground) no se va a
			# curiosear estímulos ni a perseguir al enemigo. EXCEPCIÓN: el
			# grito de ayuda de un aliado (ALLY_ALERT) sí mueve a los pasivos.
			if following or (passive_holds_ground and not _stimulus_is_ally_alert(heard)):
				_idle_behavior(delta)
			else:
				_investigate_stimulus_or_memory(delta)
		StoryNPCTacticalBrain.Schedule.SEARCH_LAST_KNOWN_POSITION:
			if following or passive_holds_ground:
				_idle_behavior(delta)
			else:
				_search_last_known_position(delta)
		_:
			_release_cover()
			_cover_timer = 0.0
			_reaction_armed = false
			_idle_behavior(delta)
	_update_npc_state()
	_refresh_tactical_debug()


## ── Daño / muerte ───────────────────────────────────────────────────────
func take_damage(amount: float, zone: String = "Torso", killer_id: int = -1, from_position: Vector3 = Vector3.INF) -> void:
	if is_dead:
		return
	var multiplier: float = 2.0 if zone == "Cabeza" else 1.0
	current_health = maxf(0.0, current_health - amount * multiplier)
	_hit_flash()
	_register_incoming_hit()
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
		if _cover_point != null and amount * multiplier >= _config().cover_invalidation_damage:
			_release_cover()
	if killer_id > 0:
		_mark_danger_from(killer_id)
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


## Al recibir daño, recuerda al agresor como objetivo (girar y reaccionar).
func _mark_danger_from(killer_id: int) -> void:
	var attacker: Object = instance_from_id(killer_id)
	if attacker == null or not (attacker is Node3D):
		return
	var attacker_node: Node3D = attacker as Node3D
	if not attacker_node.is_inside_tree() or _is_dead(attacker_node):
		return
	if not _is_hostile(attacker_node):
		return
	_memory_target = attacker_node
	_remember_position(attacker_node.global_position, 0.9)
	_reaction_armed = false


func die(killer_id: int = -1) -> void:
	if is_dead:
		return
	is_dead = true
	_tactical_brain.mark_dead("Salud agotada")
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", true)
	_tint(Color(0.2, 0.2, 0.2))
	_hide_swap_prompt()
	following = false
	_release_cover()
	if drop_weapon_on_death:
		_drop_weapon()
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


## Suelta el arma actual como un WeaponPickup recogible por el jugador.
func _drop_weapon() -> void:
	if _weapon == null or not is_instance_valid(_weapon):
		return
	if not is_inside_tree():
		return
	var drop: Node = DROPPED_WEAPON.instantiate()
	# Persistencia de campaña: el arma soltada por un NPC muerto debe quedar en
	# el mapa al ir y volver. Le damos una identidad única ANTES de añadirla a
	# la escena para que se registre como entidad persistente y, al regresar, el
	# nivel la re-cree si sigue en el suelo (LevelStateManager.collect_dynamic_drops).
	drop.set("state_id", "dyn_drop_%d_%d" % [get_instance_id(), Time.get_ticks_usec()])
	get_parent().add_child(drop)
	drop.global_transform.origin = global_position + Vector3.UP * 0.5
	if drop.has_method("set_weapon_data"):
		drop.set_weapon_data(get_weapon_data())


## ── Armas ───────────────────────────────────────────────────────────────
func _equip_weapon(arma: String) -> void:
	if _weapon != null and is_instance_valid(_weapon):
		_weapon.queue_free()
		_weapon = null
	if arma.is_empty():
		return
	var weapon_scene: PackedScene = ResourceLoader.load(
		WEAPON_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene
	if weapon_scene == null:
		push_error("Tirador: No se pudo cargar weapon_placeholder.tscn")
		return
	var inst: Node = weapon_scene.instantiate()
	# Normalmente el arma cuelga del WeaponHolder del soldado; si aún no estamos
	# en el árbol (p. ej. pruebas/units o durante apply_spawn_config antes del
	# ready), usar el propio soldado como padre para no depender del árbol.
	var holder: Node = weapon_holder if weapon_holder != null else self
	holder.add_child(inst)
	_weapon = inst as Weapon
	if _weapon == null:
		push_error("Tirador: weapon_instance no es un Weapon")
		return
	_weapon.initialize_from_name(arma)
	_weapon.set_equip_locked(false)
	_weapon.load_ai_profile()
	if weapon_mag_override >= 0:
		_weapon.ammo_in_mag = clampi(weapon_mag_override, 0, _weapon.clip_size)
	if weapon_reserve_override >= 0:
		_weapon.reserve_ammo = clampi(weapon_reserve_override, 0, _weapon.max_ammo)
	# Guarda el total con el que parte el soldado: es el default al que volverá
	# automáticamente si algún día llega a 0 balas.
	_default_total_ammo = _weapon.ammo_in_mag + _weapon.reserve_ammo


## Datos del arma actual (para soltarla o intercambiarla).
func get_weapon_data() -> Dictionary:
	if _weapon == null or not is_instance_valid(_weapon):
		return {}
	return {
		"tipo_arma": _weapon.weapon_name,
		"balas_cargador": _weapon.ammo_in_mag,
		"balas_reserva": _weapon.reserve_ammo,
		"capacidad_cargador": _weapon.clip_size,
	}


## Recibe un arma del suelo (o el intercambio con el jugador) y la equipa.
func pickup_weapon(data: Dictionary) -> void:
	var arma: String = str(data.get("tipo_arma", ""))
	if arma.is_empty():
		return
	var mag: int = int(data.get("balas_cargador", 0))
	var reserve: int = int(data.get("balas_reserva", 0))
	# Misma arma: solo suma munición (tope).
	if _weapon != null and is_instance_valid(_weapon) \
			and _weapon.weapon_name.to_lower() == arma.to_lower():
		_weapon.ammo_in_mag = mini(_weapon.ammo_in_mag + mag, _weapon.clip_size)
		_weapon.reserve_ammo = mini(_weapon.reserve_ammo + reserve, _weapon.max_ammo)
		return
	weapon_name = arma
	_equip_weapon(arma)
	if _weapon != null and is_instance_valid(_weapon):
		_weapon.ammo_in_mag = mag
		_weapon.reserve_ammo = reserve


## ── Intercambio estilo Halo con aliados ─────────────────────────────────
## ¿Es aliado del jugador humano?
func is_allied_with_player() -> bool:
	return not StoryFactionSystem.are_hostile(faction_id, StoryFactionSystem.PLAYER_FACTION)


## ¿Puede el jugador intercambiar armas conmigo ahora mismo?
func can_swap_with(player: Player) -> bool:
	if is_dead:
		return false
	if player == null or not is_instance_valid(player):
		return false
	if not is_allied_with_player():
		return false
	if _weapon == null or not is_instance_valid(_weapon):
		return false
	if player.active_weapon == null or not is_instance_valid(player.active_weapon):
		return false
	# No tiene sentido intercambiar la misma arma (a menos que quieras munición).
	if _weapon.weapon_name.to_lower() == player.active_weapon.weapon_name.to_lower():
		return false
	return true


## La mitad del intercambio que vive en el NPC: recibe el arma del jugador.
func swap_with_player(player: Player) -> bool:
	if not can_swap_with(player):
		return false
	var npc_data: Dictionary = get_weapon_data()
	var player_data: Dictionary = {
		"tipo_arma": player.active_weapon.weapon_name,
		"balas_cargador": player.active_weapon.ammo_in_mag,
		"balas_reserva": player.active_weapon.reserve_ammo,
		"capacidad_cargador": player.active_weapon.clip_size,
	}
	# El jugador se queda con el arma del aliado (con su munición actual).
	player.cambiar_arma(str(npc_data["tipo_arma"]))
	if player.active_weapon and is_instance_valid(player.active_weapon):
		player.active_weapon.ammo_in_mag = int(npc_data["balas_cargador"])
		player.active_weapon.reserve_ammo = int(npc_data["balas_reserva"])
		player.active_weapon.weapon_ammo_changed.emit(
			player.active_weapon.ammo_in_mag, player.active_weapon.reserve_ammo
		)
	# El aliado se queda con el arma que llevaba el jugador.
	pickup_weapon(player_data)
	_hide_swap_prompt()
	return true


func _on_trade_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_trade = body as Player


func _on_trade_body_exited(body: Node3D) -> void:
	if body == _player_in_trade:
		_player_in_trade = null
		_hide_swap_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if _player_in_trade == null or not is_instance_valid(_player_in_trade):
		return
	if not is_allied_with_player():
		return
	# Mientras el menú de órdenes está abierto no respondemos a E/Tab.
	if _is_command_menu_open():
		return
	var player := _player_in_trade
	if event.is_action_pressed("interact"):
		# [E]: abrir el menú de órdenes para este aliado (cerca y mirándolo).
		if is_player_looking_at(player):
			_open_command_menu(player)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("scoreboard"):
		# [Tab]: intercambiar arma con este aliado (cerca y mirándolo).
		if is_player_looking_at(player) and swap_with_player(player):
			get_viewport().set_input_as_handled()


func _update_swap_prompt(_delta: float) -> void:
	if _player_in_trade == null or not is_instance_valid(_player_in_trade):
		return
	if is_dead or not is_allied_with_player():
		_hide_swap_prompt()
		return
	var text: String = "[E] Órdenes"
	if can_swap_with(_player_in_trade):
		text += "   [Tab] Intercambiar: %s" % _weapon.weapon_name
	prompt_label.text = text
	# Un ligero "parpadeo" ayuda a verlo; se actualiza cada frame en caliente.
	prompt_label.visible = true


func _hide_swap_prompt() -> void:
	if prompt_label:
		prompt_label.visible = false


## ── Menú de órdenes [E] ──────────────────────────────────────────────────
## ¿Hay un menú de órdenes de aliado abierto (para no abrirlo dos veces)?
func _is_command_menu_open() -> bool:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	return hud != null and hud.has_method("is_npc_command_menu_open") \
			and bool(hud.call("is_npc_command_menu_open"))


func _open_command_menu(_player: Player) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("open_npc_command_menu"):
		return
	hud.call("open_npc_command_menu", self)


## ¿El jugador está apuntando (crosshair) a este NPC? Raycast desde su cámara.
func is_player_looking_at(player: Player) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var is_third: bool = bool(player.get("is_third_person"))
	var active_cam: Camera3D = player.get("third_person_camera") if is_third else player.get("camera")
	if active_cam == null or not is_instance_valid(active_cam):
		return false
	var from: Vector3 = active_cam.global_position
	var to: Vector3 = from + (-active_cam.global_transform.basis.z) * 60.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2 | 4  # cuerpo de NPCs (2) y headshots (4)
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude.append(player.get_rid())
	query.exclude = exclude
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Node = hit.get("collider") as Node
	return _is_related_to_self(collider)


## ¿El collider golpeado pertenece a este NPC (cuerpo o Area3D hijo)?
func _is_related_to_self(collider: Node) -> bool:
	if collider == null:
		return false
	var n: Node = collider
	while n != null:
		if n == self:
			return true
		n = n.get_parent()
	return false


## Aplica una orden del menú [E] a este aliado (solo Tiradores).
##  - "libre" : PATROL + agresivo (deambula y asalta)
##  - "guard" : GUARD + agresivo (defiende el puesto y asalta)
##  - "follow": seguir al jugador + agresivo
func apply_command_mode(mode: String) -> void:
	match mode:
		"guard":
			spawn_mode = SpawnMode.GUARD
			aggressive_enabled = true
			set_following(false)
		"follow":
			spawn_mode = SpawnMode.PATROL
			aggressive_enabled = true
			set_following(true)
		_:  # "libre"
			spawn_mode = SpawnMode.PATROL
			aggressive_enabled = true
			set_following(false)
	_wander_timer = randf_range(0.25, 0.75)


## ── Percepción ───────────────────────────────────────────────────────────
## Mantiene un target breve entre comprobaciones para reducir escaneos/raycasts
## cuando el nivel tiene muchas oleadas de soldados.
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


## La visión se actualiza por intervalo; la memoria se conserva por separado
## para evitar persecución omnisciente tras perder la línea de visión.
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


## Compatibilidad privada para herramientas/pruebas existentes.
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
	# estados) y, en modo agresivo, corre a su posición (rush al cadáver).
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
	_push_destination = Vector3.INF


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
	var safe_destination: Vector3 = global_position + away * maxf(_config().grenade_safety_radius, 4.0)
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
	# PUSH ON RELOAD (agresivo con cargador sano): avanzar unos metros hacia
	# la última posición en vez de la búsqueda completa.
	if _try_push_on_reload(delta):
		return
	_run_intent = &"persiguiendo"
	_navigate_to(_last_known_position, delta)


## Push on reload: si el enemigo se acaba de perder de vista y nuestro
## cargador está sano, avanzar hasta push_distance metros hacia su última
## posición (castiga al que recarga en campo abierto). Devuelve true si empuja.
func _try_push_on_reload(delta: float) -> bool:
	if not push_on_reload_enabled or not aggressive_enabled:
		return false
	var now_msec: int = Time.get_ticks_msec()
	var since_seen_sec: float = float(now_msec - _last_known_time_msec) / 1000.0
	# Ventana de gracia + el tiempo que tarda el avance de push_distance.
	if since_seen_sec > push_lost_grace + push_distance / maxf(movement_speed, 0.1):
		_push_destination = Vector3.INF
		return false
	# Solo con el cargador sano.
	if _weapon == null or not is_instance_valid(_weapon) or _weapon.clip_size <= 0:
		return false
	if _weapon.ammo_in_mag < int(ceil(_weapon.clip_size * push_on_reload_mag_fraction)):
		return false
	# Destino del push: avanzar hacia la última posición sin pasarse.
	if not _push_destination.is_finite():
		var to_memory: Vector3 = _last_known_position - _safe_position_of(self)
		to_memory.y = 0.0
		if to_memory.length_squared() < 0.01:
			return false
		_push_destination = _safe_position_of(self) \
				+ to_memory.normalized() * minf(push_distance, to_memory.length())
	if _safe_position_of(self).distance_to(_push_destination) <= stop_distance:
		_push_destination = Vector3.INF
		return false
	_run_intent = &"apurarse"
	_navigate_to(_push_destination, delta)
	return true


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


func _has_line_of_sight(target: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 1.5
	var to: Vector3 = target.global_position + Vector3.UP * 0.9
	# Fuego amigo OFF (global): los aliados no bloquean la línea de visión ni el
	# disparo. Se salta todo cuerpo no-hostil y solo se detienen paredes o
	# enemigos. Excluimos nuestro propio cuerpo (RID) y los aliados iterados.
	var exclude: Array[RID] = [get_rid()]
	for _i in range(8):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return false
		var node: Node = result.get("collider") as Node
		# ¿Es el objetivo? → línea de visión clara.
		var walk: Node = node
		while walk != null:
			if walk == target:
				return true
			walk = walk.get_parent()
		# ¿Es un body NO hostil (aliado)? → atravesar y seguir.
		var body: Node3D = _resolve_body_node(node) as Node3D
		if body != null and body.has_method("take_damage") and not _is_hostile(body):
			var body_rid: RID = _body_rid(body)
			if body_rid.is_valid():
				exclude.append(body_rid)
			continue
		# Pared u obstáculo → sin línea de visión.
		return false
	return false


## Resuelve el CharacterBody/body raíz desde un collider (CollisionShape3D, etc).
func _resolve_body_node(node: Node) -> Node:
	var current: Node = node
	while current is CollisionShape3D and current.get_parent():
		current = current.get_parent()
	return current


func _body_rid(body: Node) -> RID:
	if body is CollisionObject3D:
		return (body as CollisionObject3D).get_rid()
	return RID()


## ── Agresivo (modo ASSAULT) ──────────────────────────────────────────────
## Avanza disparando hasta agotar un umbral de cargador (con suelo de balas y
## metros), retrocede si el enemigo se acerca demasiado y corre al cadáver del
## enemigo que mata.
func _engage_aggressive(target: Node3D, delta: float) -> void:
	var horizontal: Vector3 = target.global_position - global_position
	horizontal.y = 0.0
	var target_distance: float = horizontal.length()

	# Reiniciar contadores al cambiar de objetivo.
	if _memory_target != target or not _agg_active:
		_agg_active = true
		_agg_start_dist = target_distance
		_end_retreat()

	# Retroceso en curso: alejarse disparando (kiting) hasta salir de la banda
	# de histéresis, o abortar por atasco y plantarse a pelear.
	if _retreat_active:
		_retreat_from(target, horizontal, delta)
		if _retreat_active \
				and target_distance >= aggressive_back_off_distance * retreat_hysteresis:
			_end_retreat()
		return

	# Enemigo demasiado cerca → retroceso con kiting anti-atasco (elige huida
	# directa, esquiva lateral o plantarse si no hay escape). Tras abortar un
	# retroceso atascado se queda plantado peleando unos segundos.
	if target_distance < aggressive_back_off_distance:
		if Time.get_ticks_msec() < _no_retreat_until_msec:
			_stand_and_fight(target, horizontal, delta)
		else:
			_start_retreat(-horizontal)
			_retreat_from(target, horizontal, delta)
		return

	# Enemigo muy cerca y con melee disponible: defensa cuerpo a cuerpo.
	if target_distance <= attack_range + 0.3 and _should_melee(target):
		_face_direction(horizontal, delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_try_melee(target)
		return

	var ammo: int = _weapon.ammo_in_mag if _weapon != null and is_instance_valid(_weapon) else 0
	var stop_mag: int = _agg_stop_mag()
	var progress: float = maxf(_agg_start_dist - target_distance, 0.0)
	var mag_rule_hit: bool = ammo <= stop_mag
	var metres_rule_hit: bool = progress >= aggressive_min_advance_metres
	var should_advance: bool = target_distance > aggressive_stop_distance \
			and ammo > 0 and not (mag_rule_hit and metres_rule_hit)

	if should_advance:
		# Avanzar mientras dispara.
		_run_intent = &"persiguiendo"
		_navigate_to(target.global_position, delta)
		_hold_and_fire(target, delta)
		return

	# En distancia útil o cargador bajo: encarar y disparar desde aquí, con
	# strafe lento de lado mientras dispara (no correr).
	_face_direction(horizontal, delta)
	if not _combat_strafe(horizontal, delta):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
	_hold_and_fire(target, delta)


## ── Strafe de combate ───────────────────────────────────────────────────
## Caminar lento de lado mientras dispara parado (nunca correr). Cambia de
## lado cada combat_strafe_interval; si hay pared a un lado prueba el otro y
## si ambos están bloqueados se queda quieto disparando.
func _combat_strafe(to_target: Vector3, delta: float) -> bool:
	if not combat_strafe_enabled:
		return false
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = combat_strafe_interval * _config().effective_strafe_interval_scale() \
				* randf_range(0.8, 1.2)
		_strafe_side = -_strafe_side
	var dir: Vector3 = _pick_strafe_dir(to_target)
	if dir.is_zero_approx():
		return false
	var speed: float = movement_speed * combat_strafe_speed_mult
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
	return true


## Dirección de strafe de este frame (perpendicular al enemigo, en el lado
## activo). Si el lado está bloqueado por pared, invierte; si ambos lo están,
## devuelve Vector3.ZERO. Parte determinista (testable sin física).
func _pick_strafe_dir(to_target: Vector3) -> Vector3:
	var side: Vector3 = to_target.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		return Vector3.ZERO
	side = side.normalized() * float(_strafe_side)
	if _retreat_dir_clear(side):
		return side
	# Lado bloqueado por pared: probar el opuesto.
	_strafe_side = -_strafe_side
	var other: Vector3 = -side
	if _retreat_dir_clear(other):
		return other
	return Vector3.ZERO


## Nº de balas del cargador por debajo del cual el agresivo deja de avanzar.
func _agg_stop_mag() -> int:
	if _weapon == null or not is_instance_valid(_weapon) or _weapon.clip_size <= 0:
		return 0
	var half: int = int(ceil(_weapon.clip_size * aggressive_stop_mag_fraction))
	return clampi(maxi(half, aggressive_min_mag_bullets), 1, _weapon.clip_size)


## Un enemigo que habíamos marcado como objetivo murió. Si fuimos nosotros
## (killer_id propio), agendamos correr a su posición.
func _on_killed_target_died(enemy: Node, killer_id: int) -> void:
	if is_dead:
		return
	# Victoria propia (máquina de estados: GANO_COMBATE).
	if killer_id == get_instance_id():
		_victory_msec = Time.get_ticks_msec()
	if not aggressive_enabled:
		return
	var enemy_node: Node3D = enemy as Node3D
	if enemy_node == null or not enemy_node.is_inside_tree():
		return
	if killer_id != get_instance_id():
		return
	_corpse_rush_position = enemy_node.global_position
	_corpse_rush_timer = 0.0


## Corre a la posición del último cadáver. Se aborta si entra en combate (ya
## garantizado por la prioridad del schedule), si llega, o si la ruta no existe
## o se agota el tiempo (posición inalcanzable).
func _rush_to_corpse(delta: float) -> void:
	_corpse_rush_timer += delta
	if _corpse_rush_timer > corpse_rush_timeout:
		_corpse_rush_position = Vector3.INF
		_idle_behavior(delta)
		return
	var to_corpse: Vector3 = _corpse_rush_position - global_position
	to_corpse.y = 0.0
	if to_corpse.length() <= stop_distance:
		_corpse_rush_position = Vector3.INF
		_idle_behavior(delta)
		return
	if not _has_path_to(_corpse_rush_position):
		_corpse_rush_position = Vector3.INF
		_idle_behavior(delta)
		return
	_navigate_to(_corpse_rush_position, delta)


func _has_path_to(dest: Vector3) -> bool:
	var map: RID = navigation_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return true  # Nav no sincronizada aún: asumir accesible.
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, global_position, dest, true)
	return path.size() >= 2


## ── Comportamiento ──────────────────────────────────────────────────────
func _engage_target(target: Node3D, delta: float) -> void:
	if aggressive_enabled:
		_engage_aggressive(target, delta)
		return

	var horizontal_to_target: Vector3 = target.global_position - global_position
	horizontal_to_target.y = 0.0
	var target_distance: float = horizontal_to_target.length()

	if spawn_mode == SpawnMode.GUARD:
		var dist_to_post: float = global_position.distance_to(_spawn_position)
		if dist_to_post > guard_radius:
			_navigate_to(_spawn_position, delta)
			return

	# Enemigo MUY cerca (dentro del alcance melee): el tirador se defiende con su
	# golpe cuerpo a cuerpo (más débil que el de un NPC especializado en melee)
	# en vez de retroceder o disparar a quemarropa.
	if target_distance <= attack_range + 0.3 and _should_melee(target):
		_face_direction(horizontal_to_target, delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_try_melee(target)
		return

	var engage := _get_engage_range()
	if target_distance > engage.y:
		# Fuera de alcance del arma. Pasivo (passive_holds_ground): mantener la
		# posición y esperar a que el enemigo entre en rango — no avanzar ni
		# perseguir. Si no, acercarse (comportamiento antiguo).
		if passive_holds_ground:
			_face_direction(horizontal_to_target, delta)
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
		else:
			_run_intent = &"persiguiendo"
			_navigate_to(target.global_position, delta)
		return
	if target_distance < engage.x * 0.55:
		# Demasiado cerca para el arma: retroceder con kiting anti-atasco
		# (huida directa, esquiva lateral o plantarse si no hay escape).
		if not _retreat_active:
			if Time.get_ticks_msec() >= _no_retreat_until_msec:
				_start_retreat(-horizontal_to_target)
		if _retreat_active:
			_retreat_from(target, horizontal_to_target, delta)
			if _retreat_active and target_distance >= engage.x:
				_end_retreat()
			return
		_stand_and_fight(target, horizontal_to_target, delta)
		return
	# En distancia útil: detenerse, mirar y disparar (con strafe lento).
	_face_direction(horizontal_to_target, delta)
	if not _combat_strafe(horizontal_to_target, delta):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
	_hold_and_fire(target, delta)


func _hold_and_fire(target: Node3D, delta: float) -> void:
	# Sin línea de visión: acercarse un poco para poder disparar (peek). Los
	# tiradores pasivos (passive_holds_ground) no persiguen: mantienen la
	# posición y esperan a recuperar la línea de visión.
	if not _has_line_of_sight(target):
		if aggressive_enabled or not passive_holds_ground:
			_run_intent = &"persiguiendo"
			_navigate_to(target.global_position, delta)
		return
	_try_fire_in_place(target, delta)


## Dispara al objetivo SIN moverse del sitio: temporizador de reacción, línea
## de visión, fuego amigo, granadas, melee a quemarropa y disparo. Lo usan el
## combate parado (_hold_and_fire), el plantarse a pelear (_stand_and_fight)
## y el retroceso disparando (_retreat_from).
func _try_fire_in_place(target: Node3D, delta: float) -> void:
	if _reaction_timer > 0.0:
		_reaction_timer = maxf(0.0, _reaction_timer - delta)
		return
	# Ver al enemigo no implica poder disparar: un aliado en la trayectoria
	# bloquea el fuego y fuerza una reevaluación del ángulo en el siguiente tick.
	if not _has_line_of_sight(target):
		return
	if _has_friendly_fire_risk(target):
		return
	_try_throw_grenade(target)
	if _should_melee(target):
		_try_melee(target)
		return
	_fire_weapon_at(target)


func _should_melee(target: Node3D) -> bool:
	if not _config().melee_fallback_enabled:
		return false
	if _safe_position_of(target).distance_to(_safe_position_of(self)) <= attack_range + 0.3:
		return true
	if _weapon == null or not is_instance_valid(_weapon):
		return true
	return false


func _try_melee(target: Node3D) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	if target.has_method("take_damage"):
		# Dificultad global: escala el daño que hacen los NPCs.
		var damage: float = melee_damage * _difficulty_damage_multiplier()
		target.call("take_damage", damage, "Torso", get_instance_id(), _safe_position_of(self))


## Posición global a prueba de árbol: en juego es global_position; fuera del
## árbol (tests unitarios sin SceneTree montado) devuelve la local, que sin
## padre equivale a la global, evitando los errores de get_global_transform.
func _safe_position_of(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


## Rango de combate preferido: desde la config o el perfil AI del arma.
func _get_engage_range() -> Vector2:
	var profile_min: float = 2.0
	var profile_max: float = maxf(vision_range * 0.85, 5.0)
	if _weapon != null and is_instance_valid(_weapon) and _weapon.ai_profile != null:
		var p: WeaponAIProfile = _weapon.ai_profile
		profile_min = p.preferred_range_min if p.preferred_range_min > 0.0 else 2.0
		if p.preferred_range_max < 999.0:
			profile_max = minf(p.preferred_range_max, vision_range)
	var cfg := _config()
	if cfg.custom_engage_range_min >= 0.0:
		profile_min = cfg.custom_engage_range_min
	if cfg.custom_engage_range_max >= 0.0:
		profile_max = minf(cfg.custom_engage_range_max, vision_range)
	# Personalidad (EN VIVO): escala la banda de combate preferida. El máximo
	# nunca supera el rango de visión.
	var personality_scale: float = cfg.effective_range_scale()
	profile_min *= personality_scale
	profile_max = minf(profile_max * personality_scale, vision_range)
	return Vector2(minf(profile_min, profile_max), maxf(profile_min, profile_max))


## ── Retroceso (kiting) con anti-atasco ──────────────────────────────────
## Inicia un episodio de retroceso eligiendo la dirección de escape (huida
## directa, esquiva lateral o ninguna si todo está bloqueado).
func _start_retreat(away: Vector3) -> void:
	_retreat_active = true
	_retreat_timer = 0.0
	_retreat_dir = _pick_retreat_dir(away)


## Termina el episodio de retroceso en curso (si lo hay).
func _end_retreat() -> void:
	_retreat_active = false
	_retreat_timer = 0.0
	_retreat_dir = Vector3.ZERO


## ¿Hay pared o geometría bloqueando esta dirección de huida? Otros
## personajes (NPCs, jugador) no bloquean: se apartan solos o están al otro
## lado. Solo geometría, props y muros cuentan como obstáculo.
func _retreat_dir_clear(dir: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 0.9
	var to: Vector3 = from + dir * retreat_wall_check_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	var node: Node = hit.get("collider") as Node
	return node is CharacterBody3D


## Elige la dirección de huida: directa si está libre; si está bloqueada,
## esquiva lateral (strafe) por el lado libre; si todo está bloqueado,
## devuelve Vector3.ZERO (sin escape: el tirador se plantará a pelear).
func _pick_retreat_dir(away: Vector3) -> Vector3:
	var dir: Vector3 = away.normalized()
	if _retreat_dir_clear(dir):
		return dir
	if not retreat_allow_strafe:
		return Vector3.ZERO
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		return Vector3.ZERO
	side = side.normalized()
	if _retreat_dir_clear(side):
		return side
	var other: Vector3 = -side
	if _retreat_dir_clear(other):
		return other
	return Vector3.ZERO


## Retrocede del objetivo (kiting): mira al enemigo mientras se aleja en la
## dirección de escape elegida, disparando si puede. Si se agota el tiempo de
## atasco (retreat_stuck_timeout) aborta y se planta a pelear un rato.
func _retreat_from(target: Node3D, to_target: Vector3, delta: float) -> void:
	_retreat_timer += delta
	if _retreat_timer >= retreat_stuck_timeout:
		# Atasco (pared, esquina o enemigo igual de rápido): plantarse a
		# pelear en vez de seguir retrocediendo para siempre.
		_end_retreat()
		_no_retreat_until_msec = Time.get_ticks_msec() + int(retreat_recover_time * 1000.0)
		_stand_and_fight(target, to_target, delta)
		return
	if _retreat_dir.is_zero_approx():
		# Sin escape (esquina cerrada): pelear desde aquí.
		_stand_and_fight(target, to_target, delta)
		return
	if retreat_fire_while_backing:
		# Kiting: mirar al enemigo mientras se aleja hacia atrás.
		_face_direction(to_target, delta)
	else:
		_face_direction(_retreat_dir, delta)
	velocity.x = _retreat_dir.x * movement_speed
	velocity.z = _retreat_dir.z * movement_speed
	move_and_slide()
	if retreat_fire_while_backing:
		_try_fire_in_place(target, delta)


## Sin huida posible o tras abortar un retroceso: quedarse quieto, encarar al
## enemigo y pelear (melee a quemarropa o disparo con línea de visión).
func _stand_and_fight(target: Node3D, to_target: Vector3, delta: float) -> void:
	_face_direction(to_target, delta)
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	_try_fire_in_place(target, delta)


## ── Máquina de estados visible (derivada del brain táctico) ──────────────
## El brain decide QUÉ HACE el NPC; esto deriva QUÉ ESTÁ PASANDO para la
## animación, la voz y el debug. Prioridad: MUERTO > CORRIENDO > DETECCION >
## EN_COMBATE > GANO_COMBATE > PATRULLANDO > QUIETO.
func _update_npc_state() -> void:
	if is_dead:
		_npc_state.set_state(StoryNpcStateMachine.State.MUERTO, &"muerto")
		return
	# CORRIENDO: huida por retroceso/kiting o peligro, o intención publicada
	# por un comportamiento del frame ("huida"/"apurarse"/"persiguiendo").
	if _retreat_active:
		_npc_state.set_state(StoryNpcStateMachine.State.CORRIENDO, &"huida")
		return
	if _corpse_rush_position.is_finite():
		_npc_state.set_state(StoryNpcStateMachine.State.CORRIENDO, &"apurarse")
		return
	if _run_intent != &"":
		_npc_state.set_state(StoryNpcStateMachine.State.CORRIENDO, _run_intent)
		return
	var now_msec: int = Time.get_ticks_msec()
	var schedule: StoryNPCTacticalBrain.Schedule = _tactical_brain.current_schedule
	# DETECCIÓN: ventana inicial tras adquirir un objetivo nuevo.
	if _target_first_seen_msec > 0 \
			and now_msec - _target_first_seen_msec <= int(state_detection_duration * 1000.0) \
			and schedule != StoryNPCTacticalBrain.Schedule.SEEK_COVER:
		var detection_sub: StringName = &"pidiendo_ayuda" if _shouted_for_target != null else &"confirmado"
		_npc_state.set_state(StoryNpcStateMachine.State.DETECCION, detection_sub)
		return
	# EN COMBATE.
	match schedule:
		StoryNPCTacticalBrain.Schedule.ATTACK_RANGED, StoryNPCTacticalBrain.Schedule.ATTACK_MELEE:
			_npc_state.set_state(StoryNpcStateMachine.State.EN_COMBATE, &"disparando")
			return
		StoryNPCTacticalBrain.Schedule.SEEK_COVER:
			_npc_state.set_state(StoryNpcStateMachine.State.EN_COMBATE, &"en_cobertura")
			return
		StoryNPCTacticalBrain.Schedule.RELOAD:
			_npc_state.set_state(StoryNpcStateMachine.State.EN_COMBATE, &"recargando")
			return
		_:
			pass
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
## el bus de estímulos. Los aliados que lo oigan decidirán si acuden
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


## ── Seguir al jugador (campaña, [Tab]) ──────────────────────────────────
## Activa/desactiva el modo escolta. Lo llama el controlador de nivel cuando
## el jugador pulsa [Tab] en una misión de Historia (solo NPCs aliados).
func set_following(value: bool) -> void:
	if following == value:
		return
	following = value
	if following:
		_follow_leader = get_tree().get_first_node_in_group(&"player")
		_release_cover()
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
	# La distancia de formación es configurable (follow_distance) para que el
	# aliado mantenga una separación cómoda en vez de pegarse al jugador.
	var behind: Vector3 = leader.global_transform.basis.z
	behind.y = 0.0
	if behind.length_squared() < 0.0001:
		behind = Vector3.BACK
	behind = behind.normalized()
	var side: Vector3 = behind.cross(Vector3.UP).normalized()
	var target_pos: Vector3 = leader.global_position + behind * follow_distance + side * _follow_slot
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
		# Guardia en el puesto: patrulla acotada DENTRO del radio de guardia y
		# vuelve al puesto si se aleja demasiado.
		var dist_to_post: float = global_position.distance_to(_spawn_position)
		if dist_to_post > guard_radius * 0.5:
			_navigate_to(_spawn_position, delta)
			if global_position.distance_to(_spawn_position) < stop_distance:
				velocity.x = 0.0
				velocity.z = 0.0
				move_and_slide()
			return
		if not _has_wander_dest:
			_wander_timer = maxf(0.0, _wander_timer - delta)
			if _wander_timer <= 0.0:
				_pick_guard_wander_dest()
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
		_navigate_to(_wander_dest, delta)
		return
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


## PATROL: exploración real SIN límite de radio (el flag aggressive_enabled no
## cambia el ocioso). Se elige un punto aleatorio del navmesh (respetando caminos
## y obstáculos); el diseño debe bloquear con paredes invisibles/barreras las
## zonas a las que no se deba ir.
func _pick_wander_dest() -> void:
	var dest: Vector3 = _pick_exploration_dest()
	if not dest.is_finite():
		dest = _spawn_position + Vector3(randf_range(-10.0, 10.0), 0.0, randf_range(-10.0, 10.0))
	_wander_dest = dest
	_wander_last_dist = INF
	_wander_stuck_frames = 0
	_has_wander_dest = true


## GUARD: destino acotado alrededor del puesto (patrulla de guardia).
func _pick_guard_wander_dest() -> void:
	var angle: float = randf() * TAU
	var radius: float = randf() * minf(guard_radius, 8.0)
	_wander_dest = _spawn_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_wander_last_dist = INF
	_wander_stuck_frames = 0
	_has_wander_dest = true


## Muestra un destino aleatorio en el navmesh alcanzable y lo valida con ruta.
func _pick_exploration_dest() -> Vector3:
	var map: RID = navigation_agent.get_navigation_map()
	var from: Vector3 = global_position
	for _i in range(8):
		var angle: float = randf() * TAU
		var radius: float = randf_range(maxf(wander_radius, 10.0), 80.0)
		var sample: Vector3 = from + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var dest: Vector3 = NavigationServer3D.map_get_closest_point(map, sample)
		if not dest.is_finite():
			continue
		if dest.distance_to(from) < 5.0:
			continue
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, dest, true)
		if path.size() >= 2:
			return dest
	return Vector3.INF


func _navigate_to(destination: Vector3, delta: float) -> void:
	var direction: Vector3 = _get_navigation_direction(destination)
	velocity.x = direction.x * movement_speed
	velocity.z = direction.z * movement_speed
	_face_direction(direction, delta)
	move_and_slide()


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


## ── Disparo ─────────────────────────────────────────────────────────────
## Rellena automáticamente el arma si el soldado se quedó SIN munición total
## (cargador + reserva = 0). Devuelve true si se rellenó. El gunner NUNCA se
## queda sin balas: al llegar a 0 vuelve a su default (el total con el que
## partió: cargador lleno primero y el resto a reserva) sin depender de
## recargas externas. Si no se registró default, usa el completo del arma.
## Gestiona una recarga como schedule: bajo presión intenta primero una
## cobertura disponible; sin cobertura conserva el fallback de recarga existente.
func _reload_or_seek_cover(target: Node3D, delta: float) -> void:
	if _weapon == null or not is_instance_valid(_weapon):
		_idle_behavior(delta)
		return
	if _should_seek_cover():
		if target != null:
			_seek_cover(target, delta)
			return
	if not _weapon.is_reloading and _weapon.ammo_in_mag <= 0 and _weapon.reserve_ammo > 0:
		_weapon.start_reload()
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()


func _refill_if_out_of_ammo() -> bool:
	if _weapon == null or not is_instance_valid(_weapon):
		return false
	if _weapon.ammo_in_mag > 0 or _weapon.reserve_ammo > 0:
		return false
	var total: int = _default_total_ammo
	if total <= 0:
		total = _weapon.clip_size + _weapon.max_ammo
	var mag: int = mini(_weapon.clip_size, total)
	var reserve: int = maxi(0, total - mag)
	_weapon.ammo_in_mag = mag
	_weapon.reserve_ammo = reserve
	_weapon.is_reloading = false
	_weapon.weapon_ammo_changed.emit(mag, reserve)
	return true


func _fire_weapon_at(target: Node3D) -> void:
	if _weapon == null or not is_instance_valid(_weapon):
		return
	if not _weapon.can_fire():
		# Munición TOTAL agotada (cargador + reserva = 0): rellenar al default
		# automáticamente. El gunner nunca se queda sin balas.
		if _refill_if_out_of_ammo():
			return
		# Cargador vacío con reserva → recargar (sin cambiar de arma).
		if _weapon.ammo_in_mag <= 0 and _weapon.reserve_ammo > 0 and not _weapon.is_reloading:
			_weapon.start_reload()
		return
	# Dificultad global: intervalo mínimo entre disparos del NPC (0 en NORMAL:
	# no restringe nada, así el comportamiento base no cambia).
	var difficulty: StoryDifficulty = StoryDifficulty.get_manager()
	if difficulty != null:
		var min_interval_msec: int = int(difficulty.fire_extra_interval() * 1000.0)
		if min_interval_msec > 0 \
				and Time.get_ticks_msec() - _last_npc_fire_msec < min_interval_msec:
			return
		_last_npc_fire_msec = Time.get_ticks_msec()

	var categoria: String = _weapon.categoria_municion
	var target_aim: Vector3 = target.global_position + Vector3.UP * 0.9
	var is_projectile: bool = categoria in ["arrojadiza", "explosiva", "plasma"]

	if is_projectile:
		var launch_pos: Vector3 = global_position + Vector3.UP * 1.4
		var aim_dir: Vector3 = (target_aim - launch_pos).normalized()
		aim_dir = _apply_aim_error_dir(aim_dir, _distance_to(target))
		_weapon.set_shoot_override(launch_pos, aim_dir)
		_weapon.fire()
		return

	if categoria == "cuerpo_a_cuerpo":
		_weapon.fire()  # el arma maneja su propio Area3D cuerpo a cuerpo
		return

	# Hit-scan: apuntar al torso del objetivo con la puntería del soldado.
	var aim_pos: Vector3 = target_aim + _compute_aim_error(target_aim)
	_weapon.override_hitscan_target(aim_pos)
	var hits: Array = _weapon.fire()
	_apply_hits_to_target(hits)


func _apply_hits_to_target(hits: Array) -> void:
	var killer_id: int = get_instance_id()
	for hit: Dictionary in hits:
		var target_node: Node = hit.get("collider")
		if target_node == null:
			continue
		if target_node is Area3D:
			var parent: Node = target_node.get_parent()
			while parent:
				if parent.has_method("take_damage"):
					target_node = parent
					break
				parent = parent.get_parent()
		if not target_node.has_method("take_damage"):
			continue
		# Fuego amigo: no herir a aliados ni al propio jugador aliado.
		if not _is_shot_hostile(target_node):
			continue
		var dmg: float = hit.get("damage_vs_npc", 0.0)
		if target_node is Player:
			dmg = hit.get("damage_vs_player", 0.0)
		# Dificultad global: escala el daño que hacen los NPCs.
		target_node.take_damage(dmg * _difficulty_damage_multiplier(), "Torso", killer_id, global_position)


func _is_shot_hostile(node: Node) -> bool:
	if node is Player:
		return StoryFactionSystem.are_hostile(faction_id, StoryFactionSystem.PLAYER_FACTION)
	var other_faction: int = int(node.get("faction_id")) if "faction_id" in node else -1
	return StoryFactionSystem.are_hostile(faction_id, other_faction)


## Fuego amigo DESACTIVADO (decisión de diseño global): los aliados no bloquean
## el disparo. Las balas atraviesan a los aliados (ver projectile_base / weapon)
## y no les hacen daño, así que esta comprobación siempre devuelve false.
## Se conserva la firma por compatibilidad con el cerebro táctico.
func _has_friendly_fire_risk(_target: Node3D) -> bool:
	return false


func _resolve_damageable_node(node: Node) -> Node:
	var current: Node = node
	while current != null:
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null


func _distance_to(target: Node3D) -> float:
	return global_position.distance_to(target.global_position)


## Desviación de puntería: se degrada con la distancia y la precisión.
func _compute_aim_error(aim_pos: Vector3) -> Vector3:
	var acc: float = _effective_accuracy()
	var dist: float = global_position.distance_to(aim_pos)
	var miss: float = (1.0 - acc) * dist * 0.25
	return Vector3(randf_range(-miss, miss), randf_range(-miss, miss), 0.0)


func _apply_aim_error_dir(aim_dir: Vector3, dist: float) -> Vector3:
	var acc: float = _effective_accuracy()
	var miss: float = (1.0 - acc) * dist * 0.02
	return (aim_dir + Vector3(randf_range(-miss, miss), randf_range(-miss, miss), 0.0)).normalized()


## Precisión efectiva: la del config, más el ajuste de dificultad global.
func _effective_accuracy() -> float:
	var manager: StoryDifficulty = StoryDifficulty.get_manager()
	var delta: float = manager.accuracy_delta() if manager != null else 0.0
	return clampf(_config().fire_accuracy + delta, 0.01, 1.0)


## Multiplicador de daño que hace este NPC (dificultad global; 1.0 sin manager).
func _difficulty_damage_multiplier() -> float:
	var manager: StoryDifficulty = StoryDifficulty.get_manager()
	return manager.damage_dealt_multiplier() if manager != null else 1.0


## ── Granadas (sin cambiar de arma) ──────────────────────────────────────
func _try_throw_grenade(target: Node3D) -> void:
	var decision: String = _evaluate_grenade(target)
	_last_grenade_decision = decision
	if decision != "permitida":
		return
	_throw_grenade_at(target.global_position + Vector3.UP * 0.5, false)


## Lanza una granada contra una posición de impacto concreta (la del objetivo
## visible, o la última posición conocida en la granada anti-cobertura).
func _throw_grenade_at(impact_position: Vector3, anti_cover: bool) -> void:
	var cfg: TiradorConfig = _config()
	var weapon_scene: PackedScene = ResourceLoader.load(
		WEAPON_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene
	if weapon_scene == null:
		_last_grenade_decision = "rechazada: escena temporal no disponible"
		return
	var grenade: Weapon = weapon_scene.instantiate() as Weapon
	weapon_holder.add_child(grenade)
	grenade.initialize_from_name(cfg.grenade_weapon_name)
	grenade.set_equip_locked(false)
	grenade.ammo_in_mag = 1
	grenade.reserve_ammo = 0
	var launch_pos: Vector3 = global_position + Vector3.UP * 1.5
	var aim_dir: Vector3 = (impact_position - launch_pos).normalized()
	grenade.set_shoot_override(launch_pos, aim_dir)
	grenade.fire()  # el proyectil ya se instancia en el árbol; el arma temporal es libre
	grenade.queue_free()
	_grenade_timer = cfg.grenade_cooldown
	var stimulus_bus: Node = get_node_or_null("/root/StoryNpcStimulusBus")
	if stimulus_bus != null:
		stimulus_bus.emit_stimulus(
			StoryNpcStimulusBus.StimulusType.EXPLOSIVE_DANGER,
			impact_position,
			self,
			1.0,
			cfg.grenade_safety_radius,
			1.5
		)
	_last_grenade_decision = "lanzada anti-cobertura" if anti_cover else "lanzada"


## Granada ANTI-COBERTURA: el enemigo acaba de esconderse y su última posición
## conocida está junto a un CoverPoint. Se evalúa cada frame en combate.
func _try_anti_cover_grenade() -> void:
	if not is_inside_tree():
		return
	var impact: Vector3 = _anti_cover_target_position()
	if not impact.is_finite():
		return
	var cfg: TiradorConfig = _config()
	if not _has_cover_point_near(impact, cfg.grenade_anti_cover_near_distance):
		return
	if _has_ally_near_position(impact, cfg.grenade_safety_radius):
		return
	if randf() > cfg.grenade_anti_cover_chance:
		return
	_throw_grenade_at(impact, true)


## Última posición conocida válida como blanco de granada anti-cobertura, o
## INF si no procede (desactivada, sin memoria, demasiado tarde, fuera de
## rango o cooldown activo). Parte determinista (testable).
func _anti_cover_target_position() -> Vector3:
	var cfg: TiradorConfig = _config()
	if not cfg.grenade_anti_cover_enabled or not cfg.can_throw_grenades:
		return Vector3.INF
	if _grenade_timer > 0.0:
		return Vector3.INF
	if not _has_valid_memory():
		return Vector3.INF
	var since_seen_sec: float = float(Time.get_ticks_msec() - _last_known_time_msec) / 1000.0
	if since_seen_sec > cfg.grenade_anti_cover_delay:
		return Vector3.INF
	var dist: float = _safe_position_of(self).distance_to(_last_known_position)
	if dist < cfg.grenade_min_distance or dist > cfg.grenade_max_distance:
		return Vector3.INF
	if dist < cfg.grenade_safety_radius:
		return Vector3.INF
	return _last_known_position


## ¿Hay un CoverPoint a menos de radius de esta posición? (Requiere árbol.)
func _has_cover_point_near(check_position: Vector3, radius: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"cover_points"):
		var cp: Node3D = node as Node3D
		if cp != null and cp.global_position.distance_to(check_position) <= radius:
			return true
	return false


## Explica la decisión de granada para depuración sin crear side effects.
func _evaluate_grenade(target: Node3D) -> String:
	var cfg: TiradorConfig = _config()
	if target == null or not is_instance_valid(target):
		return "rechazada: sin objetivo válido"
	if not cfg.can_throw_grenades:
		return "rechazada: perfil sin granadas"
	if _grenade_timer > 0.0:
		return "rechazada: cooldown activo"
	if cfg.grenade_weapon_name.is_empty():
		return "rechazada: arma de granada vacía"
	var dist: float = global_position.distance_to(target.global_position)
	if dist < cfg.grenade_min_distance or dist > cfg.grenade_max_distance:
		return "rechazada: distancia fuera de rango"
	var impact_position: Vector3 = target.global_position
	if global_position.distance_to(impact_position) < cfg.grenade_safety_radius:
		return "rechazada: impacto demasiado cercano"
	if _has_ally_near_position(impact_position, cfg.grenade_safety_radius):
		return "rechazada: aliado dentro del radio seguro"
	if randf() > cfg.effective_grenade_chance():
		return "rechazada: probabilidad táctica"
	return "permitida"


func _has_ally_near_position(check_position: Vector3, radius: float) -> bool:
	if global_position.distance_to(check_position) <= radius:
		return true
	for node: Node in get_tree().get_nodes_in_group(&"npc"):
		var ally: Node3D = node as Node3D
		if ally == null or ally == self or _is_dead(ally):
			continue
		if not StoryFactionSystem.are_allied(faction_id, int(ally.get("faction_id"))):
			continue
		if ally.global_position.distance_to(check_position) <= radius:
			return true
	return false


## ── Cobertura (compatible con props one_way_low_wall) ───────────────────
func _should_seek_cover() -> bool:
	var cfg := _config()
	if not cfg.can_take_cover or is_dead:
		return false
	if _cover_point != null:
		return true  # ya está cubierto: mantener hasta agotar el tiempo máximo aleatorio
	# Fuego recibido sostenido: la petición la marca _register_incoming_hit.
	if _sustained_fire_cover_request:
		return true
	return (current_health / maxf(max_health, 1.0)) <= cfg.effective_cover_health_threshold()


func _seek_cover(target: Node3D, delta: float) -> void:
	var cfg: TiradorConfig = _config()
	if _cover_point == null or not is_instance_valid(_cover_point):
		_cover_point = _find_cover_point(target)
		if _cover_point == null:
			# Sin cobertura disponible: seguir combatiendo.
			_engage_target(target, delta)
			return
		_cover_point.occupy(self)
		_cover_destination = _cover_point.get_cover_position()
		_cover_last_distance = INF
		_cover_stuck_frames = 0
		# Cobertura conseguida: la petición por fuego sostenido queda servida.
		_sustained_fire_cover_request = false
		_recent_hits_msec.clear()
		# Tiempo MÁXIMO de cobertura aleatorio (se queda entre min y max).
		_cover_timer = randf_range(cfg.cover_max_time_min, cfg.cover_max_time_max)

	var dest: Vector3 = _cover_destination
	var distance: float = global_position.distance_to(dest)
	if distance > stop_distance:
		if distance < _cover_last_distance - 0.05:
			_cover_stuck_frames = 0
		else:
			_cover_stuck_frames += 1
		if _cover_stuck_frames > 90:
			_release_cover()
			_engage_target(target, delta)
			return
		_cover_last_distance = distance
		_run_intent = &"huida"
		_navigate_to(dest, delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		# Revalidar: una cobertura útil debe bloquear la amenaza actual.
		if not _cover_blocks_threat(_cover_point, target.global_position):
			_release_cover()
			_engage_target(target, delta)
			return
		# Girar hacia el enemigo y, si hay línea de visión, disparar (peek).
		var facing: Vector3 = target.global_position - global_position
		facing.y = 0.0
		_face_direction(facing, delta)
		if cfg.cover_fire_while_covering and _has_line_of_sight(target) and not _has_friendly_fire_risk(target):
			_hold_and_fire(target, delta)

	# Mientras está cubierto se cura X% de la vida máxima por segundo
	# (cover_heal_per_second: 0.05 = 5% / segundo), hasta la vida máxima.
	current_health = minf(
		current_health + max_health * cfg.cover_heal_per_second * delta,
		max_health
	)

	_cover_timer = maxf(0.0, _cover_timer - delta)
	# Al agotarse el tiempo máximo aleatorio sale de la cobertura, cure o no.
	if _cover_timer <= 0.0:
		_release_cover()


func _find_cover_point(threat_target: Node3D = null) -> CoverPoint:
	var cfg: TiradorConfig = _config()
	var best: CoverPoint = null
	var best_score: float = INF
	var threat_position: Vector3 = threat_target.global_position if threat_target != null else _last_known_position
	for node: Node in get_tree().get_nodes_in_group(&"cover_points"):
		var cp: CoverPoint = node as CoverPoint
		if cp == null:
			continue
		if not cp.is_available(self):
			continue
		var pos: Vector3 = cp.get_cover_position()
		var dist_self: float = global_position.distance_to(pos)
		if dist_self > cfg.cover_search_radius:
			continue
		var score: float = dist_self - cp.priority * 5.0
		# La cobertura orientada o con un obstáculo real ante la amenaza obtiene
		# preferencia; una expuesta continúa disponible como fallback.
		if threat_position.is_finite():
			if _cover_blocks_threat(cp, threat_position):
				score -= 12.0
			if _cover_faces_threat(cp, threat_position):
				score -= 3.0
		if score < best_score:
			best_score = score
			best = cp
	return best


func _cover_blocks_threat(cover: CoverPoint, threat_position: Vector3) -> bool:
	if cover == null or not is_instance_valid(cover) or not threat_position.is_finite():
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var cover_position: Vector3 = cover.get_cover_position() + Vector3.UP * 1.0
	var from: Vector3 = threat_position + Vector3.UP * 1.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, cover_position)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return false
	var collider: Node = result.get("collider") as Node
	return collider != self


func _cover_faces_threat(cover: CoverPoint, threat_position: Vector3) -> bool:
	var facing: Vector3 = cover.global_transform.basis.z
	facing.y = 0.0
	var toward_threat: Vector3 = threat_position - cover.global_position
	toward_threat.y = 0.0
	if facing.length_squared() < 0.001 or toward_threat.length_squared() < 0.001:
		return false
	return facing.normalized().dot(toward_threat.normalized()) > 0.15


func _release_cover() -> void:
	if _cover_point != null and is_instance_valid(_cover_point):
		_cover_point.release(self)
	_cover_point = null
	_cover_timer = 0.0
	_cover_destination = Vector3.INF
	_cover_last_distance = INF
	_cover_stuck_frames = 0
	# Al salir de cobertura: anular la petición de fuego sostenido y arrancar
	# el delay antes de poder volver a cubrirse por la misma razón.
	_sustained_fire_cover_request = false
	_last_cover_exit_msec = Time.get_ticks_msec()
	_recent_hits_msec.clear()


## Registra un impacto recibido para la regla de cobertura por fuego sostenido:
## tras cover_fire_hit_count impactos en cover_fire_time_window segundos se
## pide buscar cobertura (si no se acaba de salir de una).
func _register_incoming_hit() -> void:
	var cfg: TiradorConfig = _config()
	if not cfg.cover_on_sustained_fire:
		return
	var now_msec: int = Time.get_ticks_msec()
	_recent_hits_msec.append(now_msec)
	var window_msec: int = int(cfg.cover_fire_time_window * 1000.0)
	while not _recent_hits_msec.is_empty() and now_msec - _recent_hits_msec[0] > window_msec:
		_recent_hits_msec.pop_front()
	if _recent_hits_msec.size() >= cfg.cover_fire_hit_count \
			and now_msec - _last_cover_exit_msec >= int(cfg.cover_recover_delay * 1000.0):
		_sustained_fire_cover_request = true


## ── Skins / tintado (idéntico a CuerpoACuerpo) ────────────────────────
func _setup_tint_material() -> void:
	if mesh.material_override is StandardMaterial3D:
		_tint_material = (mesh.material_override as StandardMaterial3D).duplicate()
		_base_albedo = _tint_material.albedo_color
		mesh.material_override = _tint_material
	else:
		_tint_material = null


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
		"grenade_decision": _last_grenade_decision,
		"cover_reserved": _cover_point != null and is_instance_valid(_cover_point),
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
## Mismo patrón que Player y BotBase: el dev menu activa/desactiva el overlay
## globalmente y este NPC responde mostrando vida, arma y schedule de IA.
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
