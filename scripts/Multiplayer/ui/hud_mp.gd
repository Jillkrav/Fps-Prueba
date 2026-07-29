# hud_mp.gd
# Skeleton para HUD Multiplayer.
# Se completara con funcionalidades MP-specific (core bars, scoreboard, match end, auto-balance).

extends CanvasLayer
class_name HUDMPClass

func _ready() -> void:
	add_to_group("hud_mp")
