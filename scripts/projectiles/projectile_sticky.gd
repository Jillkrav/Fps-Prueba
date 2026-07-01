# scripts/projectiles/projectile_sticky.gd
# Proyectil que se clava en superficies: cuchillos, flechas de ballesta.
# Extiende ProjectileBase para comportamiento de clavado.
class_name ProjectileSticky
extends ProjectileBase

# ─── Propiedades específicas ──────────────────────────────────────────────
var stick_offset: Vector3 = Vector3.ZERO  # Offset local al punto de impacto

func on_hit(body: Node) -> void:
	if body == shooter:
		return
	if _hit_bodies.has(body):
		return
	
	_hit_bodies.append(body)
	hit_target.emit(body)
	
	# Aplicar daño directo
	_apply_damage(body)
	
	# Penetración
	if penetration > 0:
		penetration -= 1
		if penetration <= 0:
			_stick_to(body)
		return
	
	# Clavarse
	if sticks:
		_stick_to(body)
		return
	
	_destroy_projectile()

func _stick_to(body: Node) -> void:
	if not is_instance_valid(body):
		_destroy_projectile()
		return
	
	sticks_to = body
	
	# Desactivar físicas
	freeze = true
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	
	# Reparentear al body para que siga su movimiento
	var _old_parent: Node = get_parent()
	reparent(body)
	
	# Si es explosivo con fuse, esperar a que explote clavado
	# (el timer de fuse ya está corriendo)
	
	print("ProjectileSticky: '%s' se clavó en '%s'" % [weapon_name, body.name])
