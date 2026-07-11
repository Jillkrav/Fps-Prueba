# scripts/core.gd
# Core destructible objective — base defense game mode.
# Inspired by FortStandard.uc from UT99 (Botpack/Prioridad).
# Extiende StaticBody3D para ser detectable por raycasts de armas.
class_name Core
extends StaticBody3D

signal core_destroyed(team: int)
signal health_changed(current: float, max_val: float)

@export var team: int = int(Enums.Equipo.AZUL)
@export var max_health: float = 500.0
@export var display_name: String = "Core"

var current_health: float = 500.0
var is_destroyed: bool = false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var label_3d: Label3D = $Label3D

func _ready() -> void:
	add_to_group("core")
	current_health = max_health
	# Auto-detectar equipo segun el nombre del nodo
	# Asi funciona incluso si el map_manager no esta attachado a la escena
	if "Rojo" in name or "Red" in name:
		team = int(Enums.Equipo.ROJO)
	elif "Azul" in name or "Blue" in name:
		team = int(Enums.Equipo.AZUL)
	_apply_team_appearance()
	
	# Conectar señales ANTES de emitir
	health_changed.connect(_on_health_changed)
	core_destroyed.connect(_on_core_destroyed)
	_update_health_label(current_health, max_health)
	health_changed.emit(current_health, max_health)
	
	# Registrarse en GameState (autoload) — esto inicia la partida cuando ambos cores esten listos
	call_deferred("_register_in_gamestate")
	
	_debug("ACTIVADO | Equipo=%s | HP=%d" % [GameState.nombre_equipo(team), int(max_health)])

func get_team() -> int:
	return team

func _register_in_gamestate() -> void:
	if is_instance_valid(GameState):
		GameState.register_core(self)

func _on_health_changed(current: float, max_val: float) -> void:
	if is_instance_valid(GameState):
		GameState.on_core_health_updated(team, current, max_val)
	_update_health_label(current, max_val)

func _on_core_destroyed(_team: int) -> void:
	if is_instance_valid(GameState):
		GameState.on_core_destroyed(_team)
	if is_instance_valid(TeamAI):
		TeamAI.on_core_destroyed(_team)

func _apply_team_appearance() -> void:
	if not mesh_instance:
		return
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
	if not mat:
		mat = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, mat)
	
	var color: Color = GameState.color_equipo(team)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.5
	mat.emission_energy_multiplier = 0.8
	
	# Tamaño del core según equipo (visual)
	mesh_instance.scale = Vector3(1.2, 1.0, 1.0)

func take_damage(amount: float, _zone: String = "Torso", _killer_id: int = -1) -> void:
	if is_destroyed:
		return
	current_health -= amount
	current_health = max(current_health, 0.0)
	health_changed.emit(current_health, max_health)
	
	# Feedback visual: parpadeo al recibir daño
	if mesh_instance:
		var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0)
		if mat:
			mat.emission_energy_multiplier = 2.0
			get_tree().create_timer(0.1).timeout.connect(
				func() -> void:
					if is_instance_valid(mat):
						mat.emission_energy_multiplier = 0.8
			)
	
	if current_health <= 0.0:
		_on_destroyed()

func _on_destroyed() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	_debug("DESTRUIDO | Equipo=%s" % GameState.nombre_equipo(team))
	
	# Efecto visual de destrucción
	if mesh_instance:
		mesh_instance.visible = false
	if label_3d:
		label_3d.text = "DESTRUIDO"
		label_3d.modulate = Color(1.0, 0.2, 0.2)
	
	core_destroyed.emit(team)

func _update_health_label(current: float, max_val: float) -> void:
	if not is_instance_valid(label_3d):
		return
	if is_destroyed:
		label_3d.text = "DESTRUIDO"
		return
	var pct: float = (current / max_val) * 100.0
	label_3d.text = "%d / %d" % [int(current), int(max_val)]
	# Color de la barra segun salud
	if pct > 50.0:
		label_3d.modulate = Color(0.3, 1.0, 0.3)  # Verde
	elif pct > 25.0:
		label_3d.modulate = Color(1.0, 0.8, 0.2)  # Amarillo
	else:
		label_3d.modulate = Color(1.0, 0.2, 0.2)  # Rojo

func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return (current_health / max_health) * 100.0

func _debug(msg: String) -> void:
	print("[Core %s] %s" % [GameState.nombre_equipo(team), msg])
