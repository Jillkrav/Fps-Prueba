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

# ─── Internos ──────────────────────────────────────────────────────────
var _lifespan_timer: Timer = null
var _direction: Vector3 = Vector3.FORWARD
var _ignore_shooter_collision: bool = true

func _ready() -> void:
	# Configurar físicas del proyectil
	freeze = false
	gravity_scale = 0.0  # Controlaremos la gravedad manualmente en _physics_process
	
	# Conectar señal de colisión
	body_entered.connect(_on_body_entered)
	
	# Aplicar velocidad inicial en dirección forward
	if speed > 0.0:
		linear_velocity = _direction * speed
	else:
		linear_velocity = _direction * 10.0
	
	# La verificación de colisión con el shooter se hace en _on_body_entered
	
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
	if body.has_method("take_damage"):
		var dmg: float = damage_vs_npc
		if body is ProjectileBase:
			return  # No dañar otros proyectiles
		if body is Player:
			dmg = damage_vs_player
		body.take_damage(dmg, "Torso", shooter.get_instance_id() if shooter else -1)

# ─── Comportamiento específico ──────────────────────────────────────────

func _stick_to(body: Node) -> void:
	if not is_instance_valid(body):
		_destroy_projectile()
		return
	
	sticks_to = body
	freeze = true
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	
	# Reparentear al body DEFFERED para evitar remover el nodo
	# durante un callback de físicas (body_entered)
	call_deferred("_deferred_stick", body)
	
	# Si además es explosivo con fuse, esperar a que explote
	# (el fuse timer ya está corriendo)


func _deferred_stick(body: Node) -> void:
	if not is_instance_valid(self) or not is_instance_valid(body):
		return
	reparent(body)

func explode() -> void:
	if not is_instance_valid(self):
		return
	
	# Buscar la escena de explosión
	var explosion_scene: PackedScene = preload("res://scenes/projectiles/explosion.tscn")
	var explosion_instance: Node3D = explosion_scene.instantiate()
	get_tree().current_scene.add_child(explosion_instance)
	explosion_instance.global_position = global_position
	
	# Configurar la explosión
	if explosion_instance.has_method("setup"):
		explosion_instance.setup(explosion_damage, explosion_radius, shooter)
	
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
