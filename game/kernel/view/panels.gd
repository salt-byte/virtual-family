class_name Panels
extends CanvasLayer
## Pop-up panels above the HUD: the shop (goods, and what the household holds), goals and
## collection, the family list and the keepsake box (a curio cabinet, `CabinetView`). One at a time, centred, closed by `btn.close` or Esc.
## Reads the World; everything it changes goes through session commands.

const LAYER := 5
const PANEL_WIDTH := 560.0
const BODY_HEIGHT := 340.0
const MARGIN := 24.0
const DONE_MARK := "✓ "
const UNKNOWN := "？"
## The most of the keepsake cabinet shown at once (it scrolls beyond).
const BOX_HEIGHT := 470.0
## Market tab ids are this prefix plus a market section id (see `_market_tabs`).
const MARKET_TAB := "market:"

var main: Main
var session: GameSession

var _root: Control
var _card: PanelContainer
var _box: VBoxContainer
var _buttons: Dictionary = {}  # id -> Button
var _kind := ""
var _tab := ""
var _signature := ""
## In the family panel: uid of the person whose livelihood is being changed (-1: none).
var _changing := -1
## In the keepsake box: the thing whose card is open ("frag:<story>:<fragment>" or
## "curio:<kind>"); "" shows the cabinet.
var _piece := ""


func setup(m: Main) -> void:
	main = m
	session = m.session
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	_root.theme = ViewWidgets.panel_theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.16, 0.11, 0.07, 0.4)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	_card = panel
	panel.custom_minimum_size.x = PANEL_WIDTH
	panel.add_theme_stylebox_override("panel", ViewWidgets.card_style(MARGIN))
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)


## One of "", "shop", "ledger", "family", "stories", "go_out" (where the selected person
## could be sent).
func opened() -> String:
	return _kind


## True while a panel covers the house.
func blocks_input() -> bool:
	return _kind != ""


## Opens a panel; ignored for an unknown name, while an overlay shows or outside a running game.
func open(what: String) -> void:
	if not what in ["shop", "ledger", "family", "stories", "go_out"]:
		return
	var w := session.world
	if w == null or w.phase != "living" or main.overlays.current() != "":
		return
	if what == "go_out":
		var p := w.person(main.selected)
		if p == null or not p.alive or main.selected_pet >= 0:
			return
	_kind = what
	_changing = -1
	_piece = ""
	_tab = _tabs()[0] if not _tabs().is_empty() else ""
	_signature = ""
	refresh()


func close() -> void:
	if _kind == "":
		return
	_kind = ""
	_tab = ""
	_changing = -1
	_piece = ""
	_signature = ""
	_rebuild()


func _tabs() -> Array:
	match _kind:
		"shop":
			var ids := []
			for t in _market_tabs(session.world):
				ids.append(t["id"])
			ids.append("tab.inventory")
			return ids
		"ledger":
			return ["tab.goals", "tab.collection"]
	return []


func _unhandled_key_input(event: InputEvent) -> void:
	if _kind != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## All text of the open panel, joined with newlines; for tests.
func text() -> String:
	var parts: Array[String] = []
	_collect(_box, parts)
	return "\n".join(parts)


func _collect(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		if c is Label or c is Button:
			out.append(c.text)
		elif c is CabinetView:
			out.append_array(c.lines())
		_collect(c, out)


func has_button(id: String) -> bool:
	return _buttons.has(id)


func is_disabled(id: String) -> bool:
	return not _buttons.has(id) or (_buttons[id] as Button).disabled


func button_node(id: String) -> Button:
	return _buttons.get(id)


## Test entry point and button handler; unknown or disabled ids do nothing. In the shop
## "tab.items" stands for the first goods tab and "tab.pets" for the one with the animals.
func press(id: String) -> void:
	if _kind == "shop" and id in ["tab.items", "tab.pets"]:
		id = _market_tab_for(id)
	if is_disabled(id):
		return
	if id == "btn.close":
		close()
	elif id in _tabs():
		_tab = id
		_signature = ""
		refresh()
	elif id.begins_with("go:"):
		var r := session.command({"type": "go_out", "person": main.selected, "action": id.substr(3)})
		if r.get("ok", false):
			close()
		else:
			refresh()
	elif id.begins_with("buy:"):
		session.command({"type": "buy", "item": id.substr(4)})
		refresh()
	elif id.begins_with("use:"):
		if main.selected_pet >= 0:
			session.command({"type": "use_item", "item": id.substr(4), "pet": main.selected_pet})
		else:
			session.command({"type": "use_item", "item": id.substr(4), "person": main.selected})
		refresh()
	elif id.begins_with("buy_pet:"):
		session.command({"type": "buy_pet", "kind": id.substr(8)})
		refresh()
	elif id.begins_with("place:"):
		# New furniture is set down by hand: hand it to arrange mode.
		close()
		main.arrange.enter()
		main.arrange.pick_type(id.substr(6))
	elif id.begins_with("build:"):
		session.command({"type": "build_room", "room": id.substr(6)})
		refresh()
	elif id.begins_with("service:"):
		session.command({"type": "buy_service", "service": id.substr(8)})
		refresh()
	elif id.begins_with("used:"):
		session.command({"type": "buy_secondhand", "listing": int(id.substr(5))})
		refresh()
	elif id.begins_with("ticket:"):
		var r := session.command({"type": "open_ticket", "ticket": int(id.substr(7))})
		if r.get("ok", false):
			main.hud.toast(session.strings.event({"type": "lottery_drawn", "amount": int(r["amount"])}, session.world))
		refresh()
	elif id.begins_with("pet:"):
		close()
		main.select_pet(int(id.substr(4)))
	elif id.begins_with("person:"):
		main.select(int(id.substr(7)))
		close()
	elif id == "stray":
		close()
		main.overlays.open_stray()
	elif id == "proposal":
		close()
		main.overlays.open_proposal()
	elif id.begins_with("change:"):
		_changing = int(id.substr(7))
		refresh()
	elif id.begins_with("frag:") or id.begins_with("curio:"):
		_piece = id
		refresh()
	elif id == "btn.back":
		_piece = ""
		refresh()
	elif id == "sell_extras":
		_sold(session.command({"type": "sell_collectible"}))
	elif id.begins_with("sell_one:"):
		_sold(session.command({"type": "sell_collectible", "kind": id.substr(9)}))
	elif id.begins_with("sell_all:"):
		_sold(session.command({"type": "sell_collectible", "kind": id.substr(9), "all": true}))
	elif id == "change.cancel":
		_changing = -1
		refresh()
	elif id.begins_with("track:"):
		session.command({"type": "change_track", "person": _changing, "track": id.substr(6)})
		_changing = -1
		refresh()


## Rebuilds only when something the panel shows has changed.
func refresh() -> void:
	if _kind == "":
		return
	var w := session.world
	if w == null or w.phase != "living" or main.overlays.current() != "":
		close()
		return
	var sig := _kind + "|" + _tab + "|" + _data_signature(w)
	if sig == _signature:
		return
	_signature = sig
	_rebuild()


func _data_signature(w: World) -> String:
	var s := session.strings
	match _kind:
		"shop":
			var sel := w.person(main.selected)
			var total := 0
			for k in w.stock:
				total += int(w.stock[k])
			var wishes := ""
			for p in w.people:
				if p.alive:
					wishes += str(p.wish)
			var pets := ""
			for pet in w.pets:
				pets += "%d%s%s" % [pet.uid, pet.state, str(pet.wish)]
			var market := "%s|%s|%s|%s|%d|%d|%d" % [str(w.secondhand), str(w.services_bought), str(w.tickets), str(w.candidate),
				w.helper_until, w.speed_until, w.rooms_built.size()]
			if _tab != "tab.inventory":
				market += "|%d" % (w.now / 60)  # the countdowns on the stall and the services
			return "%d|%d|%s|%s|%s|%d|%s|%d|%s" % [w.money, total, str(w.inventory), s.person_name(sel) if sel != null and sel.alive else "", wishes,
				main.selected_pet, pets, w.objects.size(), market + "|" + w.festival]
		"go_out":
			var who := w.person(main.selected)
			if who == null:
				return ""
			var parts: Array[String] = [str(who.uid)]
			for o in OutingSystem.options(w, who):
				parts.append("%s:%s" % [o["action"], o["why"]])
			return "|".join(parts)
		"stories":
			return "%s|%s|%s|%d" % [str(w.stories), str(w.box), _piece, w.money]
		"ledger":
			return "%s|%s" % [str(w.goals_done), str(w.collection)]
		"family":
			var parts: Array[String] = [str(w.pet_offer), str(w.proposals.size()), str(_changing), str(BirthSystem.blocked(w))]
			for p in w.people:
				if p.alive:
					parts.append("%d:%s:%s:%s:%d" % [p.uid, s.person_line(p, w), s.status_line(p, w), s.job_line(p), p.spouse])
				else:
					parts.append("%d:dead" % p.uid)
			for pet in w.pets:
				parts.append("p%d:%s:%s:%s" % [pet.uid, pet.state, str(pet.alive), s.pet_status(pet, w)])
			return "|".join(parts)
	return ""


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_root.visible = _kind != ""
	if _kind == "":
		return
	var s := session.strings
	var w := session.world
	var head := HBoxContainer.new()
	_box.add_child(head)
	var title := ViewWidgets.label(s.t("btn." + _kind))
	if _kind == "go_out" and w.person(main.selected) != null:
		title.text = s.t("title.go_out").replace("{name}", s.person_name(w.person(main.selected)))
	title.add_theme_font_size_override("font_size", 22)
	ViewWidgets.use_title_font(title)
	head.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	if _kind == "shop":
		var money := ViewWidgets.label(s.t("money").replace("{n}", str(w.money)))
		ViewWidgets.use_title_font(money)
		head.add_child(money)
	_button("btn.close", s.t("btn.close"), head)
	_card.custom_minimum_size.x = PANEL_WIDTH
	if _kind == "stories":
		_fill_box(w)
		return
	var tabs := _tabs()
	if not tabs.is_empty():
		# Tabs wrap onto a second line rather than widen the card.
		var row := HFlowContainer.new()
		row.custom_minimum_size.x = PANEL_WIDTH - 2.0 * MARGIN
		_box.add_child(row)
		row.add_theme_constant_override("h_separation", 5)
		row.add_theme_constant_override("v_separation", 5)
		for t in tabs:
			var tb := _button(t, _tab_name(t), row)
			ViewWidgets.small_button(tb)
			tb.custom_minimum_size.y = 30
			tb.disabled = (t == _tab)
			if t == _tab:
				# The open tab: the wood fill reads as "you are here", not as "can't".
				var on := ViewWidgets.chip_style(ViewWidgets.WOOD, ViewWidgets.INK)
				on.set_corner_radius_all(9)
				on.content_margin_left = 8
				on.content_margin_right = 8
				tb.add_theme_stylebox_override("disabled", on)
				tb.add_theme_color_override("font_disabled_color", ViewWidgets.CREAM)
	var scroll := ScrollContainer.new()
	# Two lines of tabs take a little of the list's height so the card stays the same size.
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 2.0 * MARGIN, BODY_HEIGHT - (40.0 if tabs.size() > 4 else 0.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if _kind == "shop" and _tab.begins_with(MARKET_TAB):
		_fill_market(list, w, _tab.substr(MARKET_TAB.length()))
		return
	match _tab if not _kind in ["family", "go_out"] else _kind:
		"go_out":
			_fill_go_out(list, w)
		"tab.inventory":
			_fill_inventory(list, w)
		"tab.goals":
			_fill_goals(list, w)
		"tab.collection":
			_fill_collection(list, w)
		"family":
			_fill_family(list, w)


## The goods tabs of the market, in order: {id "market:<section id>", sid, name, cats (the
## `group` headings of its entries), pets (animals for sale are here)}, one per section of
## the kernel's catalogue (`MarketSystem`). With a market in the pack every section is a tab,
## also while it is empty (the used-goods stall before its first stock); without one, the
## kinds of goods that have anything are.
func _market_tabs(w: World) -> Array[Dictionary]:
	var s := session.strings
	var cat := MarketSystem.catalogue(w)
	var by_id := {}
	for sec in cat:
		by_id[sec.id] = sec
	var secs: Array = MarketSystem.sections(w.pack) if MarketSystem.enabled(w.pack) else cat
	var out: Array[Dictionary] = []
	for sec in secs:
		var entries: Array = by_id.get(sec.id, {}).get("entries", [])
		var cats: Array = []
		var pets := false
		for e in entries:
			if not str(e.group) in cats:
				cats.append(str(e.group))
			if e.kind == "pet":
				pets = true
		var name := str(sec.name)
		if not MarketSystem.enabled(w.pack) and s.has("market.plain." + name):
			name = s.t("market.plain." + name)
		out.append({"id": MARKET_TAB + str(sec.id), "sid": str(sec.id), "name": name, "cats": cats, "pets": pets})
	return out


## The tab id `alias` ("tab.items", "tab.pets") stands for.
func _market_tab_for(alias: String) -> String:
	for t in _market_tabs(session.world):
		if alias == "tab.items" and not (t["cats"] as Array).is_empty():
			return t["id"]
		if alias == "tab.pets" and t["pets"]:
			return t["id"]
	return alias


func _tab_name(id: String) -> String:
	if id.begins_with(MARKET_TAB):
		for t in _market_tabs(session.world):
			if t["id"] == id:
				return str(t["name"])
		return id
	return session.strings.t(id)


## One market section from the kernel's catalogue: its entries under their `group` headings,
## each a row of name, a note (who wants it, why it cannot be had, the new price of used goods),
## price and a button. The services section starts with what is waiting on the player; an
## empty section says the goods have not come in yet.
func _fill_market(list: VBoxContainer, w: World, sid: String) -> void:
	var s := session.strings
	var section := {}
	for sec in MarketSystem.catalogue(w):
		if sec.id == sid:
			section = sec
	var entries: Array = section.get("entries", [])
	if sid == str(MarketSystem.secondhand_cfg(w.pack).get("section", "")):
		var left := MarketSystem.secondhand_refresh_at(w) - w.now
		list.add_child(_note(s.t("shop.restock").replace("{t}", _span(left))))
	if entries.any(func(e): return e.kind == "service"):
		_fill_service_news(list, w)
	if entries.is_empty():
		var none := ViewWidgets.wrapped(s.t("market.empty"))
		none.add_theme_color_override("font_color", ViewWidgets.MUTED)
		list.add_child(none)
		return
	var groups := {}
	for e in entries:
		groups[str(e.group)] = true
	var group := ""
	for e in entries:
		if str(e.group) != group:
			group = str(e.group)
			if group != "" and groups.size() > 1:
				var head := ViewWidgets.wrapped(group)
				ViewWidgets.use_title_font(head)
				head.add_theme_color_override("font_color", ViewWidgets.WOOD)
				list.add_child(head)
		var row := ViewWidgets.row(list)
		var name := ViewWidgets.name_label(str(e.name))
		row.add_child(name)
		var note := _entry_note(w, e)
		if note != "":
			var mark := ViewWidgets.price_label(note)
			mark.add_theme_color_override("font_color", ViewWidgets.ACCENT if str(e.why) == "" else ViewWidgets.MUTED)
			row.add_child(mark)
		row.add_child(ViewWidgets.price_label(s.t("money").replace("{n}", str(int(e.price)))))
		var b := _button(_entry_button(e), s.t(_entry_label(e)), row)
		b.disabled = str(e.why) != ""
		if str(e.why) == "no_money":
			b.text = s.t("error.no_money")
		if str(e.get("desc", "")) != "":
			list.add_child(_note("　" + str(e.desc)))


## The id of the button that buys a catalogue entry.
static func _entry_button(e: Dictionary) -> String:
	match str(e.kind):
		"item":
			return "buy:" + str(e.id)
		"object":
			return "place:" + str(e.id)
		"room":
			return "build:" + str(e.id)
		"pet":
			return "buy_pet:" + str(e.id)
		"service":
			return "service:" + str(e.id)
	return "used:%d" % int(e.id)


static func _entry_label(e: Dictionary) -> String:
	match str(e.kind):
		"object":
			return "btn.place"
		"room":
			return "btn.build"
		"pet":
			return "btn.buy_pet"
	return "btn.buy"


## The small note beside an entry: why it cannot be had (not for want of money), who wishes
## for it, or what used goods cost new.
func _entry_note(w: World, e: Dictionary) -> String:
	var s := session.strings
	var why := str(e.why)
	if why != "" and why != "no_money":
		var thing := ""
		if why == "no_perch":
			thing = str(w.pack.object_types.get(str(w.pack.pets[e.id].get("perch", "")), {}).get("name", ""))
		elif why == "needs_object":
			thing = str(w.pack.object_types.get(str(w.pack.services[e.id]["requires"].get("object", "")), {}).get("name", ""))
		return s.t("shop.why." + why).replace("{thing}", thing)
	var wanted := ""
	match str(e.kind):
		"item":
			wanted = _wanted_by(w, str(e.id))
		"pet":
			wanted = _pet_wanted_by(w, str(e.id))
		"object", "room":
			wanted = _place_wanted_by(w, str(e.kind), str(e.id))
		"secondhand":
			if str(e.of) == "item":
				wanted = _wanted_by(w, str(e.ref))
			if wanted == "":
				return s.t("shop.full_price").replace("{n}", s.t("money").replace("{n}", str(int(e.full_price))))
	if wanted != "":
		return s.t("shop.wanted").replace("{name}", wanted)
	return ""


## What is waiting on the player among the services: lottery tickets, a hired hand's days
## left and a faster clock's time left. (People on offer get the adoption picker.)
func _fill_service_news(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	for t in w.tickets:
		if int(t.amount) < 0:
			list.add_child(_note(s.t("shop.ticket_wait").replace("{n}", str(int(t.id))).replace("{t}", _span(int(t.draw_at) - w.now))))
		else:
			var row := ViewWidgets.row(list)
			row.add_child(ViewWidgets.name_label(s.t("shop.ticket_drawn").replace("{n}", str(int(t.id)))))
			_button("ticket:%d" % int(t.id), s.t("btn.open_ticket"), row)
	if w.helper_until > w.now:
		list.add_child(_note(s.t("shop.helper").replace("{t}", _span(w.helper_until - w.now))))
	var fast := w.speed_until - int(ServiceSystem.real_now(w))
	if fast > 0:
		list.add_child(_note(s.t("shop.speed").replace("{t}", _span(fast))))


## The names of the living people who wish for that piece of furniture or that room.
func _place_wanted_by(w: World, kind: String, id: String) -> String:
	var names: Array[String] = []
	for p in w.people:
		if not p.alive:
			continue
		var wish := WishSystem.current(w, p)
		if str(wish.get("kind", "")) == kind and str(wish.get(kind, "")) == id:
			names.append(session.strings.person_name(p))
	return "、".join(names)


## A span of seconds in the largest whole unit that fits: days, hours or minutes (at least 1).
func _span(seconds: int) -> String:
	var s := session.strings
	if seconds >= 86400:
		return s.t("time.days").replace("{n}", str(seconds / 86400))
	if seconds >= 3600:
		return s.t("time.hours").replace("{n}", str(seconds / 3600))
	return s.t("time.minutes").replace("{n}", str(maxi(1, seconds / 60)))


func _note(text: String) -> Label:
	var l := ViewWidgets.wrapped(text)
	l.add_theme_color_override("font_color", ViewWidgets.MUTED)
	return l


## The names of the living people who wish for an animal of this kind, joined.
func _pet_wanted_by(w: World, kind: String) -> String:
	var names: Array[String] = []
	for p in w.people:
		if not p.alive:
			continue
		var wish := WishSystem.current(w, p)
		if str(wish.get("kind", "")) == "pet" and str(wish.get("pet", "")) == kind:
			names.append(session.strings.person_name(p))
	return "、".join(names)


## The names of the living people whose wish is this item, joined; "" for nobody.
func _wanted_by(w: World, item: String) -> String:
	var names: Array[String] = []
	for p in w.people:
		if not p.alive:
			continue
		var wish := WishSystem.current(w, p)
		if str(wish.get("kind", "")) == "item" and str(wish.get("item", "")) == item:
			names.append(session.strings.person_name(p))
	return "、".join(names)


## The keepsake box: the cabinet (`_box_shelves`) under a line that offers to sell the
## extras, or the card of the thing picked in it.
func _fill_box(w: World) -> void:
	var s := session.strings
	if _piece != "":
		_fill_piece(w)
		return
	var top := ViewWidgets.row(_box)
	var empty := w.stories.is_empty() and w.box.is_empty()
	var hint := ViewWidgets.wrapped(s.t("stories.none") if empty else s.t("box.hint"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_color_override("font_color", ViewWidgets.MUTED)
	top.add_child(hint)
	var extra := CollectibleSystem.extras_value(w) if CollectibleSystem.keeps(w.pack) else 0
	if extra > 0:
		var b := _button("sell_extras", s.t("box.sell_extras").replace("{money}", s.t("money").replace("{n}", str(extra))), top)
		ViewWidgets.small_button(b)
		b.custom_minimum_size.y = 30
	var cab := CabinetView.new()
	cab.setup(_box_shelves(w), _skin(), func(id: String, parent: Control) -> Button:
		var btn := Button.new()
		btn.pressed.connect(press.bind(id))
		parent.add_child(btn)
		_buttons[id] = btn
		return btn)
	_card.custom_minimum_size.x = maxf(PANEL_WIDTH, cab.custom_minimum_size.x + 2.0 * MARGIN + 12.0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(cab.custom_minimum_size.x + 12.0, minf(cab.custom_minimum_size.y, BOX_HEIGHT))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	scroll.add_child(cab)


func _skin() -> PackSkin:
	return main.house.skin if main != null and main.house != null else null


## The shelves of the box: one per story that has come to light (its fragments in order),
## then the things picked up, `CabinetView.COLUMNS` to a shelf (a story's keepsake only once
## it is in).
func _box_shelves(w: World) -> Array:
	var s := session.strings
	var skin := _skin()
	var out: Array = []
	for sid in w.pack.stories:
		if not w.stories.has(sid):
			continue
		var found: Array = w.stories[sid]["found"]
		var slots: Array = []
		for f in w.pack.stories[sid]["fragments"]:
			var fid := str(f["id"])
			slots.append({"id": "frag:%s:%s" % [sid, fid], "found": found.has(fid),
				"tex": skin.piece(fid) if skin != null and found.has(fid) else null})
		var progress := "%d / %d" % [found.size(), slots.size()]
		if str(w.stories[sid]["stage"]) == "done":
			progress += " ✓"
		out.append({"title": s.story_title(sid, w) if not found.is_empty() else "", "progress": progress, "slots": slots})
	var keep := CollectibleSystem.keeps(w.pack)
	var curios: Array = []
	var have := 0
	for k in w.pack.collectibles:
		var n := int(w.box.get(k, 0)) if keep else mini(1, int(w.collection.get(k, 0)))
		if bool(w.pack.collectibles[k]["keepsake"]) and n <= 0:
			continue
		if n > 0:
			have += 1
		curios.append({"id": "curio:" + str(k), "found": n > 0, "count": n,
			"tex": skin.collectible_sprite(str(k)) if skin != null and n > 0 else null})
	var total := curios.size()
	var first := true
	while not curios.is_empty():
		out.append({"title": s.t("box.curios") if first else "",
			"progress": "%d / %d" % [have, total] if first else "", "slots": curios.slice(0, CabinetView.COLUMNS)})
		curios = curios.slice(CabinetView.COLUMNS)
		first = false
	return out


## The card of one thing in the box: its picture large, its name and words; for a thing
## picked up, how many are kept and what one fetches, with the buttons that sell extras.
func _fill_piece(w: World) -> void:
	var s := session.strings
	var skin := _skin()
	var parts := _piece.split(":")
	var tex: Texture2D = null
	var name := ""
	var text := ""
	var kind := ""
	if parts[0] == "frag" and parts.size() == 3 and (w.stories.get(parts[1], {}).get("found", []) as Array).has(parts[2]):
		var f := StorySystem.fragment(w.pack, parts[1], parts[2])
		tex = skin.piece(parts[2]) if skin != null else null
		name = str(f.get("name", ""))
		text = str(f.get("text", ""))
	elif parts[0] == "curio" and parts.size() == 2 and w.pack.collectibles.has(parts[1]):
		kind = parts[1]
		tex = skin.collectible_sprite(kind) if skin != null else null
		name = str(w.pack.collectibles[kind]["name"])
	else:
		_piece = ""
		_fill_box(w)
		return
	var side := HBoxContainer.new()
	side.add_theme_constant_override("separation", 18)
	_box.add_child(side)
	side.add_child(piece_picture(tex, Vector2(220, 220)))
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 300
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_child(col)
	var head := ViewWidgets.wrapped(name)
	head.add_theme_font_size_override("font_size", 20)
	ViewWidgets.use_title_font(head)
	col.add_child(head)
	if kind == "":
		col.add_child(_note("「%s」" % s.story_title(parts[1], w)))
		col.add_child(ViewWidgets.wrapped(text))
	var row := ViewWidgets.row(_box)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if kind != "":
		var c: Dictionary = w.pack.collectibles[kind]
		var keep := CollectibleSystem.keeps(w.pack)
		var n := int(w.box.get(kind, 0)) if keep else mini(1, int(w.collection.get(kind, 0)))
		col.add_child(ViewWidgets.wrapped(s.t("box.count").replace("{n}", str(n))))
		if bool(c["keepsake"]):
			col.add_child(_note(s.t("error.keepsake")))
		elif keep:
			var price := s.t("money").replace("{n}", str(int(c["value"])))
			col.add_child(_note(s.t("box.price").replace("{money}", price)))
			var extra := CollectibleSystem.extras(w, kind)
			_button("sell_one:" + kind, s.t("box.sell_one").replace("{money}", price), row).disabled = extra < 1
			if extra > 1:
				_button("sell_all:" + kind, s.t("box.sell_all").replace("{n}", str(extra)).replace("{money}",
					s.t("money").replace("{n}", str(extra * int(c["value"])))), row)
	_button("btn.back", s.t("btn.back"), row)


## A thing's picture at `size` (aspect kept), or the wrapped bundle while it has none.
static func piece_picture(tex: Texture2D, size: Vector2) -> Control:
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = size
		return r
	var c := Control.new()
	c.custom_minimum_size = size
	c.draw.connect(func(): CabinetView.bundle(c, Rect2(Vector2.ZERO, c.size)))
	return c


## After a sale (its toast comes with the event): the panel shows what is left.
func _sold(_r: Dictionary) -> void:
	refresh()


func _fill_inventory(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var total := 0
	for k in w.stock:
		total += int(w.stock[k])
	list.add_child(ViewWidgets.wrapped(s.t("stock").replace("{n}", str(total))))
	var sel := w.person(main.selected)
	var who := s.person_name(sel) if sel != null and sel.alive else ""
	var pet := PetSystem.find(w, main.selected_pet) if main.selected_pet >= 0 else null
	if pet != null and pet.home():
		who = pet.given
	for id in w.pack.items:
		var count := int(w.inventory.get(id, 0))
		if count <= 0:
			continue
		var row := ViewWidgets.row(list)
		row.add_child(ViewWidgets.name_label("%s × %d" % [str(w.pack.items[id]["name"]), count]))
		var for_pet := not (w.pack.items[id].get("pet", {}) as Dictionary).is_empty()
		var fits := who != "" and for_pet == (pet != null and pet.home())
		_button("use:" + id, s.t("btn.use_on").replace("{name}", who), row).disabled = not fits


func _fill_goals(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var open_ids: Array = []
	var done_ids: Array = []
	for id in w.pack.goals:
		(done_ids if id in w.goals_done else open_ids).append(id)
	for id in open_ids + done_ids:
		var g: Dictionary = w.pack.goals[id]
		var mark := DONE_MARK if id in done_ids else ""
		list.add_child(ViewWidgets.wrapped("%s%s（%s）" % [mark, str(g["text"]), s.t("money").replace("{n}", str(int(g.get("reward", 0))))]))


func _fill_collection(list: VBoxContainer, w: World) -> void:
	for id in w.pack.collectibles:
		list.add_child(ViewWidgets.name_label(str(w.pack.collectibles[id]["name"]) if w.collection.has(id) else UNKNOWN))


func _fill_family(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var who := w.person(_changing)
	if who != null and who.alive:
		_fill_change(list, w, who)
		return
	_changing = -1
	if not w.proposals.is_empty():
		_button("proposal", s.t("title.proposal"), list)
	if not w.pet_offer.is_empty():
		_button("stray", s.t("title.stray"), list)
	if BirthSystem.blocked(w):
		var hint := ViewWidgets.wrapped(s.t("hint.no_bed"))
		hint.add_theme_color_override("font_color", ViewWidgets.ACCENT)
		list.add_child(hint)
	# With births the household spans generations: one heading per generation, the dead
	# greyed out among them. Without births, the living as one list.
	var lineage := BirthSystem.enabled(w.pack)
	var by_gen := {}
	for p in w.people:
		if p.alive or lineage:
			var g := s.shown_generation(p, w) if lineage else 0
			if not by_gen.has(g):
				by_gen[g] = []
			by_gen[g].append(p)
	var gens := by_gen.keys()
	gens.sort()
	for g in gens:
		if lineage:
			var head := ViewWidgets.wrapped(s.generation_label(int(g)))
			head.add_theme_font_size_override("font_size", 17)
			list.add_child(head)
		for p in by_gen[g]:
			if p.alive:
				_family_row(list, w, p, lineage)
			else:
				var dead := ViewWidgets.wrapped("%s  %s" % [s.person_name(p), s.t("family.dead").replace("{n}", str(int(p.age)))])
				dead.modulate = Color(1, 1, 1, 0.45)
				list.add_child(dead)
	_fill_family_pets(list, w)


## The animals: the ones at home as buttons (picking one shows it in the bar), the ones that
## ran off, died or never came back greyed out, as the household's record.
func _fill_family_pets(list: VBoxContainer, w: World) -> void:
	if w.pets.is_empty():
		return
	var s := session.strings
	var head := ViewWidgets.wrapped(s.t("family.pets"))
	head.add_theme_font_size_override("font_size", 17)
	list.add_child(head)
	for pet in w.pets:
		if pet.home():
			var b := _button("pet:%d" % pet.uid, "%s  %s  %s" % [s.pet_name(pet, w), s.pet_line(pet, w), s.pet_status(pet, w)], list)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else:
			var gone := ViewWidgets.wrapped(s.pet_record(pet, w))
			gone.modulate = Color(1, 1, 1, 0.45)
			list.add_child(gone)


## One living person in the family panel: their button, then livelihood (or "too young") and,
## with births, whom they married and whose child they are.
func _family_row(list: VBoxContainer, w: World, p: Person, lineage: bool) -> void:
	var s := session.strings
	var b := _button("person:%d" % p.uid, "%s  %s  %s" % [s.person_name(p), s.person_line(p, w), s.status_line(p, w)], list)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var row := ViewWidgets.row(list)
	if p.stage(w.pack) in ["adult", "elder"]:
		row.add_child(ViewWidgets.name_label("    " + s.job_line(p)))
		_button("change:%d" % p.uid, s.t("btn.change_track"), row)
	else:
		row.add_child(ViewWidgets.name_label("    " + s.t("family.child")))
	if not lineage:
		return
	var ties: Array[String] = []
	var mother := w.person(p.mother)
	var father := w.person(p.father)
	if mother != null and father != null:
		ties.append(s.t("family.parents").format({"father": s.person_name(father), "mother": s.person_name(mother)}))
	var spouse := w.person(p.spouse)
	if spouse != null:
		ties.append(s.t("family.spouse").replace("{name}", s.person_name(spouse)))
	if not ties.is_empty():
		var l := ViewWidgets.wrapped("    " + "　".join(ties))
		l.modulate = Color(1, 1, 1, 0.75)
		list.add_child(l)


## The livelihoods `p` could change to, with what each starts at; picking one changes it.
func _fill_change(list: VBoxContainer, w: World, p: Person) -> void:
	var s := session.strings
	list.add_child(ViewWidgets.wrapped(s.t("title.change_track").replace("{name}", s.person_name(p))))
	list.add_child(ViewWidgets.wrapped(s.t("change.note")))
	for t in w.pack.livelihoods:
		if t == p.track:
			continue
		var job: Dictionary = w.pack.livelihoods[t]
		var first: Dictionary = (job["levels"] as Array)[0]
		var text := s.t("change.option").format({"job": str(job["name"]), "level": str(first["name"]),
			"money": s.t("money").replace("{n}", str(int(first["daily_income"])))})
		var b := _button("track:" + str(t), text, list)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button("change.cancel", s.t("btn.cancel"), list)


## Every label that sits in a row beside other widgets; for layout tests.
func row_labels() -> Array[Label]:
	var out: Array[Label] = []
	_row_labels(_box, out)
	return out


func _row_labels(n: Node, out: Array[Label]) -> void:
	for c in n.get_children():
		if c is Label and n is HBoxContainer:
			out.append(c)
		_row_labels(c, out)


## The card's minimum size as the layout computes it; for layout tests.
func card_size() -> Vector2:
	return _card.get_combined_minimum_size()


func _button(id: String, label: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(press.bind(id))
	parent.add_child(b)
	_buttons[id] = b
	return b


## Where the selected person could go: the outings (away for a few hours, back with
## something) first, then the places outside the wall; one that cannot be done now is
## greyed with the reason.
func _fill_go_out(list: VBoxContainer, w: World) -> void:
	var s := session.strings
	var p := w.person(main.selected)
	if p == null:
		return
	var all := OutingSystem.options(w, p)
	var opts := all.filter(func(o): return o["outing"]) + all.filter(func(o): return not o["outing"])
	if opts.is_empty():
		var none := ViewWidgets.wrapped(s.t("go_out.none"))
		none.add_theme_color_override("font_color", ViewWidgets.MUTED)
		list.add_child(none)
	for o in opts:
		var row := ViewWidgets.row(list)
		row.add_child(ViewWidgets.name_label(str(o["label"])))
		if o["outing"]:
			var note := ViewWidgets.price_label(s.t("go_out.away"))
			note.add_theme_color_override("font_color", ViewWidgets.WOOD)
			row.add_child(note)
		var go := _button("go:" + str(o["action"]), s.t("btn.go_out"), row)
		if str(o["why"]) != "":
			go.disabled = true
			go.text = s.error(str(o["why"]))
