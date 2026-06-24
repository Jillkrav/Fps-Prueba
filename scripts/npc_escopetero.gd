# scripts/npc_escopetero.gd
extends NpcBase
class_name NpcEscopetero

func _ready() -> void:
	npc_name    = "NPC Escopeta"
	experiencia = Experiencia.MEDIA
	estado      = Estado.IDLE
	speed       = 3.0
	attack_range = 6.0
	attack_rate  = 2.0

	# Solo sobreescribe la relacion si NO fue forzada externamente
	if not _relacion_forzada:
		relacion = Relacion.ENEMIGO

	# Arma: usa nombre_arma si fue asignado externamente, si no usa M3 por defecto
	if nombre_arma == "":
		nombre_arma = "M3"
	var cfg := ConfigManager.get_arma(nombre_arma)
	damage = float(cfg.get("DañoAlNPC", 132.0))

	super._ready()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	var dist: float = global_transform.origin.distance_to(target.global_transform.origin)
	var damage_mult: float = clamp((attack_range - dist) / attack_range, 0.2, 1.0)
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_transform.origin + Vector3(0, 1.0, 0),
		target.global_transform.origin + Vector3(0, 1.0, 0)
	)
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)
	if result and result.get("collider") == target:
		target.take_damage(damage * damage_mult)
		for _i in range(4):
			var offset_end := target.global_transform.origin + Vector3(
				randf_range(-0.4, 0.4),
				randf_range(-0.4, 0.4),
				randf_range(-0.4, 0.4)
			)
			draw_debug_laser(global_transform.origin + Vector3(0, 1.0, 0), offset_end, Color.ORANGE)
