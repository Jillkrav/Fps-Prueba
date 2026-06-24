# scripts/npc_escopetero.gd
# NPC con escopeta. Hereda de NpcBase.
# Daño leído desde ConfigManager (arma M3). Vida desde npc_base._ready().
extends NpcBase
class_name NpcEscopetero

func _ready() -> void:
	npc_name     = "NPC Escopeta"
	sexo         = Sexo.MASCULINO
	relacion     = Relacion.ENEMIGO
	experiencia  = Experiencia.MEDIA
	estado       = Estado.IDLE

	speed        = 3.0
	attack_range = 6.0
	attack_rate  = 2.0
	# Daño: DañoAlJugador de la M3
	var cfg := ConfigManager.get_arma("M3")
	damage = float(cfg.get("DañoAlJugador", 110.0))
	# max_health = 0.0 → npc_base._ready() lo leerá desde ConfigManager
	super._ready()

func perform_attack() -> void:
	if not target or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return

	var dist: float = global_transform.origin.distance_to(target.global_transform.origin)
	var damage_mult: float  = clamp((attack_range - dist) / attack_range, 0.2, 1.0)
	var final_damage: float = damage * damage_mult

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_transform.origin + Vector3(0, 1.0, 0),
		target.global_transform.origin + Vector3(0, 1.0, 0)
	)
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)

	if result and result.get("collider") == target:
		target.take_damage(final_damage)
		for _i in range(4):
			var offset_end: Vector3 = target.global_transform.origin + Vector3(
				randf_range(-0.4, 0.4),
				randf_range(-0.4, 0.4),
				randf_range(-0.4, 0.4)
			)
			draw_debug_laser(
				global_transform.origin + Vector3(0, 1.0, 0),
				offset_end,
				Color.ORANGE
			)
