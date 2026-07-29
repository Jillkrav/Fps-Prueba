# skin_data.gd
# ─────────────────────────────────────────────────────────────────────────────
# Recurso que define una skin/modelo para el personaje.
# Cada skin tiene su propia escena 3D, texturas y configuración de animaciones.
#
# Uso:
#   - Crear un archivo .tres con este script como recurso
#   - Asignar la escena 3D y las texturas correspondientes
#   - SkinManager descubre automáticamente los archivos .tres en las subcarpetas
# ─────────────────────────────────────────────────────────────────────────────
extends Resource
class_name SkinData

## Identificador único de la skin (ej: "teddy", "combine", "gign").
@export var id: String = ""

## Nombre legible para mostrar en UI.
@export var name: String = ""

## Breve descripción de la skin.
@export var description: String = ""

## Escena 3D que contiene el modelo visual del personaje.
## La escena debe tener una estructura consistente con un AnimationPlayer
## y al menos un MeshInstance3D para aplicar texturas.
@export var model_scene: PackedScene = null

## Path relativo dentro de model_scene al MeshInstance3D principal
## donde se aplicarán las texturas. Ej: "Character/Skeleton3D/Mesh_0"
@export var mesh_path: NodePath = ""

## Path relativo dentro de model_scene al AnimationPlayer.
## Ej: "Character/AnimationPlayer"
@export var animation_player_path: NodePath = ""

## Indica si el modelo 3D tiene un Skeleton3D con huesos para
## animaciones esqueléticas. False para modelos estáticos (ej: OBJ).
@export var has_skeleton: bool = true

# ─── Texturas ──────────────────────────────────────────────────────────────
@export var albedo_texture: Texture2D = null
@export var normal_texture: Texture2D = null
@export var roughness_texture: Texture2D = null
@export var metallic_texture: Texture2D = null

## Color base del material (solo si NO hay albedo_texture).
## Si es Color.WHITE y no hay albedo_texture, se preserva el material original.
## Útil para variantes de color sólido sin textura (ej: Teddy Azul, Teddy Rojo).
@export var albedo_color: Color = Color.WHITE

## Valores por defecto del material cuando no hay textura de roughness/metallic.
@export var roughness: float = 0.8
@export var metallic: float = 0.0

## Set de animaciones que usa esta skin.
## Si es null, se usa el animation_set_default (definido en
## res://Assets/Animaciones/Player/animation_set_default.tres).
##
## Cada playermodel puede tener su PROPIO AnimationSet, sobreescribiendo
## el default. Esto permite que modelos distintos tengan animaciones
## diferentes (ej: Teddy usa animaciones más lentas que GIGN).
##
## Para crear un AnimationSet personalizado:
##   1. Crea un nuevo recurso .tres con script AnimationSet
##   2. Asígnale los FBX correspondientes
##   3. Enlázalo aquí en este campo
##   4. Si es null, se usará el default automáticamente
@export var animation_set: AnimationSet = null

## Preview de la skin para menús de selección.
@export var thumbnail: Texture2D = null

## Datos de cámara y presentación cargados desde characters.json.
var runtime_camera_config: Dictionary = {}

## Aplica las texturas de esta skin al modelo visual instanciado.
## Busca el MeshInstance3D objetivo usando mesh_path si está definido,
## o encuentra el primer mesh disponible como fallback.
## Si la skin no tiene texturas asignadas (has_textures == false),
## no modifica los materiales originales del modelo (útil para OBJ
## con texturas embebidas como Teddy).
func apply_textures_to(model_instance: Node3D) -> void:
    # 1. Encontrar el MeshInstance3D objetivo
    var mesh_instance: MeshInstance3D = null
    if mesh_path and not mesh_path.is_empty():
        mesh_instance = model_instance.get_node_or_null(mesh_path) as MeshInstance3D
    if not mesh_instance:
        mesh_instance = _find_first_mesh(model_instance)
    if not mesh_instance:
        return
    
    # 2. Verificar si hay texturas o color que aplicar
    var has_textures: bool = albedo_texture != null or normal_texture != null \
        or roughness_texture != null or metallic_texture != null
    var has_color_override: bool = albedo_color != Color.WHITE
    
    if not has_textures and not has_color_override:
        return  # Preservar materiales originales del modelo
    
    # 3. Crear material con las texturas/color de la skin
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    if albedo_texture:
        mat.albedo_texture = albedo_texture
    else:
        mat.albedo_color = albedo_color
    if normal_texture:
        mat.normal_texture = normal_texture
    if roughness_texture:
        mat.roughness_texture = roughness_texture
    else:
        mat.roughness = roughness
    if metallic_texture:
        mat.metallic_texture = metallic_texture
    else:
        mat.metallic = metallic
    
    mesh_instance.material_override = mat


## Busca recursivamente el primer MeshInstance3D dentro de un nodo.
static func _find_first_mesh(node: Node) -> MeshInstance3D:
    if node is MeshInstance3D:
        return node as MeshInstance3D
    for i in node.get_child_count():
        var child: Node = node.get_child(i)
        var found: MeshInstance3D = _find_first_mesh(child)
        if found:
            return found
    return null
