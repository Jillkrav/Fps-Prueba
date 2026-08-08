# scripts/bot_base.gd
# Base class for all NPCs. Orchestrator de sistemas modulares (Fase 8).
extends CharacterBody3D
class_name BotBase

# ─────────────────────────────────────────
# EXPORTS & CONFIG
# ─────────────────────────────────────────

@export var equipo_id: int = int(Enums.Equipo.ROJO)
@export var nombre_arma: String = "USP"
@export var experiencia: int = int(Enums.Experiencia.MEDIA)
@export var rol: int = int(Roles.Type.ASALTO)

## Modelo visual opcional para el bot (ej: TeddyModel.tscn).
## Si se asigna, se instancia como hijo en _ready().
## Si es null (default), el bot funciona sin modelo visible.
@export var visual_model: PackedScene = null

## ID de skin desde SkinManager (para usar el sistema de skins).
## Si está definida, sobreescribe visual_model cargando la skin
## desde SkinManager automáticamente.
@export var skin_id: String = ""

# ─────────────────────────────────────────
# REFERENCIAS A SISTEMAS MODULARES
# ─────────────────────────────────────────

## Sistema de percepción (FASE 1). ÚNICO escritor de sensor_data.
var perception_sys: PerceptionSystem = null

## Sistema de memoria (FASE 1). ÚNICO escritor de memory_store.
var memory_sys: MemorySystem = null

## Sistema de navegación. Gestiona el NavigationAgent3D.
var navigation_sys: NavigationSystem = null

## Sistema de movimiento (FASE 2). ÚNICO escritor de velocity.
var movement_sys: MovementSystem = null

## Sistema de decisión FSM (FASE 3). ÚNICO escritor de target_entity,
## movement_command y combat_command.
var decision_sys: DecisionSystem = null

## Sistema de combate (FASE 4). ÚNICO escritor de aim_rotation.
var combat_sys: CombatSystem = null

## Sistema de armas (FASE 5). Gestiona selección táctica y perfiles AI.
var weapon_sys: WeaponSystem = null

## Sistema táctico de supervivencia. Evalúa recursos, presión y modo Huir.
var tactical_sys: TacticalUtilitySystem = null

# ── Estado del NPC ────────────────────────
var is_dead: bool = false
var max_health: float = 100.0
var current_health: float = 100.0
var is_invisible: bool = false

# ── Freeze state ──────────────────────────
## El NPC está congelado (no se mueve, no procesa IA).
var is_frozen: bool = false
## Timer interno para descongelar automáticamente.
var _frozen_timer: SceneTreeTimer = null

# (Jump-to-cube variables removed — now handled externally by controllers)

## Compatibilidad para triggers SaltoInicio/SaltoFin. La física real vive en
## MovementSystem, que conserva la propiedad exclusiva de velocity.
func start_authored_jump(finish: SaltoFin) -> bool:
	return movement_sys != null and movement_sys.start_authored_jump(finish)


func finish_authored_jump(finish: SaltoFin, _next_path: NodePath = NodePath()) -> void:
	if movement_sys != null:
		movement_sys.finish_authored_jump(finish)

# ── Core / Objective System ──────────────
var _enemy_core: Node3D = null
var _is_attacking_core: bool = false
var _team_objective: Vector3 = Vector3.ZERO

# ── TeamAI / Order System (FASE 6) ───────
# ── Tactical Role ────────────────────────
var _tactical_role = null

var current_order_type: int = -1
var current_order_name: String = "--"
var current_order_target: Vector3 = Vector3.ZERO

# ── Components ────────────────────────────
var _weapon: Weapon = null
const DROPPED_WEAPON: PackedScene = preload("res://scenes/Compartido/pickups/dropped_weapon.tscn")
const DEBUG_OVERLAY: PackedScene = preload("res://scenes/Multiplayer/objetos/bots/bot_debug_overlay.tscn")
var _debug_overlay: Node3D = null

# ── Visual de modo cobarde ─────────────────
var _coward_light: OmniLight3D = null
var _coward_material_overrides: Dictionary = {}

# ── Pickup system ─────────────────────────
var _pickup_target: Node = null
var _pickup_check_timer: float = 0.0

var _npc_id: int = 0

# ── Turn detection (para animaciones de giro) ──
## Señal: el bot giró un ángulo significativo.
signal turn_detected(angle_degrees: float, direction: int)
## Ángulo de facing en el frame anterior (para calcular delta).
var _last_facing_angle: float = 0.0
## Dirección desde la que recibió el último daño (para hit reaction).
var last_hit_direction: Vector3 = Vector3.ZERO
## Dirección desde la que recibió el golpe mortal (para death anim).
var death_direction: Vector3 = Vector3.ZERO

# ── Crouch state ──
## Indica si el bot está agachado (collision shape reducida).
var is_crouching: bool = false
## Altura original de la cápsula de colisión (para restaurar al levantarse).
var _original_collision_height: float = 0.0

# ── Tick Rate Reducido de IA ─────────────────────
## Cada cuántos frames se ejecuta el pipeline pesado de IA
## (percepción, decisión, combate, armas).
## Valor 3 → IA corre 20 veces/segundo a 60fps.
const AI_TICK_INTERVAL: int = 3

## Contador regresivo de frames para IA.
## Se inicializa con staggering: _npc_id % AI_TICK_INTERVAL
## para que los bots no piensen todos en el mismo frame.
var _ai_tick_counter: int = 0

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var area_vision: Area3D = $AreaVision
@onready var raycast_vision: RayCast3D = $RaycastVision
@onready var head: Node3D = $Head
@onready var _pickup_manager = get_node("/root/PickupManager")
# (ObstacleEvader eliminado en FASE 2 — StuckHandler unificado en MovementSystem)

## Referencia al collision shape (para crouch).
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

## Componente de estado de arma equipada/guardada (Fase 1+4).
@onready var weapon_equip_state: WeaponEquipState = $WeaponEquipState

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func set_runtime_skin(new_skin_id: String) -> void:
	skin_id = new_skin_id
	var old_model: Node = get_node_or_null("VisualModel")
	if old_model:
		old_model.queue_free()
	var skin_mgr: Node = get_node_or_null("/root/SkinManager")
	if skin_mgr == null:
		return
	var skin_data: SkinData = skin_mgr.get_skin(skin_id)
	if skin_data == null or skin_data.model_scene == null:
		return
	var model_instance: Node3D = skin_data.model_scene.instantiate() as Node3D
	if model_instance == null:
		return
	model_instance.name = "VisualModel"
	add_child(model_instance)
	_aplicar_texturas_skin(skin_data, model_instance)
	$MeshInstance3D.hide()
	$Head/HeadMesh.hide()

func _ready() -> void:
	_npc_id = randi() % 9000 + 1000
	# Inicializar contador de tick rate con staggering:
	# cada bot tiene un desfase único según su ID, así no ejecutan
	# IA todos en el mismo frame.
	_ai_tick_counter = _npc_id % AI_TICK_INTERVAL
	add_to_group("npc")
	
	# ── Step-up: configurar CharacterBody3D para movimiento natural ────
	# El factor MÁS importante es el radio de la cápsula (0.65 en escena).
	# El step-up interno de move_and_slide() escala con el radio de la
	# forma de colisión. Radio 0.65 → step máximo ≈ 0.42 unidades.
	# ── Guardar altura original de colisión (para crouch) ──
	if _collision_shape and _collision_shape.shape is CapsuleShape3D:
		_original_collision_height = _collision_shape.shape.height
	
	motion_mode = MotionMode.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(50.0)   # 50° para rampas de hasta ~48°
	floor_block_on_wall = false          # NO bloquearse en paredes — las caras
										 # laterales de rampas CSGBox3D no
										 # deben detener al NPC. El step-up
										 # nativo funciona sin este bloqueo.
	floor_constant_speed = true          # Velocidad constante en pendientes
	floor_stop_on_slope = true           # No deslizarse en pendientes
	max_slides = 8                       # Más iteraciones para mejor transición rampa↔piso
	
	max_health = ConfigManager.get_vida_npc("Enemigo")
	current_health = max_health
	
	# ── Inicializar sistemas modulares ────────────────────────
	perception_sys = PerceptionSystem.new()
	perception_sys.name = "PerceptionSystem"
	add_child(perception_sys)
	
	memory_sys = MemorySystem.new()
	memory_sys.name = "MemorySystem"
	add_child(memory_sys)
	
	navigation_sys = NavigationSystem.new()
	navigation_sys.name = "NavigationSystem"
	add_child(navigation_sys)
	
	movement_sys = MovementSystem.new()
	movement_sys.name = "MovementSystem"
	add_child(movement_sys)
	
	decision_sys = DecisionSystem.new()
	decision_sys.name = "DecisionSystem"
	add_child(decision_sys)
	_add_fsm_states()
	
	# ── BUGFIX: Re-registrar estados FSM ────────────────────────
	# DecisionSystem._ready() ejecutó _register_child_states() antes
	# de que _add_fsm_states() añadiera los estados como hijos.
	# Sin esto, _states queda vacío y el bot NUNCA transiciona
	# a ningún estado (ni roaming, ni combat, ni dispara).
	if decision_sys.has_method("_register_child_states"):
		decision_sys._register_child_states()
		if decision_sys.current_state == null and decision_sys._states.size() > 0:
			decision_sys._change_state(BotState.StateType.ROAMING)
	
	weapon_sys = WeaponSystem.new()
	weapon_sys.name = "WeaponSystem"
	add_child(weapon_sys)
	
	tactical_sys = TacticalUtilitySystem.new()
	tactical_sys.name = "TacticalUtilitySystem"
	add_child(tactical_sys)
	
	combat_sys = CombatSystem.new()
	combat_sys.name = "CombatSystem"
	add_child(combat_sys)
	
	# ── Equipar arma y color (AHORA con weapon_sys disponible) ──
	_equipar_arma()
	_aplicar_color_equipo()
	
	# ── Conectar señales ─────────────────────────────────────
	_connect_decision_signals()
	
	# ── (EVASIÓN unificada en MovementSystem.StuckHandler — FASE 2) ──
	
	# ── Inicializar rol táctico ──
	_tactical_role = TacticalRole.for_npc(self)
	
	# Encontrar core enemigo como objetivo principal
	call_deferred("_find_enemy_core")
	
	# ── Instanciar modelo visual opcional ────────────────
	# Si skin_id está definido, priorizar SkinManager.
	# Si skin_id está vacío, auto-asignar skin según equipo
	# (Fase 3: Sistema de skins por equipo).
	# Sino, si visual_model está asignado, lo añade como hijo.
	# NO modifica el comportamiento del bot.
	# Si es null, el bot funciona igual que antes.
	var model_loaded: bool = false
	if skin_id.is_empty():
		var mgr: Node = get_node_or_null("/root/SkinManager")
		if mgr and mgr.has_method("get_skin_for_team"):
			var team_skin: SkinData = mgr.get_skin_for_team(equipo_id)
			if team_skin and not team_skin.id.is_empty():
				skin_id = team_skin.id
	var skin_mgr = get_node_or_null("/root/SkinManager") if not skin_id.is_empty() else null
	if skin_mgr and is_instance_valid(skin_mgr):
		var skin_data: SkinData = skin_mgr.get_skin(skin_id)
		if skin_data and skin_data.model_scene:
			var model_instance: Node3D = skin_data.model_scene.instantiate() as Node3D
			if model_instance:
				model_instance.name = "VisualModel"
				add_child(model_instance)
				# Aplicar texturas desde SkinData
				_aplicar_texturas_skin(skin_data, model_instance)
				model_loaded = true
				# Ocultar la cápsula placeholder
				if has_node("MeshInstance3D"):
					$MeshInstance3D.hide()
				if has_node("Head/HeadMesh"):
					$Head/HeadMesh.hide()
	
	if not model_loaded and visual_model and visual_model is PackedScene:
		var model_instance: Node = visual_model.instantiate()
		if model_instance:
			model_instance.name = "VisualModel"
			add_child(model_instance)
			# Ocultar la cápsula placeholder (tapaba al modelo)
			if has_node("MeshInstance3D"):
				$MeshInstance3D.hide()
			if has_node("Head/HeadMesh"):
				$Head/HeadMesh.hide()
	
	_setup_debug_overlay()


## Añade los estados de la FSM como hijos del DecisionSystem.
func _add_fsm_states() -> void:
	if decision_sys == null:
		return
	
	var roaming: BotState = load("res://Scripts/Multiplayer/ai/bot_behaviors/state_roaming.gd").new()
	roaming.name = "State_Roaming"
	decision_sys.add_child(roaming)
	
	var hunting: BotState = load("res://Scripts/Multiplayer/ai/bot_behaviors/state_hunting.gd").new()
	hunting.name = "State_Hunting"
	decision_sys.add_child(hunting)
	
	var combat: BotState = load("res://Scripts/Multiplayer/ai/bot_behaviors/state_combat.gd").new()
	combat.name = "State_Combat"
	decision_sys.add_child(combat)
	
	var retreating: BotState = load("res://Scripts/Multiplayer/ai/bot_behaviors/state_retreating.gd").new()
	retreating.name = "State_Retreating"
	decision_sys.add_child(retreating)
	
	var hit: BotState = load("res://Scripts/Multiplayer/ai/bot_behaviors/state_hit.gd").new()
	hit.name = "State_Hit"
	decision_sys.add_child(hit)
	
	var fleeing: BotState = load("res://Scripts/Multiplayer/ai/bot_behaviors/state_fleeing.gd").new()
	fleeing.name = "State_Fleeing"
	decision_sys.add_child(fleeing)
	
	var cover_reload: BotState = load("res://Scripts/Multiplayer/ai/bot_behaviors/state_cover_reload.gd").new()
	cover_reload.name = "State_CoverReload"
	decision_sys.add_child(cover_reload)
	


## Conecta las señales de percepción al DecisionSystem.
func _connect_decision_signals() -> void:
	if not perception_sys or not decision_sys:
		return
	
	if not perception_sys.is_connected("entity_detected", _on_decision_entity_detected):
		perception_sys.connect("entity_detected", _on_decision_entity_detected)
	if not perception_sys.is_connected("entity_lost", _on_decision_entity_lost):
		perception_sys.connect("entity_lost", _on_decision_entity_lost)


## Cuando PerceptionSystem detecta un nuevo enemigo prioritario.
func _on_decision_entity_detected(entity: Node3D, detected_pos: Vector3) -> void:
	if decision_sys:
		decision_sys.target_entity = entity
		decision_sys.focus_point = detected_pos
		decision_sys.notify_see_player(entity)


## Cuando PerceptionSystem pierde de vista al objetivo actual.
func _on_decision_entity_lost(entity: Node3D) -> void:
	if decision_sys:
		if decision_sys.target_entity == entity:
			pass  # MemorySystem maneja el HUNTING state


# _on_evasion_failed() y _pick_target() eliminados en FASE 2 —
# StuckHandler unificado maneja re-ruteo en _force_path_recalculation()


func _physics_process(delta: float) -> void:
	if is_dead or not is_inside_tree():
		return
	
	# ── CONGELADO: no se mueve ni procesa IA ───────────────────
	if is_frozen:
		velocity = Vector3.ZERO
		move_and_slide()
		if navigation_agent:
			navigation_agent.target_position = global_position
		return
	
	# ═══════════════════════════════════════════════════════════
	# TICK RATE REDUCIDO DE IA
	# ═══════════════════════════════════════════════════════════
	# El pipeline se divide en dos frecuencias:
	#
	#   ALTA (cada frame)   → Movimiento, física, post-process
	#   BAJA (cada N frames) → Percepción, decisión, combate, armas
	#
	# El contador _ai_tick_counter se inicializa con un desfase
	# según _npc_id para que los bots no ejecuten IA en el mismo
	# frame (staggering).
	# ═══════════════════════════════════════════════════════════
	
	_ai_tick_counter -= 1
	var ai_tick: bool = _ai_tick_counter <= 0
	
	# ── FASE 1: Percepción y memoria (solo en ai_tick) ─────
	if ai_tick:
		if perception_sys:
			perception_sys.update(delta)
		if memory_sys:
			memory_sys.update(delta)
	
	# ── FASE 1b: Orden de TeamAI (solo en ai_tick) ────
	if ai_tick:
		_update_order_cache()
	
	# ── FASE 2: Proximidad al core enemigo (solo en ai_tick) ─
	if ai_tick:
		_check_core_proximity()
	
	# ── FASE 2c: Necesidades tácticas (solo en ai_tick) ──
	if ai_tick and tactical_sys:
		tactical_sys.update(delta)
	
	# ── FASE 3: Decisión FSM (solo en ai_tick) ────────────
	if ai_tick and decision_sys:
		decision_sys.process(delta)
	
	# ── FASE 4: Movimiento — SIEMPRE (escribe velocity) ──
	if movement_sys:
		movement_sys.process(delta)
	
	# ── FASE 4b: (Evasión unificada en MovementSystem.StuckHandler — FASE 2) ──
	
	# ── FASE 5: Combate (solo en ai_tick) ───────────────
	if ai_tick and combat_sys:
		combat_sys.process(delta)
	
	# ── FASE 5b: Armas (solo en ai_tick) ───────────────
	if ai_tick and weapon_sys:
		weapon_sys.process(delta)
	
	# ── FASE 6: Física — SIEMPRE ──────────────────────
	move_and_slide()
	
	# ── FASE 6b: (Post-evasIón unificada en StuckHandler.post_process — FASE 2) ──
	
	# ── FASE 7: Post-movimiento — SIEMPRE ──────────────
	if movement_sys:
		movement_sys.post_process(delta)
	
	# ── FASE 7b: Crouch state — SIEMPRE ─────────────
	_update_crouch_state()
	
	# ── FASE 8: Turn detection — SIEMPRE ─────────────
	_detect_turn()
	
	# ── Reset contador de tick ──────────────────────────
	if ai_tick:
		_ai_tick_counter = AI_TICK_INTERVAL


# ─────────────────────────────────────────
# SISTEMA DE PICKUPS
# ─────────────────────────────────────────

## Busca pickups cercanos y navega hacia el más útil.
func _check_for_pickups(delta: float) -> bool:
	_pickup_check_timer -= delta
	if _pickup_check_timer > 0.0:
		if _pickup_target and is_instance_valid(_pickup_target) and _pickup_target.is_inside_tree():
			_move_to_pickup()
			return true
		return false
	_pickup_check_timer = 2.0
	
	if _pickup_target and is_instance_valid(_pickup_target) and _pickup_target.is_inside_tree():
		_move_to_pickup()
		return true
	
	_pickup_target = null
	
	# Prioridad 1: Si no tenemos arma, buscar un arma
	if not _weapon or not is_instance_valid(_weapon):
		var weapon_pickup = _pickup_manager.get_nearest_pickup(global_position, 0, 8.0)
		if weapon_pickup:
			_pickup_target = weapon_pickup
			_move_to_pickup()
			return true
		return false
	
	# Prioridad 2: Salud baja → buscar un botiquín (Type.HEALTH = 1)
	var health_pct: float = _get_health_pct()
	if health_pct < 0.5:
		var medkit = _pickup_manager.get_nearest_pickup(global_position, 1, 12.0)
		if medkit:
			_pickup_target = medkit
			_move_to_pickup()
			return true
	
	# Prioridad 3: Baja munición → primero un paquete de munición (Type.AMMO = 2),
	#               luego un arma en el suelo (que también da munición).
	var ammo_pct: float = _get_ammo_pct()
	if ammo_pct < 0.5:
		var ammo_pack = _pickup_manager.get_nearest_pickup(global_position, 2, 12.0)
		if ammo_pack:
			_pickup_target = ammo_pack
			_move_to_pickup()
			return true
		var weapon_pickup = _pickup_manager.get_nearest_pickup(global_position, 0, 10.0)
		if weapon_pickup:
			_pickup_target = weapon_pickup
			_move_to_pickup()
			return true
	
	return false


## Porcentaje de salud del bot (0.0 a 1.0).
func _get_health_pct() -> float:
	if max_health <= 0.0:
		return 1.0
	return float(current_health) / float(max_health)


## Porcentaje de munición del arma equipada (0.0 a 1.0).
func _get_ammo_pct() -> float:
	if not _weapon or not is_instance_valid(_weapon):
		return 1.0
	if _weapon.max_ammo <= 0:
		return 1.0
	return float(_weapon.ammo_in_mag + _weapon.reserve_ammo) / float(_weapon.max_ammo + _weapon.clip_size)


## Reabastece la munición del arma equipada (llamado por AmmoPack).
func refill_ammo(amount: int) -> void:
	if _weapon and is_instance_valid(_weapon):
		_weapon.reserve_ammo = min(_weapon.reserve_ammo + amount, _weapon.max_ammo)
		if weapon_sys:
			weapon_sys.sync_from_current_weapon()
		_pickup_target = null
		if tactical_sys:
			tactical_sys.notify_resource_collected(int(Pickup.Type.AMMO))


## Navega hacia el pickup objetivo usando MovementSystem.
func _move_to_pickup() -> void:
	if not _pickup_target or not is_instance_valid(_pickup_target) or not _pickup_target.is_inside_tree():
		_pickup_target = null
		return
	
	var target_pos: Vector3 = _pickup_target.global_position
	var dist: float = global_position.distance_to(target_pos)
	
	if movement_sys and movement_sys.command:
		movement_sys.command.set_navigate(target_pos, 5.0 if dist > 1.5 else 2.0)


## Llamado por el Pickup cuando este NPC entra en su área de recogida.
func _on_pickup_area_entered(pickup: Node) -> void:
	if is_dead:
		return
	if not is_instance_valid(pickup):
		return
	var ptype: int = pickup.get("pickup_type") if "pickup_type" in pickup else -1
	# No desperdiciar: si está a tope de salud/municion, ignorar el pickup.
	if ptype == int(Pickup.Type.HEALTH) and _get_health_pct() >= 0.99:
		return
	if ptype == int(Pickup.Type.AMMO) and _get_ammo_pct() >= 0.99:
		return
	pickup.pick_up(self)
	if tactical_sys:
		tactical_sys.notify_resource_collected(ptype)


## Recibe un arma recogida del suelo y la equipa.
func pickup_weapon(data: Dictionary) -> void:
	var weapon_name: String = data.get("tipo_arma", "")
	if weapon_name == "":
		return
	
	var balas_cargador: int = data.get("balas_cargador", 0)
	var balas_reserva: int = data.get("balas_reserva", 0)
	
	_pickup_target = null
	
	# Si ya tiene esta arma, sumar munición
	if _weapon and is_instance_valid(_weapon):
		if _weapon.weapon_name.to_lower() == weapon_name.to_lower():
			_weapon.ammo_in_mag += balas_cargador
			_weapon.ammo_in_mag = min(_weapon.ammo_in_mag, _weapon.clip_size)
			_weapon.reserve_ammo += balas_reserva
			_weapon.reserve_ammo = min(_weapon.reserve_ammo, _weapon.max_ammo)
			return
	
	# Arma diferente: reemplazar
	nombre_arma = weapon_name
	
	if _weapon and is_instance_valid(_weapon):
		if weapon_sys:
			weapon_sys.unregister_weapon(_weapon)
		_weapon.queue_free()
		_weapon = null
	
	_equipar_arma()
	if _weapon:
		_weapon.ammo_in_mag = balas_cargador
		_weapon.reserve_ammo = balas_reserva


# ─────────────────────────────────────────
# SISTEMA DE DAÑO & EQUIPOS
# ─────────────────────────────────────────

## Calcula la dirección desde la que llegó el daño.
## Usa el killer_id para encontrar al atacante y calcular
## un vector normalizado desde el atacante hacia el bot.
func _compute_hit_direction(killer_id: int) -> void:
	if killer_id > 0:
		var attacker: Object = instance_from_id(killer_id)
		if attacker and attacker is Node3D and is_instance_valid(attacker):
			var attacker_node: Node3D = attacker as Node3D
			if attacker_node.is_inside_tree():
				# Vector desde atacante → bot, normalizado
				last_hit_direction = (global_position - attacker_node.global_position).normalized()
				return
	
	# Fallback: si no hay atacante válido, asumir desde el frente
	last_hit_direction = -global_transform.basis.z


func take_damage(amount: float, zone: String = "Torso", killer_id: int = -1) -> void:
	if is_dead: return
	var mult: float = 2.0 if zone == "Cabeza" else 1.0
	current_health -= amount * mult
	current_health = clampf(current_health, 0.0, max_health)
	
	# ── Hit direction: calcular vector desde el atacante ──
	_compute_hit_direction(killer_id)
	var attacker_node: Node3D = null
	if killer_id > 0:
		var attacker_instance: Object = instance_from_id(killer_id)
		if attacker_instance is Node3D and is_instance_valid(attacker_instance):
			attacker_node = attacker_instance as Node3D
	if tactical_sys:
		tactical_sys.notify_damage(attacker_node)
	if decision_sys:
		decision_sys.notify_take_damage(amount * mult, attacker_node)
	
	# ── Hook: notificar al rol del daño recibido (FASE 7) ──
	if _tactical_role and killer_id > 0:
		var attacker: Object = instance_from_id(killer_id)
		if attacker is Node3D and is_instance_valid(attacker):
			_tactical_role.on_took_damage(self, attacker as Node3D)

	# ── Invulnerabilidad post-stun (FASE 7): ignorar daño si el
	# estado actual tiene invulnerabilidad activa ──
	var inv_timer: Variant = null
	if decision_sys and decision_sys.current_state:
		inv_timer = decision_sys.current_state.get("_invulnerability_timer")
	var is_invulnerable: bool = inv_timer != null and inv_timer > 0.0
	if is_invulnerable:
		_debug("Invulnerable, ignorando %.1f de daño" % [amount * mult])
		return

	# ── Transicionar a estado HIT (stun) si el daño no es letal ──
	# Solo si la FSM está activa y no estamos ya en hit/stun.
	if current_health > 0 and decision_sys and decision_sys.current_state:
		var current_type: int = decision_sys.current_state.state_type
		if current_type != BotState.StateType.TAKING_HIT:
			decision_sys.change_state(BotState.StateType.TAKING_HIT)
	
	if current_health <= 0:
		death_direction = last_hit_direction
		die(killer_id)


func die(killer_id: int = -1) -> void:
	if is_dead: return
	is_dead = true
	if tactical_sys:
		tactical_sys.reset()
	_drop_weapon()
	
	if is_instance_valid(MatchManager):
		MatchManager.reportar_muerte(self, killer_id)
		MatchManager.reportar_muerte_bot(self)
	
	set_physics_process(false)
	set_process(false)
	# hide() removido — TeddyAnimator reproduce la animación de muerte
	
	var cs: CollisionShape3D = find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = true
	
	if navigation_agent:
		navigation_agent.target_position = global_position
	
	var killer_name: String = "desconocido"
	if is_instance_valid(MatchManager) and killer_id >= 0:
		var kd = MatchManager.get_player_data(killer_id)
		if kd:
			killer_name = kd.player_name
	_debug("MUERTO por %s - esperando respawn..." % killer_name)


func _drop_weapon() -> void:
	if not DROPPED_WEAPON or not _weapon:
		return
	if not is_inside_tree():
		return
	if weapon_sys and _weapon:
		weapon_sys.unregister_weapon(_weapon)
	var drop: Node = DROPPED_WEAPON.instantiate()
	if not drop: return
	get_parent().add_child(drop)
	drop.global_transform.origin = global_transform.origin + Vector3.UP * 0.5
	if drop.has_method("set_weapon_data"):
		drop.set_weapon_data({
			"tipo_arma": _weapon.weapon_name,
			"balas_cargador": _weapon.ammo_in_mag,
			"balas_reserva": _weapon.reserve_ammo,
			"capacidad_cargador": _weapon.clip_size
		})


func _re_evaluar_enemigos() -> void:
	_is_attacking_core = false
	_enemy_core = null
	_team_objective = Vector3.ZERO
	
	if decision_sys:
		decision_sys.target_entity = null
	if perception_sys:
		perception_sys.reset()


# ─────────────────────────────────────────
# CORE DETECTION
# ─────────────────────────────────────────

func _find_enemy_core() -> void:
	_enemy_core = null
	_is_attacking_core = false
	_team_objective = Vector3.ZERO
	
	var cores: Array[Node] = get_tree().get_nodes_in_group("core")
	for core in cores:
		if not is_instance_valid(core):
			continue
		if core.get("is_destroyed") == true:
			continue
		var core_team: int = core.get("team") if "team" in core else -1
		if GameState.son_enemigos(equipo_id, core_team):
			_enemy_core = core
			_team_objective = core.global_position
			_debug("OBJETIVO: Core %s en %s" % [GameState.nombre_equipo(core_team), str(_team_objective)])
			return
	
	get_tree().create_timer(1.0).timeout.connect(_find_enemy_core)


func _check_core_proximity() -> void:
	if not _enemy_core or not is_instance_valid(_enemy_core) or not _enemy_core.is_inside_tree():
		_find_enemy_core()
		return
	if _enemy_core.get("is_destroyed") == true:
		_enemy_core = null
		_is_attacking_core = false
		return
	
	var target_entity = decision_sys.target_entity if decision_sys else null
	if target_entity and target_entity is CharacterBody3D and not target_entity.get("is_dead"):
		return
	
	var dist: float = global_position.distance_to(_enemy_core.global_position)
	if dist > 25.0:
		return
	
	# Verificar línea de visión con el core
	var target_pos: Vector3 = _enemy_core.global_position + Vector3.UP * 0.7
	var local_target: Vector3 = to_local(target_pos)
	raycast_vision.target_position = local_target
	raycast_vision.force_raycast_update()
	
	var collider = raycast_vision.get_collider()
	var core_hit: bool = (collider == _enemy_core)
	if not core_hit and collider:
		var parent_check: Node = collider.get_parent()
		while parent_check:
			if parent_check == _enemy_core:
				core_hit = true
				break
			parent_check = parent_check.get_parent()
	
	if core_hit:
		if not _is_attacking_core:
			_is_attacking_core = true
			if decision_sys:
				decision_sys.target_entity = _enemy_core
			_debug("ATACANDO CORE enemigo! Distancia: %.1f" % dist)
	else:
		if _is_attacking_core:
			_is_attacking_core = false
			if decision_sys:
				decision_sys.target_entity = null


## Devuelve el nombre del estado FSM activo.
func _get_current_behavior_name() -> String:
	if decision_sys and decision_sys.current_state:
		return decision_sys.current_state.state_name
	return "unknown"


# ─────────────────────────────────────────
# EQUIPAMIENTO
# ─────────────────────────────────────────

func _equipar_arma() -> void:
	if nombre_arma == "":
		return

	# ── Limpiar arma anterior si existe ──
	if _weapon and is_instance_valid(_weapon):
		if weapon_sys:
			weapon_sys.unregister_weapon(_weapon)
		_weapon.queue_free()
		_weapon = null

	# Cargar escena en tiempo de ejecución para evitar problemas de
	# compilación encadenada con autoloads durante el escaneo de class_name.
	var weapon_scene: PackedScene = ResourceLoader.load(
		"res://scenes/Compartido/weapons/weapon_placeholder.tscn",
		"PackedScene",
		ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene
	if not weapon_scene:
		push_error("_equipar_arma: No se pudo cargar weapon_placeholder.tscn")
		return
	var weapon_instance: Node3D = weapon_scene.instantiate()
	if not weapon_instance:
		push_error("_equipar_arma: weapon_scene.instantiate() devolvió null")
		return
	if head:
		head.add_child(weapon_instance)
		_weapon = weapon_instance as Weapon
		if _weapon:
			_weapon.initialize_from_name(nombre_arma)
			if weapon_sys:
				weapon_sys.register_weapon(_weapon)
			# Sincronizar bloqueo de equipamiento (Fase 4)
			_sync_weapon_equip_lock()
			if not weapon_equip_state.equip_state_changed.is_connected(_on_npc_weapon_equip_state_changed):
				weapon_equip_state.equip_state_changed.connect(_on_npc_weapon_equip_state_changed)


# ══════════════════════════════════════════════════════════════════
# SISTEMA DE EQUIPAMIENTO DE ARMA (Fase 4)
# ══════════════════════════════════════════════════════════════════

## Sincroniza el bloqueo de equipamiento del arma activa con el
## estado actual del WeaponEquipState.
func _sync_weapon_equip_lock() -> void:
	if _weapon and weapon_equip_state:
		_weapon.set_equip_locked(not weapon_equip_state.is_equipped)


## Se ejecuta cuando WeaponEquipState cambia de estado.
func _on_npc_weapon_equip_state_changed(is_now_equipped: bool) -> void:
	if _weapon:
		_weapon.set_equip_locked(not is_now_equipped)


func _aplicar_color_equipo() -> void:
	var color: Color = GameState.color_equipo(equipo_id)
	if has_node("MeshInstance3D"): _aplicar_color_a_mesh($MeshInstance3D, color)
	if has_node("Head/HeadMesh"): _aplicar_color_a_mesh($Head/HeadMesh, color)


func _aplicar_color_a_mesh(mesh: MeshInstance3D, color: Color) -> void:
	var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
	if not mat: mat = mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if not mat: return
	mat = mat.duplicate()
	mat.albedo_color = color
	mesh.set_surface_override_material(0, mat)


## Aplica texturas desde un SkinData al modelo visual del NPC.
## Delega en SkinData.apply_textures_to() que usa mesh_path
## primero y busca el primer mesh como fallback.
func _aplicar_texturas_skin(skin_data: SkinData, model_instance: Node3D) -> void:
	if not skin_data or not model_instance:
		return
	skin_data.apply_textures_to(model_instance)


## Activa o limpia la señal visual temporal del modo cobarde.
func set_coward_visual(enabled: bool) -> void:
	if enabled:
		if _coward_light == null:
			_coward_light = OmniLight3D.new()
			_coward_light.name = "CowardGlow"
			_coward_light.light_color = Color(1.0, 0.76, 0.12)
			_coward_light.light_energy = 3.0
			_coward_light.omni_range = 4.0
			_coward_light.shadow_enabled = false
			add_child(_coward_light)
		_apply_coward_materials(true)
		return
	if _coward_light != null and is_instance_valid(_coward_light):
		_coward_light.queue_free()
	_coward_light = null
	_apply_coward_materials(false)


func _apply_coward_materials(enabled: bool) -> void:
	var meshes: Array[Node] = find_children("*", "MeshInstance3D", true, false)
	if enabled:
		for node: Node in meshes:
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			if not _coward_material_overrides.has(mesh):
				_coward_material_overrides[mesh] = mesh.get_surface_override_material(0)
			var glow_material: StandardMaterial3D = StandardMaterial3D.new()
			glow_material.albedo_color = Color(1.0, 0.72, 0.08)
			glow_material.emission_enabled = true
			glow_material.emission = Color(1.0, 0.3, 0.02)
			glow_material.emission_energy_multiplier = 2.5
			mesh.set_surface_override_material(0, glow_material)
		return
	for mesh_key: Variant in _coward_material_overrides.keys():
		var mesh: MeshInstance3D = mesh_key as MeshInstance3D
		if mesh != null and is_instance_valid(mesh):
			mesh.set_surface_override_material(0, _coward_material_overrides[mesh_key])
	_coward_material_overrides.clear()


# ─────────────────────────────────────────
# RESPAWN
# ─────────────────────────────────────────

func respawn() -> void:
	is_dead = false
	is_frozen = false  # Seguridad: descongelar siempre al respawnear
	current_health = max_health
	if tactical_sys:
		tactical_sys.reset()
	
	set_physics_process(true)
	set_process(true)
	show()
	
	var cs: CollisionShape3D = find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = false
	
	_is_attacking_core = false
	_enemy_core = null
	_team_objective = Vector3.ZERO
	_pickup_target = null
	_pickup_check_timer = 0.0
	if tactical_sys:
		tactical_sys.reset()
	
	if perception_sys:
		perception_sys.reset()
	if memory_sys:
		memory_sys.clear_all()
	if decision_sys:
		decision_sys.target_entity = null
		decision_sys.movement_command.reset()
		decision_sys.combat_command.reset()
		decision_sys.change_state(BotState.StateType.ROAMING)
	if movement_sys:
		movement_sys.reset()
	
	_tactical_role = TacticalRole.for_npc(self)
	
	_equipar_arma()
	_aplicar_color_equipo()
	_setup_debug_overlay()
	
	call_deferred("_refresh_order")
	call_deferred("_find_enemy_core")
	


# ─────────────────────────────────────────
# CONGELACIÓN
# ─────────────────────────────────────────

func set_frozen() -> void:
	if is_dead or is_frozen:
		return
	is_frozen = true
	if navigation_agent:
		navigation_agent.target_position = global_position
	velocity = Vector3.ZERO

## Congela al NPC por [duration] segundos.
## Mientras está congelado no se mueve, no procesa IA, no dispara.
func freeze(duration: float) -> void:
	if is_dead:
		return
	if is_frozen:
		return
	
	is_frozen = true
	
	# Detener cualquier navegación activa
	if navigation_agent:
		navigation_agent.target_position = global_position
	
	# Detener movimiento
	velocity = Vector3.ZERO
	
	# Timer de descongelación
	_frozen_timer = get_tree().create_timer(duration)
	_frozen_timer.timeout.connect(unfreeze)


## (freeze_to_yellow eliminado — ya no se usa)


## Descongela al NPC y reanuda su comportamiento normal.
## Pública — llamada por jump controllers y SceneTreeTimer.
func unfreeze() -> void:
	if not is_frozen:
		return
	is_frozen = false
	_frozen_timer = null


# ── Salto al Green Cube ────────────────────

# (Jump-to-cube methods removed — _start_jump_to_green_cube, _start_jump_to_yellow_cube, _find_nearest_green_cube, _find_nearest_yellow_cube)


# (Process jump methods removed — _process_jump_to_green, _process_jump_to_yellow)



# ─────────────────────────────────────────
# TEAMAI / ORDER SYSTEM (FASE 6)
# ─────────────────────────────────────────

func _refresh_order() -> void:
	if not is_instance_valid(TeamAI):
		return
	if equipo_id == int(Enums.Equipo.ESPECTADOR):
		return
	TeamAI.assign_order_by_role(self)


func _update_order_cache() -> void:
	if not is_instance_valid(TeamAI):
		return
	
	var order_data: Dictionary = TeamAI.get_order_for_bot(self)
	current_order_type = order_data.get("type", TeamAI.OrderType.FREELANCE)
	current_order_name = TeamAI.order_type_name(current_order_type)
	
	if order_data.get("is_temp", false):
		current_order_name += " [!]"
		current_order_target = order_data.get("target_position", Vector3.ZERO)
	elif current_order_type == TeamAI.OrderType.ATTACK:
		var enemy_core: Node = TeamAI._get_enemy_core(equipo_id)
		if enemy_core:
			current_order_target = enemy_core.global_position
	elif current_order_type == TeamAI.OrderType.DEFEND:
		var own_core: Node = TeamAI._get_own_core(equipo_id)
		if own_core:
			current_order_target = own_core.global_position


func get_current_order() -> Dictionary:
	if is_instance_valid(TeamAI):
		return TeamAI.get_order_for_bot(self)
	return {"type": TeamAI.OrderType.FREELANCE, "target_position": Vector3.ZERO,
		"target_node": NodePath(), "is_temp": false, "reason": ""}


func is_order_offensive() -> bool:
	match current_order_type:
		TeamAI.OrderType.ATTACK, TeamAI.OrderType.PATROL, TeamAI.OrderType.CAPTURE:
			return true
		TeamAI.OrderType.FREELANCE:
			return true
		_: return false


func is_order_defensive() -> bool:
	return current_order_type == TeamAI.OrderType.DEFEND or current_order_type == TeamAI.OrderType.HOLD


func get_order_target_position() -> Vector3:
	if current_order_type == TeamAI.OrderType.ATTACK:
		if _enemy_core and is_instance_valid(_enemy_core):
			return _enemy_core.global_position
	elif current_order_type == TeamAI.OrderType.DEFEND:
		var own_core: Node = _get_own_core()
		if own_core:
			return own_core.global_position
	return current_order_target


# ─────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────

func _get_own_core() -> Node:
	if equipo_id == int(Enums.Equipo.AZUL):
		return GameStateMP.core_blue if is_instance_valid(GameStateMP.core_blue) else null
	elif equipo_id == int(Enums.Equipo.ROJO):
		return GameStateMP.core_red if is_instance_valid(GameStateMP.core_red) else null
	return null


func _get_dist_to_own_core() -> float:
	var core: Node = _get_own_core()
	if core and is_instance_valid(core) and core.is_inside_tree():
		return global_position.distance_to(core.global_position)
	return 0.0


func _role_speed(role, base_speed: float) -> float:
	if role and "speed_multiplier" in role:
		return base_speed * role.speed_multiplier
	return base_speed


## Retorna la Velocidad con Arma equipada (VA) según el arma actual.
## Si el arma está guardada, o no tiene arma, devuelve base_speed.
func _get_weapon_va(base_speed: float = 6.0) -> float:
	if weapon_equip_state and not weapon_equip_state.is_equipped:
		return base_speed
	var arma: Weapon = get_current_weapon()
	if arma and is_instance_valid(arma) and arma.weapon_name != "":
		return VelocidadesArmas.get_va(arma.weapon_name)
	return base_speed


## Retorna la Velocidad mientras Dispara (VD) según el arma actual.
## Si el arma está guardada, o no tiene arma, devuelve base_speed.
func _get_weapon_vd(base_speed: float = 6.0) -> float:
	if weapon_equip_state and not weapon_equip_state.is_equipped:
		return base_speed
	var arma: Weapon = get_current_weapon()
	if arma and is_instance_valid(arma) and arma.weapon_name != "":
		return VelocidadesArmas.get_vd(arma.weapon_name)
	return base_speed


## Indica si el bot está disparando o intenta disparar (para VD).
func _is_bot_firing() -> bool:
	if decision_sys and decision_sys.combat_command:
		return decision_sys.combat_command.engage or decision_sys.combat_command.force_fire
	return false


## Indica si el bot está apuntando (en combate, mirando a un objetivo).
## Cuando apunta, la velocidad se reduce a la mitad.
func _is_bot_aiming() -> bool:
	if decision_sys and decision_sys.combat_command:
		return decision_sys.combat_command.engage
	return false


func _role_wander_radius(role) -> float:
	if not role:
		return 20.0
	if "movement_profile" in role:
		match role.movement_profile:
			0: return 12.0  # DEFENSIVE
			1: return 30.0  # FLANKING
			2: return 20.0  # PATROL
	return 20.0


# ─────────────────────────────────────────
# DEBUG OVERLAY
# ─────────────────────────────────────────

func _setup_debug_overlay() -> void:
	if BotDebugOverlay.enabled:
		_add_debug_overlay()
	else:
		_remove_debug_overlay()


func _add_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		return
	if not DEBUG_OVERLAY:
		return
	var overlay: Node3D = DEBUG_OVERLAY.instantiate()
	add_child(overlay)
	_debug_overlay = overlay


func _remove_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		_debug_overlay.queue_free()
		_debug_overlay = null


static func toggle_debug_overlay_all() -> void:
	BotDebugOverlay.enabled = not BotDebugOverlay.enabled
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var npcs: Array[Node] = tree.get_nodes_in_group("npc")
	for npc in npcs:
		if npc is BotBase:
			npc._setup_debug_overlay()


# ══════════════════════════════════════════════════════════════════
# TURN DETECTION — Metadata para animaciones de giro
# ══════════════════════════════════════════════════════════════════

## Detecta giros bruscos del bot y emite turn_detected si corresponde.
## No modifica físicas — solo observación.
func _detect_turn() -> void:
	if is_frozen or is_dead:
		return
	
	var facing: Vector3 = -global_transform.basis.z
	var facing_angle: float = atan2(facing.x, facing.z)
	
	# Calcular delta angular (manejar cruce de -PI/PI)
	var delta_angle: float = facing_angle - _last_facing_angle
	if delta_angle > PI:
		delta_angle -= TAU
	elif delta_angle < -PI:
		delta_angle += TAU
	
	# Umbral: solo reportar giros significativos (> 30°)
	var abs_delta_deg: float = rad_to_deg(abs(delta_angle))
	if abs_delta_deg > 30.0:
		var direction: int = 1 if delta_angle > 0 else -1
		turn_detected.emit(abs_delta_deg, direction)
	
	_last_facing_angle = facing_angle


# ══════════════════════════════════════════════════════════════════
# CROUCH — Colisión y estado físico
# ══════════════════════════════════════════════════════════════════

## Actualiza el estado de crouch según el MovementCommand.
## Modifica la altura de la cápsula de colisión y reposiciona la cabeza.
func _update_crouch_state() -> void:
	if movement_sys == null:
		return
	
	var want_crouch: bool = movement_sys.command.crouch
	
	if want_crouch and not is_crouching:
		_enter_crouch()
	elif not want_crouch and is_crouching:
		_exit_crouch()


func _enter_crouch() -> void:
	is_crouching = true
	if _collision_shape == null or not (_collision_shape.shape is CapsuleShape3D):
		return
	if _original_collision_height <= 0.0:
		_original_collision_height = _collision_shape.shape.height
	
	var shape: CapsuleShape3D = _collision_shape.shape
	shape.height = _original_collision_height * 0.5
	# Reposicionar la cabeza para que quede centrada en la cápsula reducida
	if head:
		head.position.y = shape.height * 0.5


func _exit_crouch() -> void:
	is_crouching = false
	if _collision_shape == null or not (_collision_shape.shape is CapsuleShape3D):
		return
	if _original_collision_height > 0.0:
		var shape: CapsuleShape3D = _collision_shape.shape
		shape.height = _original_collision_height
		if head:
			head.position.y = shape.height * 0.5


## Devuelve la posición desde donde debe lanzarse un proyectil
## (desde la cabeza del bot, no desde el centro del cuerpo).
func get_projectile_launch_position() -> Vector3:
	if head and is_instance_valid(head):
		return head.global_position - head.global_transform.basis.z * 0.3
	return global_position + Vector3.UP * 0.8


func get_current_weapon() -> Weapon:
	if weapon_sys and is_instance_valid(weapon_sys) and weapon_sys.current_weapon:
		return weapon_sys.current_weapon
	return _weapon


func _debug(msg: String) -> void:
	print("[NPC #%d | %s] %s" % [_npc_id, GameState.nombre_equipo(equipo_id), msg])
