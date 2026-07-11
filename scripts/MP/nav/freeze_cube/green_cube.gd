# scripts/green_cube.gd
# ──────────────────────────────────────────────────────────────────
# CUBO VERDE — Punto de salto para bots congelados
#
# Los bots congelados por FreezeCube saltan/levitan hacia el
# green cube más cercano mientras permanecen congelados.
# ──────────────────────────────────────────────────────────────────
extends Node3D
class_name GreenCube


func _ready() -> void:
	add_to_group("green_cube")
