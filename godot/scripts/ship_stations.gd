class_name ShipStations
extends NpcStationProvider
## Ship-side adapter for the npc_life addon (H1): turns the Marker3D catalogue of ship_stations.tscn, the ship lanterns and the sails into
## NpcStation nodes. Everything lives under Ship/Pivot, so every anchor is pivot-local and a rolling ship never moves a station.
## Scene layout: ShipStations (Node3D, instanced under Ship/Pivot) / Markers (Marker3D with metadata, see gen_ship_stations.py) and this node (Provider).
## Stations created here: one per station marker (helm, spyglass_post, crows_nest, ratline_path, chart_table, violin_seat, listen_spot, social_spot,
## fishing_rail, repair_spot, mop_zone, boat_check), `lantern_<id>` per ShipLantern (anchor = its stand point), `reef_line_<idx>` per sail (on the deck
## beside the nearest mast base). Test aid: `--debug-stations` draws a labelled marker on every station and logs each one.
## Plain-data view for code that must not hold nodes: get_stations().

const STATION_KINDS: Array[StringName] = [&"helm", &"spyglass_post", &"crows_nest", &"ratline_path", &"chart_table", &"violin_seat", &"listen_spot",
	&"social_spot", &"fishing_rail", &"repair_spot", &"mop_zone", &"boat_check"]
const NON_STATION_KINDS: Array[StringName] = [&"nav", &"reef_pin", &"stairs", &"door"]
const REEF_SIDE_OFFSET := 1.6

@export var ship_path := NodePath("../../..")
@export var helm_path := NodePath("../../Helm")

var _root: Node3D
var _stations_root: Node3D
var _by_id: Dictionary = {}              # StringName -> NpcStation
var _sail_positions: Array[Vector3] = []  # test / fallback input when the ship has no sail_defs
var _debug := OS.get_cmdline_user_args().has("--debug-stations")
var _built := false

func _ready() -> void:
	_root = get_parent() as Node3D
	var loader := get_node_or_null("../../Model")
	if loader != null and loader.has_signal("ship_ready"):
		loader.ship_ready.connect(_on_ship_ready.unbind(3), CONNECT_DEFERRED)
	else:
		rebuild.call_deferred()

func _on_ship_ready() -> void:
	rebuild()

## Pivot-local sail positions used for the reef lines when the ship does not provide `sail_defs` (tests).
func set_sail_positions(list: Array) -> void:
	_sail_positions.clear()
	for p in list:
		_sail_positions.append(p as Vector3)

# ---- build -----------------------------------------------------------------------------------------------------------------------------

func rebuild() -> void:
	if _root == null:
		_root = get_parent() as Node3D
	if _root == null:
		return
	if _stations_root != null and is_instance_valid(_stations_root):
		_root.remove_child(_stations_root)
		_stations_root.free()
	_by_id.clear()
	_stations_root = Node3D.new()
	_stations_root.name = "Stations"
	_root.add_child(_stations_root)
	var markers := _root.get_node_or_null("Markers")
	if markers != null:
		for m in markers.get_children():
			if not (m is Marker3D):
				continue
			var kind := StringName(m.get_meta("kind", &""))
			if kind == &"" or NON_STATION_KINDS.has(kind):
				continue
			var st := _make_station(StringName(m.name), kind, m.position)
			st.slot_count = int(m.get_meta("slots", 1))
			st.facing_deg = float(m.get_meta("facing_deg", 0.0))
			st.anim_tag = StringName(m.get_meta("anim_tag", &""))
			st.must_staff = bool(m.get_meta("must_staff", false))
	_build_lantern_stations()
	_build_reef_stations()
	_bind_ik()
	_built = true
	_late_refresh.call_deferred()
	stations_changed.emit()
	print("[crew] stations: ", _counts_text())
	if _debug:
		_draw_debug()

func _late_refresh() -> void:
	if not is_inside_tree():
		return
	for i in 6:
		await get_tree().physics_frame # the lantern stances are ready after ~3 physics frames
	_refresh_lanterns()
	_bind_ik()
	if _debug:
		for id in _sorted_ids():
			var st: NpcStation = _by_id[id]
			if st.kind == &"lantern":
				print("[crew] station ", id, " (after the deck rays) local=", st.position.snapped(Vector3.ONE * 0.01), " facing=", snappedf(st.facing_deg, 0.1))
	stations_changed.emit()

func _make_station(id: StringName, kind: StringName, pos: Vector3) -> NpcStation:
	var st := NpcStation.new()
	st.name = String(id)
	st.station_id = id
	st.kind = kind
	st.approach_offset = Vector3.ZERO # anchors are placed on the deck: the stance point is the anchor itself
	_stations_root.add_child(st)
	st.position = pos
	_by_id[id] = st
	return st

func _build_lantern_stations() -> void:
	var pivot := _pivot()
	for n in get_tree().get_nodes_in_group("ship_lantern") if is_inside_tree() else []:
		if not (n is ShipLantern) or pivot == null or not pivot.is_ancestor_of(n):
			continue
		var l := n as ShipLantern
		var st := _make_station(StringName("lantern_" + l.id), &"lantern", l.stand_local)
		st.facing_deg = l.stand_facing_deg
		st.anim_tag = &"light"
		st.ik_targets[&"look_at"] = st.get_path_to(l)
		st.set_meta(&"lantern_node", l.get_path())

## ShipLights computes the stance points a few physics frames after ship_ready (deck rays), so the lantern stations follow the lanterns' stance
## fields whenever the set is asked for. Station-local position = pivot-local stand point (the stations root sits at the pivot's origin).
func _refresh_lanterns() -> void:
	for st: NpcStation in _by_id.values():
		if st.kind != &"lantern" or not st.has_meta(&"lantern_node"):
			continue
		var l := get_node_or_null(st.get_meta(&"lantern_node")) as ShipLantern
		if l != null:
			if not st.position.is_equal_approx(l.stand_local):
				st.position = l.stand_local
			st.facing_deg = l.stand_facing_deg

func _sail_pivot_positions() -> Array[Vector3]:
	var ship := get_node_or_null(ship_path)
	if ship != null and "sail_defs" in ship and not (ship.sail_defs as Array).is_empty():
		var out: Array[Vector3] = []
		for d in ship.sail_defs:
			out.append(d["pos"] as Vector3)
		return out
	return _sail_positions

func _build_reef_stations() -> void:
	var markers := _root.get_node_or_null("Markers")
	if markers == null:
		return
	var pins: Array[Vector3] = []
	for m in markers.get_children():
		if m is Marker3D and StringName(m.get_meta("kind", &"")) == &"reef_pin":
			pins.append((m as Marker3D).position)
	if pins.is_empty():
		return
	var sails := _sail_pivot_positions()
	var per_pin := {} # pin z -> how many reef lines already sit there (spreads them out: alternate side, 0.7 m steps along z)
	for i in sails.size():
		var best := pins[0]
		for p in pins:
			if absf(p.z - sails[i].z) < absf(best.z - sails[i].z):
				best = p
		var k := int(per_pin.get(best.z, 0))
		per_pin[best.z] = k + 1
		var side := 1.0 if k % 2 == 0 else -1.0
		var dz := -0.7 * float(k / 2)
		var st := _make_station(StringName("reef_line_%d" % i), &"reef_line", Vector3(side * REEF_SIDE_OFFSET, best.y, best.z + dz))
		st.facing_deg = 90.0 if side > 0.0 else -90.0 # towards the mast: starboard side faces port (+90)
		st.anim_tag = &"haul"

## Hand targets of the helm station (Helm creates them at ship_ready; this is repeated whenever the set is asked for, in case they were late).
func _bind_ik() -> void:
	var helm_st: NpcStation = _by_id.get(&"helm")
	var helm := get_node_or_null(helm_path)
	if helm_st == null or helm == null:
		return
	for chain in [&"hand_l", &"hand_r"]:
		var h: Variant = helm.get(chain) if chain in helm else null
		if h is Node3D and is_instance_valid(h) and (h as Node).is_inside_tree() and helm_st.is_inside_tree():
			helm_st.ik_targets[chain] = helm_st.get_path_to(h as Node)

func _pivot() -> Node3D:
	return _root.get_parent() as Node3D if _root != null and _root.get_parent() is Node3D else _root

# ---- provider and plain-data API -------------------------------------------------------------------------------------------------------

func provide_stations() -> Array[NpcStation]:
	if not _built:
		return super.provide_stations()
	_bind_ik()
	_refresh_lanterns()
	var out: Array[NpcStation] = []
	for id in _sorted_ids():
		out.append(_by_id[id])
	return out

func station(id: StringName) -> NpcStation:
	return _by_id.get(id) as NpcStation

func kind_counts() -> Dictionary:
	var counts := {}
	for st: NpcStation in _by_id.values():
		counts[st.kind] = int(counts.get(st.kind, 0)) + 1
	return counts

func _counts_text() -> String:
	var counts := kind_counts()
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b)) # StringName < compares pointers: sort by text
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%d" % [k, counts[k]])
	return " ".join(parts)

func _sorted_ids() -> Array:
	var ids: Array = _by_id.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	return ids

## Level name of a pivot-local point (deck survey, odd/evidence/npc-crew-jobs/H1/deck_survey.md).
static func level_of(p: Vector3) -> StringName:
	if p.y > 10.0:
		return &"mast"
	if p.y >= 6.0:
		return &"poop"
	if p.y < 2.6:
		return &"waist"
	if p.z < -5.0:
		return &"forecastle"
	return &"quarter"

func get_stations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pivot := _pivot()
	for st in provide_stations():
		var anchor := st.anchor_local(0, pivot).origin
		var occ: Array[StringName] = []
		for s in st.capacity():
			if st.occupant(s) != &"":
				occ.append(st.occupant(s))
		var ik := {}
		for chain in st.ik_targets:
			ik[chain] = st.ik_targets[chain]
		out.append({"id": st.station_id, "kind": st.kind, "anchor": anchor, "approach": st.approach_local(0, pivot), "facing_deg": st.facing_deg,
			"level": level_of(anchor), "slots": st.capacity(), "anim_tag": st.anim_tag, "ik": ik, "occupied_by": occ, "must_staff": st.must_staff})
	return out

## Markers that are not stations: {kind: Array of {name, pos}} for `stairs`, `door` (and `reef_pin`, `nav` for the graph bake).
func access_markers() -> Dictionary:
	var out := {}
	var markers := _root.get_node_or_null("Markers") if _root != null else null
	if markers == null:
		return out
	for m in markers.get_children():
		if not (m is Marker3D):
			continue
		var kind := StringName(m.get_meta("kind", &""))
		if NON_STATION_KINDS.has(kind):
			if not out.has(kind):
				out[kind] = []
			out[kind].append({"name": StringName(m.name), "pos": (m as Marker3D).position})
	return out

# ---- debug overlay ---------------------------------------------------------------------------------------------------------------------

func _draw_debug() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 1.0)
	mat.no_depth_test = true
	for id in _sorted_ids():
		var st: NpcStation = _by_id[id]
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		ball.mesh = sm
		ball.material_override = mat
		st.add_child(ball)
		var lb := Label3D.new()
		lb.text = String(st.station_id)
		lb.font_size = 48
		lb.pixel_size = 0.008
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.modulate = Color(1, 1, 0)
		lb.outline_size = 12
		lb.position = Vector3(0, 0.35, 0)
		st.add_child(lb)
		print("[crew] station ", st.station_id, " kind=", st.kind, " level=", level_of(st.position), " local=", st.position.snapped(Vector3.ONE * 0.01), " facing=", st.facing_deg, " must_staff=", st.must_staff)
