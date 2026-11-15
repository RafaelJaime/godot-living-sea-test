class_name NpcJobSource
extends Node
## Abstract job source: derives jobs from the game world and posts them on the board; reacts to the world effect of a finished action.
## Extend it in the game (the addon never reads game state itself). `world` parameters are typed Node so this file does not depend on NpcWorld.

@export var source_id: StringName
@export var poll_hz := 2.0

## The board to post on. NpcWorld sets it when the source is registered; tests may set it directly.
var board: NpcJobBoard
var _next_poll := 0.0

## Virtual: post and clear jobs. `now` is the world's logical clock.
func _poll(_world: Node, _now: float) -> void:
	pass

## Virtual: the work reached its effect moment (e.g. light the lantern).
func _on_job_effect(_job: NpcJob, _agent: Node, _effect: StringName) -> void:
	pass

## Virtual: the job ended (`done`, `aborted`, `expired`, `preempted`).
func _on_job_finished(_job: NpcJob, _agent: Node, _result: StringName) -> void:
	pass

## Calls `_poll` when due according to `poll_hz`. Returns true when it polled.
func poll_if_due(world: Node, now: float) -> bool:
	if now < _next_poll:
		return false
	_next_poll = now + 1.0 / maxf(poll_hz, 0.001)
	_poll(world, now)
	return true

## Posts a job stamped with this source's id (an existing id is updated in place).
func post_job(job: NpcJob, now := -1.0) -> NpcJob:
	job.source_id = source_id
	return board.post(job, now) if board else job

func clear_job(id: StringName) -> bool:
	return board.clear(id) if board else false
