# scripts/weapon_pickup.gd
# Representa un arma en el suelo que puede ser recogida.
# Se crea cuando un NPC muere (drop) o puede colocarse en el mapa.
#
# Comportamiento al recoger:
# - Jugador/NPC ya tiene el arma → suma la munición del pickup
# - Jugador/NPC no tiene el arma → la equipa con su estado exacto
# @tool: el script se ejecuta en el editor para poder leer skill.json,
# generar el desplegable de armas y rellenar automáticamente la munición.
@tool
extends Pickup
class_name WeaponPickup

## Ruta del archivo que define todas las armas del juego.
const WEAPON_CONFIG_PATH := "res://config/Compartido/skill.json"

# ─── Arma colocada (propiedades que el Inspector muestra) ───────────────
# Estas propiedades se exponen al Inspector mediante _get_property_list().
# `weapon_name` es un menú desplegable cuyas opciones se generan
# automáticamente desde skill.json (nada que mantener a mano).
## Nombre del arma tirada en el suelo. Menú desplegable con todas las armas.
var weapon_name: String = "Glock"
## Munición inicial en el cargador. Se rellena automáticamente al elegir el arma.
var starting_mag_ammo: int = 20
## Munición inicial de reserva. Se rellena automáticamente al elegir el arma.
var starting_reserve_ammo: int = 60
## Si el arma permanece en el suelo tras ser usada (no se gasta al recogerla).
var persistent_on_floor: bool = false

## Arma cuyos valores por defecto ya fueron aplicados a la munición.
var _ammo_applied_for: String = ""

# ─── Inspector: propiedades virtuales y desplegable dinámico ─────────────
func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append({
		"name": "Arma colocada",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_CATEGORY,
	})
	# Opciones del desplegable: se leen de skill.json en cada consulta,
	# así la lista se mantiene al día automáticamente al añadir nuevas armas.
	var armas: Array[String] = _load_weapon_names()
	if armas.is_empty():
		armas = ["Glock", "USP", "Deagle"]
	props.append({
		"name": "weapon_name",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(armas),
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "starting_mag_ammo",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "1,1000,1,or_greater",
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "starting_reserve_ammo",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,10000,1,or_greater",
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	props.append({
		"name": "persistent_on_floor",
		"type": TYPE_BOOL,
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE,
	})
	return props


func _get(property: StringName) -> Variant:
	match property:
		&"weapon_name":
			return weapon_name
		&"starting_mag_ammo":
			return starting_mag_ammo
		&"starting_reserve_ammo":
			return starting_reserve_ammo
		&"persistent_on_floor":
			return persistent_on_floor
	return null


func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"weapon_name":
			weapon_name = str(value)
			_on_weapon_changed(str(value))
			return true
		&"starting_mag_ammo":
			starting_mag_ammo = int(value)
			return true
		&"starting_reserve_ammo":
			starting_reserve_ammo = int(value)
			return true
		&"persistent_on_floor":
			persistent_on_floor = bool(value)
			return true
	return false


## Al cambiar el arma en el Inspector, rellena automáticamente la munición con
## los valores por defecto de esa arma (TamanoCargador / ReservaMunicionMaxima).
## Solo actúa en el editor: en tiempo de ejecución no modifica nada (el gameplay
## sigue usando exactamente los valores guardados en la escena).
func _on_weapon_changed(nombre: String) -> void:
	if not Engine.is_editor_hint():
		return
	if nombre == _ammo_applied_for:
		return
	var cfg: Dictionary = _load_weapon_config(nombre)
	if cfg.is_empty():
		return
	starting_mag_ammo = int(cfg.get("TamanoCargador", starting_mag_ammo))
	starting_reserve_ammo = int(cfg.get("ReservaMunicionMaxima", starting_reserve_ammo))
	_ammo_applied_for = nombre
	notify_property_list_changed()
	if is_inside_tree():
		_update_visual()

# ─── Lectura de skill.json ──────────────────────────────────────────────

## Devuelve todos los datos de armas de skill.json: { nombre_arma: { campos... } }.
func _load_weapon_data() -> Dictionary:
	var datos: Dictionary = {}
	var file := FileAccess.open(WEAPON_CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("weapon_pickup: no se pudo leer " + WEAPON_CONFIG_PATH)
		return datos
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("weapon_pickup: error al parsear " + WEAPON_CONFIG_PATH)
		return datos
	var armas: Variant = json.data.get("ConfiguracionJuego", {}).get("Armas", {})
	if armas is Dictionary:
		for _categoria: Variant in armas:
			var lista: Variant = armas[_categoria]
			if lista is Dictionary:
				datos.merge(lista, true)
	return datos


func _load_weapon_names() -> Array[String]:
	var resultado: Array[String] = []
	for nombre: Variant in _load_weapon_data():
		resultado.append(str(nombre))
	return resultado


func _load_weapon_config(nombre: String) -> Dictionary:
	return _load_weapon_data().get(nombre, {})

# ─── Inicialización ───────────────────────────────────────────────────
func _ready() -> void:
	# En el editor (script @tool) no queremos correr toda la lógica física ni
	# el registro del pickup: solo preparamos los datos del arma y el rótulo.
	if Engine.is_editor_hint():
		pickup_data = _build_pickup_data()
		_update_visual()
		return
	# ── En tiempo de ejecución ──────────────────────────────────────
	pickup_type = Type.WEAPON
	respawn_on_pickup = false
	persistent_on_pickup = persistent_on_floor
	if pickup_data.is_empty():
		pickup_data = _build_pickup_data()
	# La scene tree se inicializa, luego llamamos a super._ready()
	# que ejecuta _update_visual()
	super()

## Construye el diccionario de datos del arma desde las propiedades de Inspector.
func _build_pickup_data() -> Dictionary:
	return {
		"tipo_arma": weapon_name,
		"balas_cargador": starting_mag_ammo,
		"balas_reserva": starting_reserve_ammo,
		"capacidad_cargador": starting_mag_ammo,
	}

## Configura los datos del arma desde un diccionario.
## Espera: {"tipo_arma", "balas_cargador", "balas_reserva", "capacidad_cargador"}
func set_weapon_data(data: Dictionary) -> void:
	pickup_data = data.duplicate()
	weapon_name = str(pickup_data.get("tipo_arma", weapon_name))
	starting_mag_ammo = int(pickup_data.get("balas_cargador", starting_mag_ammo))
	starting_reserve_ammo = int(pickup_data.get("balas_reserva", starting_reserve_ammo))
	_update_visual()

# ─── Lógica de recogida ───────────────────────────────────────────────
func _on_picked_up(picker: Node) -> void:
	var picked_weapon_name: String = pickup_data.get("tipo_arma", "")
	if picked_weapon_name == "":
		return

	var balas_cargador: int = pickup_data.get("balas_cargador", 0)
	var balas_reserva: int = pickup_data.get("balas_reserva", 0)
	var capacidad_cargador: int = pickup_data.get("capacidad_cargador", 0)

	# ── Caso: Jugador humano ───────────────────────────────────────
	if picker is Player:
		_recoger_por_jugador(picker, picked_weapon_name, balas_cargador, balas_reserva, capacidad_cargador)
		return

	# ── Caso: NPC / Bot ────────────────────────────────────────────
	if picker is BotBase:
		_recoger_por_npc(picker, picked_weapon_name, balas_cargador, balas_reserva, capacidad_cargador)
		return

# ─── Recogida por jugador ─────────────────────────────────────────────
func _recoger_por_jugador(player: Player, picked_weapon_name: String, balas_cargador: int, balas_reserva: int, _capacidad_cargador: int) -> void:
	# Verificar si el jugador ya tiene esta arma equipada
	var tiene_misma_arma: bool = false
	if player.active_weapon and is_instance_valid(player.active_weapon):
		tiene_misma_arma = player.active_weapon.weapon_name.to_lower() == picked_weapon_name.to_lower()

	if tiene_misma_arma:
		# Caso 1: Ya tiene el arma → sumar balas
		var weapon: Weapon = player.active_weapon
		weapon.ammo_in_mag += balas_cargador
		weapon.ammo_in_mag = min(weapon.ammo_in_mag, weapon.clip_size)
		weapon.reserve_ammo += balas_reserva
		weapon.reserve_ammo = min(weapon.reserve_ammo, weapon.max_ammo)
		weapon.weapon_ammo_changed.emit(weapon.ammo_in_mag, weapon.reserve_ammo)
		print("WeaponPickup: %s recogió balas de %s (cargador=%d reserva=%d)" % [
			player.name, picked_weapon_name, balas_cargador, balas_reserva
		])
	else:
		# Caso 2: No tiene el arma → equiparla
		if not player.active_weapon or not is_instance_valid(player.active_weapon):
			player.setup_weapon(picked_weapon_name)
		else:
			# El arma actual se queda en el suelo (drop) antes de equipar la nueva
			if player.has_method("drop_current_weapon"):
				player.drop_current_weapon()
			player.cambiar_arma(picked_weapon_name)

		if player.active_weapon and is_instance_valid(player.active_weapon):
			player.active_weapon.ammo_in_mag = balas_cargador
			player.active_weapon.reserve_ammo = balas_reserva
			player.active_weapon.weapon_ammo_changed.emit(
				player.active_weapon.ammo_in_mag, player.active_weapon.reserve_ammo
			)
			print("WeaponPickup: %s equipó %s (cargador=%d reserva=%d)" % [
				player.name, picked_weapon_name, balas_cargador, balas_reserva
			])

# ─── Persistencia de campaña (arma tirada) ─────────────────────────────
## Además del estado de recogida heredado, guardamos la POSICIÓN y los DATOS
## del arma. Así, si un NPC la soltó en una visita anterior (arma dinámica,
## clave "dyn_drop_*"), el nivel puede re-crearla al volver (ver
## LevelStateManager.collect_dynamic_drops). Para los pickups colocados en el
## mapa estos campos extra se ignoran (se restauran en su sitio).
func get_persistent_state() -> Dictionary:
	var st: Dictionary = super.get_persistent_state()
	st["transform"] = [
		global_position.x, global_position.y, global_position.z, global_rotation.y
	]
	st["weapon_data"] = pickup_data
	return st


## Al dejar el arma «recogida para siempre» (state_id de campaña), el modelo
## real de esta escena se llama WeaponMesh (la base busca un nodo "ItemMesh"
## que aquí no existe y no lo ocultaría). Lo escondemos aquí para que el arma
## desaparezca del suelo al recogerla — tanto al recogerla en vivo como al
## restaurar el estado recogido al volver al mapa.
func _mark_collected_permanent() -> void:
	super._mark_collected_permanent()
	var weapon_mesh: MeshInstance3D = find_child("WeaponMesh") as MeshInstance3D
	if weapon_mesh != null and not weapon_mesh.is_queued_for_deletion():
		weapon_mesh.hide()


# ─── Recogida por NPC ─────────────────────────────────────────────────
func _recoger_por_npc(npc: BotBase, picked_weapon_name: String, balas_cargador: int, balas_reserva: int, _capacidad_cargador: int) -> void:
	npc.pickup_weapon({
		"tipo_arma": picked_weapon_name,
		"balas_cargador": balas_cargador,
		"balas_reserva": balas_reserva,
		"capacidad_cargador": _capacidad_cargador
	})
	print("WeaponPickup: NPC %s recogió %s" % [npc.name, picked_weapon_name])

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
	# Apuntar el modelo real al campo que usa la base para ocultarlo al quedar
	# recogido (la base busca "ItemMesh"; aquí se llama "WeaponMesh").
	_item_mesh = weapon_mesh

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
