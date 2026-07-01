# scripts/effects/explosion.gd
# Sistema de explosión con daño de área y efecto visual.
# Se instancia cuando un proyectil explosivo detona.
class_name Explosion
extends Area3D

# ─── Señales ──────────────────────────────────────────────────────────────
signal explosion_completed()

# ─── Propiedades ──────────────────────────────────────────────────────────
var damage: float = 50.0
var radius: float = 5.0
var shooter: Node3D = null

# ─── Internos ──────────────────────────────────────────────────────────
var _hit_bodies: Array[Node] = []

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var light: OmniLight3D = $OmniLight3D
@onready var light_tween: Tween = null

func _ready() -> void:
	# Configurar el área de la explosión
	if collision_shape and collision_shape.shape is SphereShape3D:
		var sphere: SphereShape3D = collision_shape.shape
		sphere.radius = radius
	
	# Expandir el collision shape gradualmente (opcional)
	body_entered.connect(_on_body_entered)
	
	# Efecto visual: destello que se desvanece
	if light:
		light.omni_range = radius * 1.5
		light_tween = create_tween()
		light_tween.tween_property(light, "light_energy", 0.0, 0.4)
		light_tween.tween_callback(_on_light_faded)
	
	# Aplicar daño después de un frame para que el área detecte cuerpos
	await get_tree().process_frame
	_apply_area_damage()
	
	# Destruir la explosión después de 0.5s
	var destroy_timer: Timer = Timer.new()
	destroy_timer.one_shot = true
	destroy_timer.wait_time = 0.5
	destroy_timer.timeout.connect(_destroy_explosion)
	add_child(destroy_timer)
	destroy_timer.start()

## Configura la explosión con parámetros específicos
func setup(p_damage: float, p_radius: float, p_shooter: Node3D) -> void:
	damage = p_damage
	radius = p_radius
	shooter = p_shooter

func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return
	if _hit_bodies.has(body):
		return
	if body == shooter:
		return
	
	_hit_bodies.append(body)
	
	# Aplicar daño según la distancia (mayor daño en el centro)
	if body.has_method("take_damage"):
		var dist: float = global_position.distance_to(body.global_position) if body is Node3D else 0.0
		var falloff: float = 1.0 - (dist / radius)
		falloff = clamp(falloff, 0.1, 1.0)
		
		var final_damage: float = damage * falloff
		
		if body is Player:
			body.take_damage(final_damage, "Torso", shooter.get_instance_id() if shooter else -1)
		else:
			body.take_damage(final_damage, "Torso", shooter.get_instance_id() if shooter else -1)

func _apply_area_damage() -> void:
	# Obtener todos los cuerpos en el área
	var bodies: Array[Node3D] = get_overlapping_bodies()
	for body in bodies:
		_on_body_entered(body)
	
	explosion_completed.emit()

func _on_light_faded() -> void:
	if is_instance_valid(light):
		light.visible = false

func _destroy_explosion() -> void:
	if is_instance_valid(self):
		queue_free()
