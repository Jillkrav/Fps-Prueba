@tool
class_name StoryElevator
extends Node3D

## Ascensor tuneable para Historia. Una sala (cuarto) que se desplaza
## verticalmente entre pisos, amplia para 4+ NPCs.
## Toda la configuración se hace desde el Inspector: dimensiones de la sala,
## puertas, velocidad, pisos, colores... El script genera la geometría y la
## reconstruye al cambiar cualquier parámetro, tanto en el editor (se ve la
## sala mientras la configuras) como al arrancar el juego.
##
## Control externo (StoryActionButton, cinemáticas, objetivos...):
##   - call_to_floor(piso)   -> ir a un piso concreto
##   - go_up() / go_down()   -> subir / bajar un piso
##   - activate()/deactivate() -> conveniencias (sube / baja)
##   - set_floor(piso)       -> teletransporte instantáneo (setup)
##
## Los NPCs (grupo "npc") y jugadores que estén dentro se "montan" en el
## ascensor durante el viaje y se sueltan al abrirse las puertas en destino.

signal arrived(floor: int)
signal departed(floor: int)
signal doors_opened()
signal doors_closed()
signal call_registered(floor: int)

enum DoorState { CLOSED, OPENING, OPEN, CLOSING }

# ── Configuración (todo desde el Inspector) ──────────────────────────────────
@export_category("Sala (dimensiones)")
@export var room_width: float = 6.0:
	set(value):
		room_width = value
		_queue_rebuild()
@export var room_depth: float = 5.0:
	set(value):
		room_depth = value
		_queue_rebuild()
@export var room_height: float = 3.2:
	set(value):
		room_height = value
		_queue_rebuild()
@export var wall_thickness: float = 0.3:
	set(value):
		wall_thickness = value
		_queue_rebuild()

@export_category("Puertas")
@export var door_width: float = 2.2:
	set(value):
		door_width = value
		_queue_rebuild()
@export var door_height: float = 2.6:
	set(value):
		door_height = value
		_queue_rebuild()
@export_range(0.2, 4.0, 0.05) var door_time: float = 0.8
@export_range(0.0, 10.0, 0.25) var door_dwell: float = 2.0

@export_category("Movimiento")
@export_range(1, 40, 1) var floor_count: int = 3:
	set(value):
		floor_count = maxi(1, value)
		start_floor = clampi(start_floor, 0, floor_count - 1)
		current_floor = clampi(current_floor, 0, floor_count - 1)
		_queue_rebuild()
@export var floor_height: float = 4.0:
	set(value):
		floor_height = value
		_queue_rebuild()
@export var max_speed: float = 3.0
@export var acceleration: float = 2.0
@export_range(0, 40, 1) var start_floor: int = 0:
	set(value):
		start_floor = clampi(value, 0, maxi(0, floor_count - 1))
		_queue_rebuild()

@export_category("Comportamiento")
@export var open_doors_on_arrival: bool = true
@export var open_doors_on_ready: bool = true:
	set(value):
		open_doors_on_ready = value
		_queue_rebuild()
@export var auto_close_doors: bool = true
@export var carry_npcs: bool = true
@export var carry_players: bool = true

@export_category("Presentación")
@export var display_name: String = "ASCENSOR":
	set(value):
		display_name = value
		_queue_rebuild()
@export var floor_label_visible: bool = true:
	set(value):
		floor_label_visible = value
		_queue_rebuild()
@export var debug: bool = false

@export_category("Apariencia")
@export var wall_color: Color = Color(0.45, 0.48, 0.52):
	set(value):
		wall_color = value
		_queue_rebuild()
@export var floor_color: Color = Color(0.30, 0.32, 0.35):
	set(value):
		floor_color = value
		_queue_rebuild()
@export var ceiling_color: Color = Color(0.80, 0.82, 0.85):
	set(value):
		ceiling_color = value
		_queue_rebuild()
@export var door_color: Color = Color(0.20, 0.35, 0.50):
	set(value):
		door_color = value
		_queue_rebuild()
@export var accent_color: Color = Color(0.90, 0.70, 0.20):
	set(value):
		accent_color = value
		_queue_rebuild()

@export_category("Persistencia (campaña)")
## ID único dentro del nivel. Si está vacío, el piso actual NO se recuerda al
## volver al mapa (se reinicia a start_floor, como antes).
@export var state_id: String = ""

# ── Nodos internos (creados por el script) ───────────────────────────────────
var carriage: StaticBody3D
var door_l: StaticBody3D
var door_r: StaticBody3D
var carrier_zone: Area3D
var panel_label: Label3D
var prompt_label: Label3D

var current_floor: int = 0
var is_moving: bool = false

var _generated: Array[Node] = []
var _velocity_y: float = 0.0
var _target_floor: int = 0
var _pending_move_floor: int = -1
var _door_state: DoorState = DoorState.CLOSED
var _occupants: Dictionary = {}          # body -> nodo padre original
var _door_closed_x: Dictionary = {}      # puerta -> x cerrada
var _door_open_x: Dictionary = {}        # puerta -> x abierta
var _door_tweens: Array[Tween] = []
var _door_collisions: Array[CollisionShape3D] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		# Construye la sala en el editor para poder tunearla visualmente.
		_rebuild()
		return
	current_floor = clampi(start_floor, 0, floor_count - 1)
	_rebuild()
	position.y = float(current_floor) * floor_height
	if open_doors_on_ready:
		_set_door_instant(true)
	_update_prompt()
	if not state_id.is_empty():
		LevelStateManager.register(self)
		call_deferred("_restore_persistent_state")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_moving:
		_velocity_y = 0.0
		return
	# Monta a cualquiera que suba a mitad de viaje.
	if carry_npcs or carry_players:
		_attach_occupants()

	var target_y: float = float(_target_floor) * floor_height
	var diff: float = target_y - position.y
	var dir: float = signf(diff)
	_velocity_y += dir * acceleration * delta
	_velocity_y = clampf(_velocity_y, -max_speed, max_speed)

	# Deceleración suave al acercarse al destino.
	var dist_to_stop: float = (_velocity_y * _velocity_y) / (2.0 * acceleration)
	if absf(diff) <= dist_to_stop:
		_velocity_y = dir * maxf(0.0, sqrt(2.0 * acceleration * absf(diff)))

	position.y += _velocity_y * delta
	if absf(diff) < 0.02:
		position.y = target_y
		_arrive(_target_floor)


# ── API de control ───────────────────────────────────────────────────────────
func call_to_floor(floor_index: int) -> void:
	var f: int = clampi(floor_index, 0, floor_count - 1)
	if debug:
		print("[%s] llamada al piso %d (actual %d, moviendose %s)" % [display_name, f, current_floor, is_moving])
	if f == current_floor:
		if _door_state == DoorState.CLOSED:
			open_doors()
		return
	if is_moving:
		_pending_move_floor = f
		call_registered.emit(f)
		return
	call_registered.emit(f)
	_start_motion(f)


func go_up() -> void:
	call_to_floor(current_floor + 1)


func go_down() -> void:
	call_to_floor(current_floor - 1)


## Conveniencia para StoryActionButton / botones.
func activate() -> void:
	go_up()


func deactivate() -> void:
	go_down()


## Teletransporte instantáneo a un piso (para setup / persistencia).
func set_floor(floor_index: int) -> void:
	var f: int = clampi(floor_index, 0, floor_count - 1)
	current_floor = f
	position.y = float(f) * floor_height
	is_moving = false
	_velocity_y = 0.0
	_target_floor = f
	_pending_move_floor = -1
	_update_prompt()


func open_doors() -> void:
	if _door_state == DoorState.OPEN or _door_state == DoorState.OPENING:
		return
	_kill_door_tweens()
	_door_state = DoorState.OPENING
	_enable_door_collisions(false)
	for door: StaticBody3D in [door_l, door_r]:
		var t: Tween = create_tween()
		t.tween_property(door, "position:x", _door_open_x[door], door_time)
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_door_tweens.append(t)
	await _door_timer(door_time)
	_door_state = DoorState.OPEN
	doors_opened.emit()
	_release_occupants()
	_update_prompt()
	if auto_close_doors and not is_moving:
		await _door_timer(door_dwell)
		close_doors()


func close_doors() -> void:
	if _door_state == DoorState.CLOSED or _door_state == DoorState.CLOSING:
		return
	if is_moving:
		return
	_kill_door_tweens()
	_door_state = DoorState.CLOSING
	for door: StaticBody3D in [door_l, door_r]:
		var t: Tween = create_tween()
		t.tween_property(door, "position:x", _door_closed_x[door], door_time)
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_door_tweens.append(t)
	await _door_timer(door_time)
	_door_state = DoorState.CLOSED
	_enable_door_collisions(true)
	doors_closed.emit()
	_update_prompt()
	if _pending_move_floor >= 0:
		var move_target: int = _pending_move_floor
		_pending_move_floor = -1
		_start_motion(move_target)


# ── Movimiento ───────────────────────────────────────────────────────────────
func _start_motion(floor_index: int) -> void:
	if _door_state != DoorState.CLOSED:
		# Esperar a que se cierren antes de arrancar.
		_pending_move_floor = floor_index
		close_doors()
		return
	_target_floor = floor_index
	if carry_npcs or carry_players:
		_attach_occupants()
	is_moving = true
	departed.emit(current_floor)
	_update_prompt()


func _arrive(floor_index: int) -> void:
	is_moving = false
	_velocity_y = 0.0
	current_floor = floor_index
	arrived.emit(floor_index)
	if open_doors_on_arrival:
		open_doors()
	else:
		_update_prompt()


# ── Ocupantes (montar / soltar) ──────────────────────────────────────────────
func _should_carry(body: Node3D) -> bool:
	if body == null:
		return false
	if body.is_in_group(&"npc"):
		return carry_npcs
	if body is Player or body.is_in_group(&"player"):
		return carry_players
	return false


func _attach_occupants() -> void:
	for body: Node3D in carrier_zone.get_overlapping_bodies():
		if _occupants.has(body):
			continue
		if not _should_carry(body):
			continue
		_occupants[body] = body.get_parent()
		_reparent_keep_transform(body, self)


func _release_occupants() -> void:
	if _occupants.is_empty():
		return
	for body: Node3D in _occupants.keys():
		if is_instance_valid(body):
			_reparent_keep_transform(body, _occupants[body])
	_occupants.clear()


func _reparent_keep_transform(node: Node3D, new_parent: Node) -> void:
	var old_parent: Node = node.get_parent()
	if old_parent == null or new_parent == null:
		return
	var gt: Transform3D = node.global_transform
	old_parent.remove_child(node)
	new_parent.add_child(node)
	node.global_transform = gt


# ── Reconstrucción en el editor / al tunear ──────────────────────────────────
func _queue_rebuild() -> void:
	call_deferred("_rebuild")


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_clear_geometry()
	_build_geometry()
	if Engine.is_editor_hint() or open_doors_on_ready:
		_set_door_instant(true)
	else:
		_set_door_instant(false)
	_update_prompt()


func _clear_geometry() -> void:
	_kill_door_tweens()
	for n: Node in _generated:
		if is_instance_valid(n):
			n.queue_free()
	_generated.clear()
	_door_collisions.clear()
	_door_closed_x.clear()
	_door_open_x.clear()
	carriage = null
	door_l = null
	door_r = null
	carrier_zone = null
	panel_label = null
	prompt_label = null


# ── Construcción de geometría ────────────────────────────────────────────────
func _build_geometry() -> void:
	carriage = StaticBody3D.new()
	carriage.name = "Carriage"
	add_child(carriage)
	_generated.append(carriage)

	var mat_wall: StandardMaterial3D = _make_material(wall_color)
	var mat_floor: StandardMaterial3D = _make_material(floor_color)
	var mat_ceiling: StandardMaterial3D = _make_material(ceiling_color)
	var mat_door: StandardMaterial3D = _make_material(door_color)
	var mat_accent: StandardMaterial3D = _make_material(accent_color)

	_add_box(carriage, "Floor", Vector3(room_width, wall_thickness, room_depth), Vector3(0, wall_thickness * 0.5, 0), mat_floor)
	_add_box(carriage, "Ceiling", Vector3(room_width, wall_thickness, room_depth), Vector3(0, room_height - wall_thickness * 0.5, 0), mat_ceiling)
	_add_box(carriage, "WallBack", Vector3(room_width, room_height, wall_thickness), Vector3(0, room_height * 0.5, -room_depth * 0.5), mat_wall)
	_add_box(carriage, "WallLeft", Vector3(wall_thickness, room_height, room_depth), Vector3(-room_width * 0.5, room_height * 0.5, 0), mat_wall)
	_add_box(carriage, "WallRight", Vector3(wall_thickness, room_height, room_depth), Vector3(room_width * 0.5, room_height * 0.5, 0), mat_wall)
	var beam_h: float = room_height - door_height
	if beam_h > 0.0:
		_add_box(carriage, "FrontBeam", Vector3(room_width, beam_h, wall_thickness), Vector3(0, door_height + beam_h * 0.5, room_depth * 0.5), mat_wall)

	# Borde del suelo delante de la puerta (accent).
	_add_box(carriage, "DoorFrame", Vector3(door_width + 0.2, 0.08, wall_thickness), Vector3(0, 0.04, room_depth * 0.5), mat_accent)

	door_l = _add_door("DoorL", -1.0, mat_door)
	door_r = _add_door("DoorR", 1.0, mat_door)

	carrier_zone = Area3D.new()
	carrier_zone.name = "CarrierZone"
	add_child(carrier_zone)
	_generated.append(carrier_zone)
	var zone_shape: BoxShape3D = BoxShape3D.new()
	zone_shape.size = Vector3(maxf(0.2, room_width - 0.4), maxf(0.2, room_height - 0.6), maxf(0.2, room_depth - 0.4))
	var zone_col: CollisionShape3D = CollisionShape3D.new()
	zone_col.name = "CarrierZoneCol"
	zone_col.shape = zone_shape
	zone_col.position = Vector3(0, room_height * 0.5, 0)
	carrier_zone.add_child(zone_col)

	panel_label = Label3D.new()
	panel_label.name = "PanelLabel"
	panel_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	panel_label.position = Vector3(0, room_height - 0.35, -room_depth * 0.5 - 0.5)
	panel_label.modulate = accent_color
	panel_label.pixel_size = 0.01
	panel_label.outline_size = 6
	panel_label.visible = floor_label_visible
	add_child(panel_label)
	_generated.append(panel_label)

	prompt_label = Label3D.new()
	prompt_label.name = "PromptLabel"
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.position = Vector3(0, door_height + 0.3, room_depth * 0.5 + 0.8)
	prompt_label.modulate = Color(0.8, 0.95, 1.0)
	prompt_label.pixel_size = 0.01
	prompt_label.outline_size = 6
	add_child(prompt_label)
	_generated.append(prompt_label)

	_update_prompt()


func _make_material(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	m.metallic = 0.1
	return m


func _add_box(static_parent: Node3D, n: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = n + "Mesh"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	static_parent.add_child(mi)

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = n + "Col"
	cs.shape = shape
	cs.position = pos
	static_parent.add_child(cs)


func _add_door(n: String, side: float, mat: Material) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = n
	add_child(body)
	_generated.append(body)

	var leaf_w: float = door_width * 0.5
	var size: Vector3 = Vector3(leaf_w, door_height, wall_thickness)
	var start_x: float = side * door_width * 0.25

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = n + "Mesh"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(start_x, door_height * 0.5, room_depth * 0.5 + wall_thickness * 0.45)
	body.add_child(mi)

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = n + "Col"
	cs.shape = shape
	cs.position = Vector3(start_x, door_height * 0.5, room_depth * 0.5 + wall_thickness * 0.45)
	body.add_child(cs)

	_door_closed_x[body] = start_x
	_door_open_x[body] = start_x + side * (leaf_w + 0.15)
	_door_collisions.append(cs)
	return body


func _kill_door_tweens() -> void:
	for t: Tween in _door_tweens:
		if t != null and t.is_valid():
			t.kill()
	_door_tweens.clear()


func _set_door_instant(open: bool) -> void:
	# Aplica el estado de puerta sin animar (para _ready / editor).
	for door: StaticBody3D in [door_l, door_r]:
		if door == null:
			continue
		door.position.x = _door_open_x[door] if open else _door_closed_x[door]
	_door_state = DoorState.OPEN if open else DoorState.CLOSED
	_enable_door_collisions(not open)


func _enable_door_collisions(enabled: bool) -> void:
	for cs: CollisionShape3D in _door_collisions:
		cs.set_deferred("disabled", not enabled)


func _door_timer(seconds: float) -> void:
	await get_tree().create_timer(maxf(0.0, seconds)).timeout


func _update_prompt() -> void:
	if panel_label == null:
		return
	if floor_label_visible:
		var arrow: String = "^" if is_moving and _target_floor > current_floor else ("v" if is_moving else "")
		panel_label.text = "%s  PISO %d %s" % [display_name, current_floor, arrow]
	if prompt_label != null:
		prompt_label.text = "%s — Piso %d" % [display_name, current_floor]


# ── Persistencia de campaña (data-driven) ────────────────────────────────────
func _restore_persistent_state() -> void:
	var st: Dictionary = LevelStateManager.get_state_for(self, state_id)
	if st.has("current_floor"):
		set_floor(int(st["current_floor"]))


func get_persistent_state() -> Dictionary:
	return {"current_floor": current_floor}


func apply_persistent_state(state: Dictionary) -> void:
	if state.has("current_floor"):
		set_floor(int(state["current_floor"]))
