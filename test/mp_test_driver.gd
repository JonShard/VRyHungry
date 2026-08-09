extends Node

## Multiplayer debug harness for the kitchen flow, living in
## test/multiPlayerTest.tscn.
##
## Two ways to use it:
##
## AUTOMATIC — pass `--mptest` and the server runs the whole scripted sequence
## and exits non-zero if any check fails. test/run_mp_test.ps1 does this
## headlessly; test/run_mp_test_windowed.ps1 does it in two visible windows with
## a pause between steps so you can watch it happen.
##
## MANUAL — just run the scene (no `--mptest`). Every window gets an on-screen
## overlay, a fixed camera over the kitchen, and keyboard controls:
##
##   H / J   host  /  join 127.0.0.1
##   1       grab the plate            2   drop it
##   3       plate -> dirt station     4   plate -> sink
##   5       raw burger -> hob         6   cooked burger -> counter
##   7       buns -> cooked burger (combine)
##   8       plate -> counter 2        9   hamburger -> plate
##   R       run the whole automatic sequence (server only)
##   0       dump state    C  toggle camera
##
## Keys act on the peer whose window has focus, so you can do a step on the
## client and watch the server window follow (or fail to).
##
## The scripted sequence:
##   1. client grabs the plate, then drops it
##   2. server grabs the plate, then drops it
##   3. client carries it to the dirt station -> snaps + turns dirty on both
##   4. both peers confirm they can still pick it up
##   5. client carries the dirty plate to the sink -> gets washed clean on both
##   6. a cook-and-plate round, run once by the CLIENT and once by the SERVER:
##      raw burger -> hob (cooks into a cooked burger, raw one removed),
##      cooked burger -> counter, buns -> cooked burger (combines into a
##      hamburger), plate -> counter 2, hamburger -> plate.

## How long the server waits for a client step reply before calling it failed.
const STEP_TIMEOUT_SEC := 30.0
## How long to wait for the client to connect and for the plate to replicate.
const SETUP_TIMEOUT_SEC := 30.0
## Distance under which an item counts as "at" a snap zone.
const SNAP_TOLERANCE := 0.12
## Cooking and washing both take ~3s of station time; allow generously for it.
const STATION_WORK_TIMEOUT := 20.0
## Lines kept in the on-screen overlay. Enough to show a whole step, without the
## panel eating the view of the kitchen underneath it.
const OVERLAY_LINES := 11

## Where the debug camera sits and what it aims at: a fixed vantage point that
## frames the whole kitchen (Counter2 at x=-2 through DirtStation at x=2).
const DEBUG_CAM_POS := Vector3(0.0, 2.1, 3.4)
const DEBUG_CAM_LOOK_AT := Vector3(0.0, 0.9, 0.0)

const HELP := "[H]ost [J]oin 1 grab 2 drop 3 dirt 4 sink 5 hob 6 counter 7 combine 8 plate>counter2 9 >plate  R run-all  A sync-audit  0 dump  C cam"

var _log_file: FileAccess
var _log_path := ""
var _debug_cam: Camera3D
var _role := "?"
var _client_id := 0
var _auto_mode := false
var _running := false
var _step_pause := 0.0
var _end_hold := 0.0
var _step_no := 0

# Server-side ledger of every check: {step, side, ok, detail}
var _results: Array[Dictionary] = []
# Latest reply from the client, consumed by _remote().
var _reply: Dictionary = {}

var _world: Node3D
var _controller: Node3D
var _hand: XRToolsFunctionPickup
var _hand_detached := false

var _overlay: Label
var _overlay_lines: Array[String] = []

# Per-step screenshots, later stitched into a side-by-side GIF of both peers.
var _frames_enabled := false
var _frames_dir := ""
var _frame_index := 0


func _ready() -> void:
	var args := OS.get_cmdline_args()
	_auto_mode = "--mptest" in args
	# Opt-in only. This node also sits in the real multiplayer scene (so a client
	# joining a test session has a driver), and must be completely inert during
	# an ordinary game — no overlay, no debug camera, no keyboard hooks.
	if not _auto_mode and not ("--mptest-manual" in args):
		queue_free()
		return
	_frames_enabled = "--mptest-frames" in args
	_step_pause = _arg_value(args, "--mptest-pause", 0.0)
	_end_hold = _arg_value(args, "--mptest-hold", 0.0)
	_world = get_parent()
	_open_log()
	_build_overlay()
	await get_tree().process_frame
	_refresh_role()
	_log("=== mp test driver ready (role=%s, peer=%d, mode=%s) ==="
		% [_role, multiplayer.get_unique_id(), "automatic" if _auto_mode else "manual"])
	# await: _resolve_nodes now waits for the server's spawns to arrive.
	if not await _resolve_nodes():
		if _auto_mode:
			_finish(false)
		return
	_build_debug_camera()
	_setup_frames()
	if not _auto_mode:
		_log("MANUAL MODE - keys act on this window's peer:")
		_log("  " + HELP)
		return
	if _role == "server":
		await _run_server()


func _arg_value(args: PackedStringArray, key: String, fallback: float) -> float:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1].to_float()
	return fallback


func _refresh_role() -> void:
	_role = "server" if NetworkManager.is_server() else ("client" if NetworkManager.is_online() else "offline")


# Only the hand is resolved up front. Everything else is looked up by name at
# use time, because items get consumed and respawned as the test runs (the raw
# burger becomes a cooked burger, which becomes a hamburger, which is absorbed
# into a plate) — caching node references would leave us holding freed objects.
func _resolve_nodes() -> bool:
	_controller = _world.get_node_or_null("XROrigin3D/XRControllerRightHand") as Node3D
	_hand = _controller.get_node_or_null("FunctionPickup") as XRToolsFunctionPickup if _controller else null
	if not _hand:
		_log("FATAL: could not resolve XROrigin3D/XRControllerRightHand/FunctionPickup")
		return false
	# The kitchen is no longer baked into the live scene: the server harvests the
	# authored nodes and respawns them replicated, so on a client nothing exists
	# until those spawns arrive. Wait for them rather than failing immediately.
	for required in ["Hob", "Sink", "DirtStation", "Counter", "Counter2", "Plate"]:
		if not await _wait_until(func(): return _find(required) != null,
				"'%s' to arrive from the server" % required, SETUP_TIMEOUT_SEC):
			_log("FATAL: '%s' never appeared in the world" % required)
			return false
	_log("resolved hand=%s; kitchen has Hob, Sink, DirtStation, Counter, Counter2" % _hand.get_path())
	_disable_despawn_timers()
	return true


# The test deliberately leaves items sitting still for minutes at a time, which
# DespawningItem would treat as litter and remove (it took the raw burger out
# before the client had even connected). Hold them indefinitely instead, so the
# run tests the kitchen rather than the despawn timer.
func _disable_despawn_timers() -> void:
	var stopped := 0
	for node in _world.find_children("*", "DespawningItem", true, false):
		if _despawn_timers_seen.has(node.get_instance_id()):
			continue
		_despawn_timers_seen[node.get_instance_id()] = true
		node.set_process(false)
		stopped += 1
	if stopped > 0:
		_log("disabled %d DespawningItem timer(s) so test items don't vanish mid-run" % stopped)


# Items appear as the run goes on (cooking and combining spawn new ones), so
# this is re-checked before every step rather than only at startup.
var _despawn_timers_seen := {}


# Items live either baked in the scene root or, once spawned at runtime, under
# WorldContent. Look in both.
func _find(node_name: String) -> Node3D:
	var n := _world.get_node_or_null(node_name)
	if not n:
		n = _world.get_node_or_null("WorldContent/" + node_name)
	return n as Node3D


func _zone_of(station_name: String) -> XRToolsSnapZone:
	var s := _find(station_name)
	return s.get_node_or_null("XRToolsSnapZone") as XRToolsSnapZone if s else null


# Cooking and combining spawn their results with engine-assigned names, so the
# only stable way to find them is by the food id they carry.
func _find_by_food_id(id: String) -> Node3D:
	for root in [_world, _world.get_node_or_null("WorldContent")]:
		if not root:
			continue
		for child in root.get_children():
			var f := child.get_node_or_null("FoodItem") as FoodItem
			if f and f.id == id and is_instance_valid(child):
				return child as Node3D
	return null


# --- Server orchestration --------------------------------------------------

func _run_server() -> void:
	_running = true
	_results.clear()
	_step_no = 0
	if not await _wait_for_client():
		_running = false
		if _auto_mode:
			_finish(false)
		return
	await _wait_frames(60)
	_banner("starting sequence")
	# A frame of the untouched kitchen, so the GIF opens on the starting state.
	await _capture_step_frame("start")

	# 0. The client opened a different, empty scene, so everything it has must
	# have arrived over the network. Check that before touching anything — this
	# is the same path a player joining mid-session takes.
	await _step("server", "world_replicated_to_client", "verify_world_replicated", [])

	# 1-2. Both peers can pick the plate up and put it down.
	await _step("client", "client_grab_plate", "grab", ["Plate"])
	await _step("client", "client_drop_plate", "drop", ["Plate"])
	await _step("server", "server_grab_plate", "grab", ["Plate"])
	await _step("server", "server_drop_plate", "drop", ["Plate"])

	# 3. Client carries it to the dirt station; it should snap in and go dirty.
	await _step("client", "client_plate_to_dirt", "place_in_zone", ["Plate", "DirtStation"])
	await _both("plate_snapped_and_dirty", "verify_snapped", ["Plate", "DirtStation"])
	await _both("plate_is_dirty", "verify_dirty", ["Plate", "true"])

	# 4. Both peers can still pick it back up out of the station.
	await _step("client", "client_regrab_plate", "grab", ["Plate"])
	await _step("client", "client_redrop_plate", "drop", ["Plate"])
	await _step("server", "server_regrab_plate", "grab", ["Plate"])
	await _step("server", "server_redrop_plate", "drop", ["Plate"])

	# 5. Client takes the dirty plate to the sink, which should wash it clean.
	await _step("client", "client_plate_to_sink", "place_in_zone", ["Plate", "Sink"])
	await _both("plate_snapped_in_sink", "verify_snapped", ["Plate", "Sink"])
	await _both("sink_bar_shown_while_washing", "verify_station_bar", ["Sink", "true"])
	await _step("server", "wait_for_wash", "await_clean", ["Plate"])
	await _both("plate_washed_clean", "verify_dirty", ["Plate", "false"])
	await _both("sink_bar_hidden_when_done", "verify_station_bar", ["Sink", "false"])

	# 6. The cook-and-plate round, once per peer. The first round uses the items
	# baked into the scene; the second uses freshly spawned ones, so both paths
	# through the spawner get covered.
	# Finished plates are parked well clear of every snap zone (all the stations
	# sit on z=0), so they can't get re-snapped on the way down.
	await _cook_and_plate_round("client", "raw_burger", "BurgerBuns", "Plate", Vector3(-2.0, 1.1, 1.5))
	await _spawn_round_items()
	await _cook_and_plate_round("server", "RawBurger2", "BurgerBuns2", "Plate2", Vector3(-1.0, 1.1, 1.5))

	_running = false
	await _report()


# One full food round performed by `actor`: cook a burger, combine it with buns
# on the counter, and put the result on a plate that's sitting on another
# counter. Every result is checked on BOTH peers, since the whole point is that
# the server's authoritative outcome reaches the client.
func _cook_and_plate_round(actor: String, burger: String, buns: String, plate: String, park_at: Vector3) -> void:
	_banner("%s's cook-and-plate round (%s + %s -> %s)" % [actor, burger, buns, plate])

	# Burger onto the hob; it should cook and the raw one should disappear.
	await _step(actor, "%s_burger_to_hob" % actor, "place_in_zone", [burger, "Hob"])
	await _both("%s_burger_snapped_in_hob" % actor, "verify_snapped", [burger, "Hob"])
	await _both("%s_hob_bar_shown_while_cooking" % actor, "verify_station_bar", ["Hob", "true"])
	await _step("server", "%s_wait_for_cook" % actor, "await_food", ["cooked_burger"])

	# Get it off the hob before anything else: the hob keeps cooking whatever is
	# in it, and a cooked burger left there burns to charcoal in another 2s —
	# which would blow up the run as soon as there's any pause between steps.
	await _step(actor, "%s_cooked_to_counter" % actor, "place_food_in_zone", ["cooked_burger", "Counter"])
	await _both("%s_raw_burger_removed" % actor, "verify_gone", [burger])
	await _both("%s_cooked_burger_exists" % actor, "verify_food_exists", ["cooked_burger"])
	await _both("%s_hob_bar_hidden_when_empty" % actor, "verify_station_bar", ["Hob", "false"])

	# Now bring the buns to it to combine.
	await _step(actor, "%s_buns_to_cooked" % actor, "carry_food_to_food", [buns, "cooked_burger"])
	await _step("server", "%s_wait_for_combine" % actor, "await_food", ["hamburger"])
	await _both("%s_ingredients_consumed" % actor, "verify_gone", [buns])
	await _both("%s_hamburger_exists" % actor, "verify_food_exists", ["hamburger"])

	# Plate onto the second counter, then the hamburger onto the plate.
	await _step(actor, "%s_plate_to_counter2" % actor, "place_in_zone", [plate, "Counter2"])
	await _both("%s_plate_snapped_on_counter2" % actor, "verify_snapped", [plate, "Counter2"])
	await _step(actor, "%s_hamburger_to_plate" % actor, "carry_food_to_item", ["hamburger", plate])
	await _both("%s_plate_holds_hamburger" % actor, "verify_plate_contains", [plate, "hamburger"])

	# Take the finished plate away again, the way a player would carry it off to
	# be served. Without this the counter stays occupied and the next round has
	# nowhere to put its plate.
	await _both("%s_food_on_plate_before_lift" % actor, "verify_plate_visuals", [plate])
	await _step(actor, "%s_plate_off_counter2" % actor, "park", [plate, park_at])
	await _both("%s_counter2_freed" % actor, "verify_zone_empty", ["Counter2"])
	# The food must still be on the plate after it has been carried off the
	# counter and set down again.
	await _both("%s_food_stayed_on_plate" % actor, "verify_plate_visuals", [plate])


# Spawn a second set of ingredients through NetworkManager for the server's
# round (the scene only bakes one of each).
func _spawn_round_items() -> void:
	_banner("state between rounds (server's view)")
	_dump_state()
	_banner("spawning a second set of ingredients for the server's round")
	var spawns := [
		["res://Items/burger.tscn", "RawBurger2", Vector3(0.3, 1.05, 0.7)],
		["res://Items/BurgerBuns.tscn", "BurgerBuns2", Vector3(-0.4, 1.05, 0.7)],
		["res://Containers/plate.tscn", "Plate2", Vector3(1.4, 1.05, 0.7)],
	]
	for s in spawns:
		NetworkManager.spawn_item(s[0], Transform3D(Basis(), s[2]), s[1])
		_log("  spawned %s" % s[1])
	await _wait_frames(30)


func _wait_for_client() -> bool:
	var ok := await _wait_until(func(): return _find_client_id() != 0, "client to connect", SETUP_TIMEOUT_SEC)
	_client_id = _find_client_id()
	if ok:
		_log("client connected: peer %d" % _client_id)
	return ok


func _find_client_id() -> int:
	for id in multiplayer.get_peers():
		if id != 1:
			return id
	return 0


# Run one step as `actor` (locally if that's us, over RPC if it's the client)
# and record the verdict.
func _step(actor: String, label: String, step: String, args: Array) -> void:
	_current_step = label
	_disable_despawn_timers()
	_banner("STEP %d: %s  (on the %s)" % [_next_step_no(), label, actor.to_upper()])
	var res: Dictionary
	if actor == "server":
		res = await _run_local_step(step, args)
	else:
		res = await _remote(step, args)
	_record(label, actor, res)
	await _audit_sync(label)
	await _capture_step_frame(label)
	await _pause()


# Run the same check on both peers - the server's state and the client's must
# agree, which is the whole point of the exercise.
func _both(label: String, step: String, args: Array) -> void:
	_current_step = label
	_disable_despawn_timers()
	_banner("STEP %d: %s  (checked on BOTH peers)" % [_next_step_no(), label])
	_record(label, "server", await _run_local_step(step, args))
	_record(label, "client", await _remote(step, args))
	await _audit_sync(label)
	await _capture_step_frame(label)
	await _pause()


func _remote(step: String, args: Array) -> Dictionary:
	_reply = {}
	_cmd.rpc_id(_client_id, step, args)
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	while _reply.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if _reply.is_empty():
		return {"ok": false, "detail": "no reply from client within %.0fs" % STEP_TIMEOUT_SEC}
	return _reply.duplicate()


func _next_step_no() -> int:
	_step_no += 1
	return _step_no


func _pause() -> void:
	if _step_pause > 0.0:
		await get_tree().create_timer(_step_pause).timeout


func _record(step: String, side: String, res: Dictionary) -> void:
	var ok: bool = res.get("ok", false)
	var detail: String = res.get("detail", "")
	_results.append({"step": step, "side": side, "ok": ok, "detail": detail})
	_log("%s [%s] %s" % ["PASS" if ok else "FAIL", side, step])
	_log("     %s" % detail)


func _report() -> void:
	var failed := 0
	_banner("RESULTS")
	for r in _results:
		if not r["ok"]:
			failed += 1
		_log("%-4s %-8s %s" % ["PASS" if r["ok"] else "FAIL", r["side"], r["step"]])
	_log("%d/%d checks passed" % [_results.size() - failed, _results.size()])
	for r in _results:
		if not r["ok"]:
			_log("FAILURE %s [%s]: %s" % [r["step"], r["side"], r["detail"]])
	await _capture_step_frame("final")
	_write_frame_index()
	_write_report(failed)
	if not _auto_mode:
		return
	_quit_client.rpc_id(_client_id)
	if _end_hold > 0.0:
		_log("holding for %.0fs so you can look at the final state..." % _end_hold)
		await get_tree().create_timer(_end_hold).timeout
	else:
		await _wait_frames(30)
	_finish(failed == 0)


# A standalone report of the run, written next to the logs so it can be read
# without scrolling the console — and so the in-editor runner can print it back.
func _write_report(failed: int) -> void:
	var path := "res://logs/mptest_report.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return
	var passed := _results.size() - failed
	f.store_line("VRyHungry multiplayer test report")
	f.store_line("run at %s" % Time.get_datetime_string_from_system())
	f.store_line("")
	f.store_line("RESULT: %s   (%d passed, %d failed, %d total)"
		% ["ALL CHECKS PASSED" if failed == 0 else "FAILED", passed, failed, _results.size()])
	f.store_line("")
	if failed > 0:
		f.store_line("--- failures ---")
		for r in _results:
			if not r["ok"]:
				f.store_line("FAIL  [%s]  %s" % [r["side"], r["step"]])
				f.store_line("        %s" % r["detail"])
		f.store_line("")
	f.store_line("--- every check, in order ---")
	for r in _results:
		f.store_line("%-4s  %-6s  %s" % ["PASS" if r["ok"] else "FAIL", r["side"], r["step"]])
	f.close()
	_log("report written to %s" % ProjectSettings.globalize_path(path))


# --- Client command handling ----------------------------------------------

@rpc("authority", "reliable")
func _cmd(step: String, args: Array) -> void:
	_current_step = step
	_disable_despawn_timers()
	_log("<- server: %s%s" % [step, args])
	_running = true
	var res := await _run_local_step(step, args)
	_running = false
	_log("%s %s" % ["PASS" if res.get("ok") else "FAIL", step])
	_log("     %s" % res.get("detail"))
	_result.rpc_id(1, step, res.get("ok", false), str(res.get("detail", "")))


@rpc("any_peer", "reliable")
func _result(step: String, ok: bool, detail: String) -> void:
	_reply = {"ok": ok, "detail": detail, "step": step}


@rpc("authority", "reliable")
func _quit_client() -> void:
	_write_frame_index()
	if _end_hold > 0.0:
		await get_tree().create_timer(_end_hold).timeout
	_finish(true)


func _run_local_step(step: String, args: Array) -> Dictionary:
	match step:
		"grab":
			return await _do_grab(_find(args[0]), args[0])
		"drop":
			return await _do_drop(_find(args[0]), args[0])
		"place_in_zone":
			return await _do_place_in_zone(_find(args[0]), args[0], args[1])
		"place_food_in_zone":
			return await _do_place_in_zone(_find_by_food_id(args[0]), args[0], args[1])
		"carry_food_to_food":
			return await _do_carry_item_to_item(_find(args[0]), args[0], _find_by_food_id(args[1]), args[1])
		"carry_food_to_item":
			return await _do_carry_item_to_item(_find_by_food_id(args[0]), args[0], _find(args[1]), args[1])
		"await_food":
			return await _do_await_food(args[0])
		"await_clean":
			return await _do_await_clean(args[0])
		"park":
			return await _do_park(_find(args[0]), args[0], args[1])
		"verify_snapped":
			return _check_snapped(args[0], args[1])
		"verify_dirty":
			return _check_dirty(args[0], args[1] == "true")
		"verify_gone":
			return _check_gone(args[0])
		"verify_food_exists":
			return _check_food_exists(args[0])
		"verify_plate_contains":
			return _check_plate_contains(args[0], args[1])
		"verify_plate_visuals":
			return _check_plate_visuals(args[0])
		"verify_station_bar":
			return _check_station_bar(args[0], args[1] == "true")
		"verify_zone_empty":
			return _check_zone_empty(args[0])
		"verify_world_replicated":
			return await _check_world_replicated()
	return {"ok": false, "detail": "unknown step %s" % step}


# --- The simulated player actions -----------------------------------------

# Reach out to an item and squeeze the grip, the same way the real controller
# path does: position the hand, let the grab Area3D register what's in range,
# refresh the closest-object pick (normally done from _process, which bails out
# headlessly because the controller reports as untracked), then press grip.
func _do_grab(item: Node3D, label: String) -> Dictionary:
	if not is_instance_valid(item):
		return {"ok": false, "detail": "'%s' does not exist on this peer" % label}
	_log("  reaching for %s at %s" % [label, item.global_position])
	_move_hand_to(item.global_position)
	await _wait_frames(4)
	_hand._update_closest_object()
	var closest := _hand.closest_object
	_log("  hand at %s, closest grabbable = %s" % [_hand.global_position, closest])
	if not is_instance_valid(closest):
		return {"ok": false, "detail": "hand found nothing to grab. %s" % _diag(item)}
	_log("  pressing grip")
	_hand._on_grip_pressed()
	await _wait_frames(4)
	if not item.is_picked_up():
		return {"ok": false, "detail": "grip pressed on %s but %s not picked up. %s"
			% [closest.name, label, _diag(item)]}
	if item.get_picked_up_by() != _hand:
		return {"ok": false, "detail": "%s is held by %s, not our hand. %s"
			% [label, item.get_picked_up_by(), _diag(item)]}
	_log("  holding %s; waiting for authority..." % label)
	if not await _wait_until(func(): return item.get_multiplayer_authority() == multiplayer.get_unique_id(),
			"authority handoff", 5.0):
		return {"ok": false, "detail": "grabbed %s, but authority stayed with peer %d. %s"
			% [label, item.get_multiplayer_authority(), _diag(item)]}
	_log("  authority is ours (peer %d)" % multiplayer.get_unique_id())
	return {"ok": true, "detail": "grabbed %s via %s; %s" % [label, closest.name, _diag(item)]}


func _do_drop(item: Node3D, label: String) -> Dictionary:
	if not is_instance_valid(item):
		return {"ok": false, "detail": "'%s' does not exist on this peer" % label}
	if not item.is_picked_up():
		return {"ok": false, "detail": "nothing to drop: %s is not held. %s" % [label, _diag(item)]}
	_log("  releasing grip (held by %s)" % item.get_picked_up_by())
	_hand._on_grip_release()
	await _wait_frames(8)
	if not is_instance_valid(item):
		return {"ok": true, "detail": "%s was consumed on release" % label}
	# Explicitly typed: `item` is a Node3D here, so the return type of
	# get_picked_up_by() isn't known statically and := can't infer it.
	var by: Node = item.get_picked_up_by()
	_log("  after release %s is held by %s" % [label, by])
	if by == _hand:
		return {"ok": false, "detail": "grip released but our hand still holds %s" % label}
	# A station catching the item on release is intended - but only on the peer
	# that owns world logic. A client's own snap zone doing it means that peer is
	# running station logic it has no authority for.
	if by is XRToolsSnapZone and not NetworkManager.owns_world():
		return {"ok": false, "detail": "%s on this client grabbed %s out of our hand; station snap zones must only run on the world owner"
			% [by.get_parent().name, label]}
	if not await _wait_until(func(): return not is_instance_valid(item) or item.get_multiplayer_authority() == 1,
			"authority return to server", 5.0):
		return {"ok": false, "detail": "dropped %s, but authority stayed with peer %d"
			% [label, item.get_multiplayer_authority()]}
	return {"ok": true, "detail": "dropped %s (now held by %s)" % [label, by]}


# Grab an item, carry it onto a station's snap zone, and let go there.
func _do_place_in_zone(item: Node3D, label: String, station: String) -> Dictionary:
	var zone := _zone_of(station)
	if not zone:
		return {"ok": false, "detail": "station '%s' has no snap zone on this peer" % station}
	var res := await _do_grab(item, label)
	if not res["ok"]:
		return res
	res = await _do_carry_to(item, label, zone.global_position)
	if not res["ok"]:
		return res
	res = await _do_drop(item, label)
	if not res["ok"]:
		return res
	_log("  waiting for %s to settle onto %s..." % [label, station])
	await _wait_until(func(): return not is_instance_valid(item) \
			or item.global_position.distance_to(zone.global_position) <= SNAP_TOLERANCE,
		"%s to settle onto %s" % [label, station], 5.0)
	return {"ok": true, "detail": "placed %s into %s; %s" % [label, station, _diag(item)]}


# Grab an item and carry it into another item, holding it there. Used for the
# combine (buns into the cooked burger) and for putting food on a plate, both of
# which are triggered by an Area3D overlap rather than by dropping.
func _do_carry_item_to_item(item: Node3D, label: String, target: Node3D, target_label: String) -> Dictionary:
	if not is_instance_valid(target):
		return {"ok": false, "detail": "target '%s' does not exist on this peer" % target_label}
	var target_pos := target.global_position
	var res := await _do_grab(item, label)
	if not res["ok"]:
		return res
	res = await _do_carry_to(item, label, target_pos)
	if not res["ok"] and is_instance_valid(item):
		return res
	# Hold it there a moment: the reaction happens on the server, and the item
	# we're holding may be consumed by it.
	for i in 60:
		if not is_instance_valid(item):
			_log("  %s was consumed (the reaction fired)" % label)
			return {"ok": true, "detail": "%s consumed on contact with %s" % [label, target_label]}
		await get_tree().physics_frame
	# Both uses of this (combining, and putting food on a plate) consume the
	# carried item, so still holding it means the reaction never fired. Let go
	# first so the next step isn't left fighting our hand.
	if is_instance_valid(item) and item.is_picked_up():
		_hand._on_grip_release()
		await _wait_frames(8)
	return {"ok": false, "detail": "%s reached %s but was never consumed - the reaction did not fire; %s"
		% [label, target_label, _diag(item)]}


# Carry an item somewhere clear and put it down, freeing the station it was in.
func _do_park(item: Node3D, label: String, pos: Vector3) -> Dictionary:
	var res := await _do_grab(item, label)
	if not res["ok"]:
		return res
	res = await _do_carry_to(item, label, pos)
	if not res["ok"]:
		return res
	res = await _do_drop(item, label)
	if not res["ok"]:
		return res
	return {"ok": true, "detail": "parked %s at %s" % [label, pos]}


# Move the held item onto a world position. Closed-loop: move the hand by
# whatever the item's remaining error is, since the grab point offsets the item
# from the hand by an amount we don't want to hard-code.
func _do_carry_to(item: Node3D, label: String, target: Vector3) -> Dictionary:
	if not is_instance_valid(item) or not item.is_picked_up():
		return {"ok": false, "detail": "cannot carry: %s is not held" % label}
	_log("  carrying %s from %s to %s" % [label, item.global_position, target])
	for i in 120:
		if not is_instance_valid(item):
			return {"ok": true, "detail": "%s was consumed while being carried" % label}
		var err := item.global_position - target
		if err.length() <= 0.01:
			break
		_controller.global_position -= err
		await get_tree().physics_frame
		await get_tree().physics_frame
	if not is_instance_valid(item):
		return {"ok": true, "detail": "%s was consumed while being carried" % label}
	var dist := item.global_position.distance_to(target)
	_log("  %s is now %.3fm from the target" % [label, dist])
	if dist > 0.05:
		return {"ok": false, "detail": "could not carry %s to the target: still %.3fm away" % [label, dist]}
	return {"ok": true, "detail": "carried %s to within %.3fm" % [label, dist]}


# Wait for a station to produce an item with the given food id (cooking the
# burger, or combining into a hamburger). Server-side: stations only run there.
func _do_await_food(food_id: String) -> Dictionary:
	_log("  waiting for a '%s' to appear..." % food_id)
	var ok := await _wait_until(func(): return _find_by_food_id(food_id) != null,
		"a '%s' to be produced" % food_id, STATION_WORK_TIMEOUT)
	if not ok:
		return {"ok": false, "detail": "no '%s' was produced within %.0fs" % [food_id, STATION_WORK_TIMEOUT]}
	# Let the spawn replicate before the checks that follow look for it.
	await _wait_frames(30)
	var made := _find_by_food_id(food_id)
	return {"ok": true, "detail": "'%s' produced: %s at %s" % [food_id, made.name, made.global_position]}


func _do_await_clean(plate_name: String) -> Dictionary:
	var plate := _find(plate_name)
	if not plate:
		return {"ok": false, "detail": "'%s' does not exist on this peer" % plate_name}
	var pc := plate.get_node_or_null("PlateController")
	_log("  waiting for the sink to wash %s (dirty=%s)..." % [plate_name, pc.is_dirty if pc else "?"])
	var ok := await _wait_until(func(): return pc and not pc.is_dirty,
		"the sink to wash the plate", STATION_WORK_TIMEOUT)
	await _wait_frames(30)
	if not ok:
		return {"ok": false, "detail": "%s was still dirty after %.0fs in the sink; %s"
			% [plate_name, STATION_WORK_TIMEOUT, _diag(plate)]}
	return {"ok": true, "detail": "%s was washed clean" % plate_name}


# --- Checks ----------------------------------------------------------------

# On the server "snapped" means the zone owns the item. On a client the snap is
# server-authoritative and never happens locally, so what must be true there is
# that the replicated item actually sits in the zone.
func _check_snapped(item_name: String, station: String) -> Dictionary:
	var item := _find(item_name)
	var zone := _zone_of(station)
	if not item:
		return {"ok": false, "detail": "'%s' does not exist on this peer" % item_name}
	if not zone:
		return {"ok": false, "detail": "station '%s' has no snap zone on this peer" % station}
	var dist := item.global_position.distance_to(zone.global_position)
	var problems: Array[String] = []
	if dist > SNAP_TOLERANCE:
		problems.append("%s is %.3fm from %s's zone (tolerance %.2f)" % [item_name, dist, station, SNAP_TOLERANCE])
	if NetworkManager.owns_world():
		if zone.picked_up_object != item:
			problems.append("%s's zone holds %s, not %s" % [station, zone.picked_up_object, item_name])
		elif not item.is_picked_up():
			problems.append("%s's zone claims %s but it has no grab driver (half-snapped)" % [station, item_name])
	if problems.is_empty():
		return {"ok": true, "detail": "%s is snapped into %s; %s" % [item_name, station, _diag(item)]}
	return {"ok": false, "detail": "%s | %s" % [", ".join(problems), _diag(item)]}


func _check_dirty(plate_name: String, want_dirty: bool) -> Dictionary:
	var plate := _find(plate_name)
	if not plate:
		return {"ok": false, "detail": "'%s' does not exist on this peer" % plate_name}
	var pc := plate.get_node_or_null("PlateController")
	if not pc:
		return {"ok": false, "detail": "'%s' has no PlateController" % plate_name}
	if pc.is_dirty != want_dirty:
		return {"ok": false, "detail": "%s.is_dirty is %s, expected %s; %s"
			% [plate_name, pc.is_dirty, want_dirty, _diag(plate)]}
	return {"ok": true, "detail": "%s.is_dirty == %s as expected" % [plate_name, want_dirty]}


# A consumed item must be gone on EVERY peer, not just the one that consumed it.
func _check_gone(item_name: String) -> Dictionary:
	var item := _find(item_name)
	if item and is_instance_valid(item):
		return {"ok": false, "detail": "'%s' still exists on this peer at %s (it should have been consumed)"
			% [item_name, item.global_position]}
	return {"ok": true, "detail": "'%s' is gone, as expected" % item_name}


func _check_food_exists(food_id: String) -> Dictionary:
	var item := _find_by_food_id(food_id)
	if not item:
		return {"ok": false, "detail": "no item with food id '%s' exists on this peer" % food_id}
	return {"ok": true, "detail": "'%s' exists: %s at %s" % [food_id, item.name, item.global_position]}


func _check_plate_contains(plate_name: String, food_id: String) -> Dictionary:
	var plate := _find(plate_name)
	if not plate:
		return {"ok": false, "detail": "'%s' does not exist on this peer" % plate_name}
	var pc := plate.get_node_or_null("PlateController")
	if not pc:
		return {"ok": false, "detail": "'%s' has no PlateController" % plate_name}
	if not (food_id in pc.contained_ids):
		return {"ok": false, "detail": "%s holds %s, expected it to contain '%s'"
			% [plate_name, str(pc.contained_ids), food_id]}
	return {"ok": true, "detail": "%s contains %s" % [plate_name, str(pc.contained_ids)]}


# --- Per-step screenshots --------------------------------------------------
#
# One frame per peer per step, saved as PNGs and stitched into a single
# side-by-side GIF afterwards (see test/make_gif.ps1). Seeing both peers'
# viewports next to each other for the same step is the fastest way to spot a
# visual desync — the numbers in the log tell you something diverged, the GIF
# shows you what it looked like.

## Frames are captured at half the viewport's resolution: 60-odd full-size
## frames per peer is a lot of pixels to write and then re-encode.
const FRAME_SCALE := 0.5


func _setup_frames() -> void:
	if not _frames_enabled:
		return
	if DisplayServer.get_name() == "headless":
		_frames_enabled = false
		_log("frame capture disabled: a headless run has no rendered output to grab")
		return
	var role := "server" if "--server" in OS.get_cmdline_args() else "client"
	_frames_dir = "res://logs/mptest_frames_%s" % role
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_frames_dir))
	# Clear out a previous run's frames, or the GIF would splice the two together.
	var dir := DirAccess.open(_frames_dir)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".png"):
				dir.remove(f)
	_log("capturing a frame per step into %s" % ProjectSettings.globalize_path(_frames_dir))


# The server numbers the frames and tells the client to grab the matching one, so
# frame N is the same step on both sides and they can be stitched in pairs.
func _capture_step_frame(label: String) -> void:
	if not _frames_enabled:
		return
	_frame_index += 1
	if NetworkManager.is_server() and _client_id != 0:
		_capture_frame_rpc.rpc_id(_client_id, _frame_index, label)
	await _save_frame(_frame_index, label)


@rpc("authority", "reliable")
func _capture_frame_rpc(index: int, label: String) -> void:
	if not _frames_enabled:
		return
	_frame_index = index
	await _save_frame(index, label)


func _save_frame(index: int, label: String) -> void:
	# Wait for the frame to actually be drawn, or we capture whatever was in the
	# buffer before this step's changes landed.
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if not tex:
		return
	var img := tex.get_image()
	if not img:
		return
	if FRAME_SCALE != 1.0:
		img.resize(int(img.get_width() * FRAME_SCALE), int(img.get_height() * FRAME_SCALE),
			Image.INTERPOLATE_BILINEAR)
	# Index-only filenames so ffmpeg's image sequence reader can pick them up as
	# frame_%04d.png; the step name is already legible in the on-screen overlay.
	var err := img.save_png("%s/frame_%04d.png" % [_frames_dir, index])
	if err != OK:
		_log("  could not save frame %d (%s)" % [index, error_string(err)])
	else:
		_frame_labels.append("%04d  %s" % [index, label])


# Written alongside the frames so a given frame number can be traced back to the
# step that produced it.
var _frame_labels: Array[String] = []


func _write_frame_index() -> void:
	if not _frames_enabled or _frame_labels.is_empty():
		return
	var f := FileAccess.open("%s/frames.txt" % _frames_dir, FileAccess.WRITE)
	if f:
		for line in _frame_labels:
			f.store_line(line)
		f.close()


# --- Cross-peer sync audit -------------------------------------------------
#
# Runs after every step. Targeted per-step assertions only look at the one thing
# the step touched, which misses the whole class of bug where some *other*
# object quietly drifts out of sync — or where the data replicates fine but the
# thing you actually see on screen doesn't. So after each step both peers
# describe every item they can see, and the two descriptions must match.

## How far apart the same item may be on the two peers before it counts as a desync.
const SYNC_POS_TOLERANCE := 0.08
## Physics keeps moving after a step (dropped items fall, snaps settle), so give
## the peers this long to converge before calling a difference a failure.
const SYNC_SETTLE_SEC := 3.0

var _client_snapshot: Dictionary = {}
var _snapshot_pending := false


# Everything about an item that should look identical on every peer. Includes
# what is actually rendered, not just the replicated data behind it: a plate
# whose contained_ids arrived but whose visuals were never rebuilt looks empty
# to the player, and that must count as a desync.
func _describe(item: Node3D) -> Dictionary:
	var d := {"pos": item.global_position, "visible": item.visible}
	var pc := item.get_node_or_null("PlateController")
	if pc:
		d["dirty"] = pc.is_dirty
		d["contents"] = ",".join(pc.contained_ids)
		var dirty_node := item.get_node_or_null("Dirty")
		d["dirty_shown"] = dirty_node.visible if dirty_node else false
		# The cosmetic copies the container builds from contained_ids - this is
		# literally what the player sees sitting on the plate.
		d["meals_shown"] = _visual_count(item, "Container/MealContainer")
		d["sides_shown"] = _visual_count(item, "Container/SidesContainer")
		# Food sitting on a plate is a cosmetic child of the plate, so it must
		# travel with it. Keys starting with "_" are per-peer diagnostics that
		# _compare() skips (floats won't match exactly across peers); the
		# attached flag is asserted absolutely instead, because this can — and
		# did — go wrong on both peers at once, which a diff would miss.
		var off := _max_visual_offset(item)
		d["_visual_offset"] = off
		d["visuals_attached"] = off <= MAX_VISUAL_OFFSET
	return d


## How far a cosmetic item on a plate may sit from the plate's origin. The plate
## is ~0.4m across and the furthest slot is ~0.12m out, so anything past this has
## come off the plate.
const MAX_VISUAL_OFFSET := 0.3


# Largest distance from the plate's origin to any of the cosmetic items it is
# displaying. -1 when the plate is showing nothing.
func _max_visual_offset(item: Node3D) -> float:
	var worst := -1.0
	for path in ["Container/MealContainer", "Container/SidesContainer"]:
		var root := item.get_node_or_null(path)
		if not root:
			continue
		for c in root.get_children():
			if c is Node3D and not c.is_queued_for_deletion():
				worst = maxf(worst, item.global_position.distance_to((c as Node3D).global_position))
	return snappedf(worst, 0.001)


# What the cosmetic children look like, for diagnosing why they moved.
func _visual_diag(item: Node3D) -> String:
	var parts: Array[String] = []
	for path in ["Container/MealContainer", "Container/SidesContainer"]:
		var root := item.get_node_or_null(path)
		if not root:
			continue
		for c in root.get_children():
			var s := "%s global=%s local=%s parent=%s (%.3fm from plate at %s)" % [
				c.name, (c as Node3D).global_position, (c as Node3D).position,
				c.get_parent().name,
				item.global_position.distance_to((c as Node3D).global_position),
				item.global_position]
			if c is RigidBody3D:
				s += " [RigidBody3D freeze=%s freeze_mode=%d layer=%d top_level=%s queued=%s]" % [
					c.freeze, c.freeze_mode, c.collision_layer, c.top_level,
					c.is_queued_for_deletion()]
			parts.append(s)
	return "; ".join(parts) if parts else "(nothing on the plate)"


func _visual_count(item: Node3D, path: String) -> int:
	var n := item.get_node_or_null(path)
	if not n:
		return -1
	var count := 0
	for c in n.get_children():
		if not c.is_queued_for_deletion():
			count += 1
	return count


## Stations whose on-screen state has to match on every peer.
const WATCHED_STATIONS := ["Hob", "Sink", "DirtStation", "Counter", "Counter2"]


func _snapshot() -> Dictionary:
	var out := {}
	for root in [_world, _world.get_node_or_null("WorldContent")]:
		if not root:
			continue
		for child in root.get_children():
			if child is XRToolsPickable and not child.is_queued_for_deletion():
				out[str(child.name)] = _describe(child)
	for station_name in WATCHED_STATIONS:
		var station := _find(station_name)
		if station:
			out["station:" + station_name] = _describe_station(station)
	return out


# What a station shows the player. Only the world owner runs a station's logic
# and snap zone, so its display has to be driven from replicated state — a
# client that never updates it shows a hob that never lights up, or a sink bar
# that stays on screen after the plate came out clean.
#
# Bar *visibility* is compared across peers; the progress value is diagnostic
# only ("_" prefix), because it changes every tick and the two peers are
# legitimately a frame apart.
func _describe_station(station: Node3D) -> Dictionary:
	var d := {}
	var bar := station.get_node_or_null("ProgressBar3D") as ProgressBar3D
	d["bar_visible"] = bar.is_bar_visible() if bar else false
	d["_bar_progress"] = snappedf(bar.get_progress(), 1.0) if bar else -1.0
	if "cooking_result" in station:
		d["cooking"] = str(station.cooking_result)
	if "is_washing" in station:
		d["washing"] = bool(station.is_washing)
	return d


@rpc("authority", "reliable")
func _request_snapshot() -> void:
	_snapshot_reply.rpc_id(1, _snapshot())


@rpc("any_peer", "reliable")
func _snapshot_reply(snap: Dictionary) -> void:
	_client_snapshot = snap
	_snapshot_pending = false


func _fetch_client_snapshot() -> Dictionary:
	_client_snapshot = {}
	_snapshot_pending = true
	_request_snapshot.rpc_id(_client_id)
	var deadline := Time.get_ticks_msec() + 10000
	while _snapshot_pending and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _client_snapshot


# Compare the server's view with the client's, returning a list of differences.
func _compare(server: Dictionary, client: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for entity_name in server:
		if not client.has(entity_name):
			problems.append("'%s' exists on the server but NOT on the client" % entity_name)
	for entity_name in client:
		if not server.has(entity_name):
			problems.append("'%s' exists on the client but NOT on the server (ghost copy)" % entity_name)
	for entity_name in server:
		if not client.has(entity_name):
			continue
		var s: Dictionary = server[entity_name]
		var c: Dictionary = client[entity_name]
		# Stations are compared on their displayed state, not a position.
		if s.has("pos") and c.has("pos"):
			var dist: float = (s["pos"] as Vector3).distance_to(c["pos"])
			if dist > SYNC_POS_TOLERANCE:
				problems.append("%s is %.3fm apart (server %s vs client %s)" % [entity_name, dist, s["pos"], c["pos"]])
		for key in s:
			# "_" keys are per-peer diagnostics, not things that must match.
			if key == "pos" or key.begins_with("_"):
				continue
			if s[key] != c[key]:
				problems.append("%s.%s: server=%s client=%s" % [entity_name, key, s[key], c[key]])
	# Absolute invariants, checked per peer. A cross-peer diff can't catch a
	# fault that happens identically on both sides.
	for peer_name in ["server", "client"]:
		var snap: Dictionary = server if peer_name == "server" else client
		for entity_name in snap:
			var d: Dictionary = snap[entity_name]
			if d.has("visuals_attached") and not d["visuals_attached"]:
				problems.append("on the %s, %s's food has come off the plate (%.3fm from it, limit %.2f)"
					% [peer_name, entity_name, d.get("_visual_offset", -1.0), MAX_VISUAL_OFFSET])
	return problems


# Poll until the two peers agree, so ordinary physics settling isn't reported as
# a desync — a real one never converges and gets reported with its details.
func _audit_sync(label: String) -> void:
	if not NetworkManager.is_server() or _client_id == 0:
		return
	var problems: Array[String] = []
	var deadline := Time.get_ticks_msec() + int(SYNC_SETTLE_SEC * 1000.0)
	while true:
		var mine := _snapshot()
		var theirs := await _fetch_client_snapshot()
		problems = _compare(mine, theirs)
		if problems.is_empty() or Time.get_ticks_msec() > deadline:
			break
		await _wait_frames(10)
	var res := {"ok": problems.is_empty(), "detail": ""}
	if problems.is_empty():
		res["detail"] = "server and client agree on all %d items" % _snapshot().size()
	else:
		res["detail"] = "after %.0fs the peers still disagree: %s" % [SYNC_SETTLE_SEC, "; ".join(problems)]
	_record("sync_after_" + label, "both", res)


# --- Live watch on plate visuals ------------------------------------------
#
# The per-step checks tell us the food ended up off the plate, but not when or
# why. This watches every frame and reports the first frame a cosmetic item
# departs from its slot, along with what was happening to the plate at the time.

## Local offset from its slot at which a cosmetic item counts as having moved.
const VISUAL_DRIFT_EPSILON := 0.05

var _current_step := "(before any step)"
var _drift_reported := {}


func _process(_delta: float) -> void:
	if not _world:
		return
	for root in [_world, _world.get_node_or_null("WorldContent")]:
		if not root:
			continue
		for item in root.get_children():
			if not (item is Node3D) or not item.get_node_or_null("PlateController"):
				continue
			_watch_plate(item as Node3D)


func _watch_plate(plate: Node3D) -> void:
	for path in ["Container/MealContainer", "Container/SidesContainer"]:
		var holder := plate.get_node_or_null(path)
		if not holder:
			continue
		for c in holder.get_children():
			if not (c is Node3D) or c.is_queued_for_deletion():
				continue
			var drift: float = (c as Node3D).position.length()
			var key := c.get_instance_id()
			if drift <= VISUAL_DRIFT_EPSILON:
				_drift_reported.erase(key)
				continue
			if _drift_reported.has(key):
				continue
			_drift_reported[key] = true
			_log("VISUAL DRIFT: %s on %s moved to local %s (%.3f from its slot) during '%s'" % [
				c.name, plate.name, (c as Node3D).position, drift, _current_step])
			_log("  plate: pos=%s freeze=%s held_by=%s authority=%d" % [
				plate.global_position, plate.freeze if plate is RigidBody3D else "-",
				plate.get_picked_up_by() if plate.has_method("get_picked_up_by") else "-",
				plate.get_multiplayer_authority()])
			if c is RigidBody3D:
				_log("  visual: freeze=%s mode=%d layer=%d top_level=%s sleeping=%s lin_vel=%s" % [
					c.freeze, c.freeze_mode, c.collision_layer, c.top_level,
					c.sleeping, c.linear_velocity])


# Food shown on a plate is a cosmetic child of that plate, so it has to stay put
# when the plate is picked up and carried around. If it drifts away, the player
# sees the burger fly off the plate.
func _check_plate_visuals(plate_name: String) -> Dictionary:
	var plate := _find(plate_name)
	if not plate:
		return {"ok": false, "detail": "'%s' does not exist on this peer" % plate_name}
	var off := _max_visual_offset(plate)
	if off < 0.0:
		return {"ok": false, "detail": "%s is not showing any food to check" % plate_name}
	if off > MAX_VISUAL_OFFSET:
		return {"ok": false, "detail": "%s's food has come off the plate: %.3fm away (limit %.2f). %s"
			% [plate_name, off, MAX_VISUAL_OFFSET, _visual_diag(plate)]}
	return {"ok": true, "detail": "%s's food is still on it (%.3fm from centre). %s"
		% [plate_name, off, _visual_diag(plate)]}


# A station's progress bar must show the same thing to everyone: visible while
# the station is working, gone once it has finished. Only the world owner runs
# station logic, so a client can only get this right if the display is driven
# from replicated state.
func _check_station_bar(station_name: String, want_visible: bool) -> Dictionary:
	var station := _find(station_name)
	if not station:
		return {"ok": false, "detail": "'%s' does not exist on this peer" % station_name}
	var bar := station.get_node_or_null("ProgressBar3D") as ProgressBar3D
	if not bar:
		return {"ok": false, "detail": "%s has no ProgressBar3D" % station_name}
	var shown := bar.is_bar_visible()
	var detail := "%s bar visible=%s progress=%.0f%%" % [station_name, shown, bar.get_progress()]
	if "cooking_result" in station:
		detail += " cooking='%s'" % station.cooking_result
	if "is_washing" in station:
		detail += " washing=%s" % station.is_washing
	if shown != want_visible:
		return {"ok": false, "detail": "expected %s's bar to be %s, but %s"
			% [station_name, "visible" if want_visible else "hidden", detail]}
	return {"ok": true, "detail": detail}


# The client loaded a bare multiplayer scene with no kitchen in it, so every
# object it can see arrived from the server. This confirms it got the whole
# layout — the same thing that has to work for a player joining mid-session.
# Server-side check: it asks the client for its inventory and compares.
func _check_world_replicated() -> Dictionary:
	var mine := _snapshot()
	var theirs := await _fetch_client_snapshot()
	if theirs.is_empty():
		return {"ok": false, "detail": "the client reported nothing at all"}
	var problems := _compare(mine, theirs)
	var detail := "server has %d objects, client has %d" % [mine.size(), theirs.size()]
	if not problems.is_empty():
		return {"ok": false, "detail": "%s; %s" % [detail, "; ".join(problems)]}
	return {"ok": true, "detail": "%s, all matching (client received the world over the network)" % detail}


# A station that has had its item taken away must not still be holding it.
func _check_zone_empty(station_name: String) -> Dictionary:
	var zone := _zone_of(station_name)
	if not zone:
		return {"ok": false, "detail": "station '%s' has no snap zone on this peer" % station_name}
	if not NetworkManager.owns_world():
		# Client zones are gated off entirely; they never hold anything.
		return {"ok": true, "detail": "%s: client zones are gated, nothing to check" % station_name}
	if is_instance_valid(zone.picked_up_object):
		return {"ok": false, "detail": "%s's zone still holds %s after it was taken away"
			% [station_name, zone.picked_up_object]}
	return {"ok": true, "detail": "%s's zone is empty" % station_name}


# --- Diagnostics -----------------------------------------------------------

func _diag(item: Node3D) -> String:
	if not is_instance_valid(item):
		return "item[freed]"
	var np := item.get_node_or_null("NetPickable")
	var pc := item.get_node_or_null("PlateController")
	var s := "%s[pos=%s authority=%d net_held_by=%s" % [
		item.name, item.global_position, item.get_multiplayer_authority(),
		np.net_held_by if np else "-",
	]
	if item is XRToolsPickable:
		s += " enabled=%s can_pick_up=%s layer=%d held_by=%s" % [
			item.enabled, item.can_pick_up(_hand), item.collision_layer, item.get_picked_up_by()]
	if pc:
		s += " dirty=%s contains=%s" % [pc.is_dirty, str(pc.contained_ids)]
	return s + "]"


func _dump_state() -> void:
	_log("  stations:")
	for station in ["Hob", "Sink", "DirtStation", "Counter", "Counter2"]:
		var z := _zone_of(station)
		if z:
			_log("    %-12s zone holds %s (enabled=%s)" % [station, z.picked_up_object, z.enabled])
	_log("  items:")
	for root in [_world, _world.get_node_or_null("WorldContent")]:
		if not root:
			continue
		for child in root.get_children():
			if child is XRToolsPickable:
				_log("    %s" % _diag(child))


# --- Manual controls -------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _running and event.keycode != KEY_0:
		_log("busy running a step, ignoring that key")
		return
	match event.keycode:
		KEY_H:
			_log("KEY: host"); NetworkManager.host(); _refresh_role()
		KEY_J:
			_log("KEY: join 127.0.0.1"); NetworkManager.join("127.0.0.1")
			await get_tree().create_timer(1.0).timeout
			_refresh_role()
		KEY_1: await _manual("grab plate", "grab", ["Plate"])
		KEY_2: await _manual("drop plate", "drop", ["Plate"])
		KEY_3: await _manual("plate -> dirt station", "place_in_zone", ["Plate", "DirtStation"])
		KEY_4: await _manual("plate -> sink", "place_in_zone", ["Plate", "Sink"])
		KEY_5: await _manual("raw burger -> hob", "place_in_zone", ["raw_burger", "Hob"])
		KEY_6: await _manual("cooked burger -> counter", "place_food_in_zone", ["cooked_burger", "Counter"])
		KEY_7: await _manual("buns -> cooked burger", "carry_food_to_food", ["BurgerBuns", "cooked_burger"])
		KEY_8: await _manual("plate -> counter 2", "place_in_zone", ["Plate", "Counter2"])
		KEY_9: await _manual("hamburger -> plate", "carry_food_to_item", ["hamburger", "Plate"])
		KEY_R:
			_refresh_role()
			if _role != "server":
				_log("KEY: run-all is server-only (this peer is %s)" % _role)
				return
			_log("KEY: running the full automatic sequence")
			await _run_server()
		KEY_0:
			_log("KEY: state dump")
			_dump_state()
		KEY_A:
			_refresh_role()
			if _role != "server":
				_log("KEY: the sync audit runs from the server window")
				return
			_log("KEY: comparing every object against the client")
			_running = true
			await _audit_sync("manual_check")
			_running = false
		KEY_C:
			_toggle_debug_camera()


func _manual(what: String, step: String, args: Array) -> void:
	_refresh_role()
	_banner("MANUAL: %s" % what)
	_running = true
	var res := await _run_local_step(step, args)
	_running = false
	_log("%s %s :: %s" % ["PASS" if res.get("ok") else "FAIL", what, res.get("detail", "")])
	# Capture manual steps too, so a hand-driven repro can be turned into a GIF.
	await _capture_step_frame(step)
	_write_frame_index()


# --- Helpers ---------------------------------------------------------------

func _move_hand_to(pos: Vector3) -> void:
	# The controller is a child of the XROrigin, whose PlayerBody keeps moving
	# (gravity) — that drags the hand off any position we place it at. top_level
	# detaches it into world space. Done lazily on first use so that simply
	# running the scene by hand leaves a real tracked controller alone.
	if not _hand_detached:
		_hand_detached = true
		_controller.top_level = true
		_log("  (detached the test hand from the XR rig so it can be driven directly)")
	_controller.global_position = pos
	_controller.force_update_transform()


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# Poll a condition instead of sleeping a guessed duration, so a slow machine
# doesn't produce a spurious failure and a fast one doesn't waste seconds.
func _wait_until(cond: Callable, what: String, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	_log("  timed out after %.0fs waiting for %s" % [timeout, what])
	return false


func _finish(ok: bool) -> void:
	_log("=== %s exiting (%s) ===" % [_role, "ok" if ok else "FAILED"])
	if _log_file:
		_log_file.flush()
	get_tree().quit(0 if ok else 1)


# --- Camera ----------------------------------------------------------------

# A fixed camera overlooking the kitchen.
#
# Without this a windowed run shows nothing useful: the only camera is the
# XROrigin's XRCamera3D, which isn't driven by anything when XR is off, and the
# rig's PlayerBody keeps falling under gravity — it ends up metres below the
# floor pointing at the void. Ours is a plain Camera3D parented to the world
# (not the rig), so it stays put.
func _build_debug_camera() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_debug_cam = Camera3D.new()
	_debug_cam.name = "MPTestDebugCamera"
	_world.add_child(_debug_cam)
	_debug_cam.global_position = DEBUG_CAM_POS
	_debug_cam.look_at(DEBUG_CAM_LOOK_AT)
	# Explicitly stand the rig's camera down first: setting `current` alone lost
	# the race against XRCamera3D, leaving the view stuck under the floor.
	var xr_cam := _world.get_node_or_null("XROrigin3D/XRCamera3D") as Camera3D
	if xr_cam:
		xr_cam.current = false
	_debug_cam.make_current()
	_log("debug camera at %s looking at %s ([C] toggles back to the XR rig camera)"
		% [DEBUG_CAM_POS, DEBUG_CAM_LOOK_AT])
	_assert_debug_camera.call_deferred()


func _assert_debug_camera() -> void:
	if _debug_cam and _debug_cam.current and get_viewport().get_camera_3d() != _debug_cam:
		_debug_cam.make_current()
	_log("rendering through camera: %s" % get_viewport().get_camera_3d())
	_check_framing()


# Confirm the things the test acts on are actually on screen. Checked by
# projection rather than by eye, because it's the only way to be sure across
# window sizes and display scaling.
func _check_framing() -> void:
	var size := get_viewport().get_visible_rect().size
	var offscreen: Array[String] = []
	for station_name in ["Counter2", "Counter", "Hob", "Sink", "DirtStation", "Plate"]:
		var n := _find(station_name)
		if not n:
			continue
		var p := _debug_cam.unproject_position(n.global_position)
		var frac := Vector2(p.x / size.x, p.y / size.y)
		var on := not _debug_cam.is_position_behind(n.global_position) \
			and frac.x > 0.02 and frac.x < 0.98 and frac.y > 0.02 and frac.y < 0.98
		_log("  framing: %-12s at %.2f,%.2f of frame%s" % [station_name, frac.x, frac.y, "" if on else "  <-- OFF SCREEN"])
		if not on:
			offscreen.append(station_name)
	if offscreen.is_empty():
		_log("  framing: all test objects are in view")
	else:
		_log("  framing: WARNING - not visible: %s (adjust DEBUG_CAM_POS)" % ", ".join(offscreen))


func _toggle_debug_camera() -> void:
	if not _debug_cam:
		_log("KEY: no debug camera in a headless run")
		return
	_debug_cam.current = not _debug_cam.current
	if not _debug_cam.current:
		var xr_cam := _world.get_node_or_null("XROrigin3D/XRCamera3D") as Camera3D
		if xr_cam:
			xr_cam.current = true
	_log("KEY: camera -> %s" % ("fixed debug camera" if _debug_cam.current else "XR rig camera"))


# --- Output ----------------------------------------------------------------

# A heading that's easy to find when scrolling a window full of engine spam.
func _banner(s: String) -> void:
	_log("")
	_log("======== %s ========" % s)


# Write the step log next to the engine's own log, under <project>/logs/, so
# everything from a run is in one place. Named per role because both instances
# would otherwise fight over one file (the engine's own godot.log has exactly
# that problem when two peers run at once — it rotates per process).
func _open_log() -> void:
	var role := "server" if "--server" in OS.get_cmdline_args() else "client"
	var path := "res://logs/mptest_%s.log" % role
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	_log_file = FileAccess.open(path, FileAccess.WRITE)
	if not _log_file:
		# res:// is read-only in an exported build; fall back to somewhere writable.
		path = OS.get_environment("TEMP").path_join("vryhungry_mptest_%s.log" % role)
		_log_file = FileAccess.open(path, FileAccess.WRITE)
	_log_path = ProjectSettings.globalize_path(path)
	print("[MPTEST] step log -> %s" % _log_path)


func _log(s: String) -> void:
	print("[MPTEST %s] %s" % [_role, s])
	if _log_file:
		_log_file.store_line(s)
		_log_file.flush()
	_push_overlay(s)


# On-screen mirror of the log, so a windowed run shows what's happening without
# needing the console — including which peer this window is.
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MPTestOverlay"
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.modulate = Color(1, 1, 1, 0.85)
	_overlay = Label.new()
	# Sized for a 1800x1200 canvas, and to stay legible once a captured frame has
	# been scaled down into the GIF.
	_overlay.add_theme_font_size_override("font_size", 22)
	_overlay.autowrap_mode = TextServer.AUTOWRAP_OFF
	_overlay.clip_text = true
	panel.add_child(_overlay)
	layer.add_child(panel)
	add_child(layer)


func _push_overlay(s: String) -> void:
	if not _overlay:
		return
	_overlay_lines.append(s)
	while _overlay_lines.size() > OVERLAY_LINES:
		_overlay_lines.pop_front()
	_overlay.text = "[%s]  %s\n%s" % [_role.to_upper(), HELP, "\n".join(_overlay_lines)]
