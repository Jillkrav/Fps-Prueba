# scripts/npc_pistolero.gd
# NPC con pistola. Hereda de NpcBase.
# Daño leído desde ConfigManager (arma USP). Vida desde npc_base._ready().
extends NpcBase
class_name NpcPistolero

@export var shoot_range: float = 15.0

func _ready() -> void:
	npc_name     = "NPC Pistolero"
	sexo         = Sexo.MASCULINO
	relacion     = Relacion.ENEMIGO
	experiencia  = Experiencia.MEDIA
	estado       = Estado.IDLE

	speed        = 2.5
	attack_range = 12.0
	attack_rate  = 1.5
	# Daño: DañoAlJugador de la USP
	var cfg := ConfigManager.get_arma("USP")
	damage = float(cfg.get("DañoAlJugador", 25.0))
	# max_health = 0.0 → npc_base._ready() lo leerá desde ConfigManager
	super._ready()

func perform_attack() -> void:
	if not target or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_transform.origin + Vector3(0, 1.0, 0),
		target.global_transform.origin + Vector3(0, 1.0, 0)
	)
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)

	if result and result.get("collider") == target:
		target.take_damage(damage)
		draw_debug_laser(
			global_transform.origin + Vector3(0, 1.0, 0),
			target.global_transform.origin + Vector3(0, 1.0, 0),
			Color.YELLOW
		)
