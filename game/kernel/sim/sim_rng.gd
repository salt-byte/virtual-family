class_name SimRng
extends RefCounted
## Deterministic random source for the sim kernel. Same seed + same calls => same results.

var _rng := RandomNumberGenerator.new()


func _init(seed: int = 0) -> void:
	_rng.seed = seed


func randf() -> float:
	return _rng.randf()


func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


func chance(p: float) -> bool:
	return p >= 1.0 or _rng.randf() < p


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


## Picks one of `items` with probability proportional to `weights` (non-positive weights never win).
func weighted_pick(items: Array, weights: Array) -> Variant:
	var total := 0.0
	var last := -1
	for i in mini(items.size(), weights.size()):
		if weights[i] > 0.0:
			total += weights[i]
			last = i
	if last < 0:
		return null
	var roll := _rng.randf() * total
	for i in last:
		if weights[i] > 0.0:
			roll -= weights[i]
			if roll < 0.0:
				return items[i]
	return items[last]


## Seed and state as Strings: 64-bit ints lose precision when saved through JSON.
func get_state() -> Dictionary:
	return {"seed": str(_rng.seed), "state": str(_rng.state)}


func set_state(d: Dictionary) -> void:
	_rng.seed = int(d["seed"])
	_rng.state = int(d["state"])
