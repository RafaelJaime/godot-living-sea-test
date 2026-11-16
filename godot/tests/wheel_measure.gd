extends SceneTree
## Prints the mount transform helm.gd computes for res://assets/ship/ship_wheel.glb (used to bake the editor preview in ship.tscn).
func _init() -> void:
	var inst := (load("res://assets/ship/ship_wheel.glb") as PackedScene).instantiate() as Node3D
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(inst)
	var box := ModelUtil.local_aabb(holder)
	var sz := box.size
	var disc := maxf(maxf(sz.x, sz.y), sz.z)
	var s := (0.72 * 2.0 * 1.2) / maxf(disc, 0.0001)
	print("[wheel] size=", sz, " center=", box.get_center(), " scale=", s, " origin=", -(box.get_center() * s))
	quit()
