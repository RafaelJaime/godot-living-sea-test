extends Node
## Test aid (`--cloth-probe=<secs>`): per-frame log of sail / flag cloth vertices in ship frame.
var _secs := 30.0
var _t := 0.0
var _rig: Node
var _flag: Node
var _n := 0

func _ready() -> void:
	process_priority = 200
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cloth-probe="):
			_secs = float(a.get_slice("=", 1))
	print("[probe] hdr,frame,t,dt,fps,sail_dx,sail_dy,sail_dz,flag_x,flag_y,flag_z,carry,wind,gust,rebased")

func _process(delta: float) -> void:
	_t += delta
	if _t > _secs:
		get_tree().quit()
		return
	if _rig == null:
		_rig = get_tree().get_first_node_in_group("sail_rig")
		_flag = get_tree().get_first_node_in_group("flag_main_mast")
	if _rig == null or _flag == null:
		return
	var s: SailCloth = _rig._sails[1]
	var k := (SailCloth.ROWS / 2) * SailCloth.COLS + SailCloth.COLS / 2
	var sd := Vector3(s._dbuf[k * 4], s._dbuf[k * 4 + 1], s._dbuf[k * 4 + 2])
	var fc: ClothSolver = _flag._cloth
	var fp: Vector3 = fc._launch_xf * fc.pos[(fc.n / 2) + 3]
	var main := get_tree().root.get_node("Main")
	print("[probe],%d,%.4f,%.4f,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%.2f,%.2f,%.1f" % [Engine.get_process_frames(), _t, delta, Engine.get_frames_per_second(),
		sd.x, sd.y, sd.z, fp.x, fp.y, fp.z, 1 if delta > ClothSolver.HITCH_DT + 1e-4 else 0, WindField.mean_speed(), s.gust, main.total_shifted])
