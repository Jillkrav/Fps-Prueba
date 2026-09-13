@tool
class_name TiradorConfig
extends Resource

## Configuración especial del soldado armado de Historia (Tirador).
##
## Este archivo es el punto de extensión del NPC con armas. Todo lo que no sea
## "stat básico" se configura aquí, de modo que el diseñador pueda crear
## variantes de soldado SIN tocar código: un soldado que lanza granadas, otro
## que se cubre al recibir daño, otro más agresivo, etc.
##
## Un .tres de este recurso se asigna en el Inspector del SDK o del Spawner
## (export `tirador_config`). También se puede construir en runtime
## (TiradorConfig.new()) para oleadas procedurales.
##
## ── Integraciones previstas (ampliar aquí en el futuro) ──
##   * Lanzar granadas SIN cambiar de arma (solo ocasional).
##   * Tomar cobertura al recibir mucho daño, compatible con los props
##     one_way_low_wall (que exponen CoverPoint en el grupo "cover_points").
##   * (Futuro) supresión, suministro, órdenes, etc.

## Personalidad de combate (ver export en la categoría "Combate").
enum Personality {
    CAUTELOSO,
    ESTANDAR,
    AGRESIVO,
}

## Multiplicadores EN VIVO por personalidad (no mutan nada: se aplican al
## leer el valor). Índice = Personality.
const PERSONALITY_COVER_THRESHOLD: Array[float] = [1.5, 1.0, 0.7]
const PERSONALITY_RANGE_SCALE: Array[float] = [1.2, 1.0, 0.8]
const PERSONALITY_STRAFE_INTERVAL: Array[float] = [0.8, 1.0, 1.3]
const PERSONALITY_GRENADE_CHANCE: Array[float] = [1.5, 1.0, 0.7]
const PERSONALITY_REACTION_TIME: Array[float] = [1.25, 1.0, 0.9]


@export_category("Combate")
## Personalidad de combate (multiplicadores EN VIVO sobre los valores de esta
## config: nunca pisan lo que edites en el Inspector).
##   CAUTELOSO: busca cobertura antes, pelea más lejos, se mueve más al
##              disparar, granadea más y reacciona más lento.
##   AGRESIVO : lo contrario: se arrima, aguanta más sin cubrirse y dispara
##              antes.
@export var combat_personality: Personality = Personality.ESTANDAR
## Rango de combate preferido MÍNIMO. -1 = usar el del perfil AI del arma
## (preferred_range_min del .tres de ai_profiles).
@export_range(-1.0, 200.0, 0.5) var custom_engage_range_min: float = -1.0
## Rango de combate preferido MÁXIMO. -1 = usar el del perfil AI del arma.
@export_range(-1.0, 200.0, 0.5) var custom_engage_range_max: float = -1.0
## Precisión (0.0 a 1.0): cuánto se desvía la puntería del soldado. 1.0 = tiro
## perfecto al torso; valores bajos hacen fallar más. El spread del arma aplica
## encima.
@export_range(0.0, 1.0, 0.01) var fire_accuracy: float = 0.82
## Tiempo de reacción al adquirir un objetivo nuevo (espera antes del 1er tiro).
@export_range(0.0, 2.0, 0.05) var reaction_time: float = 0.12

@export_category("Granadas")
## Si true, el soldado lanza granadas de vez en cuando SIN cambiar de arma.
@export var can_throw_grenades: bool = true
## Nombre del arma arrojadiza que usa para lanzar. Menú desplegable (skill.json).
var grenade_weapon_name: String = "Granada"
## Probabilidad por comprobación (0..1) de lanzar una granada cuando está
## en rango, con el enfriamiento listo y hay línea de visión.
@export_range(0.0, 1.0, 0.05) var grenade_chance: float = 0.3
## Segundos entre lanzamientos (enfriamiento).
@export_range(0.0, 60.0, 0.5) var grenade_cooldown: float = 9.0
## Distancia mínima al objetivo para lanzar (no granadearse a sí mismo).
@export_range(0.0, 30.0, 0.5) var grenade_min_distance: float = 6.0
## Distancia máxima al objetivo para lanzar.
@export_range(1.0, 80.0, 0.5) var grenade_max_distance: float = 28.0
## Granada ANTI-COBERTURA: si el enemigo acaba de perderse de vista y su
## última posición conocida está junto a una cobertura (CoverPoint),
## probabilidad de granadear esa posición para sacarlo.
@export var grenade_anti_cover_enabled: bool = true
## Probabilidad por comprobación de la granada anti-cobertura.
@export_range(0.0, 1.0, 0.05) var grenade_anti_cover_chance: float = 0.35
## Segundos tras perderlo de vista en los que se considera que "acaba de
## cubrirse" (más tiempo = el enemigo ya se movió de la cobertura).
@export_range(0.1, 5.0, 0.1) var grenade_anti_cover_delay: float = 1.2
## Distancia (m) máxima entre la última posición conocida y un CoverPoint
## para que cuente como "se ha puesto a cubierto".
@export_range(0.5, 10.0, 0.25) var grenade_anti_cover_near_distance: float = 3.0
## Radio que se reserva alrededor del impacto previsto: se rechaza el lanzamiento
## si un aliado o el propio lanzador quedaría dentro de esta zona.
@export_range(1.0, 20.0, 0.5) var grenade_safety_radius: float = 5.0

@export_category("Cobertura")
## Si true, el soldado busca cobertura (CoverPoint) cuando recibe mucho daño.
## Funciona con los props de "Muro bajo" (one_way_low_wall), que exponen
## CoverPoint en el grupo "cover_points".
@export var can_take_cover: bool = true
## Buscar cobertura también por FUEGO RECIBIDO SOSTENIDO (además de por vida
## baja): tras recibir cover_fire_hit_count impactos en menos de
## cover_fire_time_window segundos.
@export var cover_on_sustained_fire: bool = true
## Impactos recibidos (en la ventana) que activan la búsqueda de cobertura.
@export_range(1, 20, 1) var cover_fire_hit_count: int = 3
## Ventana de tiempo (s) en la que se cuentan esos impactos.
@export_range(0.5, 10.0, 0.25) var cover_fire_time_window: float = 3.0
## Segundos tras salir de cobertura antes de poder volver a entrar por fuego.
@export_range(0.0, 30.0, 0.5) var cover_recover_delay: float = 5.0
## Fracción de salud por debajo de la cual empieza a buscar cobertura (0.45 = 45%).
@export_range(0.01, 1.0, 0.01) var cover_health_threshold: float = 0.45
## Radio en el que busca puntos de cobertura cercanos.
@export_range(1.0, 60.0, 0.5) var cover_search_radius: float = 14.0
## Mínimo (s) del tiempo ALEATORIO que permanece cubierto: al agotarse sale.
@export_range(1.0, 30.0, 0.5) var cover_max_time_min: float = 7.0
## Máximo (s) del tiempo ALEATORIO que permanece cubierto: al agotarse sale.
@export_range(1.0, 30.0, 0.5) var cover_max_time_max: float = 10.0
## Fracción de vida máxima que se regenera POR SEGUNDO mientras está cubierto
## (0.05 = 5% por segundo).
@export_range(0.0, 1.0, 0.01) var cover_heal_per_second: float = 0.05
## Si true, dispara al objetivo mientras está cubierto (peek) cuando hay línea
## de visión desde la cobertura.
@export var cover_fire_while_covering: bool = true
## Si recibe daño desde una dirección que la cobertura no bloquea, abandona la
## reserva y vuelve a evaluar otra cobertura. 0 desactiva la regla.
@export_range(0.0, 10000.0, 0.5) var cover_invalidation_damage: float = 18.0

@export_category("Cuerpo a cuerpo")
## Si true y el objetivo entra en attack_range, el soldado usa su golpe cuerpo
## a cuerpo (melee_damage) en vez de seguir disparando a quemarropa.
@export var melee_fallback_enabled: bool = true


## Menú desplegable data-driven para el arma arrojadiza (skill.json).
func _get_property_list() -> Array[Dictionary]:
    return [{
        "name": "grenade_weapon_name",
        "type": TYPE_STRING,
        "hint": PROPERTY_HINT_ENUM,
        "hint_string": StoryDataCatalog.weapon_hint(),
        "usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
    }]


func _get(property: StringName) -> Variant:
    if property == &"grenade_weapon_name":
        return grenade_weapon_name
    return null


func _set(property: StringName, value: Variant) -> bool:
    if property == &"grenade_weapon_name":
        grenade_weapon_name = str(value)
        return true
    return false


## ── Valores EFECTIVOS (personalidad × dificultad, EN VIVO) ──────────────
## Nunca mutan los campos editables: el Tirador lee por estos getters y la
## personalidad/dificultad actúan como multiplicadores transparentes.
## Composición final: valor base × personalidad × dificultad global
## (autoload StoryDifficulty). El parámetro difficulty_mult permite tests
## deterministas (-1 = leer la dificultad global real).

## Umbral de vida para buscar cobertura, ajustado por personalidad y
## dificultad.
func effective_cover_health_threshold(difficulty_mult: float = -1.0) -> float:
    var value: float = cover_health_threshold * PERSONALITY_COVER_THRESHOLD[combat_personality]
    return value * _difficulty_mult(difficulty_mult, &"cover_threshold")


## Tiempo de reacción al adquirir objetivo, ajustado por personalidad y
## dificultad.
func effective_reaction_time(difficulty_mult: float = -1.0) -> float:
    var value: float = reaction_time * PERSONALITY_REACTION_TIME[combat_personality]
    return value * _difficulty_mult(difficulty_mult, &"reaction")


## Probabilidad de granada por comprobación, ajustada por personalidad.
func effective_grenade_chance() -> float:
    return grenade_chance * PERSONALITY_GRENADE_CHANCE[combat_personality]


## Escala del rango preferido del arma (1.2 = pelea más lejos), por personalidad.
func effective_range_scale() -> float:
    return PERSONALITY_RANGE_SCALE[combat_personality]


## Escala del intervalo de strafe (0.8 = cambia de lado más a menudo).
func effective_strafe_interval_scale() -> float:
    return PERSONALITY_STRAFE_INTERVAL[combat_personality]


## Multiplicador de dificultad explícito (tests) o el global en vivo.
func _difficulty_mult(explicit: float, key: StringName) -> float:
    if explicit >= 0.0:
        return explicit
    var manager: StoryDifficulty = StoryDifficulty.get_manager()
    if manager == null:
        return 1.0
    match key:
        &"cover_threshold":
            return manager.cover_threshold_multiplier()
        &"reaction":
            return manager.reaction_multiplier()
    return 1.0
