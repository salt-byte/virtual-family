class_name TestCase
extends RefCounted
## Base class for tests. A failed assertion records a message and the run continues.

var failures: Array[String] = []
var assertions := 0


func assert_true(cond: bool, msg := "") -> void:
	assertions += 1
	if not cond:
		failures.append("assert_true failed" + _suffix(msg))


func assert_eq(a, b, msg := "") -> void:
	assertions += 1
	if typeof(a) != typeof(b) or a != b:
		failures.append("assert_eq failed: %s != %s%s" % [str(a), str(b), _suffix(msg)])


func assert_near(a: float, b: float, eps := 0.001, msg := "") -> void:
	assertions += 1
	if absf(a - b) > eps:
		failures.append("assert_near failed: %s !~ %s (eps %s)%s" % [str(a), str(b), str(eps), _suffix(msg)])


func _suffix(msg: String) -> String:
	return "" if msg == "" else " - " + msg
