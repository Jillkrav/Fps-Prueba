# scripts/tactical_role.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE ROLES TÁCTICOS PARA NPCs
# Inspirado en los bots de Unreal Tournament (UT99).
#
# ── FILOSOFÍA ──
# Una única IA con distintos perfiles de comportamiento.
# Cada rol modifica CÓMO el bot se desplaza y a QUÉ PRIORIZA,
# sin necesidad de crear implementaciones separadas.
#
# ── USO ──
#   var rol = TacticalRole.for_npc(self)       # según Enums.Rol
#   var rol = TacticalRole.create(TacticalRole.Type.ASSAULT)
#
# ── CÓMO EXTENDER ──
# 1. Agrega un valor al enum Type (ej: SNIPER = 4)
# 2. Agrega su configuración en _build_configs()
# 3. Si necesita lógica especial, agrega un método on_*()
#    y documéntalo al final del archivo.
#
# ── EL ARCHIVO ESCALA PORQUE ──
# - Los datos están centralizados en un solo lugar
# - Las decisiones se toman por métodos con nombre claro
# - Agregar un rol nuevo = 1 entrada en el enum + 1 bloque en configs
# - No requiere tocar npc_base.gd a menos que se quieran hooks nuevos
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name TacticalRole


# ══════════════════════════════════════════════════════════════════
# ENUM — TIPOS DE ROL
# ══════════════════════════════════════════════════════════════════
# Agrega aquí nuevos roles. Cada entrada debe tener su configuración
# en _build_configs() más abajo.
# ══════════════════════════════════════════════════════════════════

enum Type {
	DEFENDER   = 0,   # Permanece cerca del núcleo, protege la base
	ASSAULT    = 1,   # Avanza constantemente hacia el objetivo principal
	FLANKER    = 2,   # Prefiere rutas secundarias, ataca por los costados
	PATROLLER  = 3,   # Recorre zonas intermedias, cambia de objetivo seguido
}


# ══════════════════════════════════════════════════════════════════
# PERFIL DE MOVIMIENTO (sub-enum)
# ══════════════════════════════════════════════════════════════════

enum MovementProfile {
	AGGRESSIVE = 0,   # Presiona siempre hacia adelante
	DEFENSIVE  = 1,   # Permanece cerca de zona segura
	FLANKING   = 2,   # Busca ángulos, rutas indirectas
	PATROL     = 3,   # Recorre, cambia de dirección
}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES DE INSTANCIA
# ══════════════════════════════════════════════════════════════════

var type: int
var role_name: String
var display_name: String

# ── Perfil de movimiento ─────────────────────────────────────────
var movement_profile: int

# ── Distancia de combate preferida ───────────────────────────────
# preferred_engagement_min/max: rango ideal de distancia al enemigo.
# El bot intentará mantenerse en este rango durante el combate.
var preferred_engagement_min: float
var preferred_engagement_max: float

# ── Agresividad (0.0 - 1.0) ──────────────────────────────────────
# 0.0 = huye/evita el combate, se retira al recibir daño
# 0.5 = equilibrado, pelea pero sabe retirarse
# 1.0 = persigue hasta la muerte, nunca se retira
var aggression: float

# ── Persistencia de objetivo (segundos) ──────────────────────────
# Tiempo mínimo que el bot mantiene un objetivo antes de reevaluar.
# Bajo (< 2s)  → cambia de objetivo frecuentemente (patrullero)
# Alto (> 6s)  → mantiene el foco en un solo enemigo (defensor)
var target_persistence: float

# ── Radio de defensa de base (unidades) ──────────────────────────
# Distancia máxima desde el core aliado antes de retornar.
# 0.0 = sin límite (el bot va a cualquier lugar)
# > 0 = el bot no se aleja más de esta distancia de su base
var base_defense_radius: float

# ── Sesgo de flanqueo (0.0 - 1.0) ────────────────────────────────
# 0.0 = siempre ruta directa (DIRECT)
# 0.5 = mezcla equilibrada de rutas
# 1.0 = siempre rutas de flanqueo (WIDE_*)
# Esto modifica el RouteType calculado por RouteDiversifier.
var flanking_bias: float

# ── Enfoque en objetivo principal (0.0 - 1.0) ────────────────────
# 0.0 = se distrae con cualquier enemigo cercano
# 0.5 = equilibrado
# 1.0 = ignora combates secundarios, solo va al core
var objective_focus: float

# ── Velocidad de movimiento (multiplicador) ──────────────────────
var speed_multiplier: float

# ── Frecuencia de salto (0.0 - 1.0) ──────────────────────────────
# Probabilidad de saltar durante strafe/bot-blocking.
var jump_frequency: float

# ── Rango de reacción (unidades) ─────────────────────────────────
# Distancia a la que el bot considera un enemigo "cercano" y
# reacciona a él. Útil para defensores que ignoran enemigos lejanos.
var reaction_range: float

# ── Frecuencia de cambio de strafe ───────────────────────────────
# Intervalo en segundos entre cambios de dirección al strafear.
# Menor = más errático, Mayor = más predecible.
var strafe_change_interval: float

# ── Tasa de re-evaluación de ruta ────────────────────────────────
# Cada N segundos, el bot reconsidera si debe cambiar de rumbo.
# Patrulleros tienen tasa alta, defensores tasa baja.
var route_re_eval_rate: float


# ══════════════════════════════════════════════════════════════════
# CONSTRUCTORES
# ══════════════════════════════════════════════════════════════════

## Crea un TacticalRole a partir del enum Enums.Rol (el del proyecto).
## Útil para integrar con el sistema existente de NpcBase.
static func for_npc(bot: Node) -> TacticalRole:
	var rol_val = bot.get("rol")
	var rol: int = rol_val if rol_val != null else Enums.Rol.SOLDADO

	match rol:
		Enums.Rol.SOLDADO:
			# SOLDADO → ASALTO (son los que van al frente)
			return create(Type.ASSAULT)
		Enums.Rol.FRANCOTIRADOR:
			# Francotirador se queda atrás → DEFENSOR (protege/base)
			return create(Type.DEFENDER)
		Enums.Rol.APOYO:
			# APOYO → PATRULLERO (recorre, cubre espacios)
			return create(Type.PATROLLER)
		Enums.Rol.EXPLORADOR:
			# EXPLORADOR → FLANQUEADOR
			return create(Type.FLANKER)
		Enums.Rol.COMANDANTE:
			# COMANDANTE → ASALTO con liderazgo (futuro)
			return create(Type.ASSAULT)
		_:
			return create(Type.ASSAULT)


## Crea un TacticalRole a partir del enum TacticalRole.Type.
static func create(role_type: int) -> TacticalRole:
	var configs: Dictionary = _build_configs()
	var cfg: Dictionary = configs.get(role_type, configs[Type.ASSAULT])

	var role := TacticalRole.new()
	role.type = role_type
	role.role_name = cfg.get("role_name", "unknown")
	role.display_name = cfg.get("display_name", "Desconocido")
	role.movement_profile = cfg.get("movement_profile", MovementProfile.AGGRESSIVE)
	role.preferred_engagement_min = cfg.get("preferred_engagement_min", 5.0)
	role.preferred_engagement_max = cfg.get("preferred_engagement_max", 15.0)
	role.aggression = cfg.get("aggression", 0.5)
	role.target_persistence = cfg.get("target_persistence", 4.0)
	role.base_defense_radius = cfg.get("base_defense_radius", 0.0)
	role.flanking_bias = cfg.get("flanking_bias", 0.0)
	role.objective_focus = cfg.get("objective_focus", 0.3)
	role.speed_multiplier = cfg.get("speed_multiplier", 1.0)
	role.jump_frequency = cfg.get("jump_frequency", 0.0)
	role.reaction_range = cfg.get("reaction_range", 99999.0)
	role.strafe_change_interval = cfg.get("strafe_change_interval", 2.0)
	role.route_re_eval_rate = cfg.get("route_re_eval_rate", 3.0)
	return role


## Crea una copia independiente del rol (útil si quieres modificar
## parámetros en caliente para un bot específico).
func duplicate_role() -> TacticalRole:
	var copy := TacticalRole.new()
	copy.type = type
	copy.role_name = role_name
	copy.display_name = display_name
	copy.movement_profile = movement_profile
	copy.preferred_engagement_min = preferred_engagement_min
	copy.preferred_engagement_max = preferred_engagement_max
	copy.aggression = aggression
	copy.target_persistence = target_persistence
	copy.base_defense_radius = base_defense_radius
	copy.flanking_bias = flanking_bias
	copy.objective_focus = objective_focus
	copy.speed_multiplier = speed_multiplier
	copy.jump_frequency = jump_frequency
	copy.reaction_range = reaction_range
	copy.strafe_change_interval = strafe_change_interval
	copy.route_re_eval_rate = route_re_eval_rate
	return copy


# ══════════════════════════════════════════════════════════════════
# CONFIGURACIÓN CENTRALIZADA DE ROLES
# ══════════════════════════════════════════════════════════════════
# 🔧 EDICIÓN RÁPIDA: Cada bloque es un rol. Cambia los números y
#    el comportamiento se ajusta automáticamente en todos los bots.
#
# 🧩 PARA AGREGAR UN NUEVO ROL:
#    1. Agrega una entrada al enum Type (arriba)
#    2. Agrega un bloque aquí abajo con la key = Type.NUEVO_ROL
#    3. Listo — el resto del sistema lo reconoce automáticamente
# ══════════════════════════════════════════════════════════════════

static func _build_configs() -> Dictionary:
	return {
		# ─────────────────────────────────────────────────────────
		# DEFENSOR
		# ─────────────────────────────────────────────────────────
		# Se queda cerca del core aliado, reacciona a enemigos
		# cercanos, no abandona la base fácilmente.
		# ─────────────────────────────────────────────────────────
		Type.DEFENDER: {
			"role_name": "defender",
			"display_name": "Defensor",

			# Se mueve poco, prioriza posición defensiva
			"movement_profile": MovementProfile.DEFENSIVE,

			# Prefiere distancia media-corta (reacciona a lo cercano)
			"preferred_engagement_min": 3.0,
			"preferred_engagement_max": 12.0,

			# Agresividad media-baja: defiende pero no persigue
			"aggression": 0.35,

			# Mantiene el objetivo el mayor tiempo (no se distrae)
			"target_persistence": 8.0,

			# NO se aleja más de 20 uds del core aliado
			"base_defense_radius": 20.0,

			# Sin sesgo de flanqueo: va directo al enemigo cercano
			"flanking_bias": 0.0,

			# Enfoque medio en objetivo: protege, pero si hay
			# enemigos cerca los prioriza
			"objective_focus": 0.4,

			# Velocidad normal, se mueve con cautela
			"speed_multiplier": 0.9,

			# Salta muy raramente (solo en strafe táctico)
			"jump_frequency": 0.02,

			# Reacciona a enemigos en un radio de 25 uds
			"reaction_range": 25.0,

			# Cambia de dirección lentamente al strafear
			"strafe_change_interval": 3.5,

			# Reevalúa ruta con poca frecuencia
			"route_re_eval_rate": 5.0,
		},

		# ─────────────────────────────────────────────────────────
		# ASALTO FRONTAL
		# ─────────────────────────────────────────────────────────
		# Busca constantemente avanzar hacia el objetivo principal.
		# Agresivo, directo, no se detiene ante combates menores.
		# ─────────────────────────────────────────────────────────
		Type.ASSAULT: {
			"role_name": "assault",
			"display_name": "Asalto",

			"movement_profile": MovementProfile.AGGRESSIVE,

			# Prefiere distancia media (avanza, no se queda atrás)
			"preferred_engagement_min": 5.0,
			"preferred_engagement_max": 18.0,

			# Alta agresividad: persigue y no se retira fácil
			"aggression": 0.75,

			# Persistencia media-alta: no se distrae del core
			"target_persistence": 6.0,

			# Sin límite de base: va a cualquier lado
			"base_defense_radius": 0.0,

			# Sesgo de flanqueo bajo: prefiere ruta directa
			"flanking_bias": 0.2,

			# Alto enfoque en objetivo: prioriza el core
			"objective_focus": 0.8,

			# Velocidad alta: avanza rápido
			"speed_multiplier": 1.15,

			# Salta moderadamente (para sortear obstáculos)
			"jump_frequency": 0.05,

			# Reacciona a enemigos en todo el mapa
			"reaction_range": 99999.0,

			# Cambio de strafe rápido y agresivo
			"strafe_change_interval": 1.5,

			# Reevalúa ruta con frecuencia media
			"route_re_eval_rate": 3.0,
		},

		# ─────────────────────────────────────────────────────────
		# FLANQUEADOR
		# ─────────────────────────────────────────────────────────
		# Prefiere rutas secundarias. Busca atacar por los costados
		# o la retaguardia enemiga. No le gusta el frente directo.
		# ─────────────────────────────────────────────────────────
		Type.FLANKER: {
			"role_name": "flanker",
			"display_name": "Flanqueador",

			"movement_profile": MovementProfile.FLANKING,

			# Prefiere distancia media-corta (golpear rápido)
			"preferred_engagement_min": 3.0,
			"preferred_engagement_max": 12.0,

			# Agresividad media-alta: ataca pero con inteligencia
			"aggression": 0.65,

			# Persistencia media: busca el momento oportuno
			"target_persistence": 4.0,

			# Sin límite de base (está en territorio enemigo)
			"base_defense_radius": 0.0,

			# Alto sesgo de flanqueo: SIEMPRE busca rutas laterales
			"flanking_bias": 0.9,

			# Enfoque medio-alto: va al core pero ataca lo que
			# encuentra en el camino
			"objective_focus": 0.6,

			# Velocidad alta (golpea y se mueve)
			"speed_multiplier": 1.2,

			# Salta mucho (busca ángulos, es evasivo)
			"jump_frequency": 0.08,

			# Reacciona a enemigos en todo el mapa
			"reaction_range": 99999.0,

			# Cambio de strafe muy rápido (errático, impredecible)
			"strafe_change_interval": 1.0,

			# Reevalúa ruta constantemente (busca el mejor ángulo)
			"route_re_eval_rate": 2.0,
		},

		# ─────────────────────────────────────────────────────────
		# PATRULLERO
		# ─────────────────────────────────────────────────────────
		# Recorre zonas intermedias entre bases. Cambia de objetivo
		# con frecuencia. Es el explorador / guardia de medio mapa.
		# ─────────────────────────────────────────────────────────
		Type.PATROLLER: {
			"role_name": "patroller",
			"display_name": "Patrullero",

			"movement_profile": MovementProfile.PATROL,

			# Prefiere distancia media (ni muy cerca ni muy lejos)
			"preferred_engagement_min": 6.0,
			"preferred_engagement_max": 20.0,

			# Agresividad media: pelea si encuentra, pero no persigue
			"aggression": 0.5,

			# Baja persistencia: cambia de objetivo constantemente
			"target_persistence": 2.5,

			# Radio de defensa amplio pero existe: patrulla la zona
			# media, no llega hasta base enemiga
			"base_defense_radius": 40.0,

			# Sesgo de flanqueo medio: a veces directo, a veces no
			"flanking_bias": 0.4,

			# Bajo enfoque en objetivo: se distrae fácilmente
			"objective_focus": 0.2,

			# Velocidad normal-constante: trote de patrulla
			"speed_multiplier": 1.0,

			# Salta ocasionalmente
			"jump_frequency": 0.03,

			# Reacciona a enemigos en un radio amplio
			"reaction_range": 35.0,

			# Cambio de strafe medio
			"strafe_change_interval": 2.5,

			# Reevalúa ruta con frecuencia alta (explora)
			"route_re_eval_rate": 2.5,
		},
	}


# ══════════════════════════════════════════════════════════════════
# MÉTODOS DE DECISIÓN
# ══════════════════════════════════════════════════════════════════
# Estos métodos traducen los perfiles en decisiones concretas.
# Se llaman desde npc_base.gd para modificar el comportamiento sin
# tocar la lógica de la FSM.
# ══════════════════════════════════════════════════════════════════

## ¿El bot debe perseguir a este enemigo o ignorarlo?
## Se basa en aggression, reaction_range y objective_focus.
func should_engage_enemy(
	bot_pos: Vector3,
	enemy_pos: Vector3,
	enemy_is_near_core: bool,
	dist_to_own_core: float
) -> bool:
	var dist_to_enemy: float = bot_pos.distance_to(enemy_pos)

	# Si el enemigo está fuera del rango de reacción, ignorar
	if dist_to_enemy > reaction_range:
		return false

	# Defensores: si el enemigo está lejos del core aliado, mejor
	# no perseguirlo
	if base_defense_radius > 0.0 and dist_to_own_core > base_defense_radius * 0.7:
		# Estamos cerca del límite defensivo — solo pelear si el
		# enemigo está muy cerca
		if dist_to_enemy > 10.0:
			return false

	# Si el enemigo está cerca del core enemigo y tenemos alto
	# objective_focus, priorizamos el core (no nos distraemos)
	if objective_focus > 0.6 and enemy_is_near_core and dist_to_enemy > preferred_engagement_max:
		return false

	# Regla base: aggression determina la probabilidad de pelear
	return randf() < aggression + 0.2


## ¿El bot debe retirarse de este combate?
## Útil para defensores que no deben alejarse de la base,
## o para cualquier bot con poca vida.
func should_retreat(
	health_pct: float,
	dist_to_own_core: float,
	has_base_defense: bool
) -> bool:
	# Si tiene radio defensivo y está muy lejos de la base
	if has_base_defense and base_defense_radius > 0.0:
		if dist_to_own_core > base_defense_radius:
			return true

	# Si la vida es muy baja y no es muy agresivo, retirarse
	if health_pct < 0.2 and aggression < 0.7:
		return true

	return false


## ¿El bot debe reevaluar su objetivo actual?
## Cuanto menor target_persistence, más seguido cambia.
func should_switch_target(time_on_target: float) -> bool:
	return time_on_target >= target_persistence


## Devuelve un multiplicador para la velocidad de movimiento
## según el perfil y la situación.
func get_speed_for_state(_current_state: int) -> float:
	return speed_multiplier


## ¿Debe priorizar la ruta directa o flanqueo?
## Retorna true si debe usar ruta de flanqueo (WIDE_*).
func prefers_flanking_route() -> bool:
	return randf() < flanking_bias


## Devuelve el RouteType preferido, modulado por flanking_bias.
## Útil para override del RouteDiversifier.
func get_preferred_route_type(base_route_type: int) -> int:
	if prefers_flanking_route():
		# Elegir entre LEFT, RIGHT, WIDE_LEFT, WIDE_RIGHT
		var flank_routes: Array[int] = [
			RouteDiversifier.RouteType.LEFT,
			RouteDiversifier.RouteType.RIGHT,
			RouteDiversifier.RouteType.WIDE_LEFT,
			RouteDiversifier.RouteType.WIDE_RIGHT,
		]
		return flank_routes[randi() % flank_routes.size()]
	else:
		# Si no flanquea, posiblemente DIRECT
		if randf() < 0.5:
			return RouteDiversifier.RouteType.DIRECT
		return base_route_type


## Devuelve un puntaje de prioridad para un enemigo candidato.
## El score más alto = más probable que el bot lo ataque.
## Se usa en _update_perception para filtrar/ordenar objetivos.
func score_enemy_priority(
	_enemy: Node3D,
	dist_to_enemy: float,
	_dist_to_own_core: float,
	_is_core_defender: bool,
	enemy_health_pct: float
) -> float:
	var score: float = 0.0

	# ── Defensor: prioriza enemigos CERCANOS a la base ──
	if movement_profile == MovementProfile.DEFENSIVE:
		# Mientras más cerca de nuestra base, mayor prioridad
		score += max(0.0, 100.0 - dist_to_enemy * 2.0)
		# Bonus extra si está muy cerca del core
		if dist_to_enemy < 10.0:
			score += 50.0
		return score

	# ── Asalto: prioriza enemigos cercanos al CORE ENEMIGO ──
	if movement_profile == MovementProfile.AGGRESSIVE:
		# Bonus por distancia al core enemigo (mientras más lejos,
		# menos importante)
		score += max(0.0, 100.0 - dist_to_enemy)
		# Prioriza enemigos con poca vida (rematarlos)
		score += (1.0 - enemy_health_pct) * 30.0
		return score

	# ── Flanqueador: prioriza enemigos AISLADOS o distraídos ──
	if movement_profile == MovementProfile.FLANKING:
		# Puntaje base por cercanía
		score += max(0.0, 100.0 - dist_to_enemy)
		# Bonus si el enemigo está lejos de su base (está aislado)
		score += 20.0
		return score

	# ── Patrullero: puntaje casi aleatorio con sesgo a cercanía ──
	score += max(0.0, 80.0 - dist_to_enemy * 1.5)
	score += randf() * 20.0  # Componente aleatorio para variar
	return score


## Devuelve true si el bot debe priorizar el core sobre los enemigos.
func should_prioritize_core(
	_dist_to_enemy_core: float,
	enemies_nearby: bool
) -> bool:
	if objective_focus > 0.7:
		# Alta prioridad: va al core incluso con enemigos cerca
		return true
	if objective_focus > 0.4 and not enemies_nearby:
		# Prioridad media: va al core si no hay enemigos cerca
		return true
	return false


## ¿Este bot puede abandonar la base?
## false = el bot no se moverá más allá de su radio defensivo.
func can_leave_base(dist_to_own_core: float) -> bool:
	if base_defense_radius <= 0.0:
		return true
	return dist_to_own_core < base_defense_radius


## Devuelve una posición de "retirada" hacia la base.
func get_fallback_position(own_core_pos: Vector3, bot_pos: Vector3) -> Vector3:
	if base_defense_radius > 0.0:
		# Caer hacia una posición dentro del radio defensivo
		var dir_to_core: Vector3 = (own_core_pos - bot_pos).normalized()
		return bot_pos + dir_to_core * min(5.0, base_defense_radius * 0.3)
	return own_core_pos


## ¿El bot debe priorizar recoger un pickup antes que el objetivo?
func should_pickup_instead_of_objective(
	health_pct: float,
	ammo_pct: float
) -> bool:
	# Defensores priorizan recoger items cerca de base
	if movement_profile == MovementProfile.DEFENSIVE:
		return health_pct < 0.6 or ammo_pct < 0.3

	# Asalto ignora pickups si tiene salud/municion suficiente
	if movement_profile == MovementProfile.AGGRESSIVE:
		return health_pct < 0.3 or ammo_pct < 0.15

	# Flanqueadores recogen lo que encuentran
	if movement_profile == MovementProfile.FLANKING:
		return health_pct < 0.5 or ammo_pct < 0.3

	# Patrulleros recogen siempre (están en el medio)
	return health_pct < 0.7 or ammo_pct < 0.4


## Devuelve una descripción legible del perfil de movimiento.
func movement_profile_name() -> String:
	match movement_profile:
		MovementProfile.AGGRESSIVE:
			return "Agresivo"
		MovementProfile.DEFENSIVE:
			return "Defensivo"
		MovementProfile.FLANKING:
			return "Flanqueo"
		MovementProfile.PATROL:
			return "Patrulla"
		_:
			return "Desconocido"


## Debug: imprime la configuración completa del rol.
func debug_string() -> String:
	return (
		"[%s] Perfil=%s | Rango=%.0f-%.0f | Agres=%.2f | Persist=%.1fs | " +
		"DefRad=%.0f | FlankBias=%.2f | ObjFocus=%.2f | Speed=%.2f | Salto=%.2f"
	) % [
		display_name,
		movement_profile_name(),
		preferred_engagement_min,
		preferred_engagement_max,
		aggression,
		target_persistence,
		base_defense_radius,
		flanking_bias,
		objective_focus,
		speed_multiplier,
		jump_frequency,
	]
