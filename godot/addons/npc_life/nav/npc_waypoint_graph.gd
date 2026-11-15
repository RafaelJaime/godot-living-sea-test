@tool
class_name NpcWaypointGraph
extends Resource
## Typed-edge waypoint graph in the LOCAL space of a platform (a ship pivot, a raft). Edges are walk / stairs / ladder / rope (more can be
## registered by listing them in `type_cost_mul`), bidirectional unless flagged one-way. Costs are length x per-edge multiplier x type multiplier.
## Not NavigationServer3D: ladders and ropes need typed edges and a platform that moves must not move the path.

const KNOWN_TYPES: Array[StringName] = [&"walk", &"stairs", &"ladder", &"rope"]
const CACHE_MAX_NODES := 256

@export var positions := PackedVector3Array()
@export var node_tags: Array[StringName] = []
## Pairs of node indices (a0, b0, a1, b1, ...).
@export var edges := PackedInt32Array()
@export var edge_types: Array[StringName] = []
@export var edge_cost_mul := PackedFloat32Array()
@export var edge_oneway := PackedByteArray()
## Cost multiplier per edge type; a type listed here is registered. Unlisted types are unknown (reported by `validate`, cost 1.0).
@export var type_cost_mul: Dictionary[StringName, float] = {&"walk": 1.0, &"stairs": 1.3, &"ladder": 2.0, &"rope": 2.5}

var _adj_to: Array[PackedInt32Array] = []
var _adj_cost: Array[PackedFloat32Array] = []
var _adj_edge: Array[PackedInt32Array] = []
var _dirty := true
var _cache := PackedFloat32Array()

# ---- building ---------------------------------------------------------------------------------------------------------------------------

func add_node(pos: Vector3, tag := &"") -> int:
	positions.append(pos)
	node_tags.append(tag)
	_dirty = true
	return positions.size() - 1

func connect_nodes(a: int, b: int, type := &"walk", cost_mul := 1.0, oneway := false) -> int:
	edges.append(a)
	edges.append(b)
	edge_types.append(type)
	edge_cost_mul.append(cost_mul)
	edge_oneway.append(1 if oneway else 0)
	_dirty = true
	return edge_types.size() - 1

## Removes node `i` and every edge touching it; later node indices shift down by one.
func remove_node(i: int) -> void:
	if i < 0 or i >= positions.size():
		return
	var keep_edges := PackedInt32Array()
	var keep_types: Array[StringName] = []
	var keep_mul := PackedFloat32Array()
	var keep_one := PackedByteArray()
	for e in edge_types.size():
		var a := edges[e * 2]
		var b := edges[e * 2 + 1]
		if a == i or b == i:
			continue
		keep_edges.append(a - 1 if a > i else a)
		keep_edges.append(b - 1 if b > i else b)
		keep_types.append(edge_types[e])
		keep_mul.append(edge_cost_mul[e] if e < edge_cost_mul.size() else 1.0)
		keep_one.append(edge_oneway[e] if e < edge_oneway.size() else 0)
	positions.remove_at(i)
	if i < node_tags.size():
		node_tags.remove_at(i)
	edges = keep_edges
	edge_types = keep_types
	edge_cost_mul = keep_mul
	edge_oneway = keep_one
	_dirty = true

func remove_edge(e: int) -> void:
	if e < 0 or e >= edge_types.size():
		return
	var ed := Array(edges)
	ed.remove_at(e * 2 + 1)
	ed.remove_at(e * 2)
	edges = PackedInt32Array(ed)
	edge_types.remove_at(e)
	if e < edge_cost_mul.size():
		edge_cost_mul.remove_at(e)
	if e < edge_oneway.size():
		edge_oneway.remove_at(e)
	_dirty = true

func set_edge_type(e: int, type: StringName) -> void:
	if e >= 0 and e < edge_types.size():
		edge_types[e] = type
		_dirty = true

func set_node_position(i: int, pos: Vector3) -> void:
	if i >= 0 and i < positions.size():
		positions[i] = pos
		_dirty = true

func node_count() -> int:
	return positions.size()

func edge_count() -> int:
	return edge_types.size()

func edge_type(i: int) -> StringName:
	return edge_types[i]

## Problems by edge (empty = valid). Unknown types are reported, never fatal.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var n := edge_types.size()
	if edges.size() != n * 2:
		out.append("edges: %d indices for %d edge types" % [edges.size(), n])
		return out
	for i in n:
		var a := edges[i * 2]
		var b := edges[i * 2 + 1]
		if a < 0 or b < 0 or a >= positions.size() or b >= positions.size():
			out.append("edge %d (%d-%d): node index out of range" % [i, a, b])
		if not type_cost_mul.has(edge_types[i]):
			out.append("edge %d (%d-%d): unknown type '%s'" % [i, a, b, edge_types[i]])
	return out

# ---- search ---------------------------------------------------------------------------------------------------------------------------------

func _edge_cost(i: int) -> float:
	var a := edges[i * 2]
	var b := edges[i * 2 + 1]
	var mul: float = edge_cost_mul[i] if i < edge_cost_mul.size() else 1.0
	return positions[a].distance_to(positions[b]) * mul * float(type_cost_mul.get(edge_types[i], 1.0))

func _rebuild_adjacency() -> void:
	var n := positions.size()
	var to: Array[Array] = []
	var cost: Array[Array] = []
	var eidx: Array[Array] = []
	for i in n:
		to.append([])
		cost.append([])
		eidx.append([])
	for i in edge_types.size():
		var a := edges[i * 2]
		var b := edges[i * 2 + 1]
		if a < 0 or b < 0 or a >= n or b >= n:
			continue
		var c := _edge_cost(i)
		to[a].append(b)
		cost[a].append(c)
		eidx[a].append(i)
		var oneway := i < edge_oneway.size() and edge_oneway[i] != 0
		if not oneway:
			to[b].append(a)
			cost[b].append(c)
			eidx[b].append(i)
	_adj_to.clear()
	_adj_cost.clear()
	_adj_edge.clear()
	for i in n:
		_adj_to.append(PackedInt32Array(to[i]))
		_adj_cost.append(PackedFloat32Array(cost[i]))
		_adj_edge.append(PackedInt32Array(eidx[i]))
	_dirty = false
	_cache = PackedFloat32Array()

## Dijkstra from `src` (stops at `dst` when >= 0). Returns {dist: PackedFloat32Array, prev: PackedInt32Array, prev_edge: PackedInt32Array}.
func _dijkstra(src: int, dst := -1) -> Dictionary:
	if _dirty:
		_rebuild_adjacency()
	var n := positions.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var prev_edge := PackedInt32Array()
	prev_edge.resize(n)
	prev_edge.fill(-1)
	if src < 0 or src >= n:
		return {"dist": dist, "prev": prev, "prev_edge": prev_edge}
	dist[src] = 0.0
	# binary min-heap of (distance, node)
	var hk := PackedFloat32Array([0.0])
	var hv := PackedInt32Array([src])
	while not hv.is_empty():
		# pop min
		var d := hk[0]
		var u := hv[0]
		var last := hv.size() - 1
		hk[0] = hk[last]
		hv[0] = hv[last]
		hk.resize(last)
		hv.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < last and hk[l] < hk[m]:
				m = l
			if r < last and hk[r] < hk[m]:
				m = r
			if m == i:
				break
			var tk := hk[i]; hk[i] = hk[m]; hk[m] = tk
			var tv := hv[i]; hv[i] = hv[m]; hv[m] = tv
			i = m
		if d > dist[u]:
			continue
		if u == dst:
			break
		var to := _adj_to[u]
		var cs := _adj_cost[u]
		for k in to.size():
			var v := to[k]
			var nd := d + cs[k]
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				prev_edge[v] = _adj_edge[u][k]
				# push
				hk.append(nd)
				hv.append(v)
				var j := hk.size() - 1
				while j > 0:
					var p := (j - 1) / 2
					if hk[p] <= hk[j]:
						break
					var tk2 := hk[p]; hk[p] = hk[j]; hk[j] = tk2
					var tv2 := hv[p]; hv[p] = hv[j]; hv[j] = tv2
					j = p
	return {"dist": dist, "prev": prev, "prev_edge": prev_edge}

## Lowest-cost node path between two nodes (inclusive); empty when unreachable.
func find_path_nodes(from_node: int, to_node: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := positions.size()
	if from_node < 0 or to_node < 0 or from_node >= n or to_node >= n:
		return out
	if from_node == to_node:
		out.append(from_node)
		return out
	var r := _dijkstra(from_node, to_node)
	if (r["dist"] as PackedFloat32Array)[to_node] == INF:
		return out
	var prev: PackedInt32Array = r["prev"]
	var cur := to_node
	while cur != -1:
		out.append(cur)
		cur = prev[cur]
	out.reverse()
	return out

## Node path between the nodes nearest to two arbitrary local points.
func find_path(from_local: Vector3, to_local: Vector3) -> PackedInt32Array:
	return find_path_nodes(nearest_node(from_local), nearest_node(to_local))

## {nodes, edge_types, cost, reason}: reason is "" or `unreachable` / `empty_graph` (never an error).
func path_info(from_local: Vector3, to_local: Vector3) -> Dictionary:
	var a := nearest_node(from_local)
	var b := nearest_node(to_local)
	var res := {"nodes": PackedInt32Array(), "edge_types": [] as Array[StringName], "cost": 0.0, "reason": &""}
	if a < 0 or b < 0:
		res["reason"] = &"empty_graph"
		return res
	if a == b:
		res["nodes"] = PackedInt32Array([a])
		return res
	var r := _dijkstra(a, b)
	if (r["dist"] as PackedFloat32Array)[b] == INF:
		res["reason"] = &"unreachable"
		return res
	var nodes := PackedInt32Array()
	var types: Array[StringName] = []
	var prev: PackedInt32Array = r["prev"]
	var prev_edge: PackedInt32Array = r["prev_edge"]
	var cur := b
	while cur != -1:
		nodes.append(cur)
		if prev_edge[cur] >= 0:
			types.append(edge_types[prev_edge[cur]])
		cur = prev[cur]
	nodes.reverse()
	types.reverse()
	res["nodes"] = nodes
	res["edge_types"] = types
	res["cost"] = (r["dist"] as PackedFloat32Array)[b]
	return res

func path_cost(nodes: PackedInt32Array) -> float:
	var total := 0.0
	for i in range(nodes.size() - 1):
		total += _step_cost(nodes[i], nodes[i + 1])
	return total

func _step_cost(a: int, b: int) -> float:
	if _dirty:
		_rebuild_adjacency()
	var best := INF
	var to := _adj_to[a]
	for k in to.size():
		if to[k] == b:
			best = minf(best, _adj_cost[a][k])
	return best

func nearest_node(p_local: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in positions.size():
		var d := positions[i].distance_squared_to(p_local)
		if d < bd:
			bd = d
			best = i
	return best

# ---- distances ------------------------------------------------------------------------------------------------------------------------------

## Precomputes all-pairs distances for graphs of up to 256 nodes (scoring then reads distances in O(1)).
func build_distance_cache() -> void:
	if _dirty:
		_rebuild_adjacency() # (clears any old cache: do it before filling the new one)
	var n := positions.size()
	if n == 0 or n > CACHE_MAX_NODES:
		_cache = PackedFloat32Array()
		return
	_cache = PackedFloat32Array()
	_cache.resize(n * n)
	for s in n:
		var d: PackedFloat32Array = _dijkstra(s)["dist"]
		for t in n:
			_cache[s * n + t] = d[t]

func has_distance_cache() -> bool:
	return not _cache.is_empty()

## Path cost between two nodes (INF when unreachable): from the cache when built, else by search.
func distance(from_node: int, to_node: int) -> float:
	var n := positions.size()
	if from_node < 0 or to_node < 0 or from_node >= n or to_node >= n:
		return INF
	if _dirty:
		_rebuild_adjacency()
	if not _cache.is_empty():
		return _cache[from_node * n + to_node]
	if from_node == to_node:
		return 0.0
	return (_dijkstra(from_node, to_node)["dist"] as PackedFloat32Array)[to_node]

## Node indices not reachable from `root_node` (following edge directions), ascending.
func check_connectivity(root_node: int) -> Array[int]:
	var out: Array[int] = []
	var d: PackedFloat32Array = _dijkstra(root_node)["dist"]
	for i in positions.size():
		if d[i] == INF:
			out.append(i)
	return out
