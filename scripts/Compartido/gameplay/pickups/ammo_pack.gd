# scripts/ammo_pack.gd
# ──────────────────────────────────────────────────────────────────
# AMMO PACK — Paquete de munición reutilizable.
#
# Reabastece la munición del personaje (Player o BotBase) que lo
# recoge. Los bots van a por paquetes de munición cuando les faltan
# balas.
#
# Extiende Pickup (RigidBody3D) y usa el tipo Type.AMMO.
# ──────────────────────────────────────────────────────────────────
extends Pickup
class_name AmmoPack

## Munición que otorga al recogerlo (reserva total que se añade).
@export var ammo_amount: int = 60


func _init() -> void:
	pickup_type = Type.AMMO
	pickup_data["cantidad"] = ammo_amount


func _ready() -> void:
	super()


## Lógica de recogida para un personaje (Player o BotBase).
func _on_picked_up(picker: Node) -> void:
	var ammo_qty: int = pickup_data.get("cantidad", ammo_amount)

	# ── Jugador humano ───────────────────────────────────────────
	if picker is Player:
		_refill_player(picker, ammo_qty)
		return

	# ── NPC / Bot ────────────────────────────────────────────────
	if picker is BotBase:
		_refill_npc(picker, ammo_qty)
		return


func _refill_player(player: Player, amount: int) -> void:
	if player.has_method("refill_ammo"):
		player.refill_ammo(amount)
		print("AmmoPack: %s reabastecido (+%d)" % [player.name, amount])
	elif player.active_weapon and is_instance_valid(player.active_weapon):
		var weapon: Weapon = player.active_weapon
		weapon.reserve_ammo = min(weapon.reserve_ammo + amount, weapon.max_ammo)
		weapon.weapon_ammo_changed.emit(weapon.ammo_in_mag, weapon.reserve_ammo)


func _refill_npc(npc: BotBase, amount: int) -> void:
	if npc.has_method("refill_ammo"):
		npc.refill_ammo(amount)
		print("AmmoPack: NPC %s reabastecido (+%d)" % [npc.name, amount])
	elif "reserve_ammo" in npc and "max_ammo" in npc:
		npc.reserve_ammo = min(npc.reserve_ammo + amount, npc.max_ammo)


## Visual: caja de munición amarilla/municiones.
func _update_visual() -> void:
	if not is_inside_tree():
		return
	if label_3d:
		label_3d.text = "Munición"
		label_3d.modulate = Color(1.0, 0.85, 0.2)

	var mesh: MeshInstance3D = find_child("ItemMesh") as MeshInstance3D
	if not mesh:
		return
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.3, 0.3, 0.3)
	mesh.mesh = box_mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.7, 0.1)  # Amarillo munición
	mesh.set_surface_override_material(0, mat)