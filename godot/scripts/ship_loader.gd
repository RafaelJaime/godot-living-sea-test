extends Node3D
## Loads the final ship GLB (res://assets/ship/barco.glb) or falls back to the placeholder, then
## normalizes it: ~22 m long, bow toward -Z (scene forward), centered on XZ, waterline at local y=0.
## After normalization the pivot-local frame is: length along Z (bow -Z, stern +Z), y=0 = water plane.

signal ship_ready(length: float, beam: float, deck_ref_y: float)

## The ship in use (Poly Haven "Ship Pinnace" rigged, converted by ../export_pinnace.py). Old hulls stay in assets/ship.
@export var model_path := "res://assets/ship/pinnace/barco_pinnace.glb"
const PLACEHOLDER_PATH := "res://assets/ship/barco.glb"

@export var target_length := 22.0 ## ignored when ship_scale_override > 0
## Extra yaw (degrees) applied after auto-orientation, in case the bow guess is wrong.
@export var ship_yaw_offset_deg := 0.0
## If > 0 replaces the auto scale factor (scale applied to the raw model).
@export var ship_scale_override := 1.0 ## 1 = real-world metres (the pinnace is modelled in metres)
## Shift of the waterline (meters, positive raises the hull out of the water).
@export var waterline_offset := 0.0
## Hull depth (keel to deck) as a fraction of ship length; the waterline sits at 35% of it above the keel.
@export var hull_depth_ratio := 0.27
@export_range(0.0, 1.0) var submerged_fraction := 0.33
## Force the bow detection: 0 = auto, 1 = bow at +end of the long axis, -1 = bow at -end.
@export var force_bow_sign := 0
@export var sail_flutter := true

var length := 22.0
var beam := 7.0
var used_path := ""
var _sails: Array[MeshInstance3D] = []
var _sail_rest: Array[Transform3D] = []
var _sail_center: Array[Vector3] = []
var _sail_phase: Array[float] = []
var _t := 0.0

func _ready() -> void:
	var path := model_path if ModelUtil.file_present(model_path) else PLACEHOLDER_PATH
	var inst := ModelUtil.load_glb(path)
	if inst == null and path == model_path:
		push_warning("Final ship GLB failed to load, using placeholder")
		path = PLACEHOLDER_PATH
		inst = ModelUtil.load_glb(path)
	if inst == null:
		push_error("No ship model available")
		return
	used_path = path
	var holder := Node3D.new() # raw model, normalized through `holder`
	holder.name = "Normalized"
	add_child(holder)
	var raw := inst as Node3D
	holder.add_child(raw)
	_normalize(holder)
	_collect_sails(holder)
	ship_ready.emit.call_deferred(length, beam, 0.0)

func _normalize(holder: Node3D) -> void:
	var box := ModelUtil.local_aabb(holder)
	var long_is_x := box.size.x >= box.size.z
	var raw_len := box.size.x if long_is_x else box.size.z
	# Direction (in raw model space) the bow points to; start from the long axis.
	var bow_sign := _detect_bow_sign(holder, box, long_is_x)
	if force_bow_sign != 0:
		bow_sign = float(force_bow_sign)
	var d := Vector3(bow_sign, 0, 0) if long_is_x else Vector3(0, 0, bow_sign)
	# Rotation about Y that maps d to (0,0,-1): theta = atan2(dx, -dz).
	var yaw := atan2(d.x, -d.z) + deg_to_rad(ship_yaw_offset_deg)
	var s := (target_length / raw_len) if ship_scale_override <= 0.0 else ship_scale_override
	length = raw_len * s
	var beam_raw := box.size.z if long_is_x else box.size.x
	beam = beam_raw * s
	var hull_basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s, s))
	var center := box.get_center()
	var keel_y := box.position.y
	var hull_depth := hull_depth_ratio * length
	var waterline_above_keel := submerged_fraction * hull_depth + waterline_offset
	# Place center (x,z) at origin and the waterline at y=0.
	var origin_raw := Vector3(center.x, keel_y + waterline_above_keel / s, center.z)
	holder.transform = Transform3D(hull_basis, -(hull_basis * origin_raw))
	print("[ship] ", used_path, " raw_len=", snappedf(raw_len, 0.01), " scale=", snappedf(s, 0.001),
		" bow_sign=", bow_sign, " yaw=", snappedf(rad_to_deg(yaw), 0.1), " length=", snappedf(length, 0.01))

## Heuristic: the bow is the narrower end of the long axis (stern carries the wide transom/quarterdeck).
func _detect_bow_sign(holder: Node3D, box: AABB, long_is_x: bool) -> float:
	var verts := ModelUtil.sample_vertices(holder)
	if verts.is_empty():
		return 1.0
	var lo := box.position.x if long_is_x else box.position.z
	var ln := box.size.x if long_is_x else box.size.z
	var slab := ln * 0.18
	var lo_min := INF; var lo_max := -INF; var hi_min := INF; var hi_max := -INF
	for v in verts:
		var a := v.x if long_is_x else v.z
		var w := v.z if long_is_x else v.x
		# Ignore the bowsprit / masts: only consider hull-level vertices (lower 45% of height).
		if v.y > box.position.y + box.size.y * 0.45:
			continue
		if a < lo + slab:
			lo_min = minf(lo_min, w); lo_max = maxf(lo_max, w)
		elif a > lo + ln - slab:
			hi_min = minf(hi_min, w); hi_max = maxf(hi_max, w)
	var lo_w := lo_max - lo_min
	var hi_w := hi_max - hi_min
	if is_inf(lo_w) or is_inf(hi_w) or absf(lo_w - hi_w) < 0.02 * ln:
		return 1.0
	return 1.0 if hi_w < lo_w else -1.0

func _collect_sails(holder: Node3D) -> void:
	for n in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if "sail" in mi.name.to_lower() or "sail" in str(mi.get_parent().name).to_lower():
			_sails.append(mi)
			_sail_rest.append(mi.transform)
			_sail_center.append(mi.get_aabb().get_center())
			_sail_phase.append(randf() * TAU)

func _process(delta: float) -> void:
	if not sail_flutter or _sails.is_empty():
		return
	_t += delta
	for i in _sails.size():
		var ph := _sail_phase[i]
		var rx := sin(_t * 1.7 + ph) * 0.012 + sin(_t * 3.1 + ph * 2.0) * 0.006
		var rz := sin(_t * 1.3 + ph * 1.5) * 0.015
		var billow := 1.0 + sin(_t * 0.9 + ph) * 0.012
		var c := _sail_center[i]
		var b := Basis.from_euler(Vector3(rx, 0.0, rz)) * Basis.from_scale(Vector3(billow, 1.0, billow))
		var local := Transform3D(b, c - b * c)
		_sails[i].transform = _sail_rest[i] * local
