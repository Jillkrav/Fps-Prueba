# scripts/npc_melee.gd
extends NpcBase
class_name NpcMelee

func _ready() -> void:
	npc_name     = "NPC Melee"
	experiencia  = Experiencia.MEDIA
	estado       = Estado.IDLE
	speed        = 4.0
	attack_range = 1.5
	attack_rate  = 1.0
	# damage fijo de melee (no tiene arma en skill.cfg.json, valor razonable)
	damage = 15.0

	# La relacion y el equipo son asignados por el spawner ANTES de _ready.
	# NO sobreescribir relacion aqui para respetar aliados spawneados.
	# Solo garantizar defaults si el spawner no toco nada.
	if relacion == Relacion.ENEMIGO and equipo == "rojo":
		pass  # defaults correctos

	super._ready()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	target.take_damage(damage)
