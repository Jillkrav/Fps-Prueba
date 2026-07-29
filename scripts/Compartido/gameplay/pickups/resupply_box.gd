extends Area3D
class_name ResupplyBox

@export var cooldown_time: float = 3.0 # Segundos de espera para reutilizarla
var is_active: bool = true

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var light: OmniLight3D = $OmniLight3D

# Almacenar materiales para retroalimentación visual de estado (activo/inactivo)
var active_material: StandardMaterial3D
var inactive_material: StandardMaterial3D

func _ready() -> void:
	# Configurar materiales
	active_material = StandardMaterial3D.new()
	active_material.albedo_color = Color(0.1, 0.9, 0.4) # Verde brillante
	active_material.emission_enabled = true
	active_material.emission = Color(0.1, 0.9, 0.4)
	active_material.emission_energy_multiplier = 1.5
	
	inactive_material = StandardMaterial3D.new()
	inactive_material.albedo_color = Color(0.4, 0.4, 0.4) # Gris apagado
	
	if mesh:
		mesh.set_surface_override_material(0, active_material)
		
	# Conectar señal de entrada
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
		
	if body is Player or body.is_in_group("player"):
		# Reabastecer al jugador
		if body.has_method("resupply"):
			body.resupply()
			deactivate()

func deactivate() -> void:
	is_active = false
	if mesh:
		mesh.set_surface_override_material(0, inactive_material)
	if light:
		light.visible = false
		
	# Timer para reactivación
	var timer: SceneTreeTimer = get_tree().create_timer(cooldown_time)
	timer.timeout.connect(activate)

func activate() -> void:
	is_active = true
	if mesh:
		mesh.set_surface_override_material(0, active_material)
	if light:
		light.visible = true
