# scripts/npc_melee.gd
# NPC que ataca cuerpo a cuerpo. Hereda de NpcBase.
# Daño configurable por export; max_health desde ConfigManager vía npc_base._ready().
extends NpcBase
class_name NpcMelee

func _ready() -> void:
	npc_name     = "NPC Melee"
	sexo         = Sexo.MASCULINO
	relacion     = Relacion.ENEMIGO
	experiencia  = Experiencia.MEDIA
	estado       = Estado.IDLE

	speed        = 4.0
	damage       = 15.0
	attack_range = 1.5
	attack_rate  = 1.0
	# max_health = 0.0 → npc_base._ready() lo leerá desde ConfigManager
	super._ready()

func perform_attack() -> void:
	if not target or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	target.take_damage(damage)
