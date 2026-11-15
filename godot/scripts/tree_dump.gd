extends Node
## Test aid (`--tree-dump=<secs>`): after <secs> of run time writes `_shots/tree_dump.txt` (sorted, one line per node: path, class, script, visibility, exported
## values) and quits. Used to prove that a scene refactor leaves the live tree identical. Auto-generated names (`@Node3D@12`) are normalised.
var secs := 6.0
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if _t < secs:
		return
	set_process(false)
	var lines: Array[String] = []
	_walk(get_tree().root, lines)
	lines.sort()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots"))
	var f := FileAccess.open("res://_shots/tree_dump.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("[tree-dump] ", lines.size(), " nodes -> _shots/tree_dump.txt")
	get_tree().quit()

func _norm(s: String) -> String:
	var re := RegEx.new()
	re.compile("@[A-Za-z0-9_]+@[0-9]+")
	return re.sub(s, "@X", true)

func _walk(n: Node, out: Array[String]) -> void:
	if n == self:
		return
	var line := "%s | %s" % [_norm(str(n.get_path())), n.get_class()]
	var sc := n.get_script() as Script
	if sc:
		line += " | " + sc.resource_path
		var vals: Array[String] = []
		for p in n.get_property_list():
			if (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) and (p["usage"] & PROPERTY_USAGE_EDITOR):
				var v: Variant = n.get(p["name"])
				if v is float:
					v = snappedf(v, 0.0001)
				if v is bool or v is int or v is float or v is String or v is StringName or v is NodePath or v is Vector2 or v is Vector3 or v is Color:
					vals.append("%s=%s" % [p["name"], str(v)])
		vals.sort()
		line += " | " + ",".join(vals)
	if n is Node3D:
		line += " | vis=" + str((n as Node3D).visible)
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		line += " | mesh=" + (str(m.get_surface_count()) if m else "none")
	out.append(line)
	for c in n.get_children():
		_walk(c, out)
