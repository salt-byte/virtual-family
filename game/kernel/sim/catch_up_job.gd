class_name CatchUpJob
extends RefCounted
## One replay of an absence (see `Offline.catch_up`), split so a view can run it a slice at a
## time between frames: `run` some steps until it returns true, then `finish` once for the
## summary. Any split gives the same world and summary as the one-shot replay. While it is
## unfinished the world is mid-replay (`offline` is on, earlier events are held here): nothing
## else may step, command or save it.

## Set by `World.begin_sync`: `finish` then also puts the sim clock at this real time
## (plus the clock lead), as `World.sync` does. -1: leave the clock where the replay left it.
var snap_unix := -1

var _world: World
var _elapsed := 0.0
var _seconds := 0.0
var _zero := true
var _done := false
var _finished := false
var _t0 := 0
var _money0 := 0
var _letter0 := 0
var _held: Array = []
var _was_offline := false


func _init(world: World, elapsed_seconds: float) -> void:
	_world = world
	_elapsed = elapsed_seconds
	if world.phase != "living" or elapsed_seconds <= 0.0:
		_done = true
		return
	_zero = false
	var cap := int(world.pack.cfg("offline_cap_hours")) * 3600
	_seconds = minf(elapsed_seconds, float(cap))
	_t0 = world.now
	_money0 = world.money
	_letter0 = world.letter_next
	_held = world.drain_events()
	_was_offline = world.offline
	world.offline = true
	world.queue_time(_seconds)


## Runs up to `max_steps` more steps (all that are left when negative); true once the replay is
## done.
func run(max_steps: int) -> bool:
	if not _done:
		_done = _world.run_steps(max_steps)
	return _done


func done() -> bool:
	return _done


## How much of the replay has run, 0..1.
func progress() -> float:
	if _done or _seconds <= 0.0:
		return 1.0
	return clampf(float(_world.now - _t0) / _seconds, 0.0, 1.0)


## Game seconds this replay covers (after the cap).
func seconds() -> float:
	return _seconds


## Ends the replay (running whatever is left) and returns its summary; see `Offline`.
func finish() -> Dictionary:
	assert(not _finished, "CatchUpJob.finish called twice")
	_finished = true
	run(-1)
	var summary: Dictionary
	if _zero:
		summary = Offline.zero_summary(_world)
	else:
		_world.offline = _was_offline
		var letters := LetterSystem.trim_new(_world, _letter0)
		summary = Offline.summarize(_world, _elapsed, _t0, _money0, letters, _held)
	if snap_unix >= 0:
		_world.snap_clock(snap_unix)
	return summary
