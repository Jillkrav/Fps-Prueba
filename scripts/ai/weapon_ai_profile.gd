# scripts/ai/weapon_ai_profile.gd
# Perfil táctico de un arma para la IA.
# Cada arma tiene un .tres con estos datos, cargado en tiempo de ejecución.
extends Resource
class_name WeaponAIProfile

# ─── Propiedades exportadas (seteadas desde los .tres) ────────────────────

@export var weapon_name: String = ""
@export var category: String = ""

@export var ai_rating: float = 0.5
@export var preferred_range_min: float = 0.0
@export var preferred_range_max: float = 50.0
@export var refire_rate: float = 0.5
@export var aim_error_base: float = 2000.0
@export var attack_style_modifier: float = 0.0

@export var lead_target: bool = false
@export var splash_damage: bool = false
@export var is_melee: bool = false
@export var is_instant_hit: bool = false


# ─── Métodos evaluadores ──────────────────────────────────────────────────

## Evalúa el rating táctico del arma en el contexto dado.
## context puede contener: target_distance, bot_health_ratio, ammo_ratio, in_cover.
## Retorna 0.0 (inútil) a 1.0 (óptimo).
func evaluate(context: Dictionary = {}) -> float:
	var rating: float = ai_rating

	# Ajustar por distancia al objetivo
	if context.has("target_distance"):
		var dist: float = context["target_distance"]
		rating *= range_rating(dist)

	# Ajustar por salud del bot
	if context.has("bot_health_ratio"):
		var health_ratio: float = context["bot_health_ratio"]
		if health_ratio < 0.3:
			rating *= 0.6  # Herido -> menos efectivo

	# Ajustar por munición restante
	if context.has("ammo_ratio"):
		var ammo_ratio: float = context["ammo_ratio"]
		if ammo_ratio < 0.2 and not is_melee:
			rating *= 0.4  # Poca munición

	return clampf(rating, 0.0, 1.0)


## Evalúa qué tan adecuada es el arma para una distancia dada.
## Retorna 0.0 (pésimo) a 1.0 (óptimo).
func range_rating(dist: float) -> float:
	if preferred_range_min <= 0 and preferred_range_max >= 999:
		return 1.0

	var mid: float = (preferred_range_min + preferred_range_max) / 2.0
	var half_span: float = max((preferred_range_max - preferred_range_min) / 2.0, 1.0)

	# Campana: a medio rango da 1.0, se degrada hacia los extremos
	var raw: float = 1.0 - abs(dist - mid) / half_span
	return clampf(raw, 0.1, 1.0)


## Sugiere un estilo de ataque según el perfil y contexto.
## Retorna -1.0 (defensivo) a +1.0 (agresivo).
func suggest_attack_style(_context: Dictionary = {}) -> float:
	var base: float = attack_style_modifier

	# Armas cuerpo a cuerpo tienden a ser agresivas
	if is_melee:
		base += 0.3

	# Armas de largo alcance tienden a ser defensivas
	if preferred_range_max > 40.0:
		base -= 0.2

	return clampf(base, -1.0, 1.0)


## Retorna una cadena descriptiva para debug.
func debug_string() -> String:
	return "%s | rating=%.2f | rango=[%.1f, %.1f] | refire=%.2f | aim_err=%.0f | melee=%s | splash=%s" % [
		weapon_name,
		ai_rating,
		preferred_range_min,
		preferred_range_max,
		refire_rate,
		aim_error_base,
		str(is_melee),
		str(splash_damage)
	]
