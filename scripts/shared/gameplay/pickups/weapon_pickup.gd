# scripts/weapon_pickup.gd
# Representa un arma en el suelo que puede ser recogida.
# Se crea cuando un NPC muere (drop) o puede colocarse en el mapa.
#
# Comportamiento al recoger:
# - Jugador/NPC ya tiene el arma → suma la munición del pickup
# - Jugador/NPC no tiene el arma → la equipa con su estado exacto
extends Pickup
class_name WeaponPickup

# ─── Inicialización ───────────────────────────────────────────────────
func _ready() -> void:
	pickup_type = Type.WEAPON
	# La scene tree se inicializa, luego llamamos a super._ready()
	# que ejecuta _update_visual()
	super()

## Configura los datos del arma desde un diccionario.
## Espera: {"tipo_arma", "balas_cargador", "balas_reserva", "capacidad_cargador"}
func set_weapon_data(data: Dictionary) -> void:
	pickup_data = data.duplicate()
	_update_visual()

# ─── Lógica de recogida ───────────────────────────────────────────────
func _on_picked_up(picker: Node) -> void:
	var weapon_name: String = pickup_data.get("tipo_arma", "")
	if weapon_name == "":
		return

	var balas_cargador: int = pickup_data.get("balas_cargador", 0)
	var balas_reserva: int = pickup_data.get("balas_reserva", 0)
	var capacidad_cargador: int = pickup_data.get("capacidad_cargador", 0)

	# ── Caso: Jugador humano ───────────────────────────────────────
	if picker is Player:
		_recoger_por_jugador(picker, weapon_name, balas_cargador, balas_reserva, capacidad_cargador)
		return

	# ── Caso: NPC / Bot ────────────────────────────────────────────
	if picker is NpcBase:
		_recoger_por_npc(picker, weapon_name, balas_cargador, balas_reserva, capacidad_cargador)
		return

# ─── Recogida por jugador ─────────────────────────────────────────────
func _recoger_por_jugador(player: Player, weapon_name: String, balas_cargador: int, balas_reserva: int, _capacidad_cargador: int) -> void:
	# Verificar si el jugador ya tiene esta arma equipada
	var tiene_misma_arma: bool = false
	if player.active_weapon and is_instance_valid(player.active_weapon):
		tiene_misma_arma = player.active_weapon.weapon_name.to_lower() == weapon_name.to_lower()

	if tiene_misma_arma:
		# Caso 1: Ya tiene el arma → sumar balas
		var weapon: Weapon = player.active_weapon
		weapon.ammo_in_mag += balas_cargador
		weapon.ammo_in_mag = min(weapon.ammo_in_mag, weapon.clip_size)
		weapon.reserve_ammo += balas_reserva
		weapon.reserve_ammo = min(weapon.reserve_ammo, weapon.max_ammo)
		weapon.weapon_ammo_changed.emit(weapon.ammo_in_mag, weapon.reserve_ammo)
		print("WeaponPickup: %s recogió balas de %s (cargador=%d reserva=%d)" % [
			player.name, weapon_name, balas_cargador, balas_reserva
		])
	else:
		# Caso 2: No tiene el arma → equiparla
		if not player.active_weapon or not is_instance_valid(player.active_weapon):
			player.setup_weapon(weapon_name)
		else:
			player.cambiar_arma(weapon_name)

		if player.active_weapon and is_instance_valid(player.active_weapon):
			player.active_weapon.ammo_in_mag = balas_cargador
			player.active_weapon.reserve_ammo = balas_reserva
			player.active_weapon.weapon_ammo_changed.emit(
				player.active_weapon.ammo_in_mag, player.active_weapon.reserve_ammo
			)
			print("WeaponPickup: %s equipó %s (cargador=%d reserva=%d)" % [
				player.name, weapon_name, balas_cargador, balas_reserva
			])

# ─── Recogida por NPC ─────────────────────────────────────────────────
func _recoger_por_npc(npc: NpcBase, weapon_name: String, balas_cargador: int, balas_reserva: int, _capacidad_cargador: int) -> void:
	npc.pickup_weapon({
		"tipo_arma": weapon_name,
		"balas_cargador": balas_cargador,
		"balas_reserva": balas_reserva,
		"capacidad_cargador": _capacidad_cargador
	})
	print("WeaponPickup: NPC %s recogió %s" % [npc.name, weapon_name])

# ─── Visual ───────────────────────────────────────────────────────────
func _update_visual() -> void:
	if not is_inside_tree():
		return

	# Actualizar label
	if label_3d:
		var wname: String = pickup_data.get("tipo_arma", "")
		if wname != "":
			label_3d.text = wname
			label_3d.modulate = Color(1.0, 0.85, 0.2)
		else:
			label_3d.text = "Arma"

	# Actualizar malla visual
	var weapon_mesh: MeshInstance3D = find_child("WeaponMesh") as MeshInstance3D
	if not weapon_mesh:
		return

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.25, 0.08, 0.15)
	weapon_mesh.mesh = box_mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED

	var nombre_bajo: String = pickup_data.get("tipo_arma", "").to_lower()
	if nombre_bajo in ["usp", "glock", "deagle"]:
		mat.albedo_color = Color(0.6, 0.6, 0.4)  # Pistola: dorado
	elif nombre_bajo in ["m3", "spas12", "recortada", "escopetaautomatica"]:
		mat.albedo_color = Color(0.7, 0.4, 0.2)  # Escopeta: marrón
	elif nombre_bajo in ["mp7", "mp5"]:
		mat.albedo_color = Color(0.3, 0.3, 0.5)  # Subfusil: azul grisáceo
	elif nombre_bajo in ["aug", "m4", "g36"]:
		mat.albedo_color = Color(0.2, 0.5, 0.2)  # Rifle: verde
	elif nombre_bajo in ["scout", "awp"]:
		mat.albedo_color = Color(0.3, 0.2, 0.6)  # Francotirador: púrpura
	else:
		mat.albedo_color = Color(0.5, 0.5, 0.5)  # Melee/otro: gris

	weapon_mesh.set_surface_override_material(0, mat)
