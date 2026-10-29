extends Node
## Binary save files with an atomic write (temp file + rename).
##
## The prototype saves when the app is paused or closed and on explicit calls;
## the format is versioned from the first commit so that old saves can be
## migrated rather than thrown away.

const SAVE_VERSION: int = 1
const SAVE_DIR: String = "user://saves"
const SLOT_MAIN: String = "main"

var last_error: String = ""


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			# Never lose a night to a phone call: flush immediately.
			save_slot(SLOT_MAIN)


func save_slot(p_slot: String) -> bool:
	var data: Dictionary = collect_state()
	var path: String = _path_for(p_slot)
	var tmp_path: String = path + ".tmp"
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		last_error = "cannot open %s: %s" % [tmp_path, error_string(FileAccess.get_open_error())]
		push_error("SaveSystem: " + last_error)
		return false
	file.store_32(0x46524F53) # "FROS"
	file.store_32(SAVE_VERSION)
	var payload: PackedByteArray = var_to_bytes(data)
	file.store_32(payload.size())
	file.store_buffer(payload)
	file.close()

	# Atomic swap: the old save stays valid until the rename succeeds.
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		last_error = "cannot open save directory"
		return false
	if dir.file_exists(tmp_path.get_file()):
		dir.remove(p_slot + ".sav")
	var err: Error = dir.rename(tmp_path.get_file(), p_slot + ".sav")
	if err != OK:
		last_error = "rename failed: %s" % error_string(err)
		push_error("SaveSystem: " + last_error)
		return false
	last_error = ""
	return true


func load_slot(p_slot: String) -> bool:
	var path: String = _path_for(p_slot)
	if not FileAccess.file_exists(path):
		last_error = "no save at %s" % path
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "cannot open %s" % path
		return false
	var magic: int = file.get_32()
	var version: int = file.get_32()
	if magic != 0x46524F53:
		last_error = "bad magic"
		return false
	if version > SAVE_VERSION:
		last_error = "save version %d is newer than this build (%d)" % [version, SAVE_VERSION]
		return false
	var size: int = file.get_32()
	var payload: PackedByteArray = file.get_buffer(size)
	file.close()
	var data: Variant = bytes_to_var(payload)
	if not (data is Dictionary):
		last_error = "corrupt payload"
		return false
	var dict: Dictionary = data
	apply_state(dict)

	last_error = ""
	return true


func has_slot(p_slot: String) -> bool:
	return FileAccess.file_exists(_path_for(p_slot))


func collect_state() -> Dictionary:
	return {
		"clock": {"day": GameClock.day, "minute": GameClock.minute},
		"rng": Rng.snapshot(),
		"game_state": GameState.to_dict(),
	}


func apply_state(p_data: Dictionary) -> void:
	var clock: Dictionary = Rng.as_dict(p_data.get("clock", {}))
	GameClock.day = GameState._as_int(clock.get("day", 0))
	GameClock.minute = GameState._as_int(clock.get("minute", 0))
	Rng.restore(Rng.as_dict(p_data.get("rng", {})))
	GameState.from_dict(Rng.as_dict(p_data.get("game_state", {})))


func _path_for(p_slot: String) -> String:
	return "%s/%s.sav" % [SAVE_DIR, p_slot]
