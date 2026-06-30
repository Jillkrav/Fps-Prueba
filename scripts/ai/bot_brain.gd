# scripts/ai/bot_brain.gd
# ──────────────────────────────────────────────────────────────────
# CEREBRO MODULAR DEL NPC — Motor de decisión por prioridades
#
# Este nodo se añade como hijo de NpcBase y reemplaza la FSM
# tradicional con un sistema de comportamientos modulares.
#
# ── CÓMO FUNCIONA ──
# Cada frame, el brain evalúa TODOS los comportamientos registrados
# y ejecuta el que retorna la prioridad más alta (> 0).
#
# Prioridades típicas:
#   100 = COMBAT     (enemigo visible y debemos atacar)
#    60 = HEALING    (futuro: baja salud, buscar botiquín)
#    55 = AMMO       (futuro: poca munición, buscar)
#    50 = HUNT       (perseguir última posición conocida)
#    40 = INVESTIGATE (futuro: sonido/explosión cercana)
#    30 = DEFEND_ALLY (futuro: proteger aliado)
#    10 = PATROL     (patrullaje / ir al objetivo principal)
#     0 = IDLE       (quieto, estado por defecto)
#
# ── CÓMO EXTENDER ──
# 1. Crea un nuevo script que extienda BotBehavior
# 2. Implementa get_priority() y execute()
# 3. Agrégalo en _register_behaviors()
# 4. El brain lo evaluará automáticamente
# ──────────────────────────────────────────────────────────────────
extends Node
class_name BotBrain

# ══════════════════════════════════════════════════════════════════
# SEÑALES
# ══════════════════════════════════════════════════════════════════

## Se emite cuando el brain cambia de comportamiento activo.
signal behavior_changed(old_behavior: BotBehavior, new_behavior: BotBehavior)


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Lista de comportamientos registrados (orden de evaluación)
var behaviors: Array[BotBehavior] = []

## Comportamiento activo actualmente
var current_behavior: BotBehavior = null

## Comportamiento anterior (útil para transiciones condicionales)
var previous_behavior: BotBehavior = null

## Prioridad del comportamiento activo (para debug)
var current_priority: float = -1.0

## Referencia al bot dueño de este cerebro
var bot: NpcBase:
	get:
		if _bot == null:
			_bot = get_parent() as NpcBase
		return _bot

var _bot: NpcBase = null

## Referencia al sistema de percepción (hermano en el árbol)
var perception: Node = null:
	get:
		if _perception == null:
			_perception = get_node_or_null("../PerceptionSystem")
		return _perception

var _perception: Node = null

## Referencia al sistema de memoria (hermano en el árbol)
var memory: MemorySystem = null:
	get:
		if _memory == null:
			_memory = get_node_or_null("../MemorySystem") as MemorySystem
		return _memory

var _memory: MemorySystem = null

## Referencia al sistema de navegación (hermano en el árbol)
var navigation: NavigationSystem = null:
	get:
		if _navigation == null:
			_navigation = get_node_or_null("../NavigationSystem") as NavigationSystem
		return _navigation

var _navigation: NavigationSystem = null

## Tiempo acumulado en el comportamiento actual (para debug)
var time_in_behavior: float = 0.0

## Contexto de decisión compartido (DecisionContext).
## Los behaviors escriben aquí sus intenciones durante execute().
## BotBrain traduce estas intenciones en execute_context().
var context: DecisionContext = null


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_register_behaviors()
	context = DecisionContext.new()
	_debug_brain("Brain listo con %d comportamientos" % behaviors.size())


## Registra todos los comportamientos disponibles.
## Para añadir uno nuevo: crea el script, impórtalo y agrégalo aquí.
func _register_behaviors() -> void:
	# NOTA: Usamos load() en lugar de preload() para evitar
	# dependencias circulares en tiempo de compilación.
	# La primera vez que se llama, los scripts ya están cargados.
	var combat_script = load("res://scripts/ai/behaviors/behavior_combat.gd")
	var hunt_script = load("res://scripts/ai/behaviors/behavior_hunt.gd")
	var patrol_script = load("res://scripts/ai/behaviors/behavior_patrol.gd")
	var idle_script = load("res://scripts/ai/behaviors/behavior_idle.gd")
	
	behaviors = [
		combat_script.new(),
		hunt_script.new(),
		patrol_script.new(),
		idle_script.new(),
	]


# ══════════════════════════════════════════════════════════════════
# CICLO PRINCIPAL — Llamado desde NpcBase._physics_process()
# ══════════════════════════════════════════════════════════════════

## Evalúa todos los comportamientos, selecciona el mejor y lo ejecuta.
##
## FLUJO ACTUALIZADO:
##   1. Resetea context (intents transitorios)
##   2. Evalúa prioridades (solo lectura del context)
##   3. Transiciona si cambia el mejor behavior
##   4. Ejecuta behavior activo → ESCRIBE en context
##   5. Resolve: valida coherencia del context
##   6. Execute: traduce context a llamadas a sistemas
##
## Retorna el nombre del comportamiento activo (para debug).
func process(delta: float) -> String:
	if bot == null or bot.is_dead:
		return "dead"
	
	# ── Fase 0: Resetear intents transitorios ─────────────────
	if context != null:
		context.reset_frame()
	
	# ── Fase 1: Evaluar prioridades (solo lectura) ─────────────
	var best_behavior: BotBehavior = null
	var best_priority: float = -1.0
	
	for behavior in behaviors:
		var priority: float = behavior.get_priority(self)
		if priority > best_priority:
			best_priority = priority
			best_behavior = behavior
	
	# ── Fase 2: Transición si el mejor es diferente al actual ──
	if best_behavior != current_behavior:
		_switch_behavior(current_behavior, best_behavior)
	
	# ── Fase 3: Ejecutar comportamiento activo → ESCRIBE context ──
	if current_behavior != null:
		time_in_behavior += delta
		current_behavior.execute(self, delta)
		
		# Sincronizar flags del contexto
		if context != null:
			context.flags.behavior_name = current_behavior.behavior_name
			context.flags.time_in_behavior = time_in_behavior
	
	# ── Fase 4: Resolver contexto (validar coherencia) ─────────
	if context != null:
		_resolve_context()
		
		# ── Fase 5: Ejecutar contexto (traducir a sistemas) ──
		_execute_context()
	
	return current_behavior.behavior_name if current_behavior else "none"


## Realiza la transición entre comportamientos.
func _switch_behavior(old_b: BotBehavior, new_b: BotBehavior) -> void:
	if old_b != null:
		old_b.exit(self)
	
	previous_behavior = old_b
	current_behavior = new_b
	current_priority = _get_priority_for(new_b)
	time_in_behavior = 0.0
	
	if new_b != null:
		new_b.enter(self)
	
	emit_signal("behavior_changed", old_b, new_b)
	_debug_brain("Comportamiento: %s → %s (prioridad %.1f)" % [
		old_b.behavior_name if old_b else "null",
		new_b.behavior_name if new_b else "null",
		current_priority
	])


## Busca la prioridad de un behavior (para debug).
func _get_priority_for(behavior: BotBehavior) -> float:
	if behavior == null:
		return -1.0
	for b in behaviors:
		if b == behavior:
			return b.get_priority(self)
	return -1.0


# ══════════════════════════════════════════════════════════════════
# RESOLUCIÓN Y EJECUCIÓN DEL CONTEXTO
# ══════════════════════════════════════════════════════════════════
# Fase 4: resolve_context() — valida coherencia del DecisionContext
# Fase 5: execute_context() — traduce context a llamadas a sistemas
#
# Durante la migración (Fase 5 de la refactorización), los behaviors
# pueden usar la API antigua (wrappers abajo) O escribir en context.
# execute_context() solo actúa si el behavior escribió en context.
# ══════════════════════════════════════════════════════════════════

## Valida y normaliza el DecisionContext antes de ejecutarlo.
## Delega en context.resolve() que contiene las reglas de validación.
func _resolve_context() -> void:
	if context == null:
		return
	context.resolve()


## Traduce las intenciones del DecisionContext a llamadas a sistemas.
## Solo actúa si el behavior escribió en context (movement.mode != NONE).
## Los behaviors que usen la API antigua (wrappers) no tocan el context,
## por lo que esta función no interfiere.
func _execute_context() -> void:
	if context == null:
		return
	
	var m: DecisionContext.MovementIntent = context.movement
	var c: DecisionContext.CombatIntent = context.combat
	
	# ── Movimiento ─────────────────────────────────────────────
	if navigation != null:
		match m.mode:
			DecisionContext.MovementIntent.Mode.NAVIGATE:
				# Pathfinding hacia un destino
				navigation.move_to(m.target, m.speed)
			
			DecisionContext.MovementIntent.Mode.DIRECT:
				# Vector directo (strafe, retreat, etc.)
				navigation.move_direction(m.vector, m.speed)
			
			DecisionContext.MovementIntent.Mode.HOLD:
				# Quieto intencional — frenar suavemente
				navigation.hold_position()
			
			# NONE: el behavior usó la API antigua, no intervenir
	else:
		# Fallback: si no hay NavigationSystem, usar métodos antiguos
		match m.mode:
			DecisionContext.MovementIntent.Mode.NAVIGATE:
				if bot:
					bot._move_to_target(0.0, m.speed, m.target)
			DecisionContext.MovementIntent.Mode.DIRECT:
				if bot and m.vector != Vector3.ZERO:
					var dir: Vector3 = m.vector.normalized()
					bot.velocity.x = dir.x * m.speed
					bot.velocity.z = dir.z * m.speed
			DecisionContext.MovementIntent.Mode.HOLD:
				if bot:
					bot.velocity.x = move_toward(bot.velocity.x, 0.0, 10.0)
					bot.velocity.z = move_toward(bot.velocity.z, 0.0, 10.0)
	
	# ── Apuntar ────────────────────────────────────────────────
	if c.aim_target != Vector3.ZERO and bot:
		bot._aim_at_target(c.aim_target)
	
	# ── Disparar ───────────────────────────────────────────────
	if c.wants_to_shoot and bot:
		bot._shoot()


# ══════════════════════════════════════════════════════════════════
# API PARA COMPORTAMIENTOS — Wrappers públicos a métodos de NpcBase
# ══════════════════════════════════════════════════════════════════
# Los behaviors llaman a estos métodos en lugar de acceder
# directamente a npc_base. Esto mantiene la separación de
# responsabilidades y facilita el testing.
# ══════════════════════════════════════════════════════════════════

## Navega hacia una posición usando el sistema de rutas.
func navigate_to(target: Vector3, speed: float, delta: float) -> void:
	if bot:
		bot._move_to_target(delta, speed, target)


## Navega hacia el objetivo con diversificación de ruta.
func navigate_with_route(delta: float, speed: float, target: Vector3) -> void:
	if bot:
		bot._navigate_with_route(delta, speed, target)


## Establece un nuevo destino de ruta diversificada.
func set_route_target(target: Vector3) -> void:
	if bot:
		bot._set_route_target(target)


## Apunta la cabeza y el cuerpo hacia una posición.
func aim_at(target: Vector3) -> void:
	if bot:
		bot._aim_at_target(target)


## Dispara el arma actual.
func shoot() -> void:
	if bot:
		bot._shoot()


## Intenta disparar si el arma está lista.
func try_shoot() -> void:
	if bot and bot._weapon and bot._weapon.can_fire():
		bot._shoot()


## Verifica y maneja detección de atasco.
## Retorna true si se está ejecutando una recuperación.
func check_stuck(delta: float) -> bool:
	if bot:
		return bot._check_stuck(delta)
	return false


## Busca pickups cercanos y navega hacia ellos.
## Retorna true si está yendo hacia un pickup.
func check_pickups(delta: float) -> bool:
	if bot:
		return bot._check_for_pickups(delta)
	return false


## Devuelve la velocidad ajustada por el rol táctico.
func role_speed(base_speed: float) -> float:
	if bot:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed


## Reinicia el estado de stuck detection.
func reset_stuck() -> void:
	if bot:
		bot._reset_stuck_state()


## Obtiene el core enemigo (si existe).
func get_enemy_core() -> Node:
	if bot:
		return bot._enemy_core
	return null


## Obtiene el core aliado (propia base).
func get_own_core() -> Node:
	if bot:
		return bot._get_own_core()
	return null


## Distancia al core aliado.
func dist_to_own_core() -> float:
	if bot:
		return bot._get_dist_to_own_core()
	return 0.0


## Re-evalúa los enemigos (resetea estado de combate).
func reevaluate_enemies() -> void:
	if bot:
		bot._re_evaluar_enemigos()


# ══════════════════════════════════════════════════════════════════
# CONSULTAS DE ESTADO — Acceso limpio a propiedades del bot
# ══════════════════════════════════════════════════════════════════

## ¿Hay un enemigo vivo como objetivo actual?
func has_target() -> bool:
	return bot != null and bot.target_enemy != null and is_instance_valid(bot.target_enemy)


## ¿El objetivo actual está muerto o destruido?
func is_target_dead() -> bool:
	if not has_target():
		return true
	if bot.target_enemy.has_method("is_queued_for_deletion") and bot.target_enemy.is_queued_for_deletion():
		return true
	if bot.target_enemy.get("is_dead") == true:
		return true
	if bot.target_enemy.get("is_destroyed") == true:
		return true
	return false


## ¿El objetivo actual es un jugador enemigo?
func is_target_character() -> bool:
	return has_target() and bot.target_enemy is CharacterBody3D


## ¿Estamos atacando el core enemigo?
func is_attacking_core() -> bool:
	return bot != null and bot._is_attacking_core


## Distancia al objetivo actual (o INF si no hay objetivo).
func dist_to_target() -> float:
	if has_target():
		return bot.global_position.distance_to(bot.target_enemy.global_position)
	return INF


## Porcentaje de vida del bot (0.0 - 1.0).
func health_pct() -> float:
	if bot and bot.max_health > 0:
		return bot.current_health / bot.max_health
	return 0.0


## Porcentaje de munición total del arma actual (0.0 - 1.0).
func ammo_pct() -> float:
	if bot and bot._weapon and bot._weapon.max_ammo > 0:
		var total: float = float(bot._weapon.ammo_in_mag + bot._weapon.reserve_ammo)
		var max_total: float = float(bot._weapon.max_ammo + bot._weapon.clip_size)
		return total / max_total
	return 0.0


# ══════════════════════════════════════════════════════════════════
# API DE MEMORIA — Wrappers a MemorySystem
# ══════════════════════════════════════════════════════════════════

## ¿Hay memoria de posición enemiga?
func has_enemy_memory() -> bool:
	return memory != null and memory.has_enemy_memory()


## Retorna la última posición conocida de un enemigo.
func get_last_enemy_position() -> Vector3:
	if memory != null:
		return memory.get_last_enemy_position()
	return Vector3.ZERO


## Retorna la entrada más reciente de un tipo de memoria.
func get_memory(type: int) -> MemorySystem.MemoryEntry:
	if memory != null:
		return memory.get_most_recent(type)
	return null


## ¿Hay una entrada del tipo especificado?
func has_memory_type(type: int, max_age: float = -1.0) -> bool:
	return memory != null and memory.has_type(type, max_age)


## Acceso al rol táctico del bot.
func get_tactical_role() -> TacticalRole:
	if bot:
		return bot._tactical_role
	return null


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func _debug_brain(msg: String) -> void:
	if bot:
		bot._debug("[Brain] " + msg)


## Devuelve una descripción del estado actual del brain.
func debug_string() -> String:
	var beh_name: String = current_behavior.behavior_name if current_behavior else "null"
	return "Brain[%s] prio=%.1f time=%.1fs  behaviors=%d" % [
		beh_name, current_priority, time_in_behavior, behaviors.size()
	]
