extends EnemyBase
class_name EnemyMelee

func _ready() -> void:
	enemy_name = "Enemigo Melee"
	max_health = 25.0
	speed = 4.0
	damage = 15.0
	attack_range = 1.8
	attack_rate = 1.0
	super._ready()
