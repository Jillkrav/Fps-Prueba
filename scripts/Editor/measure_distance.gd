@tool
extends EditorScript
## Herramienta para medir distancias en el editor.
##
## COMO USARLA:
## 1. Selecciona DOS nodos en el árbol de escena (Ctrl+clic para selección múltiple)
## 2. Abre este script en el editor de scripts
## 3. Pulsa Ctrl+Shift+X (Ejecutar) o File -> Run
## 4. En la consola verás la distancia en metros
##
## Nota: 1 unidad de Godot = 1 metro en este proyecto.

func _run() -> void:
	var nodes: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	if nodes.size() != 2:
		printerr("Selecciona exactamente DOS nodos. Ahora hay ", nodes.size(), ".")
		return

	var a: Node3D = nodes[0] as Node3D
	var b: Node3D = nodes[1] as Node3D
	if a == null or b == null:
		printerr("Ambos nodos deben ser Node3D.")
		return

	var pa: Vector3 = a.global_position
	var pb: Vector3 = b.global_position
	var dist: float = pa.distance_to(pb)

	# Distancia horizontal (sin tener en cuenta la altura) - la util para diseño de niveles
	var horizontal: Vector3 = Vector3(pa.x, 0, pa.z) - Vector3(pb.x, 0, pb.z)
	var dist_h: float = horizontal.length()
	var dist_y: float = absf(pa.y - pb.y)

	print("==========================================")
	print("A: ", a.name, "  pos: ", pa)
	print("B: ", b.name, "  pos: ", pb)
	print("Distancia 3D: ", "%.2f" % dist, " m")
	print("Distancia horizontal (suelo): ", "%.2f" % dist_h, " m")
	print("Diferencia de altura: ", "%.2f" % dist_y, " m")
	print("==========================================")
