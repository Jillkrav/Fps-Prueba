# scripts/ai/weapon_system.gd
# ──────────────────────────────────────────────────────────────────
# WEAPON SYSTEM — FASE 5 REFACTORIZACIÓN
#
# Gestor de armas para bots. Administra el estado del arma actual,
# la selección táctica basada en perfiles AI, y la recarga.
#
# ── PROPIETARIO DE (solo él escribe) ──
#   weapon_status (Dictionary)
#   ammo_count (int)
#   reserve_ammo (int)
#   current_weapon (Weapon)
#   available_weapons (Array[Weapon])
#
# ── LECTURA DE ──
#   fire_request (de DecisionSystem / CombatCommand)
#   Enemy distance (de CombatSystem / PerceptionSystem)
#
# ── NUNCA ESCRIBE ──
#   velocity, target_entity, movement_command, combat_command
# ──────────────────────────────────────────────────────────────────
extends Node
class_name WeaponSystem


# ══════════════════════════════════════════════════════════════════
# SEÑALES
# ══════════════════════════════════════════════════════════════════

## El arma está lista para disparar.
signal weapon_ready()

## El arma se quedó sin munición.
signal weapon_empty()

## Se inició una recarga.
signal reload_started(duration: float)

## Recarga completada.
signal reload_completed()

## Cambió la munición (actual, reserva).
signal ammo_changed(current: int, reserve: int)

## Se cambió de arma (nombre, rating).
signal weapon_switched(weapon_name: String, rating: float)

## Se emite cuando el bot debería considerar cambiar de arma.
## DecisionSystem escucha esto para evaluar alternativas.
signal suggest_weapon_switch(reason: String)


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Ruta base donde se guardan los perfiles AI de armas.
const AI_PROFILES_DIR: String = "res://config/ai_profiles/"


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES — PROPIETARIO
# ══════════════════════════════════════════════════════════════════

## Arma actualmente equipada.
var current_weapon: Weapon = null

## Armas disponibles (actualmente el bot solo tiene una).
## En el futuro, el bot podría tener un inventario múltiple.
var available_weapons: Array[Weapon] = []

## Estado del arma actual como diccionario legible por otros sistemas.
var weapon_status: Dictionary = {}

## Munición actual en el cargador.
var ammo_count: int = 0

## Munición en reserva.
var reserve_ammo: int = 0

## Perfiles AI cargados (nombre_arma → WeaponAIProfile).
var ai_profiles: Dictionary = {}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES — INTERNAS
# ══════════════════════════════════════════════════════════════════

var bot: NpcBase = null

## Temporizador interno para chequeo periódico de cambio de arma.
var _switch_check_timer: float = 0.0

## Distancia al enemigo en el último chequeo (caché).
var _last_enemy_distance: float = 0.0

## ¿Está en medio de una recarga?
var _is_reloading: bool = false


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	bot = get_parent() as NpcBase
	_preload_ai_profiles()
	_debug_ws("WeaponSystem listo (%d perfiles cargados)" % ai_profiles.size())


## Procesa el estado del arma cada frame.
## Llamar desde NpcBase._physics_process().
func process(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	if current_weapon == null or not is_instance_valid(current_weapon):
		return

	# Actualizar estado del arma
	_update_weapon_status()

	# Verificar recarga automática si está vacío y no recargando
	if current_weapon.ammo_in_mag <= 0 and current_weapon.reserve_ammo > 0 and not _is_reloading:
		_start_reload()

	# Chequeo periódico de cambio de arma
	_switch_check_timer += delta
	if _switch_check_timer >= 2.0:
		_switch_check_timer = 0.0
		_evaluate_weapon_switch()


# ══════════════════════════════════════════════════════════════════
# GESTIÓN DE ARMAS
# ══════════════════════════════════════════════════════════════════

## Registra un arma como disponible. Si es la primera, la equipa.
func register_weapon(weapon: Weapon) -> void:
	if weapon == null:
		return
	if weapon in available_weapons:
		return

	available_weapons.append(weapon)
	_debug_ws("Arma registrada: %s" % weapon.weapon_name)

	# Cargar perfil AI si no está ya
	_load_profile_for(weapon)

	# Si no hay arma actual, equipar esta
	if current_weapon == null:
		_equip_weapon(weapon)


## Equipa un arma como la activa.
func _equip_weapon(weapon: Weapon) -> void:
	if current_weapon == weapon:
		return

	current_weapon = weapon
	ammo_count = weapon.ammo_in_mag
	reserve_ammo = weapon.reserve_ammo
	_update_weapon_status()
	ammo_changed.emit(ammo_count, reserve_ammo)

	var rating: float = _get_weapon_rating(weapon)
	weapon_switched.emit(weapon.weapon_name, rating)
	_debug_ws("Arma equipada: %s (rating AI: %.2f)" % [weapon.weapon_name, rating])


## Elimina un arma del inventario.
func unregister_weapon(weapon: Weapon) -> void:
	available_weapons.erase(weapon)
	if current_weapon == weapon:
		current_weapon = null
		# Equipar la primera disponible si queda alguna
		if available_weapons.size() > 0:
			_equip_weapon(available_weapons[0])


## Reemplaza el arma actual con una nueva (recogida del suelo).
func replace_weapon(new_weapon: Weapon) -> void:
	# Si ya teníamos un arma, desregistrarla
	if current_weapon and is_instance_valid(current_weapon):
		unregister_weapon(current_weapon)

	register_weapon(new_weapon)


# ══════════════════════════════════════════════════════════════════
# SELECCIÓN TÁCTICA DE ARMAS
# ══════════════════════════════════════════════════════════════════

## Evalúa todas las armas disponibles y retorna la mejor
## para la distancia y contexto dados.
func get_best_weapon_for(target_distance: float, context: Dictionary = {}) -> Weapon:
	if available_weapons.size() == 0:
		return current_weapon
	if available_weapons.size() == 1:
		return available_weapons[0]

	var best_weapon: Weapon = available_weapons[0]
	var best_rating: float = -1.0

	var eval_context: Dictionary = context.duplicate()
	eval_context["target_distance"] = target_distance
	if bot:
		eval_context["bot_health_ratio"] = bot.current_health / max(bot.max_health, 1.0)

	for weapon in available_weapons:
		var rating: float = _get_weapon_rating(weapon, eval_context)
		if rating > best_rating:
			best_rating = rating
			best_weapon = weapon

	return best_weapon


## Retorna el rating combinado de un arma en el contexto actual.
func _get_weapon_rating(weapon: Weapon, context: Dictionary = {}) -> float:
	var profile: WeaponAIProfile = ai_profiles.get(weapon.weapon_name)
	if profile == null:
		return 0.3  # Rating por defecto bajo

	var eval_context: Dictionary = context.duplicate()
	if not eval_context.has("target_distance"):
		eval_context["target_distance"] = _last_enemy_distance
	if bot and not eval_context.has("bot_health_ratio"):
		eval_context["bot_health_ratio"] = bot.current_health / max(bot.max_health, 1.0)
	if not eval_context.has("ammo_ratio"):
		var total_ammo: int = weapon.ammo_in_mag + weapon.reserve_ammo
		var max_total: int = weapon.clip_size + weapon.max_ammo
		eval_context["ammo_ratio"] = float(total_ammo) / float(max(max_total, 1))

	return profile.evaluate(eval_context)


## Chequea periódicamente si debe cambiar de arma.
func _evaluate_weapon_switch() -> void:
	if available_weapons.size() <= 1:
		return
	if current_weapon == null:
		return

	# Evaluar el arma actual vs la mejor opción
	var current_rating: float = _get_weapon_rating(current_weapon)
	var best_weapon: Weapon = get_best_weapon_for(_last_enemy_distance)
	var best_rating: float = _get_weapon_rating(best_weapon)

	# Si hay una opción significativamente mejor (>20% mejor), sugerir cambio
	if best_weapon != current_weapon and best_rating > current_rating * 1.2:
		suggest_weapon_switch.emit(
			"Mejor opción: %s (%.2f vs actual %.2f)" % [best_weapon.weapon_name, best_rating, current_rating]
		)
		_debug_ws("Sugiere cambio: %s → %s (rating: %.2f → %.2f)" % [
			current_weapon.weapon_name, best_weapon.weapon_name,
			current_rating, best_rating
		])


## Actualiza la distancia al enemigo para evaluaciones.
func update_enemy_distance(distance: float) -> void:
	_last_enemy_distance = distance


## Obtiene el perfil AI del arma actual.
func get_current_profile() -> WeaponAIProfile:
	if current_weapon == null:
		return null
	return ai_profiles.get(current_weapon.weapon_name)


## Obtiene el perfil AI de un arma por nombre.
func get_profile_for(weapon_name: String) -> WeaponAIProfile:
	return ai_profiles.get(weapon_name)


# ══════════════════════════════════════════════════════════════════
# RECARGA
# ══════════════════════════════════════════════════════════════════

func _start_reload() -> void:
	if current_weapon == null or _is_reloading:
		return
	if current_weapon.reserve_ammo <= 0:
		return

	_is_reloading = true
	reload_started.emit(current_weapon.reload_time)
	current_weapon.start_reload()

	# Conectar señal de recarga completada (one-shot)
	if current_weapon.reload_completed.is_connected(_on_reload_completed):
		current_weapon.reload_completed.disconnect(_on_reload_completed)
	current_weapon.reload_completed.connect(_on_reload_completed, CONNECT_ONE_SHOT)


func _on_reload_completed() -> void:
	_is_reloading = false
	ammo_count = current_weapon.ammo_in_mag if current_weapon else 0
	reserve_ammo = current_weapon.reserve_ammo if current_weapon else 0
	_update_weapon_status()
	reload_completed.emit()
	weapon_ready.emit()


# ══════════════════════════════════════════════════════════════════
# ESTADO
# ══════════════════════════════════════════════════════════════════

## Actualiza el diccionario de estado del arma para otros sistemas.
func _update_weapon_status() -> void:
	if current_weapon == null:
		weapon_status = {}
		ammo_count = 0
		reserve_ammo = 0
		return

	var prev_ammo: int = ammo_count
	var prev_reserve: int = reserve_ammo

	weapon_status = {
		"name": current_weapon.weapon_name,
		"ammo": current_weapon.ammo_in_mag,
		"reserve": current_weapon.reserve_ammo,
		"clip_size": current_weapon.clip_size,
		"max_ammo": current_weapon.max_ammo,
		"is_reloading": _is_reloading,
		"can_fire": current_weapon.can_fire(),
		"damage": current_weapon.damage_vs_npc,
		"spread": current_weapon.spread,
		"range": current_weapon.weapon_range,
	}

	# Emitir señal si la munición cambió
	if ammo_count != prev_ammo or reserve_ammo != prev_reserve:
		ammo_changed.emit(ammo_count, reserve_ammo)


## Retorna true si el arma actual puede disparar.
func can_fire() -> bool:
	if current_weapon == null:
		return false
	if _is_reloading:
		return false
	return current_weapon.can_fire()


## Dispara el arma actual. Retorna hits array.
func fire() -> Array:
	if not can_fire():
		return []
	if current_weapon == null:
		return []

	var hits: Array = current_weapon.fire()
	ammo_count = current_weapon.ammo_in_mag
	reserve_ammo = current_weapon.reserve_ammo
	_update_weapon_status()

	if current_weapon.ammo_in_mag <= 0 and current_weapon.reserve_ammo > 0:
		weapon_empty.emit()

	return hits


# ══════════════════════════════════════════════════════════════════
# PERFILES AI
# ══════════════════════════════════════════════════════════════════

## Precarga todos los perfiles AI desde disco.
func _preload_ai_profiles() -> void:
	var dir: DirAccess = DirAccess.open(AI_PROFILES_DIR)
	if dir == null:
		push_warning("WeaponSystem: No se pudo abrir %s" % AI_PROFILES_DIR)
		return

	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while filename != "":
		if filename.ends_with(".tres"):
			var path: String = AI_PROFILES_DIR + filename
			var profile: WeaponAIProfile = ResourceLoader.load(path) as WeaponAIProfile
			if profile and profile.weapon_name != "":
				ai_profiles[profile.weapon_name] = profile
		filename = dir.get_next()
	dir.list_dir_end()


## Carga el perfil AI para un arma específica.
func _load_profile_for(weapon: Weapon) -> void:
	if weapon == null:
		return
	if ai_profiles.has(weapon.weapon_name):
		return  # Ya cargado

	var filename: String = weapon.weapon_name.to_lower().replace(" ", "_")
	var path: String = AI_PROFILES_DIR + filename + ".tres"
	var profile: WeaponAIProfile = ResourceLoader.load(path) as WeaponAIProfile
	if profile:
		ai_profiles[weapon.weapon_name] = profile
		weapon.ai_profile = profile
		_debug_ws("Perfil cargado para: %s" % weapon.weapon_name)


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func _debug_ws(msg: String) -> void:
	print("[WeaponSystem] %s" % msg)
