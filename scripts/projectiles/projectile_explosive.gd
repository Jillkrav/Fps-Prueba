# scripts/projectiles/projectile_explosive.gd
# Proyectil explosivo: granadas, cohetes, etc.
# Extiende ProjectileBase y añade comportamiento de explosión avanzado.
class_name ProjectileExplosive
extends ProjectileBase

# ─── Propiedades específicas ──────────────────────────────────────────────
var bounce_friction: float = 0.5  # Pérdida de velocidad al rebotar

func _ready() -> void:
	super()
	# Configurar propiedades físicas para explosivos (PhysicsMaterial para el rebote)
	var mat: PhysicsMaterial = PhysicsMaterial.new()
	mat.bounce = bounce_friction if bounces_left > 0 else 0.0
	physics_material_override = mat
	
	# Si tiene fuse y NO explota al impactar (granada de tiempo), el fuse ya se inició en base

func on_hit(body: Node) -> void:
	# Ignorar al shooter y ya impactados
	if body == shooter:
		return
	if _hit_bodies.has(body):
		return
	
	_hit_bodies.append(body)
	hit_target.emit(body)
	
	# Aplicar daño directo por impacto (menor para explosivos)
	if body.has_method("take_damage"):
		var dmg: float = damage_vs_npc * 0.3  # 30% del daño como daño de impacto
		if body is Player:
			dmg = damage_vs_player * 0.3
		body.take_damage(dmg, "Torso", shooter.get_instance_id() if shooter else -1)
	
	# Explotar al impactar
	if explodes_on_impact:
		explode()
		return
	
	# Rebote
	if bounces_left > 0:
		bounces_left -= 1
		# El motor de físicas ya maneja el rebote, solo reducimos velocidad
		linear_velocity *= bounce_friction
		return
	
	# Si no explota al impactar (granada de tiempo que rueda), dejar que siga
	# Solo destruir si ya no rebota y no es temporizada
	if fuse_time <= 0.0:
		_destroy_projectile()

func _on_body_entered(body: Node) -> void:
	# Para explosivos, queremos detectar también áreas (para détectores de proximidad)
	super(body)
	
	# Rebote visual/sonido
	if bounces_left >= 0 and body is StaticBody3D:
		_on_bounce()

func _on_bounce() -> void:
	# Efecto visual/sonoro de rebote (implementación futura)
	pass
