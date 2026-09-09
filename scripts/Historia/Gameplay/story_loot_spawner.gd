class_name StoryLootSpawner
extends Node3D

## Generador de loot para campaña, activable por eventos, botones u oleadas.
## Instancia armas, munición, botiquines o escenas propias a partir de recursos
## StoryLootEntry. No usa sistemas de multijugador.

const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/Compartido/pickups/dropped_weapon.tscn")
const AMMO_PICKUP_SCENE: PackedScene = preload("res://scenes/Compartido/pickups/ammo_pack.tscn")
const MEDKIT_PICKUP_SCENE: PackedScene = preload("res://scenes/Compartido/pickups/medkit.tscn")
const LOOT_WEAPON: int = 0
const LOOT_AMMO: int = 1
const LOOT_MEDKIT: int = 2
const LOOT_PACKED_SCENE: int = 3

@export_category("Loot")
## Añade recursos StoryLootEntry (.tres) desde el Inspector.
@export var entries: Array[Resource] = []
@export var spawn_on_ready: bool = false
@export var one_shot: bool = true
@export_range(0.0, 10.0, 0.05) var vertical_offset: float = 0.45

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, el loot vuelve a generarse al
## volver al mapa. Si se rellena, una recompensa ya generada no se regenera.
@export var state_id: String = ""

@export_category("Destino")
@export var spawn_parent: Node

var has_spawned: bool = false
var spawned_items: Array[Node] = []


func _ready() -> void:
	if not state_id.is_empty():
		LevelStateManager.register(self)
		call_deferred("_restore_persistent_state")
	if spawn_on_ready:
		call_deferred("activate")


func activate() -> void:
	if one_shot and has_spawned:
		return
	for entry: Resource in entries:
		var amount: int = int(entry.get("amount")) if entry != null else 0
		var chance: float = float(entry.get("chance")) if entry != null else 0.0
		if entry == null or amount <= 0 or randf() > chance:
			continue
		for index: int in amount:
			_spawn_entry(entry, index)
	has_spawned = true


func deactivate() -> void:
	for item: Node in spawned_items:
		if is_instance_valid(item):
			item.queue_free()
	spawned_items.clear()
	has_spawned = false


func reset_loot() -> void:
	deactivate()


func _spawn_entry(entry: Resource, index: int) -> void:
	var scene: PackedScene = _resolve_scene(entry)
	if scene == null:
		push_warning("[StoryLootSpawner] Entrada sin escena válida en '%s'." % name)
		return
	var instance: Node = scene.instantiate()
	var parent: Node = spawn_parent if spawn_parent != null else get_tree().current_scene
	if parent == null:
		parent = get_parent()
	if parent == null:
		return
	parent.add_child(instance)
	if instance is Node3D:
		var position_offset: Vector3 = _get_scatter(float(entry.get("spread_radius")), index)
		(instance as Node3D).global_position = global_position + position_offset + Vector3.UP * vertical_offset
	_apply_entry(instance, entry)
	spawned_items.append(instance)


func _resolve_scene(entry: Resource) -> PackedScene:
	var loot_type: int = int(entry.get("loot_type"))
	match loot_type:
		LOOT_WEAPON:
			return WEAPON_PICKUP_SCENE
		LOOT_AMMO:
			return AMMO_PICKUP_SCENE
		LOOT_MEDKIT:
			return MEDKIT_PICKUP_SCENE
		LOOT_PACKED_SCENE:
			return entry.get("packed_scene") as PackedScene
	return null


func _apply_entry(instance: Node, entry: Resource) -> void:
	var loot_type: int = int(entry.get("loot_type"))
	match loot_type:
		LOOT_WEAPON:
			if instance is WeaponPickup:
				var weapon: WeaponPickup = instance as WeaponPickup
				var weapon_name: String = str(entry.get("weapon_name"))
				var mag: int = int(entry.get("magazine_ammo"))
				var reserve: int = int(entry.get("reserve_ammo"))
				var defaults: Dictionary = _get_weapon_defaults(weapon_name)
				if mag < 0:
					mag = int(defaults.get("TamanoCargador", 0))
				if reserve < 0:
					reserve = int(defaults.get("ReservaMunicionMaxima", 0))
				weapon.weapon_name = weapon_name
				weapon.starting_mag_ammo = mag
				weapon.starting_reserve_ammo = reserve
				weapon.persistent_on_floor = bool(entry.get("persistent_on_floor"))
				weapon.set_weapon_data({
					"tipo_arma": weapon_name,
					"balas_cargador": mag,
					"balas_reserva": reserve,
					"capacidad_cargador": mag,
				})
		LOOT_AMMO:
			if instance is AmmoPack:
				var ammo: AmmoPack = instance as AmmoPack
				var ammo_amount: int = int(entry.get("ammo_amount"))
				ammo.ammo_amount = ammo_amount
				ammo.pickup_data["cantidad"] = ammo_amount
		LOOT_MEDKIT:
			if instance is Medkit:
				var medkit: Medkit = instance as Medkit
				var heal_amount: float = float(entry.get("heal_amount"))
				medkit.heal_amount = heal_amount
				medkit.pickup_data["curacion"] = heal_amount


func _get_weapon_defaults(weapon_name: String) -> Dictionary:
	var config_manager: Node = get_node_or_null("/root/ConfigManager")
	if config_manager != null and config_manager.has_method("get_arma"):
		return config_manager.call("get_arma", weapon_name) as Dictionary
	return {}


func _get_scatter(radius: float, index: int) -> Vector3:
	if radius <= 0.0 or index == 0:
		return Vector3.ZERO
	var angle: float = randf() * TAU
	var distance: float = randf() * radius
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


# ── Persistencia de campaña (data-driven) ────────────────────────────────────

func _restore_persistent_state() -> void:
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	apply_persistent_state(st)


func get_persistent_state() -> Dictionary:
	return {"spawned": has_spawned}


func apply_persistent_state(state: Dictionary) -> void:
	if bool(state.get("spawned", false)):
		has_spawned = true
