# scripts/projectiles/projectile_plasma.gd
# Proyectil de plasma: sin gravedad, viaja recto, impacto visual.
# Extiende ProjectileBase con comportamiento específico de plasma.
class_name ProjectilePlasma
extends ProjectileBase

func _ready() -> void:
	# Plasma: sin gravedad, sin rebote, sin clavado
	gravity_factor = 0.0
	bounces_left = 0
	sticks = false
	
	super()
	
	# Efecto visual: partículas de estela (implementación futura)
	# Tamaño pequeño y brillante
	scale = Vector3(0.8, 0.8, 0.8)

func on_hit(body: Node) -> void:
	if body == shooter:
		return
	if _hit_bodies.has(body):
		return
	
	_hit_bodies.append(body)
	hit_target.emit(body)
	
	# Aplicar daño directo
	_apply_damage(body)
	
	# Penetración limitada para plasma
	if penetration > 0:
		penetration -= 1
		return
	
	# Efecto visual de impacto
	_spawn_impact_effect()
	
	_destroy_projectile()

func _spawn_impact_effect() -> void:
	# Efecto visual simple: un destello de luz
	var flash: OmniLight3D = OmniLight3D.new()
	flash.light_color = Color(0.2, 0.8, 1.0, 1.0)  # Azul brillante
	flash.omni_range = 2.0
	flash.visible = true
	
	get_tree().current_scene.add_child(flash)
	flash.global_position = global_position
	
	# Auto-destruir después de 0.1s
	var flash_timer: Timer = Timer.new()
	flash_timer.one_shot = true
	flash_timer.wait_time = 0.1
	flash_timer.timeout.connect(func() -> void:
		if is_instance_valid(flash):
			flash.queue_free()
	)
	add_child(flash_timer)
	flash_timer.start()
