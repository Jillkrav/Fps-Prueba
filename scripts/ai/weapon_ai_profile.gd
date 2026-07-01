# scripts/ai/weapon_ai_profile.gd
# ──────────────────────────────────────────────────────────────────
# WEAPON AI PROFILE — Resource
#
# Define el perfil táctico de un arma para uso por bots.
# Cada arma tiene UN perfil que describe cómo debe usarla un bot:
# distancias óptimas, estilo de ataque, precisión, etc.
#
# ── USO ──
#   var profile := WeaponAIProfile.new()
#   profile.weapon_name = "USP"
#   profile.preferred_range_min = 5.0
#   profile.preferred_range_max = 25.0
#   ResourceSaver.save(profile, "res://config/ai_profiles/usp.tres")
#
# ── LECTURA ──
#   CombatSystem lee profiles para ajustar puntería
#   WeaponSystem usa profiles para elegir mejor arma
# ──────────────────────────────────────────────────────────────────
extends Resource
class_name WeaponAIProfile

## Nombre del arma (debe coincidir con skill.json y weapon.weapon_name)
@export var weapon_name: String = ""

## Poder general del arma (0.0 - 1.0). Influye en qué tan probable
## es que el bot la elija sobre otras.
@export var ai_rating: float = 0.5

## Distancia mínima óptima en unidades 3D. A menor distancia que
## esta, el arma es menos efectiva.
@export var preferred_range_min: float = 2.0

## Distancia máxima óptima en unidades 3D. A mayor distancia que
## esta, el arma pierde efectividad.
@export var preferred_range_max: float = 30.0

## ¿Tiene daño por área (splash)? Armas como cohetes, granadas.
## Si es true, CombatSystem apunta al suelo cerca del objetivo,
## no directamente a él.
@export var splash_damage: bool = false

## ¿Predecir posición del objetivo? Armas con proyectil lento
## (cohetes, flechas) necesitan lead prediction.
@export var lead_target: bool = true

## Probabilidad de seguir disparando (0.0 - 1.0). Armas de fuego
## rápido tienen alta refire_rate; francotiradores baja.
@export var refire_rate: float = 0.8

## Error base de puntería en milésimas de radian (0 = preciso).
## Se combina con el skill del bot para el error final.
## Valores típicos: 500 (preciso) a 5000 (muy impreciso).
@export var aim_error_base: int = 2000

## Modificador de estilo de ataque (-1.0 a +1.0).
## -1.0: el bot usa esta arma defensivamente (retrocede, cubre)
##  0.0: neutro
## +1.0: el bot usa esta arma agresivamente (carga, persigue)
@export var attack_style_modifier: float = 0.0

## ¿Prefiere usar modo alterno de fuego?
## Ej: lanzagranadas en modo alterno vs disparo directo.
@export var prefers_alt_fire: bool = false

## ¿Es arma cuerpo a cuerpo? Afecta cómo el bot se acerca.
@export var is_melee: bool = false

## ¿Es hit-scan (impacto instantáneo)? false = proyectil.
## Afecta el cálculo de puntería (lead vs directo).
@export var is_instant_hit: bool = true

## Categoría del arma (Pistolas, Escopetas, Subfusiles, etc.)
@export var category: String = ""

# ──────────────────────────────────────────────────────────────────
# MÉTODOS DE EVALUACIÓN
# ──────────────────────────────────────────────────────────────────

## Evalúa qué tan efectiva es esta arma a una distancia dada.
## Retorna 0.0 (pésimo) a 1.0 (óptimo).
func range_rating(target_distance: float) -> float:
	if target_distance <= 0.0:
		return 0.0

	if target_distance < preferred_range_min:
		# Demasiado cerca: penalizar
		var ratio: float = target_distance / max(preferred_range_min, 0.1)
		return max(0.1, ratio * 0.8)

	if target_distance <= preferred_range_max:
		# En rango óptimo
		return 1.0

	# Demasiado lejos: decaimiento suave
	var excess: float = target_distance - preferred_range_max
	var decay: float = exp(-excess / (preferred_range_max * 0.5))
	return max(0.05, decay)


## Evalúa el arma en un contexto completo de combate.
## context puede contener:
##   - target_distance: float
##   - bot_health_ratio: float (0.0 - 1.0)
##   - ammo_ratio: float (0.0 - 1.0)
##   - in_cover: bool
##   - num_enemies: int
## Retorna rating combinado (0.0 - 1.0).
func evaluate(context: Dictionary) -> float:
	var distance: float = context.get("target_distance", 15.0)
	var health_ratio: float = context.get("bot_health_ratio", 1.0)
	var ammo_ratio: float = context.get("ammo_ratio", 1.0)
	var _in_cover: bool = context.get("in_cover", false)

	var rating: float = ai_rating

	# Factor de distancia (el más importante)
	rating *= range_rating(distance)

	# Si el arma es agresiva y el bot está débil, penalizar
	if attack_style_modifier > 0.3 and health_ratio < 0.3:
		rating *= 0.5

	# Si el arma es defensiva y el bot está con mucha salud, ligera penalización
	if attack_style_modifier < -0.3 and health_ratio > 0.8:
		rating *= 0.8

	# Sin munición: inútil
	if ammo_ratio <= 0.0:
		return 0.0

	# Poca munición: penalizar según refire_rate (armas que gastan rápido)
	if ammo_ratio < 0.2 and refire_rate > 0.7:
		rating *= 0.6

	return clamp(rating, 0.0, 1.0)


## Sugiere el estilo de ataque para esta arma en el contexto actual.
## Retorna un valor entre -1.0 (defensivo) y +1.0 (agresivo).
func suggest_attack_style(context: Dictionary) -> float:
	var base_style: float = attack_style_modifier
	var health_ratio: float = context.get("bot_health_ratio", 1.0)

	# Si el bot está muy débil, incluso armas agresivas se usan con cautela
	if health_ratio < 0.25:
		base_style -= 0.5

	# Si el bot está con mucha salud, es más agresivo
	if health_ratio > 0.8:
		base_style += 0.2

	return clamp(base_style, -1.0, 1.0)


## Retorna una descripción textual del perfil para debug.
func debug_string() -> String:
	return "%s | rating=%.2f rango=%.0f-%.0f splash=%s melee=%s" % [
		weapon_name, ai_rating, preferred_range_min, preferred_range_max,
		"sí" if splash_damage else "no",
		"sí" if is_melee else "no"
	]
