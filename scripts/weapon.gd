extends Node3D
class_name Weapon

signal weapon_fired(ammo_in_mag: int, reserve_ammo: int)
signal weapon_ammo_changed(ammo_in_mag: int, reserve_ammo: int)
signal reload_started()
signal reload_completed()

@export var weapon_name: String = "Arma"
@export var damage_vs_player: float = 10.0
@export var damage_vs_npc: float = 12.0
@export var segundos_por_bala: float = 0.2
@export var max_ammo: int = 60
@export var clip_size: int = 12
@export var spread: float = 0.05
@export var weapon_range: float = 50.0
@export var pellets: int = 1
@export var reload_time: float = 1.5
@export var tipo_recarga: String = "Cargador"
@export var tipo_ataque: String = "Proyectil"
@export var alcance_melee: float = 1.5

var ammo_in_mag: int = 0
var reserve_ammo: int = 0
var is_reloading: bool = false
var last_fire_time: int = 0

@onready var raycast: RayCast3D = get_node_or_null("RayCast3D")
@onready var muzzle_flash_light: OmniLight3D = get_node_or_null("MuzzleFlash")

func _ready() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = false

func initialize_from_name(nombre_arma: String) -> void:
	var cfg := ConfigManager.get_arma(nombre_arma)
	if cfg.is_empty():
		push_warning("Weapon '%s': config no encontrada, se usan valores por defecto." % nombre_arma)
		ammo_in_mag = clip_size
		reserve_ammo = max_ammo
		return

	weapon_name = nombre_arma
	tipo_recarga = cfg.get("TipoRecarga", tipo_recarga)
	reload_time = float(cfg.get("TiempoRecargaSegundos", reload_time))

	if ConfigManager.es_melee(cfg):
		tipo_ataque = "Melee"
		damage_vs_player = float(cfg.get("DañoAlJugador", damage_vs_player))
		damage_vs_npc = float(cfg.get("DañoAlNPC", damage_vs_npc))
		segundos_por_bala = float(cfg.get("SegundosPorGolpe", segundos_por_bala))
		alcance_melee = float(cfg.get("Alcance", alcance_melee))
		ammo_in_mag = -1
		reserve_ammo = -1
	elif ConfigManager.es_escopeta(cfg):
		tipo_ataque = "Proyectil"
		pellets = int(cfg.get("CantidadPerdigones", pellets))
		damage_vs_player = float(cfg.get("DañoPorPerdigonJugador", damage_vs_player))
		damage_vs_npc = float(cfg.get("DañoPorPerdigonNPC", damage_vs_npc))
		segundos_por_bala = float(cfg.get("SegundosPorBala", segundos_por_bala))
		clip_size = int(cfg.get("TamañoCargador", clip_size))
		max_ammo = int(cfg.get("ReservaMunicionMaxima", max_ammo))
		ammo_in_mag = clip_size
		reserve_ammo = max_ammo
	else:
		tipo_ataque = "Proyectil"
		pellets = 1
		damage_vs_player = float(cfg.get("DañoAlJugador", damage_vs_player))
		damage_vs_npc = float(cfg.get("DañoAlNPC", damage_vs_npc))
		segundos_por_bala = float(cfg.get("SegundosPorBala", segundos_por_bala))
		clip_size = int(cfg.get("TamañoCargador", clip_size))
		max_ammo = int(cfg.get("ReservaMunicionMaxima", max_ammo))
		ammo_in_mag = clip_size
		reserve_ammo = max_ammo

func can_fire() -> bool:
	if is_reloading:
		return false
	if tipo_ataque == "Melee":
		return (Time.get_ticks_msec() - last_fire_time) / 1000.0 >= segundos_por_bala
	var elapsed: float = (Time.get_ticks_msec() - last_fire_time) / 1000.0
	return ammo_in_mag > 0 and elapsed >= segundos_por_bala

func fire(precision: float = 1.0) -> Array:
	if not can_fire():
		return []

	last_fire_time = Time.get_ticks_msec()

	if tipo_ataque == "Melee":
		return _perform_melee_attack()

	if ammo_in_mag != -1:
		ammo_in_mag -= 1
	weapon_fired.emit(ammo_in_mag, reserve_ammo)
	show_muzzle_flash()

	var hits: Array = []
	var spread_efectivo: float = spread * (1.0 - clampf(precision, 0.0, 1.0))

	for _i in range(pellets):
		_perform_raycast_with_spread(spread_efectivo)
		if raycast and raycast.is_colliding():
			hits.append({
				"collider": raycast.get_collider(),
				"point": raycast.get_collision_point(),
				"normal": raycast.get_collision_normal(),
				"damage_vs_player": damage_vs_player,
				"damage_vs_npc": damage_vs_npc
			})
	return hits

func _perform_melee_attack() -> Array:
	if not raycast:
		return []
	raycast.target_position = Vector3(0, 0, -alcance_melee)
	raycast.force_raycast_update()
	if raycast.is_colliding():
		return [{
			"collider": raycast.get_collider(),
			"point": raycast.get_collision_point(),
			"normal": raycast.get_collision_normal(),
			"damage_vs_player": damage_vs_player,
			"damage_vs_npc": damage_vs_npc
		}]
	return []

func _perform_raycast_with_spread(spread_val: float) -> void:
	if not raycast:
		return
	raycast.target_position = Vector3(0, 0, -weapon_range)
	if spread_val > 0.0:
		raycast.target_position += Vector3(
			randf_range(-spread_val, spread_val) * weapon_range,
			randf_range(-spread_val, spread_val) * weapon_range,
			0
		)
	raycast.force_raycast_update()

func start_reload() -> void:
	if tipo_ataque == "Melee" or is_reloading or reserve_ammo <= 0:
		return
	if tipo_recarga == "Cargador" and ammo_in_mag == clip_size:
		return
	is_reloading = true
	reload_started.emit()
	get_tree().create_timer(reload_time).timeout.connect(_on_reload_tick)

func _on_reload_tick() -> void:
	if not is_reloading:
		return

	if tipo_recarga == "PorCartucho":
		if ammo_in_mag < clip_size and reserve_ammo > 0:
			ammo_in_mag += 1
			reserve_ammo -= 1
			weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)
			if ammo_in_mag < clip_size and reserve_ammo > 0:
				get_tree().create_timer(reload_time).timeout.connect(_on_reload_tick)
				return
	else:
		var needed: int = clip_size - ammo_in_mag
		var to_add: int = min(needed, reserve_ammo)
		ammo_in_mag += to_add
		reserve_ammo -= to_add
		weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)

	is_reloading = false
	reload_completed.emit()

func show_muzzle_flash() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = true
		get_tree().create_timer(0.05).timeout.connect(func() -> void: muzzle_flash_light.visible = false)

func resupply() -> void:
	if tipo_ataque == "Melee":
		return
	ammo_in_mag = clip_size
	reserve_ammo = max_ammo
	is_reloading = false
	weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)
