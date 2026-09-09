# scripts/medkit.gd
# ──────────────────────────────────────────────────────────────────
# MEDKIT — Botiquín de salud reutilizable.
#
# Cura al personaje (Player o BotBase) que lo recoge.
# Los bots van a por botiquines cuando tienen la salud baja.
#
# Extiende Pickup (RigidBody3D) y usa el tipo Type.HEALTH.
# ──────────────────────────────────────────────────────────────────
extends Pickup
class_name Medkit

## Cantidad de vida que cura al recogerlo.
@export var heal_amount: float = 50.0


func _init() -> void:
	pickup_type = Type.HEALTH
	pickup_data["curacion"] = heal_amount


func _ready() -> void:
	# La propiedad del Inspector es la fuente de verdad para instancias de mapa.
	pickup_type = Type.HEALTH
	pickup_data["curacion"] = heal_amount
	super()


## Lógica de recogida para un personaje (Player o BotBase).
func _on_picked_up(picker: Node) -> void:
	var heal_data: float = pickup_data.get("curacion", heal_amount)

	# ── Jugador humano ───────────────────────────────────────────
	if picker is Player:
		_heal_player(picker, heal_data)
		return

	# ── NPC / Bot ────────────────────────────────────────────────
	if picker is BotBase:
		_heal_npc(picker, heal_data)
		return


func _heal_player(player: Player, amount: float) -> void:
	if player.has_method("curar"):
		player.curar(amount)
		print("Medkit: %s curado (+%.0f)" % [player.name, amount])
	elif "current_health" in player:
		player.current_health = min(player.current_health + amount, player.max_health)


func _heal_npc(npc: BotBase, amount: float) -> void:
	if "current_health" in npc and "max_health" in npc:
		npc.current_health = min(npc.current_health + amount, npc.max_health)
		print("Medkit: NPC %s curado (+%.0f)" % [npc.name, amount])


## Visual: caja sanitaria verde/cruz.
func _update_visual() -> void:
	if not is_inside_tree():
		return
	if label_3d:
		label_3d.text = "Salud"
		label_3d.modulate = Color(0.2, 1.0, 0.3)

	var mesh: MeshInstance3D = find_child("ItemMesh") as MeshInstance3D
	if not mesh:
		return
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.3, 0.3, 0.3)
	mesh.mesh = box_mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.2, 0.2)  # Rojo de botiquín
	mesh.set_surface_override_material(0, mat)