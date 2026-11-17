extends TestCase

func test_same_seed_same_sequence():
	var a := SimRng.new(42)
	var b := SimRng.new(42)
	for i in 20:
		assert_eq(a.randi_range(0, 1000), b.randi_range(0, 1000))

func test_state_roundtrip():
	var a := SimRng.new(7)
	a.randf()
	var s := a.get_state()
	var x := a.randf()
	a.set_state(s)
	assert_eq(a.randf(), x)

func test_state_is_strings():
	var s := SimRng.new(7).get_state()
	assert_eq(typeof(s["seed"]), TYPE_STRING)
	assert_eq(typeof(s["state"]), TYPE_STRING)

func test_weighted_pick_respects_zero_weight():
	var r := SimRng.new(1)
	for i in 50:
		assert_eq(r.weighted_pick(["a", "b"], [0.0, 1.0]), "b")

func test_chance_bounds():
	var r := SimRng.new(1)
	assert_true(not r.chance(0.0))
	assert_true(r.chance(1.0))
