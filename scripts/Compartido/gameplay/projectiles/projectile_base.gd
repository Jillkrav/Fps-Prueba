# scripts/projectiles/projectile_base.gd
# Clase base para todos los proyectiles físicos (extends RigidBody3D)
class_name ProjectileBase
extends RigidBody3D

# ─── Señales ──────────────────────────────────────────────────────────────
signal hit_target(target: Node)
signal exploded(position: Vector3)

# ─── Propiedades del proyectil ──────────────────────────────────────────
var damage_vs_player: float = 10.0
var damage_vs_npc: float = 12.0
var shooter: Node3D = null          # Quien disparó
var weapon_name: String = ""        # Nombre del arma origen
var categoria: String = ""          # "arrojadiza", "explosiva", "plasma"
var speed: float = 0.0              # Velocidad inicial (unidades/segundo)
var lifespan: float = 5.0           # Tiempo máximo de vida en segundos

# ─── Físicas ──────────────────────────────────────────────────────────────
var gravity_factor: float = 1.0     # 0 = sin gravedad, 1 = gravedad normal
var bounces_left: int = 0           # Rebotes restantes (-1 = infinito)
var sticks: bool = false            # ¿Se clava en superficies?
var sticks_to: Node = null          # En qué nodo se clavó

# ─── Explosión ────────────────────────────────────────────────────────────
var explosive: bool = false
var explosion_radius: float = 0.0
var explosion_damage: float = 0.0
var fuse_time: float = 0.0          # Si > 0, explota después de N segundos (granadas de tiempo)
var explodes_on_impact: bool = false # Explota al impactar

# ─── Penetración ──────────────────────────────────────────────────────────
var penetration: int = 0            # 0 = no penetra, >0 = penetra N objetivos
var _hit_bodies: Array[Node] = []   # Cuerpos ya impactados (para penetración)

# ─── Fuego amigo ─────────────────────────────────────────────────────────
## Si true, la bala ATRAVIESA a los cuerpos NO hostiles al shooter (aliados):
## no los daña y continúa hasta un enemigo o una pared. Fuego amigo OFF global.
## false = comportamiento clásico (se detiene en el primer body). Los
## explosivos/granadas usan false (el efecto de explosión no debe cancelarse).
var passes_through_allies: bool = false

# ─── Internos ──────────────────────────────────────────────────────────
var _lifespan_timer: Timer = null
var _direction: Vector3 = Vector3.FORWARD
var _ignore_shooter_collision: bool = true
var _stick_offset: Transform3D
var _original_collision_layer: int
var _original_collision_mask: int
var _prev_position: Vector3 = Vector3.ZERO  # Posición previa para raycast de personajes

func _ready() -> void:
	# Guardar valores originales de colisión
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask
	
	# ── Separar física de detección de personajes ──────────────────────────
	# Quitar la capa 2 (jugadores/bots) de la colisión FÍSICA del RigidBody
	# para que las balas NO empujen a los personajes. La detección de impacto
	# contra personajes se hace con un raycast por frame (sin colisión física).
	var mask_sin_personajes: int = _original_collision_mask & ~(1 << 1)
	_original_collision_mask = mask_sin_personajes
	
	# Desactivar colisión temporalmente (período de gracia) para evitar
	# que el proyectil colisione con el shooter que acaba de dispararlo
	collision_layer = 0
	collision_mask = 0
	
	# Timer de gracia: reactivar colisión después de 0.2 segundos
	var grace_timer: Timer = Timer.new()
	grace_timer.one_shot = true
	grace_timer.wait_time = 0.02
	grace_timer.timeout.connect(_on_grace_period_end)
	add_child(grace_timer)
	grace_timer.start()
	
	# Configurar físicas del proyectil
	freeze = false
	gravity_scale = 0.0  # Controlaremos la gravedad manualmente en _physics_process
	
	# Conectar señal de colisión (paredes, objetivos, mundo)
	body_entered.connect(_on_body_entered)
	
	# Aplicar velocidad inicial en dirección forward
	if speed > 0.0:
		linear_velocity = _direction * speed
	else:
		linear_velocity = _direction * 10.0
	
	# Posición inicial para el raycast de personajes
	_prev_position = global_position
	
	# Timer de vida útil
	_lifespan_timer = Timer.new()
	_lifespan_timer.one_shot = true
	_lifespan_timer.wait_time = lifespan
	_lifespan_timer.timeout.connect(_on_lifespan_expired)
	add_child(_lifespan_timer)
	_lifespan_timer.start()
	
	# Configurar fuse si es temporizado
	if fuse_time > 0.0 and explosive:
		var fuse_timer: Timer = Timer.new()
		fuse_timer.one_shot = true
		fuse_timer.wait_time = fuse_time
		fuse_timer.timeout.connect(_on_fuse_expired)
		add_child(fuse_timer)
		fuse_timer.start()

func _physics_process(delta: float) -> void:
	# Aplicar gravedad personalizada si gravity_factor > 0
	if gravity_factor > 0.0:
		var grav: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
		linear_velocity.y -= grav * gravity_factor * delta
	
	# Orientar el proyectil en la dirección de movimiento (opcional)
	if linear_velocity.length_squared() > 0.01:
		var dir: Vector3 = linear_velocity.normalized()
		# Evitar vectores colineales: si la dirección es casi vertical
		# (paralela a UP), usar RIGHT como vector de referencia
		var up: Vector3 = Vector3.RIGHT if abs(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
		look_at(global_position + dir, up)
	
	# Detección de impacto contra jugadores/bots (capa 2) por raycast.
	# El RigidBody ya no colisiona físicamente con ellos (no los empuja),
	# así que usamos un raycast por frame para detectar el impacto sin
	# generar colisión física ni empuje.
	_check_character_hits()

func _process(_delta: float) -> void:
	# Seguimiento del cuerpo donde está clavado (sin reparentear para evitar
	# escalas no uniformes que Jolt Physics no soporta)
	if sticks_to and is_instance_valid(sticks_to):
		var body_3d: Node3D = sticks_to as Node3D
		if body_3d and not body_3d.is_queued_for_deletion():
			global_transform = body_3d.global_transform * _stick_offset
		else:
			sticks_to = null
			_destroy_projectile()

# ─── Configuración inicial ──────────────────────────────────────────────

## Configura el proyectil desde un diccionario de datos (proveniente de skill.json)
func configure_from_dict(data: Dictionary) -> void:
	categoria = data.get("CategoriaMunicion", categoria)
	speed = float(data.get("VelocidadProyectil", speed))
	gravity_factor = float(data.get("GravedadProyectil", gravity_factor))
	penetration = int(data.get("Penetracion", penetration))
	sticks = bool(data.get("SeClava", sticks))
	explosive = bool(data.get("ExplotaAlImpactar", explosive)) or (float(data.get("DanioArea", 0.0)) > 0.0)
	fuse_time = float(data.get("TiempoExplosion", fuse_time))
	bounces_left = int(data.get("NumeroRebotes", bounces_left))
	explosion_radius = float(data.get("RadioExplosion", explosion_radius))
	explosion_damage = float(data.get("DanioArea", explosion_damage))
	explodes_on_impact = bool(data.get("ExplotaAlImpactar", explodes_on_impact))

## Establece la dirección inicial del proyectil
func set_direction(dir: Vector3) -> void:
	_direction = dir.normalized()
	# Siempre actualizar linear_velocity. Si speed > 0 usa esa velocidad,
	# si no, usar 10.0 como fallback (mismo default que _ready)
	var vel: float = speed if speed > 0.0 else 10.0
	linear_velocity = _direction * vel

## Ignora colisiones con un nodo específico (útil para el shooter)
func ignore_collision_with(_node: Node) -> void:
	# Ya se maneja en _on_body_entered ignorando al shooter por referencia
	pass

# ─── Manejo de colisiones ──────────────────────────────────────────────

## Reactiva la colisión del proyectil después del período de gracia inicial
func _on_grace_period_end() -> void:
	if not is_instance_valid(self):
		return
	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask

## Raycast por frame para detectar impactos contra jugadores/bots (capa 2).
## El proyectil no colisiona físicamente con ellos (no los empuja), pero
## este raycast detecta el impacto a lo largo del desplazamiento del frame.
func _check_character_hits() -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	# Solo tras el período de gracia
	if collision_layer == 0:
		_prev_position = global_position
		return
	
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = _prev_position
	var to: Vector3 = global_position
	
	# Si no hay desplazamiento este frame, no hay nada que comprobar
	if from.distance_squared_to(to) < 0.0001:
		_prev_position = global_position
		return
	
	# Detectar capas 1 (paredes) y 2 (jugadores/bots). Si la primera colisión
	# es una pared, la bala no debe atravesarla (el RigidBody se encarga de
	# destruirla al impactar); solo hacemos daño si el primer objeto es un personaje.
	var exclude: Array[RID] = [get_rid()]
	var query := PhysicsRayQueryParameters3D.create(
		from,
		to,
		(1 << 0) | (1 << 1)  # Capa 1 (mundo) y capa 2 (jugadores/bots)
	)
	query.exclude = exclude
	var result := space_state.intersect_ray(query)
	
	# Fuego amigo OFF: si la bala atraviesa aliados (passes_through_allies),
	# se salta cada cuerpo NO hostil y se sigue hasta un enemigo o una pared.
	var iterations: int = 0
	while not result.is_empty() and iterations < 16:
		iterations += 1
		var body: Object = result.get("collider")
		# El collider puede ser el CollisionShape3D del personaje; subir al body
		while body is CollisionShape3D and body.get_parent():
			body = body.get_parent()
		if body is Node3D and body.has_method("take_damage"):
			if passes_through_allies and _is_friendly_to_shooter(body):
				var body_rid: RID = _body_rid(body)
				if body_rid.is_valid():
					exclude.append(body_rid)
				query.exclude = exclude
				result = space_state.intersect_ray(query)
				continue
			_on_detected_body(body)
		break
	
	_prev_position = global_position

## Procesa un cuerpo detectado por el raycast de personajes.
func _on_detected_body(body: Node) -> void:
	if not is_instance_valid(body):
		return
	# Ignorar al shooter y cuerpos ya impactados
	if _ignore_shooter_collision and body == shooter:
		return
	if _hit_bodies.has(body):
		return
	on_hit(body)

func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return
	
	# Ignorar al shooter
	if _ignore_shooter_collision and body == shooter:
		return
	
	# Ignorar cuerpos ya impactados (penetración)
	if _hit_bodies.has(body):
		return
	
	on_hit(body)

## Método virtual - se sobreescribe en subclases para comportamiento específico
func on_hit(body: Node) -> void:
	# Registrar impacto
	_hit_bodies.append(body)
	hit_target.emit(body)
	
	# Aplicar daño directo
	_apply_damage(body)
	
	# Penetración: si quedan penetraciones, continuar
	if penetration > 0:
		penetration -= 1
		if penetration <= 0:
			_destroy_projectile()
		return
	
	# Si explota al impactar
	if explosive and explodes_on_impact:
		explode()
		return
	
	# Si tiene rebotes
	if bounces_left > 0:
		bounces_left -= 1
		return  # El motor de físicas maneja el rebote
	
	# Si se clava
	if sticks:
		_stick_to(body)
		return
	
	# Por defecto: destruir el proyectil
	_destroy_projectile()

func _apply_damage(body: Node) -> void:
	if not is_instance_valid(body):
		return
	# Fuego amigo OFF (global): nunca dañar a un aliado del shooter.
	if _is_friendly_to_shooter(body):
		return
	if body.has_method("take_damage"):
		var dmg: float = damage_vs_npc
		if body is ProjectileBase:
			return  # No dañar otros proyectiles
		if body is Player:
			dmg = damage_vs_player
		body.take_damage(
			dmg, "Torso",
			shooter.get_instance_id() if shooter else -1,
			shooter.global_position if shooter else global_position
		)

# ─── Comportamiento específico ──────────────────────────────────────────

func _stick_to(body: Node) -> void:
	if not is_instance_valid(body):
		_destroy_projectile()
		return
	
	sticks_to = body
	freeze = true
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	
	# Calcular offset y activar seguimiento (en deferred para evitar
	# modificar el árbol durante un callback de físicas)
	call_deferred("_deferred_stick", body)
	
	# Si además es explosivo con fuse, esperar a que explote
	# (el fuse timer ya está corriendo)


func _deferred_stick(body: Node) -> void:
	if not is_instance_valid(self) or not is_instance_valid(body):
		return
	
	var body_3d: Node3D = body as Node3D
	if not body_3d:
		_destroy_projectile()
		return
	
	# Guardar offset relativo al body (en espacio global) para seguimiento manual
	_stick_offset = body_3d.global_transform.affine_inverse() * global_transform
	sticks_to = body_3d
	
	# No reparentear: evitar heredar escala no uniforme del padre,
	# que Jolt Physics no soporta en shapes de colisión.

func explode() -> void:
	if not is_instance_valid(self):
		return
	
	# Buscar la escena de explosión
	var explosion_scene: PackedScene = preload("res://scenes/Compartido/projectiles/explosion.tscn")
	var explosion_instance: Node3D = explosion_scene.instantiate()
	get_tree().current_scene.add_child(explosion_instance)
	explosion_instance.global_position = global_position
	
	# Configurar la explosión
	if explosion_instance.has_method("setup"):
		var valid_shooter: Node3D = shooter if is_instance_valid(shooter) else null
		explosion_instance.setup(explosion_damage, explosion_radius, valid_shooter)
	
	exploded.emit(global_position)
	_destroy_projectile()

func _on_fuse_expired() -> void:
	if explosive:
		explode()

func _on_lifespan_expired() -> void:
	_destroy_projectile()

func _destroy_projectile() -> void:
	if not is_instance_valid(self):
		return
	queue_free()

# ─── Helpers ──────────────────────────────────────────────────────────────

## Devuelve true si el proyectil sigue activo
func is_active() -> bool:
	return is_instance_valid(self) and not is_queued_for_deletion()


# ─── Fuego amigo / facciones ────────────────────────────────────────────────

## RID del body raíz (CollisionObject3D) para poder excluirlo de un raycast.
func _body_rid(body: Node) -> RID:
	if body is CollisionObject3D:
		return (body as CollisionObject3D).get_rid()
	return RID()


## ¿El cuerpo es NO hostil (aliado) respecto al shooter? Sin shooter se trata
## como hostil para conservar el comportamiento clásico.
func _is_friendly_to_shooter(body: Node) -> bool:
	if not is_instance_valid(shooter):
		return false
	var shooter_faction: int = _get_faction_of(shooter)
	if shooter_faction < 0:
		return false
	var body_faction: int = _get_faction_of(body)
	if body_faction < 0:
		return false
	return not StoryFactionSystem.are_hostile(shooter_faction, body_faction)


func _get_faction_of(node: Node) -> int:
	if node.is_in_group(&"player"):
		return StoryFactionSystem.PLAYER_FACTION
	if "faction_id" in node:
		return int(node.get("faction_id"))
	return -1
