# scripts/yellow_cube.gd
# ──────────────────────────────────────────────────────────────────
# CUBO AMARILLO — Punto de salto exclusivo para bots congelados
# por FreezeCube2 (cubo morado).
#
# Los bots congelados por FreezeCube2 saltan/levitan hacia el
# yellow_cube más cercano mientras permanecen congelados.
# ──────────────────────────────────────────────────────────────────
extends Node3D
class_name YellowCube


func _ready() -> void:
	add_to_group("yellow_cube")
