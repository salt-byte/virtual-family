class_name Overlays
extends CanvasLayer
## Full-screen overlays above the HUD: broken pack, unreadable save, adoption, game over,
## the "while you were away" summary and a marriage proposal. Which one shows is decided
## afresh on every `refresh()`; a half-transparent backdrop keeps clicks off the house.

const LAYER := 10
const PANEL_WIDTH := 460.0

var main: Main
var session: GameSession

var _root: Control
var _card: StyleBoxFlat
var _box: VBoxContainer
var _buttons: Dictionary = {}  # key -> Button
var _current := ""
var _signature := ""
var _away: Dictionary = {}
var _proposal_id := -1
## True while the player has opened the card of the animal waiting at the gate.
var _stray_open := false
## Story fragments picked up while playing, waiting to be read: {story, fragment}.
var _fragments: Array = []
## Family news waiting to be read: the events "born" and "relative_arrived", in order.
var _news: Array = []


func setup(m: Main) -> void:
	main = m
	session = m.session
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	_card = StyleBoxFlat.new()
	_card.bg_color = Color(0.13, 0.12, 0.11, 1.0)
	_card.set_corner_radius_all(8)
	_card.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", _card)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)
	session.away.connect(func(summary: Dictionary): _away = summary)
	session.event.connect(func(e: Dictionary):
		var type := str(e.get("type", ""))
		if type == "fragment_found":
			_fragments.append({"story": str(e["story"]), "fragment": str(e["fragment"])})
		elif type == "born" or type == "relative_arrived":
			_news.append({"type": type, "person": int(e["person"])}))
	refresh()


## One of "", "pack_error", "load_error", "adopt", "over", "away", "fragment", "born",
## "relative", "visitor", "stray", "proposal".
func current() -> String:
	return _current


## The card's panel style; for tests.
func card_style() -> StyleBoxFlat:
	return _card


## True while an overlay covers the house.
func blocks_input() -> bool:
	return _current != ""


## Opens the card of the animal waiting at the gate; does nothing when none waits.
func open_stray() -> void:
	var w := session.world
	if w != null and w.phase == "living" and not w.pet_offer.is_empty():
		_stray_open = true
		refresh()


## Opens the card for the first waiting proposal; does nothing when none waits.
func open_proposal() -> void:
	var w := session.world
	if w != null and w.phase == "living" and not w.proposals.is_empty():
		_proposal_id = int(w.proposals[0]["id"])
		refresh()


## All text of the overlay on screen, joined with newlines; for tests.
func text() -> String:
	var parts: Array[String] = []
	_collect(_box, parts)
	return "\n".join(parts)


func _collect(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is Label or c is Button:
			out.append(c.text)
		_collect(c, out)


func press(button_key: String) -> void:
	if not _buttons.has(button_key):
		return
	match _current:
		"load_error":
			if session.new_game():
				_away = {}
		"adopt":
			if button_key == "btn.adopt":
				_adopt()
			else:
				session.command({"type": "reroll"})
		"over":
			_away = {}
			session.command({"type": "reroll"})
		"away":
			_away = {}
		"fragment":
			if not _fragments.is_empty():
				_fragments.pop_front()
		"born", "relative":
			if not _news.is_empty():
				_news.pop_front()
		"stray":
			if button_key != "btn.close":
				session.command({"type": "answer_stray", "accept": button_key == "btn.take_in"})
			_stray_open = false
		"visitor":
			var v := StorySystem.visitors(session.world)
			if not v.is_empty():
				session.command({"type": "receive_visitor", "story": str(v[0])})
		"proposal":
			if button_key == "btn.close":
				_proposal_id = -1
			else:
				session.command({"type": "answer_proposal", "id": _proposal_id,
					"accept": button_key == "btn.accept"})
				_proposal_id = -1
	refresh()


## Adopts the candidate; the first adoption of a brand-new world, once per install, also
## tells the player that people can be dragged.
func _adopt() -> void:
	var first := not session.world.adopted_once
	var r := session.command({"type": "adopt"})
	if r.get("ok", false) and first and not bool(session.settings.get("hint_seen", false)):
		main.hud.toast(session.strings.t("hint.drag"))
		session.set_setting("hint_seen", true)


## Priority: pack_error, load_error, away, adopt, over, fragment, visitor, proposal. The away summary outranks the
## game-over card (the dead are still in the world, so names resolve) but is dropped as stale
## once a new game is adopting: the world it described is gone.
func refresh() -> void:
	var w := session.world
	if w != null and w.phase == "adopting":
		_away = {}
		_news.clear()
	if w == null or w.pet_offer.is_empty():
		_stray_open = false
	var proposal := _find_proposal(w)
	if proposal.is_empty():
		_proposal_id = -1
	var kind := ""
	var sig := ""
	if w != null and w.phase == "invalid":
		kind = "pack_error"
		sig = str(session.pack.errors)
	elif session.load_error != "":
		kind = "load_error"
		sig = session.load_error
	elif not _away.is_empty() and w != null:
		kind = "away"
		sig = str(_away)
	elif w != null and w.phase == "adopting":
		kind = "adopt"
		sig = str(w.candidate)
	elif w != null and w.phase == "over":
		kind = "over"
	elif not _fragments.is_empty() and w != null and w.phase == "living":
		kind = "fragment"
		sig = str(_fragments[0])
	elif not _news.is_empty() and w != null and w.phase == "living":
		kind = "born" if str(_news[0]["type"]) == "born" else "relative"
		sig = str(_news[0])
	elif w != null and w.phase == "living" and not StorySystem.visitors(w).is_empty():
		kind = "visitor"
		sig = str(StorySystem.visitors(w)[0])
	elif _stray_open and w != null and w.phase == "living" and not w.pet_offer.is_empty():
		kind = "stray"
		sig = str(w.pet_offer)
	elif not proposal.is_empty():
		kind = "proposal"
		sig = str(proposal)
	if kind == _current and sig == _signature:
		return
	_current = kind
	_signature = sig
	_rebuild(w, proposal)


func _find_proposal(w: World) -> Dictionary:
	if w == null or w.phase != "living" or _proposal_id < 0:
		return {}
	for pr in w.proposals:
		if int(pr["id"]) == _proposal_id:
			return pr
	return {}


func _rebuild(w: World, proposal: Dictionary) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_root.visible = _current != ""
	var s := session.strings
	match _current:
		"pack_error":
			_title(s.t("title.pack_error"))
			var scroll := ScrollContainer.new()
			scroll.custom_minimum_size = Vector2(PANEL_WIDTH, 240)
			_box.add_child(scroll)
			var list := VBoxContainer.new()
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(list)
			for e in session.pack.errors:
				list.add_child(_label(e))
		"load_error":
			_title(s.t("title.load_error"))
			_box.add_child(_label(s.t("load." + session.load_error)))
			_box.add_child(_label(s.t("load.backup")))
			_button("btn.new_game")
		"adopt":
			_title(s.t("title.adopt"))
			_person_card(Person.from_dict(w.candidate))
			var row := _row()
			_button("btn.adopt", row)
			_button("btn.reroll", row)
		"over":
			_title(s.t("title.over"))
			_box.add_child(_label(s.t("over.reason")))
			_box.add_child(_label(s.t("over.carry")))
			_button("btn.new_game")
		"away":
			_title(s.t("title.away"))
			for line in s.summary_lines(_away, w):
				_box.add_child(_label(line))
			_button("btn.close")
		"fragment":
			var fr: Dictionary = _fragments[0]
			_title(s.story_title(str(fr["story"]), w))
			var f := StorySystem.fragment(w.pack, str(fr["story"]), str(fr["fragment"]))
			_box.add_child(_label(s.t("ev.fragment").replace("{name}", str(f.get("name", "")))))
			_box.add_child(_label(str(f.get("text", ""))))
			_button("btn.close")
		"born":
			var child := w.person(int(_news[0]["person"]))
			_title(s.t("title.born"))
			if child != null:
				_box.add_child(_label(s.born_line(child)))
				var mother := w.person(child.mother)
				var father := w.person(child.father)
				if mother != null and father != null:
					_box.add_child(_label(s.t("born.parents").format({"father": s.person_name(father), "mother": s.person_name(mother)})))
				_box.add_child(_label(s.generation_label(child.generation)))
			_button("btn.close")
		"relative":
			_title(s.t("title.relative"))
			var who := w.person(int(_news[0]["person"]))
			if who != null:
				_box.add_child(_label(s.t("ev.relative").replace("{name}", s.person_name(who))))
				_person_card(who)
			_button("btn.close")
		"visitor":
			var sid := str(StorySystem.visitors(w)[0])
			var fin: Dictionary = w.pack.stories[sid]["finale"]
			_title(s.story_title(sid, w))
			_box.add_child(_label(str(fin.get("text", ""))))
			if int(fin.get("money", 0)) > 0:
				_box.add_child(_label(s.t("visitor.money").replace("{money}", s.t("money").replace("{n}", str(int(fin["money"]))))))
			_button("btn.receive")
		"stray":
			var k: Dictionary = w.pack.pets.get(str(w.pet_offer["kind"]), {})
			_title(s.t("title.stray"))
			_box.add_child(_label(str(k.get("stray_text", k.get("name", "")))))
			_box.add_child(_label("%s · %s" % [str(k.get("name", "")), s.t("years").replace("{n}", str(int(float(w.pet_offer["age"]))))]))
			var row := _row()
			_button("btn.take_in", row)
			_button("btn.shoo", row)
			_button("btn.close", row)
		"proposal":
			_title(s.t("title.proposal"))
			var target := w.person(int(proposal.get("for", -1)))
			if target != null:
				_box.add_child(_label(s.t("proposal.for").replace("{name}", s.person_name(target))))
			_person_card(Person.from_dict(proposal["person"]))
			_box.add_child(_label(s.t("label.savings").replace("{n}", s.t("money").replace("{n}", str(int(proposal["savings"]))))))
			var row := _row()
			_button("btn.accept", row)
			_button("btn.decline", row)
			_button("btn.close", row)


func _person_card(p: Person) -> void:
	var s := session.strings
	_box.add_child(_label(s.person_name(p)))
	var gender := s.t("gender." + p.gender) if p.gender != "" else ""
	var bits: Array[String] = []
	if gender != "" and gender != "gender." + p.gender:
		bits.append(gender)
	bits.append(s.t("years").replace("{n}", str(int(p.age))))
	var job: Dictionary = session.pack.livelihoods.get(p.track, {})
	if not job.is_empty():
		var levels: Array = job.get("levels", [])
		var lv := str(levels[p.level]["name"]) if p.level >= 0 and p.level < levels.size() else ""
		var job_bits: Array[String] = []
		for part in [str(job.get("name", "")), lv]:
			if part != "":
				job_bits.append(part)
		bits.append(" · ".join(job_bits))
	_box.add_child(_label(" · ".join(bits)))
	if not p.likes.is_empty():
		_box.add_child(_label(s.t("label.likes") + "：" + "、".join(p.likes)))
	if not p.dislikes.is_empty():
		_box.add_child(_label(s.t("label.dislikes") + "：" + "、".join(p.dislikes)))


func _title(t: String) -> void:
	var l := _label(t)
	l.add_theme_font_size_override("font_size", 22)
	_box.add_child(l)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PANEL_WIDTH - 48
	return l


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	_box.add_child(r)
	return r


func _button(key: String, parent: Control = null) -> void:
	var b := Button.new()
	b.text = session.strings.t(key)
	b.pressed.connect(press.bind(key))
	(parent if parent != null else _box).add_child(b)
	_buttons[key] = b
