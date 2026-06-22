extends EnemyBase
class_name EnemyMelee

func _ready() -> void:
	enemy_name = "Enemigo Melee"
	max_health = 25.0
	speed = 4.0 # Más rápido
	damage = 15.0 # Daño medio
	attack_range = 1.8 # Corto alcance
	attack_rate = 1.0
	super._ready()
