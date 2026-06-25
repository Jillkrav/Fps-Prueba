# scripts/dropped_weapon.gd
# Arma que un NPC deja caer al morir. El jugador puede recogerla.
# - Si el jugador ya tiene ese tipo de arma: se agregan las balas
#   (cargador + reserva) al inventario del jugador.
# - Si no la tiene: la equipa con el estado exacto (cargador y balas).
extends RigidBody3D
class_name DroppedWeapon

signal picked_up(weapon_name: String)

# ─── Datos del arma ───────────────────────────────────────────────────
var tipo_arma: String = ""
var balas_cargador: int = 0
var balas_reserva: int = 0
var capacidad_cargador: int = 0

@onready var pickup_area: Area3D = $PickupArea
@onready var weapon_mesh: MeshInstance3D = $WeaponMesh
@onready var label_3d: Label3D = $Label3D
@onready var despawn_timer: Timer = $DespawnTimer

func _ready() -> void:
	if pickup_area:
		pickup_area.body_entered.connect(_on_pickup_area_entered)
	if despawn_timer:
		despawn_timer.timeout.connect(_on_despawn_timeout)
		despawn_timer.start()

	# Aplicar gravedad normal
	gravity_scale = 1.0
	# Permitir rotación libre (el arma puede rodar un poco al caer)

	# Mostrar nombre en Label3D
	if label_3d and tipo_arma != "":
		label_3d.text = tipo_arma
		label_3d.modulate = Color(1.0, 0.85, 0.2)

	# Mostrar malla visual (un cubo pequeño representando el arma)
	_update_mesh()

func set_weapon_data(data: Dictionary) -> void:
	tipo_arma = data.get("tipo_arma", "")
	balas_cargador = data.get("balas_cargador", 0)
	balas_reserva = data.get("balas_reserva", 0)
	capacidad_cargador = data.get("capacidad_cargador", 0)

	if label_3d and tipo_arma != "":
		label_3d.text = tipo_arma

	_update_mesh()

func _update_mesh() -> void:
	if not weapon_mesh:
		return
	# Crear un cubo con color basado en el tipo de arma
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.25, 0.08, 0.15)
	weapon_mesh.mesh = box_mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED

	# Color del arma según tipo
	var nombre_bajo: String = tipo_arma.to_lower()
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

func _on_pickup_area_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if tipo_arma == "":
		return

	var player: Player = body as Player
	if not player or not is_instance_valid(player):
		return

	_recoger_por_jugador(player)

func _recoger_por_jugador(player: Player) -> void:
	# Verificar si el jugador ya tiene esta arma
	var tiene_misma_arma: bool = false
	if player.active_weapon and is_instance_valid(player.active_weapon):
		# Comparar por nombre
		var weapon_name_lower: String = player.active_weapon.weapon_name.to_lower()
		tiene_misma_arma = (weapon_name_lower == tipo_arma.to_lower())

	if tiene_misma_arma:
		# Caso 1: Ya tiene el arma -> sumar balas
		var weapon: Weapon = player.active_weapon
		# Las balas del cargador del NPC se suman al cargador actual del jugador
		# Las balas de reserva del NPC se suman a la reserva del jugador
		weapon.ammo_in_mag += balas_cargador
		weapon.ammo_in_mag = min(weapon.ammo_in_mag, weapon.clip_size)
		weapon.reserve_ammo += balas_reserva
		weapon.reserve_ammo = min(weapon.reserve_ammo, weapon.max_ammo)
		weapon.weapon_ammo_changed.emit(weapon.ammo_in_mag, weapon.reserve_ammo)
		print("DroppedWeapon: %s recogió balas de %s (cargador=%d reserva=%d)" % [
			player.name, tipo_arma, balas_cargador, balas_reserva
		])
	else:
		# Caso 2: No tiene el arma -> equiparla con el estado exacto del NPC
		# Primero, cambiar al arma (inicializa con valores fresh)
		# Luego sobreescribir con los valores del NPC
		if not player.active_weapon:
			player.setup_weapon(tipo_arma)
		else:
			player.cambiar_arma(tipo_arma)

		if player.active_weapon and is_instance_valid(player.active_weapon):
			player.active_weapon.ammo_in_mag = balas_cargador
			player.active_weapon.reserve_ammo = balas_reserva
			player.active_weapon.weapon_ammo_changed.emit(
				player.active_weapon.ammo_in_mag, player.active_weapon.reserve_ammo
			)
			print("DroppedWeapon: %s equipó %s (cargador=%d/%d reserva=%d)" % [
				player.name, tipo_arma, balas_cargador, capacidad_cargador, balas_reserva
			])

	picked_up.emit(tipo_arma)
	queue_free()

func _on_despawn_timeout() -> void:
	# Desaparecer después de 30 segundos
	queue_free()
