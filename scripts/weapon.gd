# scripts/weapon.gd
extends Node3D
class_name Weapon

signal weapon_fired(ammo_in_mag: int, reserve_ammo: int)
signal weapon_ammo_changed(ammo_in_mag: int, reserve_ammo: int)
signal reload_started()
signal reload_completed()

# ─── Propiedades básicas ────────────────────────────────────────────────
@export var weapon_name:       String = "Arma"
@export var damage_vs_player:  float  = 10.0
@export var damage_vs_npc:     float  = 12.0
@export var segundos_por_bala: float  = 0.12
@export var max_ammo:          int    = 120
@export var clip_size:         int    = 30
@export var spread:            float  = 0.05
@export var weapon_range:      float  = 50.0
@export var pellets:           int    = 1
@export var reload_time:       float  = 1.5
@export var tipo_recarga:      String = "Cargador"

# ─── Propiedades melee (FASE 7) ───────────────────────────────────────
@export var melee_range:            float  = 2.5   # Alcance del melee en unidades
@export var melee_knockback_strength: float = 8.0  # Fuerza del knockback
@export var melee_swing_duration:    float = 0.25  # Duración de la animación de swing

# ─── Nuevas propiedades para proyectiles (FASE 2) ─────────────────────
@export var categoria_municion:     String = "bala"
@export var velocidad_proyectil:    float  = 0.0
@export var danio_area:             float  = 0.0
@export var radio_explosion:        float  = 0.0
@export var gravedad_proyectil:     float  = 0.0
@export var penetracion:            int    = 0
@export var se_clava:               bool   = false
@export var explota_al_impactar:    bool   = false
@export var tiempo_explosion:       float  = 0.0
@export var numero_perdigones:      int    = 1
@export var rebota:                 bool   = false
@export var numero_rebotes:         int    = 0

# ─── Escena de proyectil ────────────────────────────────────────────────
var projectile_scene: PackedScene = preload("res://scenes/projectiles/projectile_placeholder.tscn")

# ─── Escena de estela de bala/perdigón ───────────────────────────────────
var bullet_trail_scene: PackedScene = preload("res://scenes/effects/bullet_trail.tscn")

# ─── Override de posición/dirección para proyectiles (desde Player) ─────
var _shoot_pos_override: Vector3 = Vector3.ZERO
var _shoot_dir_override: Vector3 = Vector3.ZERO

# ─── Override de posición de impacto para hit-scan (bots) ───────────────
## Cuando se asigna, perform_raycast_with_spread() apunta a esta posición
## del mundo en lugar de usar la dirección -Z del arma.
var _hitscan_target_override: Vector3 = Vector3.ZERO

## Perfil AI táctico.
var ai_profile: WeaponAIProfile = null

var ammo_in_mag:    int  = 0
var reserve_ammo:   int  = 0
var is_reloading:   bool = false
var last_fire_time: int  = 0

@onready var raycast:            RayCast3D         = get_node_or_null("RayCast3D")
@onready var muzzle_flash_light: OmniLight3D       = get_node_or_null("MuzzleFlash")
@onready var melee_area:         Area3D            = get_node_or_null("MeleeArea")
@onready var melee_swing_sound:  AudioStreamPlayer3D = get_node_or_null("MeleeSwingSound")
@onready var melee_hit_sound:    AudioStreamPlayer3D = get_node_or_null("MeleeHitSound")
@onready var weapon_mesh:        MeshInstance3D     = get_node_or_null("WeaponMesh")

# ─── Almacena transform original del mesh para animación melee ──────────
var _weapon_mesh_original_position: Vector3 = Vector3.ZERO
var _weapon_mesh_original_rotation: Vector3 = Vector3.ZERO

func _ready() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = false

	# Guardar transform original del mesh para animación de swing
	if weapon_mesh:
		_weapon_mesh_original_position = weapon_mesh.position
		_weapon_mesh_original_rotation = weapon_mesh.rotation

	# Configurar el área melee si existe
	_configure_melee_area()

# ── Inicializar desde ConfigManager ──
func initialize_from_name(nombre_arma: String) -> void:
	var cfg: Dictionary = ConfigManager.get_arma(nombre_arma)
	if cfg.is_empty():
		push_warning("Weapon: Config no encontrada para '%s', usando valores por defecto." % nombre_arma)
		ammo_in_mag  = clip_size
		reserve_ammo = max_ammo
		return

	weapon_name         = nombre_arma
	damage_vs_player    = float(cfg.get("DanioAlJugador",        damage_vs_player))
	damage_vs_npc       = float(cfg.get("DanioAlNPC",            damage_vs_npc))
	segundos_por_bala   = float(cfg.get("DanioPorSegundo",       segundos_por_bala))
	clip_size           = int(cfg.get("TamanoCargador",          clip_size))
	max_ammo            = int(cfg.get("ReservaMunicionMaxima",   max_ammo))
	reload_time         = float(cfg.get("TiempoRecargaSegundos", reload_time))
	tipo_recarga        = str(cfg.get("TipoRecarga",             tipo_recarga))
	spread              = float(cfg.get("Spread",                spread))
	pellets             = int(cfg.get("NumeroPerdigones",        pellets))

	# ─── Nuevos campos de munición (FASE 2) ───────────────────────────
	categoria_municion  = str(cfg.get("CategoriaMunicion",       "bala"))
	velocidad_proyectil = float(cfg.get("VelocidadProyectil",    0.0))
	danio_area          = float(cfg.get("DanioArea",             0.0))
	radio_explosion     = float(cfg.get("RadioExplosion",        0.0))
	gravedad_proyectil  = float(cfg.get("GravedadProyectil",     0.0))
	penetracion         = int(cfg.get("Penetracion",             0))
	se_clava            = bool(cfg.get("SeClava",                false))
	explota_al_impactar = bool(cfg.get("ExplotaAlImpactar",      false))
	tiempo_explosion    = float(cfg.get("TiempoExplosion",       0.0))
	numero_perdigones   = int(cfg.get("NumeroPerdigones",        1))
	rebota              = bool(cfg.get("Rebota",                 false))
	numero_rebotes      = int(cfg.get("NumeroRebotes",           0))

	ammo_in_mag  = clip_size
	reserve_ammo = max_ammo
	print("Weapon: '%s' inicializada — categoria=%s dano=%.0f cargador=%d" % [weapon_name, categoria_municion, damage_vs_player, clip_size])

## Configura el área de detección melee según melee_range.
func _configure_melee_area() -> void:
	if not melee_area:
		return
	# Ajustar el tamaño del CollisionShape3D basado en melee_range
	var col_shape: CollisionShape3D = melee_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape and col_shape.shape is BoxShape3D:
		var box: BoxShape3D = col_shape.shape as BoxShape3D
		# El tamaño en Z (profundidad) es melee_range, centrado en frente del arma
		box.size.z = melee_range
		# Reposicionar el shape para que empiece desde el arma y se extienda hacia adelante
		col_shape.position.z = -melee_range * 0.5
	# Configurar capas de colisión: detectar capa 1 (jugadores) y 2 (NPCs) por defecto
	melee_area.collision_mask = 3  # Capas 1 y 2


func can_fire() -> bool:
	if is_reloading:
		return false
	var elapsed: float = (Time.get_ticks_msec() - last_fire_time) / 1000.0
	return ammo_in_mag > 0 and elapsed >= segundos_por_bala

# ═══════════════════════════════════════════════════════════════════════════
# MÉTODO PRINCIPAL fire() — Bifurcación según CategoriaMunicion
# ═══════════════════════════════════════════════════════════════════════════
func fire() -> Array:
	if not can_fire():
		return []
	ammo_in_mag    -= 1
	last_fire_time  = Time.get_ticks_msec()
	weapon_fired.emit(ammo_in_mag, reserve_ammo)
	show_muzzle_flash()
	# Log visible para debug de bots
	print("[Weapon.fire] %s dispara! ammo=%d" % [weapon_name, ammo_in_mag])

	match categoria_municion:
		"bala":
			return _fire_hitscan()
		"perdigones":
			return _fire_hitscan_multi_pellet()
		"arrojadiza", "explosiva", "plasma":
			return _fire_projectile()
		"cuerpo_a_cuerpo":
			return _fire_melee()
		_:
			return _fire_hitscan()

# ─── HIT-SCAN (Balas, Perdigones) ────────────────────────────────────────

func _fire_hitscan() -> Array:
	var hits: Array = []
	var muzzle_pos: Vector3 = _get_muzzle_position()
	for _i in range(max(1, pellets)):
		perform_raycast_with_spread()
		if raycast and raycast.is_colliding():
			var hit_point: Vector3 = raycast.get_collision_point()
			hits.append({
				"collider":         raycast.get_collider(),
				"point":            hit_point,
				"normal":           raycast.get_collision_normal(),
				"damage_vs_player": damage_vs_player,
				"damage_vs_npc":    damage_vs_npc
			})
			_spawn_bullet_trail(muzzle_pos, hit_point)
		else:
			# Incluso si no impacta, mostrar trail hasta el final del raycast
			var end_pos: Vector3 = _get_raycast_endpoint()
			_spawn_bullet_trail(muzzle_pos, end_pos)
	return hits

func _fire_hitscan_multi_pellet() -> Array:
	var hits: Array = []
	var pellet_count: int = max(1, numero_perdigones)
	var muzzle_pos: Vector3 = _get_muzzle_position()
	for _i in range(pellet_count):
		perform_raycast_with_spread()
		if raycast and raycast.is_colliding():
			var hit_point: Vector3 = raycast.get_collision_point()
			hits.append({
				"collider":         raycast.get_collider(),
				"point":            hit_point,
				"normal":           raycast.get_collision_normal(),
				"damage_vs_player": damage_vs_player / float(pellet_count),
				"damage_vs_npc":    damage_vs_npc / float(pellet_count)
			})
			_spawn_bullet_trail(muzzle_pos, hit_point)
		else:
			var end_pos: Vector3 = _get_raycast_endpoint()
			_spawn_bullet_trail(muzzle_pos, end_pos)
	return hits

func perform_raycast_with_spread() -> void:
	if not raycast:
		return

	# Usar la dirección override si está activa (bot apuntando al torso)
	if _hitscan_target_override != Vector3.ZERO:
		var local_target: Vector3 = raycast.to_local(_hitscan_target_override)
		if spread > 0.0:
			var dist_to_target: float = max(local_target.length(), 1.0)
			var spread_offset: float = spread * dist_to_target
			var rx: float = randf_range(-spread_offset, spread_offset)
			var ry: float = randf_range(-spread_offset, spread_offset)
			local_target += Vector3(rx, ry, 0)
		raycast.target_position = local_target
	else:
		raycast.target_position = Vector3(0, 0, -weapon_range)
		if spread > 0.0:
			var rx: float = randf_range(-spread, spread)
			var ry: float = randf_range(-spread, spread)
			raycast.target_position += Vector3(rx * weapon_range, ry * weapon_range, 0)
	raycast.force_raycast_update()

# ─── PROYECTILES FÍSICOS (Arrojadizas, Explosivas, Plasma) ───────────────

func _fire_projectile() -> Array:
	if not projectile_scene:
		push_warning("Weapon: No hay projectile_scene asignada para '%s'" % weapon_name)
		return []

	var projectile: ProjectileBase = projectile_scene.instantiate()
	get_tree().root.add_child(projectile)

	# Posición: desde el override (Player/cámara) o por defecto (raycaster/arma)
	var spawn_pos: Vector3 = raycast.global_position if raycast else global_position
	if _shoot_pos_override != Vector3.ZERO:
		spawn_pos = _shoot_pos_override
		_shoot_pos_override = Vector3.ZERO
	projectile.global_position = spawn_pos

	# Dirección: desde el override (Player/cámara) o por defecto, con spread
	var base_dir: Vector3 = -global_transform.basis.z
	if _shoot_dir_override != Vector3.ZERO:
		base_dir = _shoot_dir_override
		_shoot_dir_override = Vector3.ZERO
	if spread > 0.0:
		var rx: float = randf_range(-spread, spread)
		var ry: float = randf_range(-spread, spread)
		base_dir = (base_dir + Vector3(rx, ry, 0)).normalized()
	# Configurar propiedades (speed ANTES de set_direction para que
	# set_direction() pueda calcular linear_velocity correctamente)
	projectile.damage_vs_player   = damage_vs_player
	projectile.damage_vs_npc      = damage_vs_npc
	projectile.shooter            = _get_shooter_node()
	projectile.weapon_name        = weapon_name
	projectile.categoria          = categoria_municion
	projectile.speed              = velocidad_proyectil
	projectile.set_direction(base_dir)
	projectile.gravity_factor     = gravedad_proyectil
	projectile.penetration        = penetracion
	projectile.sticks             = se_clava
	projectile.explosive          = explota_al_impactar or (danio_area > 0.0)
	projectile.explosion_radius   = radio_explosion
	projectile.explosion_damage   = danio_area
	projectile.fuse_time          = tiempo_explosion
	projectile.explodes_on_impact = explota_al_impactar
	projectile.bounces_left       = numero_rebotes if rebota else 0

	return []  # El daño se maneja cuando el proyectil impacta

## Permite al Player (o bot) sobreescribir la posición y dirección desde donde
## se dispara el próximo proyectil. Útil para que el proyectil salga de la
## cámara (Player) o del head (NPC) en lugar del arma.
func set_shoot_override(pos: Vector3, dir: Vector3) -> void:
	_shoot_pos_override = pos
	_shoot_dir_override = dir


## Permite al bot sobreescribir el punto de impacto para armas hit-scan.
## Hace que perform_raycast_with_spread() apunte directamente a target_pos
## (posición mundial del torso del enemigo) en lugar de usar -Z.
func override_hitscan_target(target_pos: Vector3) -> void:
	_hitscan_target_override = target_pos


func _get_shooter_node() -> Node3D:
	var parent: Node = get_parent()
	while parent:
		if parent is Player or parent.has_method("take_damage"):
			return parent as Node3D
		parent = parent.get_parent()
	return null

# ─── MELEE (Cuerpo a cuerpo) — FASE 7: Area3D + Animación + Knockback ──

func _fire_melee() -> Array:
	var hits: Array = []

	# ── Swing animation ──────────────────────────────────────────────────
	_play_melee_swing()

	# ── Detección por Area3D ─────────────────────────────────────────────
	var shooter_node: Node3D = _get_shooter_node()
	var bodies_to_process: Array[Node] = []

	if melee_area:
		# Forzar actualización de la transform del área (sigue al arma)
		melee_area.global_transform = global_transform
		# Obtener todos los cuerpos superpuestos en el área de golpe
		var overlapping: Array[Node3D] = melee_area.get_overlapping_bodies()
		for body in overlapping:
			if not is_instance_valid(body):
				continue
			# Ignorar al shooter
			if body == shooter_node:
				continue
			# Ignorar si ya está en la lista (evitar duplicados)
			if bodies_to_process.has(body):
				continue
			bodies_to_process.append(body)

		# También revisar areas (para hitboxes como HeadHitbox)
		var overlapping_areas: Array[Area3D] = melee_area.get_overlapping_areas()
		for area in overlapping_areas:
			if not is_instance_valid(area):
				continue
			# Buscar el nodo padre que tiene take_damage
			var parent: Node = area.get_parent()
			var found_target: Node = null
			while parent:
				if parent.has_method("take_damage"):
					found_target = parent
					break
				parent = parent.get_parent()
			if found_target and found_target != shooter_node:
				if not bodies_to_process.has(found_target):
					bodies_to_process.append(found_target)

	# ── Procesar hits ────────────────────────────────────────────────────
	var hit_something: bool = false
	for target in bodies_to_process:
		if not target.has_method("take_damage"):
			continue

		# Determinar daño según si es player o NPC
		var dmg: float = damage_vs_npc
		if target is Player:
			dmg = damage_vs_player

		# Aplicar daño
		target.take_damage(dmg, "Torso", shooter_node.get_instance_id() if shooter_node else -1)

		# Aplicar knockback
		_apply_melee_knockback(target, shooter_node)

		# Registrar hit para retorno
		hits.append({
			"collider":         target,
			"point":            target.global_position,
			"damage_vs_player": dmg,
			"damage_vs_npc":    dmg
		})
		hit_something = true

	# ── Sonidos ──────────────────────────────────────────────────────────
	if hit_something:
		_play_melee_hit_sound()
	else:
		# Aún así reproducir sonido de swing aunque no haya impacto
		pass  # El sonido de swing ya se reprodujo en _play_melee_swing()

	return hits


# ─── Animación de Swing ──────────────────────────────────────────────────

func _play_melee_swing() -> void:
	# Sonido de swing
	_play_melee_swing_sound()

	if not weapon_mesh:
		return

	# Usar los valores originales almacenados en _ready para reset correcto
	var orig_pos: Vector3 = _weapon_mesh_original_position
	var orig_rot: Vector3 = _weapon_mesh_original_rotation

	# Asegurar que el mesh esté en su posición original antes de animar
	weapon_mesh.position = orig_pos
	weapon_mesh.rotation = orig_rot

	# Crear tween para la animación de swing
	var tween: Tween = create_tween().set_parallel(true)

	# Swing: rotar en X (golpe hacia abajo) con un ligero movimiento en Z
	tween.tween_property(weapon_mesh, "rotation:x", orig_rot.x - deg_to_rad(60.0), melee_swing_duration * 0.5)
	tween.tween_property(weapon_mesh, "rotation:x", orig_rot.x, melee_swing_duration * 0.5).set_delay(melee_swing_duration * 0.5)

	# Pequeño desplazamiento hacia adelante y atrás
	tween.tween_property(weapon_mesh, "position:z", orig_pos.z - 0.15, melee_swing_duration * 0.3)
	tween.tween_property(weapon_mesh, "position:z", orig_pos.z, melee_swing_duration * 0.3).set_delay(melee_swing_duration * 0.3)


# ─── Knockback ───────────────────────────────────────────────────────────

func _apply_melee_knockback(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or not is_instance_valid(attacker):
		return

	# Dirección del knockback: desde el atacante hacia el objetivo
	var knockback_dir: Vector3 = (target.global_position - attacker.global_position).normalized()
	knockback_dir.y = 0.3  # Pequeño impulso hacia arriba para efecto visual

	# Aplicar según el tipo de target
	if target is CharacterBody3D:
		# Para CharacterBody3D (Player, NpcBase): aplicar directamente a la velocidad
		var kb_velocity: Vector3 = knockback_dir * melee_knockback_strength
		# Usar setter de velocity si existe
		if target.has_method("apply_central_impulse"):
			# Si tiene método RigidBody-like
			target.apply_central_impulse(kb_velocity)
		else:
			# Para CharacterBody3D, modificar velocity directamente
			target.velocity = target.velocity * 0.5 + kb_velocity
	elif target is RigidBody3D:
		target.apply_central_impulse(knockback_dir * melee_knockback_strength)


# ─── Sonidos Melee ───────────────────────────────────────────────────────

func _play_melee_swing_sound() -> void:
	if melee_swing_sound and melee_swing_sound.stream:
		melee_swing_sound.play()

func _play_melee_hit_sound() -> void:
	if melee_hit_sound and melee_hit_sound.stream:
		melee_hit_sound.play()

# ─── VFX ──────────────────────────────────────────────────────────────────

func show_muzzle_flash() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.visible = true
		get_tree().create_timer(0.05).timeout.connect(
			func() -> void: muzzle_flash_light.visible = false
		)


# ─── BULLET TRAIL VFX ─────────────────────────────────────────────────

## Devuelve la posición de la boca del arma (muzzle) en coordenadas globales.
func _get_muzzle_position() -> Vector3:
	if muzzle_flash_light and is_instance_valid(muzzle_flash_light):
		return muzzle_flash_light.global_position
	# Fallback: adelante del arma
	return global_position - global_transform.basis.z * 0.65


## Devuelve el punto final del raycast (donde termina si no impacta nada).
func _get_raycast_endpoint() -> Vector3:
	if not raycast:
		return global_position - global_transform.basis.z * weapon_range
	return raycast.global_position + (raycast.global_transform.basis * raycast.target_position)


## Instancia un efecto visual de estela entre dos puntos.
func _spawn_bullet_trail(from_pos: Vector3, to_pos: Vector3) -> void:
	if not bullet_trail_scene or not is_inside_tree():
		return
	var trail: Node3D = bullet_trail_scene.instantiate()
	get_tree().root.add_child(trail)
	if trail.has_method("setup"):
		trail.setup(from_pos, to_pos)


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
		var needed: int      = clip_size - ammo_in_mag
		var to_transfer: int = min(needed, reserve_ammo)
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


# ══════════════════════════════════════════════════════════════════
# AI PROFILE INTEGRATION — FASE 5
# ══════════════════════════════════════════════════════════════════

## Carga el perfil AI para esta arma desde los archivos .tres.
## Retorna true si se cargó correctamente.
func load_ai_profile() -> bool:
	if ai_profile != null:
		return true
	var filename: String = weapon_name.to_lower().replace(" ", "_")
	var path: String = "res://config/ai_profiles/" + filename + ".tres"
	var profile: WeaponAIProfile = ResourceLoader.load(path) as WeaponAIProfile
	if profile:
		ai_profile = profile
		return true
	return false


## Evalúa el rating táctico de esta arma en el contexto dado.
## context puede contener: target_distance, bot_health_ratio, ammo_ratio, in_cover.
## Retorna 0.0 (inútil) a 1.0 (óptimo).
func get_ai_rating(context: Dictionary = {}) -> float:
	if ai_profile == null:
		load_ai_profile()
	if ai_profile == null:
		return 0.3  # Rating por defecto para armas sin perfil
	return ai_profile.evaluate(context)


## Sugiere el estilo de ataque según el perfil y contexto.
## Retorna -1.0 (defensivo) a +1.0 (agresivo).
func suggest_attack_style(context: Dictionary = {}) -> float:
	if ai_profile == null:
		load_ai_profile()
	if ai_profile == null:
		return 0.0
	return ai_profile.suggest_attack_style(context)


## Retorna una cadena descriptiva para debug.
func ai_debug_string() -> String:
	if ai_profile:
		return ai_profile.debug_string()
	var profile_loaded: bool = load_ai_profile()
	if profile_loaded and ai_profile:
		return ai_profile.debug_string()
	return "%s | sin perfil AI" % weapon_name
