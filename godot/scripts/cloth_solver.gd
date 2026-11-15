class_name ClothSolver
extends RefCounted
## XPBD cloth on a regular grid (flags and sails share it). World space, own integrator (not SoftBody3D).
##  - constraints: structural (stretch, near-inextensible), shear (diagonals), light bending (skip-one), all XPBD
##    distance constraints with per-type compliance; hard pins (inverse mass 0, follow the owner's target every substep,
##    linearly interpolated across the frame) and soft pins (compliant point constraints: sheets, bowlines);
##  - forces: real gravity + TWO-SIDED per-triangle aerodynamics from the apparent wind (WindField true wind at the
##    particle minus the particle velocity):  F = 1/2 rho A |v| ( cN (v.n) n + cT (v - (v.n) n) ),
##    i.e. pressure drag + lift through the normal term and skin drag through the tangential term; A is the triangle area,
##    the force is split between the 3 vertices;
##  - 1-2 % velocity damping per substep, 2-4 substeps x 8-10 Gauss-Seidel iterations, velocity clamp, capsule
##    colliders (masts / staff);
##  - all registered cloths are stepped in parallel on the WorkerThreadPool by ClothSolver.tick(), called once a frame
##    by the WindField autoload AFTER the owners wrote this frame's pin targets (launch) and joined at the START of the next
##    frame (sync), so the cloth math overlaps rendering; `post_step` is then called on the main thread and the owner updates
##    meshes / textures. Results are one frame old, so owners express them in the SHIP frame (`_launch_xf`) and re-apply the
##    current ship transform: rigid ship motion never lags, only the cloth's own dynamics do.
## Outputs per frame: aero_force (N, world, frame average), aero_point (centre of effort), area, constraint_force (N,
## reaction on the pins = tension), pressure (Pa).

const RHO := 1.225
const MAX_SPEED := 55.0

static var _all: Array[ClothSolver] = []
static var disabled := OS.get_cmdline_user_args().has("--no-cloth") ## profiling aid
static var step_ms := 0.0 ## wall time of the last parallel step of everything (ms)

var cols := 0
var rows := 0
var n := 0
var enabled := true
var built := false
var density := 0.25 ## kg/m2
var cN := 1.25
var cT := 0.06
var gravity := Vector3(0, -9.81, 0)
var flutter := 0.0 ## small-scale gust jitter per particle (0..1) on top of the lattice wind; makes flags snap and sails luff
var damping := 0.012 ## velocity loss per substep
var substeps := 3
static var _qlogged := false
var iterations := 9
var min_quality := 0.0 ## floor for Quality.cloth_scale: sails need the full solve or they limit-cycle (visible as jumps) at 30 fps
var max_extra_substeps := 2 ## strong wind adds up to this many substeps (> 14 and > 22 m/s)
var sor := 1.0 ## successive over-relaxation factor of the Gauss-Seidel sweeps (faster tension propagation along the grid)
var max_aero_accel := 1.0e9 ## cap on the aerodynamic acceleration of a particle (m/s2): keeps light flags numerically sane in storms
var boost_iters := 0 ## extra iterations per wind step (> 14 m/s and > 22 m/s); the small, strongly loaded flags use it
var alpha_stretch := 1.0e-7
var alpha_shear := 2.0e-5
var alpha_bend := 2.0e-3
var use_bending := true ## skip-one distance constraints (flags); sails are stiff enough from stretch+shear and 1/3 cheaper without

var pos := PackedVector3Array()
var prev := PackedVector3Array() ## position at the start of the last substep
var vel := PackedVector3Array()
var inv_mass := PackedFloat32Array()
var mass := PackedFloat32Array()
var wind := PackedVector3Array()
var lat_idx := PackedInt32Array() ## particles that sample the wind
var wi := PackedInt32Array() ## 4 lattice indices per particle
var ww := PackedFloat32Array() ## their 4 bilinear weights
var force := PackedVector3Array()
var tris := PackedInt32Array()

var ca := PackedInt32Array()
var cb := PackedInt32Array()
var crest := PackedFloat32Array()
var calpha := PackedFloat32Array()
var lam := PackedFloat32Array()

var anchor_idx := PackedInt32Array()
var anchor_alpha := PackedFloat32Array() ## 0 = hard pin
var anchor_t := PackedVector3Array() ## world targets, written by the owner each frame
var anchor_prev := PackedVector3Array()
var anchor_lam := PackedFloat32Array()
var _anchor_primed := false

var cap_a := PackedVector3Array()
var cap_b := PackedVector3Array()
var cap_r := PackedFloat32Array()

var post_step := Callable()
var reset_provider := Callable() ## () -> PackedVector3Array: rest layout in world space, used to self-heal after a blow-up
var resets := 0
var tag := ""
var _bad := false
var _prev_xf := Transform3D.IDENTITY
var _xf_primed := false
var max_stretch_last := 0.0
var pivot_inv := Transform3D.IDENTITY ## world -> owner frame at the time of the pin targets (owner writes it every frame)
var _launch_xf := Transform3D.IDENTITY ## the transform the finished step was computed with

# outputs
var area := 0.0
var aero_force := Vector3.ZERO
var aero_point := Vector3.ZERO
var constraint_force := Vector3.ZERO
var pressure := 0.0
var gust_seen := 1.0 ## mean gust factor over the cloth (from WindField)
var max_stretch := 0.0
var _frame_dt := 0.016

static func register(c: ClothSolver) -> void:
	if not _all.has(c):
		_all.append(c)

static func unregister(c: ClothSolver) -> void:
	_all.erase(c)

static var _group := -1
static var _live: Array[ClothSolver] = []
static var stall_ms := 0.0 ## main-thread time spent waiting for the cloth workers (0 = fully hidden behind the frame)

## Late in the frame (owners already wrote their pin targets): starts all cloths on the worker threads and returns at once.
## The previous step was joined by sync() at the start of the frame, so nothing else touches the cloth data meanwhile.
static func launch(delta: float) -> void:
	if disabled or _group != -1:
		return
	_live.clear()
	for c in _all:
		if c.enabled and c.built:
			c._launch_xf = c.pivot_inv
			_live.append(c)
	if _live.is_empty():
		return
	var d := clampf(delta, 0.001, 1.0)
	_t_launch = Time.get_ticks_usec()
	_group = WorkerThreadPool.add_group_task(_run.bind(_live, d), _live.size(), -1, true, "cloth")

## First thing in the next frame: joins the workers and lets every owner consume the fresh results (post_step).
## `finish = false` only joins the workers and drops their results: used at exit, when the owners (flags, sails) have already left
## the tree and their post_step callbacks would touch nodes that are no longer inside it.
static func sync(finish := true) -> void:
	if _group == -1:
		return
	var t0 := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_group_task_completion(_group)
	_group = -1
	var t1 := Time.get_ticks_usec()
	stall_ms = lerpf(stall_ms, (t1 - t0) / 1000.0, 0.05)
	step_ms = lerpf(step_ms, (t1 - _t_launch) / 1000.0, 0.05)
	if not finish:
		return
	for c in _live:
		c._finish()

static var _t_launch := 0

static func _run(i: int, live: Array[ClothSolver], d: float) -> void:
	live[i]._step(d)

## Builds the grid from REST positions (world space, row-major, cols x rows). Rest lengths come from them, so any
## planar layout (rectangle, trapezoid) works. Particle mass = density x (1/3 of the adjacent triangle areas).
func build(p_cols: int, p_rows: int, rest: PackedVector3Array) -> void:
	cols = p_cols
	rows = p_rows
	n = cols * rows
	pos = rest.duplicate()
	prev = rest.duplicate()
	vel.resize(n)
	vel.fill(Vector3.ZERO)
	wind.resize(n)
	wind.fill(Vector3.ZERO)
	force.resize(n)
	mass.resize(n)
	mass.fill(0.0)
	inv_mass.resize(n)
	tris.clear()
	area = 0.0
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + 1
			var d := a + cols
			var e := d + 1
			tris.append_array([a, b, d, b, e, d])
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var ar := 0.5 * (rest[b] - rest[a]).cross(rest[c] - rest[a]).length()
		area += ar
		for k in [a, b, c]:
			mass[k] += density * ar / 3.0
	for i in n:
		inv_mass[i] = 1.0 / maxf(mass[i], 1.0e-4)
	ca.clear(); cb.clear(); crest.clear(); calpha.clear()
	for r in rows:
		for c in cols:
			var i := r * cols + c
			if c < cols - 1: _add(i, i + 1, alpha_stretch)
			if r < rows - 1: _add(i, i + cols, alpha_stretch)
			if c < cols - 1 and r < rows - 1:
				_add(i, i + cols + 1, alpha_shear)
				_add(i + 1, i + cols, alpha_shear)
			if use_bending and c < cols - 2: _add(i, i + 2, alpha_bend)
			if use_bending and r < rows - 2: _add(i, i + 2 * cols, alpha_bend)
	lam.resize(ca.size())
	_build_lattice()
	built = true
	register(self)

func _build_lattice() -> void:
	var lc := mini(cols, 4)
	var lr := mini(rows, 3)
	lat_idx.clear()
	for j in lr:
		for i in lc:
			var r := roundi(float(j) * float(rows - 1) / float(maxi(lr - 1, 1)))
			var c := roundi(float(i) * float(cols - 1) / float(maxi(lc - 1, 1)))
			lat_idx.append(r * cols + c)
	wi.resize(n * 4)
	ww.resize(n * 4)
	for r in rows:
		for c in cols:
			var fx := float(c) / float(cols - 1) * float(lc - 1)
			var fy := float(r) / float(rows - 1) * float(lr - 1)
			var ix := mini(int(fx), maxi(lc - 2, 0))
			var iy := mini(int(fy), maxi(lr - 2, 0))
			var tx := clampf(fx - float(ix), 0.0, 1.0) if lc > 1 else 0.0
			var ty := clampf(fy - float(iy), 0.0, 1.0) if lr > 1 else 0.0
			var ix1 := mini(ix + 1, lc - 1)
			var iy1 := mini(iy + 1, lr - 1)
			var o := (r * cols + c) * 4
			wi[o] = iy * lc + ix; ww[o] = (1.0 - tx) * (1.0 - ty)
			wi[o + 1] = iy * lc + ix1; ww[o + 1] = tx * (1.0 - ty)
			wi[o + 2] = iy1 * lc + ix; ww[o + 2] = (1.0 - tx) * ty
			wi[o + 3] = iy1 * lc + ix1; ww[o + 3] = tx * ty

func _add(a: int, b: int, alpha: float) -> void:
	ca.append(a); cb.append(b)
	crest.append(pos[a].distance_to(pos[b]))
	calpha.append(alpha)

## Adds an anchor on particle `idx`; alpha 0 = hard pin (the particle becomes infinitely heavy), otherwise a compliant
## point constraint (m/N; ~1e-4 firm, ~1e-2 elastic). Returns the anchor id for set_anchor().
func add_anchor(idx: int, alpha: float, world_pos: Vector3) -> int:
	anchor_idx.append(idx)
	anchor_alpha.append(alpha)
	anchor_t.append(world_pos)
	anchor_prev.append(world_pos)
	anchor_lam.append(0.0)
	if alpha <= 0.0:
		inv_mass[idx] = 0.0
		pos[idx] = world_pos
		prev[idx] = world_pos
	return anchor_idx.size() - 1

func set_anchor(k: int, world_pos: Vector3) -> void:
	anchor_t[k] = world_pos

func set_capsules(a: PackedVector3Array, b: PackedVector3Array, r: PackedFloat32Array) -> void:
	cap_a = a; cap_b = b; cap_r = r

## Never integrate more than this per frame, and treat anything longer as a real hitch (see _step). 30 fps (dev cap) is NOT a hitch.
const HITCH_DT := 0.05

func rebase(shift: Vector3) -> void:
	sync() # never mutate while the workers run
	# Keep the world->ship frame of the last step consistent with the shifted particles, or the next read is `shift` metres off.
	var t := Transform3D(Basis(), shift)
	_launch_xf = _launch_xf * t
	_prev_xf = _prev_xf * t
	for i in n:
		pos[i] -= shift
		prev[i] -= shift
	for k in anchor_t.size():
		anchor_t[k] -= shift
		anchor_prev[k] -= shift

func destroy() -> void:
	unregister(self)
	built = false

func particle(r: int, c: int) -> Vector3:
	return pos[r * cols + c]

func _finish() -> void:
	if _bad and reset_provider.is_valid():
		var rest: PackedVector3Array = reset_provider.call()
		if rest.size() == n:
			pos = rest.duplicate()
			prev = rest.duplicate()
			vel.fill(Vector3.ZERO)
			resets += 1
			print("[cloth] RESET ", tag, " #", resets, " t=", snappedf(WindField.time, 0.1), " stretch=", snappedf(max_stretch_last, 0.01), " |F|=", snappedf(aero_force.length(), 1.0), " gust=", snappedf(gust_seen, 0.01))
			max_stretch = 0.0
		_bad = false
	anchor_prev = anchor_t.duplicate()
	_anchor_primed = true
	if post_step.is_valid():
		post_step.call()

## One frame: wind sample, then `substeps` XPBD substeps. Runs on a worker thread; touches only this object's arrays
## (plus read-only WindField state). Hot loops work on local copies of the packed arrays (member access is slow in GDScript);
## they are written back at the end.
func _step(delta_raw: float) -> void:
	var delta := minf(delta_raw, HITCH_DT) # never integrate a huge step...
	_frame_dt = delta
	if not _xf_primed:
		_prev_xf = _launch_xf
		_xf_primed = true
	if not _anchor_primed:
		anchor_prev = anchor_t.duplicate()
		_anchor_primed = true
	if delta_raw > HITCH_DT + 1.0e-4:
		# ...but after a hitch the ship has moved a lot in that time: carry the whole cloth rigidly with the ship frame
		# (instead of letting the pins yank it) and restart the pin interpolation from the new targets.
		var carry := _launch_xf.affine_inverse() * _prev_xf
		for i in n:
			pos[i] = carry * pos[i]
			prev[i] = carry * prev[i]
		anchor_prev = anchor_t.duplicate()
	_prev_xf = _launch_xf
	# --- wind: sampled on a coarse lattice, bilinear to every particle (gusts/eddies are much larger than the cells)
	var lat := PackedVector3Array()
	var gs := 0.0
	for k in lat_idx.size():
		var p := pos[lat_idx[k]]
		lat.append(WindField.sample(p))
		gs += WindField.gust_factor(p)
	gust_seen = gs / float(maxi(lat_idx.size(), 1))
	var W := wind
	var P0 := pos
	for i in n:
		W[i] = lat[wi[i * 4]] * ww[i * 4] + lat[wi[i * 4 + 1]] * ww[i * 4 + 1] + lat[wi[i * 4 + 2]] * ww[i * 4 + 2] + lat[wi[i * 4 + 3]] * ww[i * 4 + 3]
	if flutter > 0.0:
		var tt := WindField.time
		var amp := flutter * 0.30 * lat[0].length()
		for i in n:
			var p := P0[i]
			W[i] += Vector3(sin(p.x * 2.1 + p.z * 1.3 + tt * 9.0 + float(i)), 0.6 * sin(p.y * 2.7 + p.x * 1.1 + tt * 12.0 - float(i) * 0.7), sin(p.z * 1.9 - p.y * 1.5 + tt * 10.0 + float(i) * 1.3)) * amp
	wind = W
	var P := pos
	var Q := prev
	var V := vel
	var F := force
	var IM := inv_mass
	var M := mass
	var TR := tris
	var CA := ca
	var CB := cb
	var CR := crest
	var CAL := calpha
	var LAM := lam
	# strong wind -> stiffer problem: more substeps (cost only when it blows)
	var ws := WindField.mean_speed()
	var nsub := maxi(1, roundi(float(substeps + mini((1 if ws > 14.0 else 0) + (1 if ws > 22.0 else 0), max_extra_substeps)) * maxf(Quality.cloth_scale, min_quality)))
	var niter := maxi(3, roundi(float(iterations + boost_iters * ((1 if ws > 14.0 else 0) + (1 if ws > 22.0 else 0))) * maxf(Quality.cloth_scale, min_quality)))
	var h := delta / float(nsub)
	var inv_h := 1.0 / h
	var inv_h2 := inv_h * inv_h
	var f_acc := Vector3.ZERO
	var cf_acc := Vector3.ZERO
	var pt_acc := Vector3.ZERO
	var w_acc := 0.0
	var nc := CA.size()
	var damp := 1.0 - damping
	var na := anchor_idx.size()
	var ncap := cap_r.size()
	var ntri := TR.size()
	var g := gravity
	var kn := 0.25 * RHO
	var amax2 := max_aero_accel * max_aero_accel
	for s in nsub:
		var u := float(s + 1) / float(nsub)
		# --- external forces: aero per triangle -----------------------------------------------------------------
		F.fill(Vector3.ZERO)
		for t in range(0, ntri, 3):
			var ia := TR[t]
			var ib := TR[t + 1]
			var ic := TR[t + 2]
			var pa := P[ia]
			var pb := P[ib]
			var pc := P[ic]
			var cr := (pb - pa).cross(pc - pa)
			var a2 := cr.length()
			if a2 < 1.0e-9:
				continue
			var nrm := cr / a2
			var vrel := (W[ia] + W[ib] + W[ic] - V[ia] - V[ib] - V[ic]) * (1.0 / 3.0)
			var vn := vrel.dot(nrm)
			var f := (kn * a2 * vrel.length()) * (nrm * (cN * vn) + (vrel - nrm * vn) * cT)
			var third := f * (1.0 / 3.0)
			F[ia] += third
			F[ib] += third
			F[ic] += third
			f_acc += f
			var wgt := f.length()
			pt_acc += (pa + pb + pc) * (wgt / 3.0)
			w_acc += wgt
		# --- integrate --------------------------------------------------------------------------------------------
		for i in n:
			var p := P[i]
			Q[i] = p
			var w := IM[i]
			if w == 0.0:
				continue
			var acc := F[i] * w
			var al2 := acc.length_squared()
			if al2 > amax2:
				acc *= max_aero_accel / sqrt(al2)
			var v := (V[i] + (g + acc) * h) * damp
			var sp2 := v.length_squared()
			if sp2 > MAX_SPEED * MAX_SPEED:
				v *= MAX_SPEED / sqrt(sp2)
			V[i] = v
			P[i] = p + v * h
		# hard pins follow their (interpolated) targets
		for k in na:
			if anchor_alpha[k] <= 0.0:
				var tgt := anchor_prev[k].lerp(anchor_t[k], u)
				var i := anchor_idx[k]
				V[i] = (tgt - Q[i]) * inv_h
				P[i] = tgt
		# --- constraints ------------------------------------------------------------------------------------------
		LAM.fill(0.0)
		anchor_lam.fill(0.0)
		# colliders act as inequality constraints INSIDE the solver loop (a post-pass fights the stretch constraints and
		# makes the cloth over-stretch where it presses on a mast); only particles near a capsule are tested
		var near: Array[PackedInt32Array] = []
		for q in ncap:
			var qa0 := cap_a[q]
			var ab0 := cap_b[q] - qa0
			var ab20 := maxf(ab0.length_squared(), 1.0e-9)
			var lim := cap_r[q] + 1.2
			var lst := PackedInt32Array()
			for i in n:
				if IM[i] == 0.0:
					continue
				var p0 := P[i]
				var cp0 := qa0 + ab0 * clampf((p0 - qa0).dot(ab0) / ab20, 0.0, 1.0)
				if p0.distance_squared_to(cp0) < lim * lim:
					lst.append(i)
			near.append(lst)
		for _it in niter:
			var rev := (_it & 1) == 1 # symmetric Gauss-Seidel: alternate sweep direction so tension propagates both ways
			for kk in nc:
				var k := (nc - 1 - kk) if rev else kk
				var a := CA[k]
				var b := CB[k]
				var wa := IM[a]
				var wb := IM[b]
				var wsum := wa + wb
				if wsum == 0.0:
					continue
				var pa := P[a]
				var pb := P[b]
				var d := pa - pb
				var l := d.length()
				if l < 1.0e-7:
					continue
				var at := CAL[k] * inv_h2
				var dl := (-(l - CR[k]) - at * LAM[k]) / (wsum + at)
				LAM[k] += dl
				var corr := d * (dl * sor / l)
				P[a] = pa + corr * wa
				P[b] = pb - corr * wb
			for k in na:
				var al := anchor_alpha[k]
				if al > 0.0:
					var i := anchor_idx[k]
					var tgt := anchor_prev[k].lerp(anchor_t[k], u)
					var d := P[i] - tgt
					var l := d.length()
					if l > 1.0e-7:
						var w := IM[i]
						var at := al * inv_h2
						var dl := (-l - at * anchor_lam[k]) / (w + at)
						anchor_lam[k] += dl
						P[i] += d * (w * dl / l)
			for q in ncap:
				var qa := cap_a[q]
				var ab := cap_b[q] - qa
				var ab2 := maxf(ab.length_squared(), 1.0e-9)
				var rad := cap_r[q]
				var rad2 := rad * rad
				for i in near[q]:
					var p := P[i]
					var cp := qa + ab * clampf((p - qa).dot(ab) / ab2, 0.0, 1.0)
					var dd := p - cp
					var dl2 := dd.length_squared()
					if dl2 < rad2:
						var dlen := sqrt(dl2)
						P[i] = cp + (dd / dlen if dlen > 1.0e-6 else Vector3(1, 0, 0)) * rad
		# --- velocities + constraint (reaction) force --------------------------------------------------------------
		var cf := Vector3.ZERO
		for i in n:
			var w := IM[i]
			if w == 0.0:
				continue
			var vnew := (P[i] - Q[i]) * inv_h
			# m dv/dt - (external) = constraint force on the particle
			cf += (vnew - V[i]) * (M[i] * inv_h)
			V[i] = vnew
		cf_acc += cf
	pos = P
	prev = Q
	vel = V
	force = F
	lam = LAM
	aero_force = f_acc / float(nsub)
	constraint_force = cf_acc / float(nsub)
	aero_point = (pt_acc / w_acc) if w_acc > 1.0e-6 else pos[n / 2]
	pressure = aero_force.length() / maxf(area, 0.01)
	# stretch diagnostics on the constraints (every 4th)
	var ms := 0.0
	for k in range(0, nc, 4):
		var l2 := pos[ca[k]].distance_to(pos[cb[k]])
		ms = maxf(ms, l2 / maxf(crest[k], 1.0e-4) - 1.0)
	max_stretch = ms
	# self-heal: numerical blow-up (NaN / absurd stretch) -> reset to the rest layout on the main thread (see _finish)
	var probe := pos[n / 2]
	if ms > 0.8 or is_nan(probe.x) or is_nan(probe.y) or is_nan(probe.z) or probe.length_squared() > 1.0e10:
		_bad = true
		max_stretch_last = ms
