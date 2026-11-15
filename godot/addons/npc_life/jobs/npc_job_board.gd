class_name NpcJobBoard
extends RefCounted
## The world's job board: sources post and clear jobs, agents claim them. Time is the world's logical clock (passed in), never wall-clock.
## Iteration is always sorted by job id so decisions are reproducible.

signal job_posted(job: NpcJob)
signal job_cleared(job: NpcJob)
signal job_expired(job: NpcJob)
signal job_claimed(job: NpcJob, agent_id: StringName)
signal job_released(job: NpcJob, agent_id: StringName)

var _jobs: Dictionary = {} # id -> NpcJob
var _agent_job: Dictionary = {} # agent_id -> job id
var _now := 0.0

func now() -> float:
	return _now

## Posts a job (stamping its posting time). An existing id is updated in place: same object, claims and posting time kept.
func post(job: NpcJob, now := -1.0) -> NpcJob:
	if now >= 0.0:
		_now = now
	var cur: NpcJob = _jobs.get(job.id)
	if cur != null:
		if cur != job:
			cur.update_from(job)
		return cur
	job.posted_at = _now
	_jobs[job.id] = job
	job_posted.emit(job)
	return job

func get_job(id: StringName) -> NpcJob:
	return _jobs.get(id)

## Removes a job (releasing its claims). False when the id is unknown.
func clear(id: StringName) -> bool:
	var j: NpcJob = _jobs.get(id)
	if j == null:
		return false
	_remove(j)
	job_cleared.emit(j)
	return true

## Clears every job of a source; returns how many.
func clear_source(source_id: StringName) -> int:
	var n := 0
	for j in open_jobs():
		if j.source_id == source_id:
			clear(j.id)
			n += 1
	return n

## Every posted job, sorted by id.
func open_jobs() -> Array[NpcJob]:
	var ids := _jobs.keys()
	ids.sort()
	var out: Array[NpcJob] = []
	for id in ids:
		out.append(_jobs[id])
	return out

## Jobs this agent may take: free slot, required tags satisfied, not already held by it. Sorted by id.
func candidates(agent_id: StringName, agent_tags: PackedStringArray) -> Array[NpcJob]:
	var out: Array[NpcJob] = []
	for j in open_jobs():
		if j.free_slots() > 0 and j.has_tags(agent_tags) and not j.claimed_by.has(agent_id):
			out.append(j)
	return out

## Claims a slot of job `id` for the agent; fails when the agent already holds a job, the job is full or the tags are not met.
func claim(id: StringName, agent_id: StringName, agent_tags := PackedStringArray()) -> bool:
	var j: NpcJob = _jobs.get(id)
	if j == null or _agent_job.has(agent_id) or j.free_slots() <= 0 or not j.has_tags(agent_tags):
		return false
	j.claimed_by.append(agent_id)
	_agent_job[agent_id] = id
	job_claimed.emit(j, agent_id)
	return true

func release(id: StringName, agent_id: StringName) -> bool:
	var j: NpcJob = _jobs.get(id)
	if j == null or not j.claimed_by.has(agent_id):
		return false
	j.claimed_by.erase(agent_id)
	_agent_job.erase(agent_id)
	job_released.emit(j, agent_id)
	return true

func claimed_job_of(agent_id: StringName) -> StringName:
	return _agent_job.get(agent_id, &"")

## Removes every job whose deadline passed (claims released); returns them, each emitted once through `job_expired`.
func expire(now: float) -> Array[NpcJob]:
	_now = now
	var gone: Array[NpcJob] = []
	for j in open_jobs():
		if now >= j.deadline():
			gone.append(j)
	for j in gone:
		_remove(j)
		job_expired.emit(j)
	return gone

## Base urgency plus growth since posting; growth stops at the deadline.
func urgency_of(job: NpcJob, now: float) -> float:
	var elapsed := maxf(now - job.posted_at, 0.0)
	if job.ttl_s > 0.0:
		elapsed = minf(elapsed, job.ttl_s)
	return job.urgency + job.urgency_rate * elapsed

func _remove(j: NpcJob) -> void:
	for a in j.claimed_by.duplicate():
		_agent_job.erase(a)
		j.claimed_by.erase(a)
		job_released.emit(j, a)
	_jobs.erase(j.id)
