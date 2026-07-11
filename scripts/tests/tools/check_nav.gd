extends SceneTree

func _init() -> void:
	var nav = NavigationMesh.new()
	print("START")
	print("Class: ", nav.get_class())
	for p in nav.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or p.usage & PROPERTY_USAGE_DEFAULT:
			print("PROP: ", p.name, " type=", p.type)
	print("END")
	quit()
