class_name TestKit
extends RefCounted
## Helpers for building worlds and people in tests.


## A living world at local noon (UTC, 2026-01-01) with nobody in it yet.
static func world(pack_id := "_smoke", seed := 1) -> World:
	var w := World.new(Pack.load_dir("res://packs/" + pack_id), seed)
	w.set_time(1767268800, 0)
	w.phase = "living"
	w.candidate = {}
	return w


## Adds an adult at each need's `start` value and a lifespan of 70.
static func adult(w: World, age := 25.0) -> Person:
	var p := Person.new()
	p.given = "Test"
	p.age = age
	p.lifespan = 70.0
	for nid in w.pack.needs:
		p.needs[nid] = float(w.pack.needs[nid]["start"])
	w.add_person(p)
	w.phase = "living"
	return p
