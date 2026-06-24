extends Node3D
class_name Weapon

signal weapon_fired(ammo_in_mag: int, reserve_ammo: int)
signal weapon_ammo_changed(ammo_in_mag: int, reserve_ammo: int)
signal reload_started()
signal reload_completed()

@export var weapon_name: String = "Arma"
@export var damage: float = 10.0
@export var fire_rate: float = 0.2
@export var max_ammo: int = 120
@export var clip_size: int = 30
@export var spread: float = 0.05
@export var weapon_range: float = 50.0
@export var pellets: int = 1
@export var reload_time: float = 1.5

var ammo_in_mag: int = 0
var reserve_ammo: int = 0
var is_reloading: bool = false
var last_fire_time: int = 0

@onready var raycast: RayCast3D = get_node_or_null("RayCast3D")
@onready var muzzle_flash_light: OmniLight3D = get_node_or_null("MuzzleFlash")

func _ready() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = false

func initialize_from_config(config: Dictionary) -> void:
	weapon_name = config.get("name", weapon_name)
	damage = config.get("damage", damage)
	fire_rate = config.get("fire_rate", fire_rate)
	max_ammo = config.get("max_ammo", max_ammo)
	clip_size = config.get("clip_size", clip_size)
	spread = config.get("spread", spread)
	weapon_range = config.get("range", weapon_range)
	pellets = config.get("pellets", pellets)
	reload_time = config.get("reload_time", reload_time)
	ammo_in_mag = clip_size
	reserve_ammo = max_ammo
	var mesh: MeshInstance3D = get_node_or_null("WeaponMesh")
	if mesh and config.has("color"):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = config["color"]
		mesh.set_surface_override_material(0, mat)

func can_fire() -> bool:
	if is_reloading:
		return false
	var current_time: int = Time.get_ticks_msec()
	var time_since_last_shot: float = (current_time - last_fire_time) / 1000.0
	return ammo_in_mag > 0 and time_since_last_shot >= fire_rate

func fire() -> Array:
	if not can_fire():
		return []
	ammo_in_mag -= 1
	last_fire_time = Time.get_ticks_msec()
	weapon_fired.emit(ammo_in_mag, reserve_ammo)
	show_muzzle_flash()

	var hits: Array = []
	for i in range(pellets):
		perform_raycast_with_spread()
		if raycast and raycast.is_colliding():
			var collider: Node = raycast.get_collider()
			var hit_point: Vector3 = raycast.get_collision_point()
			var hit_normal: Vector3 = raycast.get_collision_normal()
			# Detectar headshot: revisar si el punto de impacto está dentro de algún HeadHitbox
			var is_headshot: bool = _check_headshot(collider, hit_point)
			hits.append({
				"collider": collider,
				"point": hit_point,
				"normal": hit_normal,
				"damage": damage,
				"is_headshot": is_headshot
			})
	return hits

## Revisa si el hit_point cae dentro del HeadHitbox del collider impactado.
func _check_headshot(collider: Node, hit_point: Vector3) -> bool:
	if collider == null:
		return false
	# Busca el HeadHitbox como hijo del collider (enemy_base structure)
	var head_hitbox: Node = collider.get_node_or_null("Head/HeadHitbox")
	if head_hitbox == null:
		return false
	var head_pos: Vector3 = head_hitbox.global_transform.origin
	# Radio de la esfera de cabeza es 0.28, usamos 0.32 con margen
	return head_pos.distance_to(hit_point) <= 0.32

func perform_raycast_with_spread() -> void:
	if not raycast:
		return
	raycast.target_position = Vector3(0, 0, -weapon_range)
	if spread > 0.0:
		var rx: float = randf_range(-spread, spread)
		var ry: float = randf_range(-spread, spread)
		raycast.target_position += Vector3(rx * weapon_range, ry * weapon_range, 0)
	raycast.force_raycast_update()

func show_muzzle_flash() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = true
		var timer: SceneTreeTimer = get_tree().create_timer(0.05)
		timer.timeout.connect(func() -> void: muzzle_flash_light.visible = false)

func start_reload() -> void:
	if is_reloading or ammo_in_mag == clip_size or reserve_ammo <= 0:
		return
	is_reloading = true
	reload_started.emit()
	var timer: SceneTreeTimer = get_tree().create_timer(reload_time)
	timer.timeout.connect(_complete_reload)

func _complete_reload() -> void:
	if not is_reloading:
		return
	var needed: int = clip_size - ammo_in_mag
	var to_transfer: int = min(needed, reserve_ammo)
	ammo_in_mag += to_transfer
	reserve_ammo -= to_transfer
	is_reloading = false
	reload_completed.emit()
	weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)

func resupply() -> void:
	ammo_in_mag = clip_size
	reserve_ammo = max_ammo
	is_reloading = false
	weapon_ammo_changed.emit(ammo_in_mag, reserve_ammo)
