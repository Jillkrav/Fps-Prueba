# scripts/weapon.gd
# Clase base para todas las armas del juego.
# Los stats se cargan desde ConfigManager vía initialize_from_name().
extends Node3D
class_name Weapon

signal weapon_fired(ammo_in_mag: int, reserve_ammo: int)
signal weapon_ammo_changed(ammo_in_mag: int, reserve_ammo: int)
signal reload_started()
signal reload_completed()

# Valores por defecto — se sobreescriben en initialize_from_name()
@export var weapon_name:       String  = "Arma"
@export var damage_vs_player:  float   = 10.0
@export var damage_vs_npc:     float   = 12.0
@export var segundos_por_bala: float   = 0.15
@export var clip_size:         int     = 30
@export var max_ammo:          int     = 120
@export var spread:            float   = 0.05
@export var weapon_range:      float   = 50.0
@export var pellets:           int     = 1
@export var reload_time:       float   = 1.5
@export var tipo_recarga:      String  = "Cargador"  # "Cargador" | "PorCartucho"

var ammo_in_mag:   int  = 0
var reserve_ammo:  int  = 0
var is_reloading:  bool = false
var last_fire_time: int = 0

@onready var raycast:          RayCast3D  = get_node_or_null("RayCast3D")
@onready var muzzle_flash_light: OmniLight3D = get_node_or_null("MuzzleFlash")

func _ready() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = false

# ── Inicialización desde JSON ────────────────────────────────────────────

## Carga todos los stats del arma desde ConfigManager usando el nombre exacto del JSON.
## Ejemplo: initialize_from_name("USP")
func initialize_from_name(nombre: String) -> void:
	var cfg := ConfigManager.get_arma(nombre)
	if cfg.is_empty():
		push_warning("Weapon: Config no encontrada para '%s'. Usando defaults." % nombre)
		_finalizar_inicializacion()
		return

	weapon_name       = nombre
	damage_vs_player  = float(cfg.get("DañoAlJugador",       damage_vs_player))
	damage_vs_npc     = float(cfg.get("DañoAlNPC",           damage_vs_npc))
	segundos_por_bala = float(cfg.get("SegundosPorBala",     segundos_por_bala))
	clip_size         = int(cfg.get("TamañoCargador",        clip_size))
	max_ammo          = int(cfg.get("ReservaMunicionMaxima", max_ammo))
	reload_time       = float(cfg.get("TiempoRecargaSegundos", reload_time))
	tipo_recarga      = cfg.get("TipoRecarga",               tipo_recarga)

	_finalizar_inicializacion()

func _finalizar_inicializacion() -> void:
	ammo_in_mag  = clip_size
	reserve_ammo = max_ammo

func set_color(color: Color) -> void:
	var mesh: MeshInstance3D = get_node_or_null("WeaponMesh")
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mesh.set_surface_override_material(0, mat)

# ── Disparo ──────────────────────────────────────────────────────────────

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
	for _i in range(pellets):
		_perform_raycast()
		if raycast and raycast.is_colliding():
			hits.append({
				"collider":        raycast.get_collider(),
				"point":           raycast.get_collision_point(),
				"normal":          raycast.get_collision_normal(),
				"damage_vs_player": damage_vs_player,
				"damage_vs_npc":    damage_vs_npc
			})
	return hits

func _perform_raycast() -> void:
	if not raycast:
		return
	raycast.target_position = Vector3(0, 0, -weapon_range)
	if spread > 0.0:
		raycast.target_position += Vector3(
			randf_range(-spread, spread) * weapon_range,
			randf_range(-spread, spread) * weapon_range,
			0.0
		)
	raycast.force_raycast_update()

func show_muzzle_flash() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = true
		get_tree().create_timer(0.05).timeout.connect(
			func() -> void: muzzle_flash_light.visible = false
		)

# ── Recarga ──────────────────────────────────────────────────────────────

func can_reload() -> bool:
	if is_reloading or reserve_ammo <= 0:
		return false
	if tipo_recarga == "Cargador":
		return ammo_in_mag < clip_size
	return ammo_in_mag < clip_size  # PorCartucho también verifica espacio

func start_reload() -> void:
	if not can_reload():
		return
	is_reloading = true
	reload_started.emit()
	get_tree().create_timer(reload_time).timeout.connect(_on_reload_tick)

func _on_reload_tick() -> void:
	if not is_reloading:
		return

	if tipo_recarga == "PorCartucho":
		# Añade un cartucho y sigue si todavía hay espacio y reserva
		if ammo_in_mag < clip_size and reserve_ammo > 0:
			ammo_in_mag  += 1
			reserve_ammo -= 1
			weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)
			if ammo_in_mag < clip_size and reserve_ammo > 0:
				get_tree().create_timer(reload_time).timeout.connect(_on_reload_tick)
				return
	else:
		# Recarga cargador completo de una vez
		var needed     := clip_size - ammo_in_mag
		var transferir := min(needed, reserve_ammo)
		ammo_in_mag  += transferir
		reserve_ammo -= transferir
		weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)

	is_reloading = false
	reload_completed.emit()

func resupply() -> void:
	ammo_in_mag  = clip_size
	reserve_ammo = max_ammo
	is_reloading = false
	weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)
