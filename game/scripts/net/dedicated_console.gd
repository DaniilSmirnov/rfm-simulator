extends RefCounted
# The dedicated server's command line: lines typed into the terminal it runs in
# (dedicated.gd carries them out). Reading stdin blocks, so a thread of its own
# reads it and queues the lines for the main loop. The reader lives in static
# state: it outlives the scene reloads that start a room over.
# Godot returns "" both for an empty line and for a closed stdin (Docker
# without -i, a pipe that ended, /dev/null); a closed one answers at once, over
# and over, and the reader then stops.
const CLOSED_AFTER = 20
const INSTANT_MSEC = 2

static var _thread: Thread
static var _mutex = Mutex.new()
static var _lines: PackedStringArray = []

static func start() -> void:
	if _thread != null:
		return
	_thread = Thread.new()
	_thread.start(_read)

static func _read() -> void:
	var instant = 0
	while instant < CLOSED_AFTER:
		var begun = Time.get_ticks_msec()
		var line = OS.read_string_from_stdin(1024).strip_edges()
		if line.is_empty():
			instant = instant + 1 if Time.get_ticks_msec() - begun <= INSTANT_MSEC else 0
			continue
		instant = 0
		_mutex.lock()
		_lines.append(line)
		_mutex.unlock()

# The lines typed since the last call, oldest first.
static func take() -> PackedStringArray:
	_mutex.lock()
	var lines = _lines
	_lines = PackedStringArray()
	_mutex.unlock()
	return lines
