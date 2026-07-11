# scripts/ai/states/state_roaming.gd
# ──────────────────────────────────────────────────────────────────
# STATE_ROAMING — Deambular / Patrullar
#
# Estado por defecto cuando no hay enemigos, objetivos urgentes
# ni situación de peligro. El bot navega hacia el core enemigo
# (objetivo principal) o deambula si no hay core disponible.
#
# Comportamiento migrado de BehaviorPatrol.
#
# ── TRANSICIONES DE SALIDA ──
# → HUNTING:      Si hay memoria de posición enemiga
# → COMBAT:       Si hay enemigos visibles
# → RETREATING:   Si la salud es baja y hay core aliado cerca
# ──────────────────────────────────────────────────────────────────
extends BotState
class_name StateRoaming


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

const PRIORITY_PATROL: float = 10.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

var _objective_reached: bool = false
var _nav_target: Vector3 = Vector3.ZERO

# ── Cooldown de cubos semánticos ──────────────────────────────────
# Duración de cooldown según el tipo de cubo.
const POINT_COOLDOWN: Dictionary = {
	SemanticPoint.PointType.ASSAULT: 55.0,
	SemanticPoint.PointType.TERCER: 55.0,
	SemanticPoint.PointType.ALTERNATE: 30.0,
	SemanticPoint.PointType.OBJECTIVE: 45.0,
	SemanticPoint.PointType.DUAL: 40.0,
}
# Dict: "x,y,z" → timestamp de expiración
var _semantic_cooldowns: Dictionary = {}

# El tipo de cubo al que el bot está navegando actualmente (-1 = no es cubo)
var _last_semantic_type: int = -1

# Timestamp del momento en que se fijó _nav_target (para detectar navegación fallida)
var _nav_target_set_time: float = 0.0

# ── Stack de ruta semántica (para CTF futuro) ───────────────────
# Almacena los puntos semánticos visitados en orden de avance.
var _semantic_path: Array[SemanticPoint] = []

# ── Checkpoint celeste obligatorio ──────────────────────────────
# Cuando el bot toca un cubo azul (OBJECTIVE) que tiene un CyanTarget,
# se activa _must_visit_cyan y se guarda la posición del cubo celeste.
# El bot DEBE ir a esa posición antes de continuar con su ruta normal.
var _cyan_checkpoint: Vector3 = Vector3.ZERO
var _must_visit_cyan: bool = false
# Flag que se activa mientras estamos navegando al celeste,
# para no aplicar cooldown del cubo azul en ese tramo intermedio.
var _navigating_to_cyan: bool = false

# ── Congelamiento al tocar punto_inicio_salto ────────────────────
# Cuando el bot toca un OBJECTIVE (punto_inicio_salto) que tiene un
# punto_final_salto enlazado, se congela 5 segundos antes de continuar.
var _frozen_timer: float = 0.0
var _is_frozen: bool = false


func _init() -> void:
	state_type = StateType.ROAMING
	state_name = "roaming"


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(_previous_state: BotState) -> void:
	_objective_reached = false
	_nav_target = Vector3.ZERO
	_last_semantic_type = -1
	_nav_target_set_time = 0.0
	_semantic_path.clear()
	_frozen_timer = 0.0
	_is_frozen = false
	movement_cmd.reset()
	if decision_system:
		decision_system.combat_command.cease_fire = true


func execute(delta: float) -> void:
	if bot == null or bot.is_dead:
		return

	# ── ¿Congelado por tocar punto_inicio_salto? ──
	if _is_frozen:
		_frozen_timer -= delta
		if _frozen_timer <= 0.0:
			_is_frozen = false
			_resume_after_freeze()
		else:
			# Quieto: no moverse ni disparar
			movement_cmd.set_hold()
			combat_cmd.cease_fire = true
		return

	# ── Verificar transiciones prioritarias ──
	if _check_transitions():
		return

	# ── 1. Ejecutar según orden de TeamAI (FASE 6) ──
	if _execute_order():
		return

	# ── 2. Radio defensivo: volver a la base si nos alejamos ──
	if _check_defense_radius():
		return

	# ── 3. Pickups cercanos ──
	if _check_pickups():
		return

	# ── 4. Decidir: ir al core enemigo o deambular ──
	if _has_valid_core() and not _should_patrol_instead():
		_advance_to_core()
	else:
		_wander()


# ══════════════════════════════════════════════════════════════════
# TRANSICIONES DE SALIDA
# ══════════════════════════════════════════════════════════════════

## Verifica si debemos salir de Roaming por eventos externos.
## Retorna true si transicionó a otro estado.
func _check_transitions() -> bool:
	# ════════════════════════════════════════════════════════════════
	# 🚫 TRAYECTO OBLIGATORIO: AZUL → CELESTE
	# Mientras el bot navega del cubo azul al celeste, NO se permite
	# ninguna interrupción (combate, cacería, retirada). El bot DEBE
	# completar ese trayecto sin importar qué ocurra.
	# ════════════════════════════════════════════════════════════════
	if _navigating_to_cyan:
		return false

	# ── ¿Enemigo visible? → COMBAT ──
	if perception and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
		return true

	# ── ¿Memoria de enemigo? → HUNTING ──
	if memory and memory.has_enemy_memory() and not perception.has_visible_enemies():
		change_state(BotState.StateType.HUNTING)
		return true

	# ── ¿Salud baja y cerca de base? → RETREATING ──
	if health_pct() < 0.25 and _dist_to_own_core() < 15.0:
		change_state(BotState.StateType.RETREATING)
		return true

	return false


# ══════════════════════════════════════════════════════════════════
# RADIO DEFENSIVO
# ══════════════════════════════════════════════════════════════════

func _check_defense_radius() -> bool:
	var role: TacticalRole = _get_role()
	if role and role.base_defense_radius > 0.0:
		var own_core: Node = _get_own_core()
		if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
			var dist_to_base: float = bot.global_position.distance_to(own_core.global_position)
			if dist_to_base > role.base_defense_radius:
				_nav_target = own_core.global_position
				movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
				return true
	return false


# ══════════════════════════════════════════════════════════════════
# PICKUPS
# ══════════════════════════════════════════════════════════════════

func _check_pickups() -> bool:
	# Llamar directamente a NpcBase._check_for_pickups
	if bot and is_instance_valid(bot):
		return bot._check_for_pickups(0.0)
	return false


# ══════════════════════════════════════════════════════════════════
# DECISIÓN: AVANZAR AL CORE VS DEAMBULAR
# ══════════════════════════════════════════════════════════════════

func _has_valid_core() -> bool:
	if bot == null:
		return false
	var core: Node = bot._enemy_core
	return core != null and is_instance_valid(core) and core.is_inside_tree() \
		and not core.get("is_destroyed")


func _should_patrol_instead() -> bool:
	var role: TacticalRole = _get_role()
	if role == null:
		return randf() < 0.3
	match role.movement_profile:
		TacticalRole.MovementProfile.PATROL:
			return randf() < 0.4
		TacticalRole.MovementProfile.DEFENSIVE:
			return randf() < 0.3
		_:
			return randf() < 0.2


func _advance_to_core() -> void:
	if bot == null or bot._enemy_core == null:
		_wander()
		return

	var core: Node = bot._enemy_core
	var dist_to_core: float = bot.global_position.distance_to(core.global_position)

	if dist_to_core < 4.0:
		_objective_reached = true

	if _nav_target == Vector3.ZERO or _objective_reached or _is_nav_finished():
		# ── Cooldown del punto al que intentamos llegar ──
		# Siempre se aplica al terminar con un cubo, haya llegado o no.
		# Así el bot no se queda atascado intentando un cubo inalcanzable
		# ni se devuelve a buscar uno que quedó atrás.
		# El cooldown se aplica a todos los puntos alcanzados (incluido OBJECTIVE).
		if _nav_target != Vector3.ZERO and _last_semantic_type >= 0 and not _navigating_to_cyan:
			_add_semantic_cooldown(_nav_target, _last_semantic_type)

		# ── ¡CONGELAR 5s al tocar punto_inicio_salto! ──
		# El bot acaba de llegar a un OBJECTIVE (punto_inicio_salto)
		# que tiene un CyanTarget (punto_final_salto) enlazado.
		# Se congela completamente durante 5 segundos.
		if _must_visit_cyan:
			_is_frozen = true
			_frozen_timer = 5.0
			_must_visit_cyan = false
			_cyan_checkpoint = Vector3.ZERO
			movement_cmd.set_hold()
			combat_cmd.cease_fire = true
			_debug("¡Punto inicio salto alcanzado! Congelado 5 segundos")
			return

		# ── Elegir punto según el rol del bot ──
		var role: TacticalRole = _get_role()
		var target_point: SemanticPoint = null
		var point_label: String = ""

		if role != null:
			match role.type:
				TacticalRole.Type.ASSAULT:
					target_point = _get_objective_point_nearby()
					point_label = "Objetivo"
					if target_point == null:
						target_point = _get_assault_point_nearby()
						point_label = "Asalto"
					if target_point == null:
						target_point = _get_tercer_point_nearby()
						point_label = "Tercercamino"
					if target_point == null:
						target_point = _get_dual_point_nearby()
						point_label = "Dual"
				TacticalRole.Type.FLANKER:
					target_point = _get_objective_point_nearby()
					point_label = "Objetivo"
					if target_point == null:
						target_point = _get_flanker_point_nearby()
						point_label = "Flanqueo"
					if target_point == null:
						target_point = _get_tercer_point_nearby()
						point_label = "Tercercamino"
					if target_point == null:
						target_point = _get_dual_point_nearby()
						point_label = "Dual"

		if target_point != null:
			# ── Si el punto OBJECTIVE tiene un CyanTarget, registrar checkpoint ──
			if target_point.point_type == SemanticPoint.PointType.OBJECTIVE \
					and target_point.secondary_position != Vector3.ZERO:
				_cyan_checkpoint = target_point.secondary_position
				_must_visit_cyan = true
				_debug("Punto OBJETIVO tiene checkpoint celeste en (%.1f, %.1f, %.1f)" % [
					_cyan_checkpoint.x, _cyan_checkpoint.y, _cyan_checkpoint.z])

			_nav_target = target_point.position
			_last_semantic_type = target_point.point_type
			_nav_target_set_time = Time.get_ticks_msec() / 1000.0
			_semantic_path.append(target_point)
			_debug("Punto de %s: navegando a (%.1f, %.1f, %.1f)" % [
				point_label, target_point.position.x,
				target_point.position.y, target_point.position.z])
			_objective_reached = false
		else:
			# Ir directo al core enemigo
			_nav_target = core.global_position
			_last_semantic_type = -1
			_nav_target_set_time = 0.0
			_objective_reached = false

	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))


func _wander() -> void:
	var wander_radius: float = _get_wander_radius()

	if _nav_target == Vector3.ZERO or _is_nav_finished():
		# ── Posición aleatoria en el navmesh ──
		var nav_map_rid: RID
		if navigation and navigation.agent:
			nav_map_rid = navigation.agent.get_navigation_map()
		elif bot and bot.navigation_agent:
			nav_map_rid = bot.navigation_agent.get_navigation_map()
		else:
			nav_map_rid = RID()

		var raw_target: Vector3 = bot.global_position + Vector3(
			randf_range(-wander_radius, wander_radius), 0,
			randf_range(-wander_radius, wander_radius))

		if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
			_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
		else:
			_nav_target = raw_target

	movement_cmd.set_navigate(_nav_target, _role_speed(3.5))


# ══════════════════════════════════════════════════════════════════
# REANUDACIÓN TRAS CONGELAMIENTO
# ══════════════════════════════════════════════════════════════════

## Llamado cuando el congelamiento de 5s termina.
## El bot sigue su rumbo normal en el siguiente execute().
func _resume_after_freeze() -> void:
	_debug("Congelamiento terminado — continuando ruta normal")


# ══════════════════════════════════════════════════════════════════
# PUNTOS DE ASALTO
# ══════════════════════════════════════════════════════════════════

## Busca un punto de asalto (SemanticPoint.PointType.ASSAULT) cercano.
## Solo los bots con rol ASSAULT pueden usarlo.
##
## ▶ Filtra cubos en cooldown (55s).
## ▶ Solo considera puntos que estén ADELANTE (más cerca del core enemigo).
## ▶ 50% de probabilidad de saltar al 2° cubo más cercano (más dinamismo).
##
## Retorna el punto seleccionado, o null si no hay puntos válidos.
func _get_assault_point_nearby() -> SemanticPoint:
	var role: TacticalRole = _get_role()
	if role == null:
		return null

	# Solo bots ASSAULT pueden usar puntos de asalto
	if role.type != TacticalRole.Type.ASSAULT:
		return null

	if not NavigationSystem._semantic_points_loaded:
		NavigationSystem.load_semantic_points()

	# Obtener TODOS los puntos ASSAULT ordenados por distancia (más cercano primero)
	var points: Array[SemanticPoint] = NavigationSystem.get_points_sorted(
		SemanticPoint.PointType.ASSAULT,
		bot.global_position,
		bot.equipo_id,
		99999.0  # Sin límite de distancia
	)
	if points.is_empty():
		return null

	# ── Filtrar: cooldown + solo puntos adelante del bot ──
	var enemy_core: Node = bot._enemy_core if bot else null
	var bot_to_core: float
	if enemy_core and is_instance_valid(enemy_core):
		bot_to_core = bot.global_position.distance_to(enemy_core.global_position)
	else:
		bot_to_core = -1.0  # Sin core, no filtrar por dirección

	var now: float = Time.get_ticks_msec() / 1000.0
	var valid_points: Array[SemanticPoint] = []
	for p in points:
		var key: String = str(p.position)
		# 1) No está en cooldown
		if _semantic_cooldowns.has(key) and _semantic_cooldowns[key] > now:
			continue
		# 2) Está adelante del bot (más cerca del core, o sin core disponible)
		if bot_to_core >= 0.0:
			var p_to_core: float = p.position.distance_to(enemy_core.global_position)
			if p_to_core > bot_to_core + 5.0:  # +5m de tolerancia lateral
				continue
		# 3) El primer paso en la navmesh no debe retroceder del core
		if _requires_backtrack(p.position):
			continue
		valid_points.append(p)

	if valid_points.is_empty():
		return null

	# 50% de probabilidad de saltar al 2° cubo más cercano
	if valid_points.size() >= 2 and randf() < 0.5:
		return valid_points[1]

	return valid_points[0]


## Busca un punto de flanqueo (SemanticPoint.PointType.ALTERNATE) cercano.
## Solo los bots con rol FLANKER pueden usarlo.
##
## ▶ Cooldown + solo adelante + sin backtrack (igual que ASSAULT).
## ▶ Scoring: elige el punto más cercano al bot pero que más se aleje
##   del core aliado (spread_weight). Esto crea rutas envolventes.
## ▶ 50% de probabilidad de saltar al 2° mejor (más dinamismo).
##
## Retorna el punto seleccionado, o null si no hay puntos válidos.
func _get_flanker_point_nearby() -> SemanticPoint:
	var role: TacticalRole = _get_role()
	if role == null:
		return null

	# Solo bots FLANKER pueden usar puntos de flanqueo
	if role.type != TacticalRole.Type.FLANKER:
		return null

	if not NavigationSystem._semantic_points_loaded:
		NavigationSystem.load_semantic_points()

	# Obtener todos los puntos ALTERNATE del mapa
	var points: Array[SemanticPoint] = NavigationSystem.get_points_sorted(
		SemanticPoint.PointType.ALTERNATE,
		bot.global_position,
		bot.equipo_id,
		99999.0
	)
	if points.is_empty():
		return null

	# Referencias a cores
	var enemy_core: Node = bot._enemy_core if bot else null
	var own_core: Node = _get_own_core()

	# Distancia del bot al core enemigo (para filtro "adelante")
	var bot_to_core: float
	if enemy_core and is_instance_valid(enemy_core):
		bot_to_core = bot.global_position.distance_to(enemy_core.global_position)
	else:
		bot_to_core = -1.0

	var now: float = Time.get_ticks_msec() / 1000.0

	# ── 1. Filtrar puntos válidos con scoring ─────────────────────
	# Cada punto recibe un score donde MENOR = MEJOR:
	#   score = distancia_al_bot - spread_weight * distancia_del_core_aliado
	# Esto favorece puntos cercanos al bot pero que también se alejen
	# del core aliado (rutas envolventes).
	var scored: Array[Dictionary] = []

	for p in points:
		var key: String = str(p.position)
		# 1) Cooldown
		if _semantic_cooldowns.has(key) and _semantic_cooldowns[key] > now:
			continue
		# 2) Adelante del bot (más cerca del core enemigo, con tolerancia)
		if bot_to_core >= 0.0:
			var p_to_core: float = p.position.distance_to(enemy_core.global_position)
			if p_to_core > bot_to_core + 5.0:
				continue
		# 3) Sin backtrack en navmesh
		if _requires_backtrack(p.position):
			continue

		# ── Calcular score ──
		var dist_to_bot: float = bot.global_position.distance_to(p.position)
		var dist_from_ally: float = 0.0
		if own_core and is_instance_valid(own_core):
			dist_from_ally = p.position.distance_to(own_core.global_position)

		var sp: float = role.spread_weight
		var score: float = dist_to_bot - sp * dist_from_ally

		scored.append({"point": p, "score": score})

	if scored.is_empty():
		return null

	# ── 2. Ordenar por score ascendente (menor = mejor) ──────────
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.score < b.score
	)

	# ── 3. Elegir el mejor, o el 2° mejor (50% de probabilidad) ──
	if scored.size() >= 2 and randf() < 0.5:
		return scored[1].point

	return scored[0].point


## Busca un punto objetivo (SemanticPoint.PointType.OBJECTIVE) cercano.
## Tanto bots ASSAULT como FLANKER pueden usarlo.
##
## ▶ Cooldown + solo adelante + sin backtrack (igual que ASSAULT).
## ▶ Simple scoring por distancia al bot (igual que ASSAULT).
## ▶ 50% de probabilidad de saltar al 2° mejor (más dinamismo).
##
## Retorna el punto seleccionado, o null si no hay puntos válidos.
func _get_objective_point_nearby() -> SemanticPoint:
	var role: TacticalRole = _get_role()
	if role == null:
		return null

	# Solo bots ASSAULT y FLANKER pueden usar puntos objetivo
	if role.type != TacticalRole.Type.ASSAULT and role.type != TacticalRole.Type.FLANKER:
		return null

	if not NavigationSystem._semantic_points_loaded:
		NavigationSystem.load_semantic_points()

	# Obtener TODOS los puntos OBJECTIVE ordenados por distancia
	var points: Array[SemanticPoint] = NavigationSystem.get_points_sorted(
		SemanticPoint.PointType.OBJECTIVE,
		bot.global_position,
		bot.equipo_id,
		99999.0
	)
	if points.is_empty():
		return null

	# ── Filtrar: cooldown + solo puntos adelante del bot ──
	var enemy_core: Node = bot._enemy_core if bot else null
	var bot_to_core: float
	if enemy_core and is_instance_valid(enemy_core):
		bot_to_core = bot.global_position.distance_to(enemy_core.global_position)
	else:
		bot_to_core = -1.0

	var now: float = Time.get_ticks_msec() / 1000.0
	var valid_points: Array[SemanticPoint] = []
	for p in points:
		var key: String = str(p.position)
		# 1) No está en cooldown
		if _semantic_cooldowns.has(key) and _semantic_cooldowns[key] > now:
			continue
		# 2) Está adelante del bot (más cerca del core, o sin core)
		if bot_to_core >= 0.0:
			var p_to_core: float = p.position.distance_to(enemy_core.global_position)
			if p_to_core > bot_to_core + 5.0:
				continue
		# 3) Sin backtrack en navmesh
		if _requires_backtrack(p.position):
			continue
		valid_points.append(p)

	if valid_points.is_empty():
		return null

	# 50% de probabilidad de saltar al 2° punto más cercano
	if valid_points.size() >= 2 and randf() < 0.5:
		return valid_points[1]

	return valid_points[0]


# ══════════════════════════════════════════════════════════════════
# PUNTOS DUALES
# ══════════════════════════════════════════════════════════════════

## Busca un punto dual (SemanticPoint.PointType.DUAL) cercano.
## Tanto bots ASSAULT como FLANKER pueden usarlo.
##
## ▶ Cooldown de 40s + solo adelante + sin backtrack (igual que ASSAULT).
## ▶ Simple scoring por distancia al bot.
## ▶ 50% de probabilidad de saltar al 2° mejor (más dinamismo).
##
## Retorna el punto seleccionado, o null si no hay puntos válidos.
func _get_dual_point_nearby() -> SemanticPoint:
	var role: TacticalRole = _get_role()
	if role == null:
		return null

	# Solo bots ASSAULT y FLANKER pueden usar puntos duales
	if role.type != TacticalRole.Type.ASSAULT and role.type != TacticalRole.Type.FLANKER:
		return null

	if not NavigationSystem._semantic_points_loaded:
		NavigationSystem.load_semantic_points()

	# Obtener TODOS los puntos DUAL ordenados por distancia
	var points: Array[SemanticPoint] = NavigationSystem.get_points_sorted(
		SemanticPoint.PointType.DUAL,
		bot.global_position,
		bot.equipo_id,
		99999.0
	)
	if points.is_empty():
		return null

	# ── Filtrar: cooldown + solo puntos adelante del bot ──
	var enemy_core: Node = bot._enemy_core if bot else null
	var bot_to_core: float
	if enemy_core and is_instance_valid(enemy_core):
		bot_to_core = bot.global_position.distance_to(enemy_core.global_position)
	else:
		bot_to_core = -1.0

	var now: float = Time.get_ticks_msec() / 1000.0
	var valid_points: Array[SemanticPoint] = []
	for p in points:
		var key: String = str(p.position)
		# 1) No está en cooldown
		if _semantic_cooldowns.has(key) and _semantic_cooldowns[key] > now:
			continue
		# 2) Está adelante del bot (más cerca del core, o sin core disponible)
		if bot_to_core >= 0.0:
			var p_to_core: float = p.position.distance_to(enemy_core.global_position)
			if p_to_core > bot_to_core + 5.0:
				continue
		# 3) Sin backtrack en navmesh
		if _requires_backtrack(p.position):
			continue
		valid_points.append(p)

	if valid_points.is_empty():
		return null

	# 50% de probabilidad de saltar al 2° cubo más cercano
	if valid_points.size() >= 2 and randf() < 0.5:
		return valid_points[1]

	return valid_points[0]


# ══════════════════════════════════════════════════════════════════
# PUNTOS TERCER CAMINO
# ══════════════════════════════════════════════════════════════════

## Busca un punto tercercamino (SemanticPoint.PointType.TERCER) cercano.
## Tanto bots ASSAULT como FLANKER pueden usarlo.
##
## ▶ Cooldown de 55s + solo adelante + sin backtrack (igual que ASSAULT).
## ▶ Simple scoring por distancia al bot (igual que ASSAULT).
## ▶ 50% de probabilidad de saltar al 2° mejor (más dinamismo).
##
## Retorna el punto seleccionado, o null si no hay puntos válidos.
func _get_tercer_point_nearby() -> SemanticPoint:
	var role: TacticalRole = _get_role()
	if role == null:
		return null

	# Solo bots ASSAULT y FLANKER pueden usar puntos tercercamino
	if role.type != TacticalRole.Type.ASSAULT and role.type != TacticalRole.Type.FLANKER:
		return null

	if not NavigationSystem._semantic_points_loaded:
		NavigationSystem.load_semantic_points()

	# Obtener TODOS los puntos TERCER ordenados por distancia
	var points: Array[SemanticPoint] = NavigationSystem.get_points_sorted(
		SemanticPoint.PointType.TERCER,
		bot.global_position,
		bot.equipo_id,
		99999.0
	)
	if points.is_empty():
		return null

	# ── Filtrar: cooldown + solo puntos adelante del bot ──
	var enemy_core: Node = bot._enemy_core if bot else null
	var bot_to_core: float
	if enemy_core and is_instance_valid(enemy_core):
		bot_to_core = bot.global_position.distance_to(enemy_core.global_position)
	else:
		bot_to_core = -1.0

	var now: float = Time.get_ticks_msec() / 1000.0
	var valid_points: Array[SemanticPoint] = []
	for p in points:
		var key: String = str(p.position)
		# 1) No está en cooldown
		if _semantic_cooldowns.has(key) and _semantic_cooldowns[key] > now:
			continue
		# 2) Está adelante del bot (más cerca del core, o sin core disponible)
		if bot_to_core >= 0.0:
			var p_to_core: float = p.position.distance_to(enemy_core.global_position)
			if p_to_core > bot_to_core + 5.0:  # +5m de tolerancia lateral
				continue
		# 3) Sin backtrack en navmesh
		if _requires_backtrack(p.position):
			continue
		valid_points.append(p)

	if valid_points.is_empty():
		return null

	# 50% de probabilidad de saltar al 2° cubo más cercano
	if valid_points.size() >= 2 and randf() < 0.5:
		return valid_points[1]

	return valid_points[0]


# ══════════════════════════════════════════════════════════════════
# COOLDOWN
# ══════════════════════════════════════════════════════════════════

## Registra un punto semántico en cooldown.
## La duración depende del tipo de punto (ASSAULT=55s, TERCER=55s, ALTERNATE=30s, OBJECTIVE=45s, DUAL=40s).
## Mientras esté en cooldown, el bot ignorará ese cubo al buscar el siguiente.
func _add_semantic_cooldown(pos: Vector3, point_type: int) -> void:
	var duration: float = POINT_COOLDOWN.get(point_type, 30.0)
	var now: float = Time.get_ticks_msec() / 1000.0
	var key: String = str(pos)
	_semantic_cooldowns[key] = now + duration
	_debug("Cubo en cooldown por %.0fs: (%.1f, %.1f, %.1f)" % [
		duration, pos.x, pos.y, pos.z])


## Verifica si la navegación hacia `pos` requiere retroceder.
## Si el primer paso del camino en la navmesh se aleja del core enemigo,
## el punto requiere devolverse → debe descartarse.
func _requires_backtrack(pos: Vector3) -> bool:
	var enemy_core: Node = bot._enemy_core if bot else null
	if not enemy_core or not is_instance_valid(enemy_core):
		return false

	var nav_map: RID
	if navigation and navigation.agent:
		nav_map = navigation.agent.get_navigation_map()
	elif bot and bot.navigation_agent:
		nav_map = bot.navigation_agent.get_navigation_map()

	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		return false

	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		nav_map, bot.global_position, pos, true
	)
	if path.size() < 2:
		return false

	# Dirección del primer paso en la navmesh vs dirección al core
	var first_step_dir: Vector3 = (path[1] - path[0]).normalized()
	var to_core_dir: Vector3 = (enemy_core.global_position - bot.global_position).normalized()

	# Si apunta en dirección opuesta al core (< -0.3) → retrocede
	return first_step_dir.dot(to_core_dir) < -0.3


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

func _get_role() -> TacticalRole:
	if bot:
		return bot._tactical_role
	return null

func _get_own_core() -> Node:
	if bot:
		return bot._get_own_core()
	return null

func _dist_to_own_core() -> float:
	if bot:
		return bot._get_dist_to_own_core()
	return 0.0

func _role_speed(base_speed: float) -> float:
	if bot:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed

func _get_wander_radius() -> float:
	var role: TacticalRole = _get_role()
	if not role:
		return 20.0
	match role.movement_profile:
		TacticalRole.MovementProfile.DEFENSIVE:
			return 10.0
		TacticalRole.MovementProfile.AGGRESSIVE:
			return 25.0
		TacticalRole.MovementProfile.FLANKING:
			return 22.0
		TacticalRole.MovementProfile.PATROL:
			return 18.0
		_:
			return 20.0

func _is_nav_finished() -> bool:
	if navigation:
		return navigation.is_navigation_finished()
	if bot and bot.navigation_agent:
		return bot.navigation_agent.is_navigation_finished()
	return true


# ══════════════════════════════════════════════════════════════════
# ÓRDENES DE EQUIPO — FASE 6
# ══════════════════════════════════════════════════════════════════

## Ejecuta la orden actual del bot según TeamAI.
## Retorna true si la orden fue procesada (el bot tiene una orden activa).
##
## ▶ ASALTO y FLANQUEADOR NUNCA defienden: si reciben orden DEFEND o HOLD,
##   las ignoran y se comportan como FREELANCE (avanzan al frente).
func _execute_order() -> bool:
	if not is_instance_valid(TeamAI):
		return false
	if bot == null:
		return false

	var order_data: Dictionary = bot.get_current_order()
	var order_type: int = order_data.get("type", TeamAI.OrderType.FREELANCE)

	# ── Solo DEFENSOR se queda quieto defendiendo.
	#    ASALTO, FLANQUEADOR y PATRULLERO ignoran órdenes defensivas.
	var role: TacticalRole = _get_role()
	if role != null and role.type != TacticalRole.Type.DEFENDER:
		if order_type == TeamAI.OrderType.DEFEND or order_type == TeamAI.OrderType.HOLD:
			order_type = TeamAI.OrderType.FREELANCE

	match order_type:
		TeamAI.OrderType.ATTACK:
			_attack_target()
			return true

		TeamAI.OrderType.DEFEND:
			_defend_position()
			return true

		TeamAI.OrderType.HOLD:
			_execute_hold()
			return true

		TeamAI.OrderType.PATROL:
			_wander()
			return true

		TeamAI.OrderType.RETURN:
			_return_to_base()
			return true

		TeamAI.OrderType.FREELANCE:
			# FREELANCE: el bot decide por sí mismo
			# Continúa con el comportamiento por defecto (wander/core)
			return false

		_:
			return false


## Ejecuta orden ATTACK: navegar hacia el core enemigo.
func _attack_target() -> void:
	if _has_valid_core():
		_advance_to_core()
	else:
		# Si no hay core enemigo, ir hacia la posición de la orden
		var target_pos: Vector3 = bot.get_order_target_position()
		if target_pos != Vector3.ZERO:
			if _nav_target == Vector3.ZERO or _is_nav_finished():
				_nav_target = target_pos
			movement_cmd.set_navigate(_nav_target, _role_speed(5.0))
		else:
			_wander()


## Ejecuta orden DEFEND: patrullar cerca del core propio.
func _defend_position() -> void:
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist_to_base: float = bot.global_position.distance_to(own_core.global_position)
		var defense_range: float = 12.0

		# Si está cerca de la base, patrullar alrededor
		if dist_to_base < defense_range:
			var wander_radius: float = 8.0
			if _nav_target == Vector3.ZERO or _is_nav_finished():
				# Wander aleatorio dentro del radio defensivo
				var raw_target: Vector3 = own_core.global_position + Vector3(
					randf_range(-wander_radius, wander_radius), 0,
					randf_range(-wander_radius, wander_radius))
				var nav_map_rid: RID
				if navigation and navigation.agent:
					nav_map_rid = navigation.agent.get_navigation_map()
				elif bot and bot.navigation_agent:
					nav_map_rid = bot.navigation_agent.get_navigation_map()
				else:
					nav_map_rid = RID()
				if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
					_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
				else:
					_nav_target = raw_target
			movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
		else:
			# Está lejos de la base, regresar
			_nav_target = own_core.global_position
			movement_cmd.set_navigate(_nav_target, _role_speed(5.0))
	else:
		_wander()


## Ejecuta orden HOLD: mantener la posición actual.
func _execute_hold() -> void:
	var order_data: Dictionary = bot.get_current_order()
	var hold_pos: Vector3 = order_data.get("target_position", bot.global_position)

	var dist_to_hold: float = bot.global_position.distance_to(hold_pos)
	if dist_to_hold > 2.0:
		# Volver a la posición de hold
		if _nav_target == Vector3.ZERO:
			_nav_target = hold_pos
		movement_cmd.set_navigate(_nav_target, _role_speed(3.0))
	else:
		# Ya en posición, quieto
		movement_cmd.set_hold()


## Ejecuta orden RETURN: regresar a la base.
func _return_to_base() -> void:
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist: float = bot.global_position.distance_to(own_core.global_position)
		if dist > 4.0:
			_nav_target = own_core.global_position
			movement_cmd.set_navigate(_nav_target, _role_speed(5.5))
		else:
			# Ya en base, quedarse quieto o patrullar
			_wander()
	else:
		_wander()
