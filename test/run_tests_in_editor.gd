@tool
extends EditorScript

## Runs the whole multiplayer test suite from inside the Godot editor.
##
## HOW TO USE
##   1. Open this file in the editor's script panel.
##   2. File > Run  (Ctrl+Shift+X).
##
## It launches two copies of the game (server + client) as separate processes,
## waits for them to finish, then prints the full pass/fail report into the
## Output panel and builds the side-by-side GIF.
##
## Everything it produces lands in logs/:
##   mptest_report.txt   every check, pass/fail, plus details for failures
##   mptest_run.gif      both peers side by side, one frame per step
##   mptest_{server,client}.log   full step logs
##
## NOTE: the editor is blocked while the run is in progress (a couple of
## minutes). Watch the two game windows to follow along.

## Give up if the server hasn't finished in this long.
const TIMEOUT_SEC := 400
## Seconds each step is held, so the run is watchable and the GIF is readable.
const STEP_PAUSE := 0.4
## Seconds the final state stays on screen before the instances close.
const END_HOLD := 3.0

## The peers load different scenes on purpose, mirroring the real game: the host
## opens whatever world it is running, the client opens the bare multiplayer
## scene and has to receive the whole layout over the network — the same path a
## client joining mid-session takes.
const SERVER_SCENE := "res://test/multiPlayerTest.tscn"
const CLIENT_SCENE := "res://scenes/multiPlayer.tscn"


func _run() -> void:
	var exe := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://").rstrip("/")
	var logs_dir := ProjectSettings.globalize_path("res://logs")
	DirAccess.make_dir_recursive_absolute(logs_dir)
	_clear_previous_results(logs_dir)

	print_rich("[b]Running the multiplayer test suite...[/b]")
	SweetLogger.info("the editor will be unresponsive until it finishes (~2 minutes)", [])

	var server_pid := _launch(exe, project_dir, ["--server"], SERVER_SCENE)
	if server_pid <= 0:
		push_error("Could not start the server instance")
		return
	# Give the host time to come up and open its port before the client dials in.
	OS.delay_msec(5000)
	var client_pid := _launch(exe, project_dir, ["--join", "127.0.0.1"], CLIENT_SCENE)
	if client_pid <= 0:
		push_error("Could not start the client instance")
		OS.kill(server_pid)
		return

	var waited := 0.0
	while OS.is_process_running(server_pid) and waited < TIMEOUT_SEC:
		OS.delay_msec(500)
		waited += 0.5
	if OS.is_process_running(server_pid):
		SweetLogger.warning("timed out after {0}s, stopping the instances", [TIMEOUT_SEC])
		OS.kill(server_pid)
	if OS.is_process_running(client_pid):
		OS.kill(client_pid)
	OS.delay_msec(500)

	_print_report(logs_dir)
	_build_gif(project_dir, logs_dir)


func _launch(exe: String, project_dir: String, extra: Array, scene: String) -> int:
	var args := PackedStringArray([
		"--xr-mode", "off", "--resolution", "900x600",
		"--path", project_dir, scene, "--",
	])
	for a in extra:
		args.append(a)
	# --mptest runs the scripted sequence; --mptest-frames captures the frame per
	# step that the GIF is stitched from (needs a real window, hence no
	# --headless here).
	args.append_array(PackedStringArray([
		"--mptest", "--mptest-frames",
		"--mptest-pause", str(STEP_PAUSE), "--mptest-hold", str(END_HOLD),
	]))
	return OS.create_process(exe, args)


# Remove the previous run's output so a failed launch can't leave stale results
# looking like this run's.
func _clear_previous_results(logs_dir: String) -> void:
	for name in ["mptest_report.txt", "mptest_run.gif", "mptest_server.log", "mptest_client.log"]:
		DirAccess.remove_absolute(logs_dir.path_join(name))
	for role in ["server", "client"]:
		var frames := logs_dir.path_join("mptest_frames_%s" % role)
		var dir := DirAccess.open(frames)
		if dir:
			for f in dir.get_files():
				if f.ends_with(".png"):
					dir.remove(f)


func _print_report(logs_dir: String) -> void:
	var path := logs_dir.path_join("mptest_report.txt")
	if not FileAccess.file_exists(path):
		push_error("No report at %s — the run did not finish. Check logs/mptest_server.log" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	SweetLogger.info("", [])
	# Colour the summary so a failure is obvious in the Output panel.
	for line in text.split("\n"):
		if line.begins_with("FAIL") or line.contains("RESULT: FAILED"):
			print_rich("[color=red]%s[/color]" % line)
		elif line.contains("ALL CHECKS PASSED"):
			print_rich("[color=green][b]%s[/b][/color]" % line)
		elif line.begins_with("PASS"):
			print_rich("[color=gray]%s[/color]" % line)
		else:
			SweetLogger.info("{0}", [line])
	SweetLogger.info("report: {0}", [path])


func _build_gif(project_dir: String, logs_dir: String) -> void:
	var script := project_dir.path_join("test/make_gif.ps1")
	var out := []
	var code := OS.execute("powershell", [
		"-ExecutionPolicy", "Bypass", "-File", script,
	], out, true)
	for line in out:
		print(line)
	var gif := logs_dir.path_join("mptest_run.gif")
	if code == 0 and FileAccess.file_exists(gif):
		print_rich("[b]gif:[/b] %s" % gif)
	else:
		push_warning("GIF was not produced (is ffmpeg on PATH?). See the output above.")
