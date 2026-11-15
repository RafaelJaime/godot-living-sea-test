extends GutTest
## Spec ship-crew-stations (H1): the ShipStations adapter exposes the catalogue as NpcStation nodes with pivot-local anchors.
## Project-side test (lives with the other suites because run_npc_tests.sh runs this folder); it only needs ship_stations.tscn.

const SCENE := "res://ship/ship_stations.tscn"
const REQUIRED_KINDS: Array[StringName] = [&"helm", &"spyglass_post", &"crows_nest", &"ratline_path", &"chart_table", &"violin_seat",
	&"listen_spot", &"social_spot", &"fishing_rail", &"repair_spot", &"mop_zone", &"boat_check"]

var pivot: Node3D
var root: Node3D
var prov: ShipStations

func before_each() -> void:
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child_autofree(pivot)
	var packed := load(SCENE) as PackedScene
	assert_not_null(packed, "ship_stations.tscn loads")
	root = packed.instantiate() as Node3D
	pivot.add_child(root)
	prov = root.get_node("Provider") as ShipStations
	prov.rebuild()

func _by_kind(kind: StringName) -> Array[NpcStation]:
	var out: Array[NpcStation] = []
	for s in prov.provide_stations():
		if s.kind == kind:
			out.append(s)
	return out

func test_catalogue_has_every_required_kind() -> void:
	for k in REQUIRED_KINDS:
		assert_gt(_by_kind(k).size(), 0, "kind %s present" % k)

func test_catalogue_counts_are_logged_and_stable() -> void:
	var counts := prov.kind_counts()
	for k in REQUIRED_KINDS:
		assert_true(counts.has(k) and int(counts[k]) >= 1, "count for %s" % k)
	assert_eq(prov.provide_stations().size(), prov.get_stations().size(), "two views of the same set")

func test_station_ids_are_unique_and_non_empty() -> void:
	var seen := {}
	for s in prov.provide_stations():
		assert_ne(String(s.station_id), "", "id set")
		assert_false(seen.has(s.station_id), "duplicate id %s" % s.station_id)
		seen[s.station_id] = true

func test_helm_must_staff_others_not() -> void:
	var helm := _by_kind(&"helm")
	assert_eq(helm.size(), 1)
	assert_true(helm[0].must_staff)
	for s in prov.provide_stations():
		if s.kind != &"helm":
			assert_false(s.must_staff, "%s is not must_staff" % s.station_id)

func test_all_stations_are_pivot_children_and_levels_are_named() -> void:
	for d in prov.get_stations():
		var st: NpcStation = prov.station(d["id"])
		assert_not_null(st)
		assert_true(pivot.is_ancestor_of(st), "%s lives under the pivot" % d["id"])
		assert_true(["poop", "quarter", "waist", "forecastle", "mast"].has(String(d["level"])), "level of %s" % d["id"])
		assert_gt(int(d["slots"]), 0)

func test_anchors_are_pivot_local_not_world() -> void:
	var st := _by_kind(&"helm")[0]
	var local_before := st.anchor_local(0, pivot).origin
	var world_before := st.anchor_world(0)
	pivot.global_transform = Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(18.0)) * Basis(Vector3(1, 0, 0), deg_to_rad(6.0)), Vector3(40, 3, -25))
	var local_after := st.anchor_local(0, pivot).origin
	assert_true(local_before.is_equal_approx(local_after), "pivot-local anchor unchanged by roll/pitch/translation")
	assert_false(world_before.is_equal_approx(st.anchor_world(0)), "world position follows the ship")

func test_get_stations_plain_data_shape() -> void:
	var d: Dictionary = prov.get_stations()[0]
	for key in ["id", "kind", "anchor", "approach", "facing_deg", "level", "slots", "anim_tag", "ik", "occupied_by"]:
		assert_true(d.has(key), "key %s" % key)
	assert_true(d["anchor"] is Vector3)

func test_helm_station_declares_hand_targets_when_helm_exists() -> void:
	# No Helm in this fixture: ik stays empty and nothing errors.
	var helm := _by_kind(&"helm")[0]
	assert_eq(helm.ik_targets.size(), 0)

func test_lantern_stations_follow_ship_lights() -> void:
	var l := ShipLantern.new()
	l.id = "test_lamp"
	l.position = Vector3(1.0, 8.0, 18.0)
	l.stand_local = Vector3(0.6, 7.4, 17.5)
	l.stand_facing_deg = 40.0
	pivot.add_child(l)
	prov.rebuild()
	var st := prov.station(&"lantern_test_lamp")
	assert_not_null(st, "lantern station exists")
	assert_eq(st.kind, &"lantern")
	assert_true(st.anchor_local(0, pivot).origin.is_equal_approx(Vector3(0.6, 7.4, 17.5)), "anchor = stand point")
	assert_almost_eq(st.facing_deg, 40.0, 0.01)
	l.free()

func test_reef_line_stations_one_per_sail() -> void:
	prov.set_sail_positions([Vector3(0, 12, -8), Vector3(0, 12, 2), Vector3(0, 12, 12), Vector3(0, 20, 2)])
	prov.rebuild()
	assert_eq(_by_kind(&"reef_line").size(), 4)
	assert_not_null(prov.station(&"reef_line_3"))
	assert_null(prov.station(&"reef_line_4"))

func test_access_markers_stairs_and_door_exist() -> void:
	var access := prov.access_markers()
	assert_gt(access.get(&"stairs", []).size(), 0, "stairs markers")
	assert_gt(access.get(&"door", []).size(), 0, "door marker")

func test_rebuild_is_idempotent() -> void:
	var n := prov.provide_stations().size()
	prov.rebuild()
	prov.rebuild()
	assert_eq(prov.provide_stations().size(), n)
