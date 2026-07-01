# scripts/effects/bullet_trail.gd
# ──────────────────────────────────────────────────────────────────
# BALA / PERDIGÓN — EFECTO ESTELA (BULLET TRAIL)
#
# Pequeño segmento visual que se muestra desde el arma hasta el
# punto de impacto. Se autodestruye tras un breve fade-out.
#
# Uso:
#   var trail: BulletTrail = preload("res://scenes/effects/bullet_trail.tscn").instantiate()
#   trail.setup(from_pos, to_pos)
#   get_tree().root.add_child(trail)
# ──────────────────────────────────────────────────────────────────
class_name BulletTrail
extends Node3D


# ─── CONSTANTES ────────────────────────────────────────────────────

## Duración total visible del trail en segundos.
const TRAIL_LIFETIME: float = 0.12

## Color base del trail (blanco/amarillento como fogonazo).
const TRAIL_COLOR: Color = Color(1.0, 0.85, 0.45, 1.0)


# ─── NODOS ─────────────────────────────────────────────────────────

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


# ════════════════════════════════════════════════════════════════════
# SETUP
# ════════════════════════════════════════════════════════════════════

## Configura el trail entre dos puntos del mundo.
func setup(from: Vector3, to: Vector3, color: Color = TRAIL_COLOR) -> void:
	# Posicionar en el punto medio
	global_position = (from + to) * 0.5

	# Calcular distancia
	var dir: Vector3 = (to - from)
	var dist: float = dir.length()
	if dist < 0.01:
		queue_free()
		return
	dir = dir.normalized()

	# Orientar: el BoxMesh base tiene size=1 en Z, escalamos al largo real
	look_at(from + dir * 10.0, Vector3.UP)
	scale.z = dist

	# Aplicar color emisivo
	if mesh_instance:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.material_override = mat

	# Auto-destrucción con fade-out
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_alpha, 1.0, 0.0, TRAIL_LIFETIME)
	tween.tween_callback(queue_free).set_delay(TRAIL_LIFETIME + 0.01)


# ════════════════════════════════════════════════════════════════════
# INTERNO
# ════════════════════════════════════════════════════════════════════

func _set_alpha(alpha: float) -> void:
	if not is_instance_valid(mesh_instance):
		return
	var mat: Material = mesh_instance.material_override
	if not mat:
		return
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	if sm:
		sm.albedo_color.a = alpha
		sm.emission_energy_multiplier = 3.0 * alpha
