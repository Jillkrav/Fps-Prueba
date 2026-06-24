# scripts/weapon.gd
extends Node3D
class_name Weapon

signal weapon_fired(ammo_in_mag: int, reserve_ammo: int)
signal weapon_ammo_changed(ammo_in_mag: int, reserve_ammo: int)
signal reload_started()
signal reload_completed()

@export var weapon_name:      String = "Arma"
@export var damage_vs_player: float  = 10.0
@export var damage_vs_npc:    float  = 12.0
@export var segundos_por_bala: float = 0.12
@export var max_ammo:         int    = 120
@export var clip_size:        int    = 30
@export var spread:           float  = 0.05
@export var weapon_range:     float  = 50.0
@export var pellets:          int    = 1
@export var reload_time:      float  = 1.5
@export var tipo_recarga:     String = "Cargador"

var ammo_in_mag:    int  = 0
var reserve_ammo:   int  = 0
var is_reloading:   bool = false
var last_fire_time: int  = 0

@onready var raycast:          RayCast3D  = get_node_or_null("RayCast3D")
@onready var muzzle_flash_light: OmniLight3D = get_node_or_null("MuzzleFlash")

func _ready() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = false

# ── Inicializar el arma desde ConfigManager por nombre exacto del JSON ──
func initialize_from_name(nombre_arma: String) -> void:
	var cfg := ConfigManager.get_arma(nombre_arma)
	if cfg.is_empty():
		push_warning("Weapon: Config no encontrada para '%s', usando valores por defecto." % nombre_arma)
		ammo_in_mag  = clip_size
		reserve_ammo = max_ammo
		return

	weapon_name        = nombre_arma
	damage_vs_player   = float(cfg.get("DanoAlJugador",        damage_vs_player))
	damage_vs_npc      = float(cfg.get("DanoAlNPC",            damage_vs_npc))
	segundos_por_bala  = float(cfg.get("SegundosPorBala",      segundos_por_bala))
	clip_size          = int(cfg.get("TamanoCargador",         clip_size))
	max_ammo           = int(cfg.get("ReservaMunicionMaxima",  max_ammo))
	reload_time        = float(cfg.get("TiempoRecargaSegundos", reload_time))
	tipo_recarga       = cfg.get("TipoRecarga",                tipo_recarga)

	ammo_in_mag  = clip_size
	reserve_ammo = max_ammo
	print("Weapon: '%s' inicializada — dano=%.0f spb=%.3f cargador=%d" % [weapon_name, damage_vs_player, segundos_por_bala, clip_size])

# Mantener compatibilidad con codigo viejo que use initialize_from_config con dict manual
func initialize_from_config(config: Dictionary) -> void:
	weapon_name        = config.get("name",        weapon_name)
	damage_vs_player   = config.get("damage",      damage_vs_player)
	damage_vs_npc      = config.get("damage",      damage_vs_npc)
	segundos_por_bala  = config.get("fire_rate",   segundos_por_bala)
	max_ammo           = config.get("max_ammo",    max_ammo)
	clip_size          = config.get("clip_size",   clip_size)
	spread             = config.get("spread",      spread)
	weapon_range       = config.get("range",       weapon_range)
	pellets            = config.get("pellets",     pellets)
	reload_time        = config.get("reload_time", reload_time)
	ammo_in_mag        = clip_size
	reserve_ammo       = max_ammo
	var mesh: MeshInstance3D = get_node_or_null("WeaponMesh")
	if mesh and config.has("color"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = config["color"]
		mesh.set_surface_override_material(0, mat)

func can_fire() -> bool:
	if is_reloading:
		return false
	var elapsed: float = (Time.get_ticks_msec() - last_fire_time) / 1000.0
	return ammo_in_mag > 0 and elapsed >= segundos_por_bala

func fire() -> Array:
	if not can_fire():
		return []
	ammo_in_mag    -= 1
	last_fire_time  = Time.get_ticks_msec()
	weapon_fired.emit(ammo_in_mag, reserve_ammo)
	show_muzzle_flash()

	var hits: Array = []
	for i in range(pellets):
		perform_raycast_with_spread()
		if raycast and raycast.is_colliding():
			hits.append({
				"collider":          raycast.get_collider(),
				"point":             raycast.get_collision_point(),
				"normal":            raycast.get_collision_normal(),
				"damage_vs_player":  damage_vs_player,
				"damage_vs_npc":     damage_vs_npc
			})
	return hits

func perform_raycast_with_spread() -> void:
	if not raycast:
		return
	raycast.target_position = Vector3(0, 0, -weapon_range)
	if spread > 0.0:
		var rx := randf_range(-spread, spread)
		var ry := randf_range(-spread, spread)
		raycast.target_position += Vector3(rx * weapon_range, ry * weapon_range, 0)
	raycast.force_raycast_update()

func show_muzzle_flash() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = true
		get_tree().create_timer(0.05).timeout.connect(
			func() -> void: muzzle_flash_light.visible = false
		)

func start_reload() -> void:
	if is_reloading or reserve_ammo <= 0:
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
			ammo_in_mag  += 1
			reserve_ammo -= 1
			weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)
			if ammo_in_mag < clip_size and reserve_ammo > 0:
				get_tree().create_timer(reload_time).timeout.connect(_on_reload_tick)
				return
	else:
		var needed      := clip_size - ammo_in_mag
		var to_transfer := min(needed, reserve_ammo)
		ammo_in_mag  += to_transfer
		reserve_ammo -= to_transfer
		weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)

	is_reloading = false
	reload_completed.emit()

func resupply() -> void:
	ammo_in_mag  = clip_size
	reserve_ammo = max_ammo
	is_reloading = false
	weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)
