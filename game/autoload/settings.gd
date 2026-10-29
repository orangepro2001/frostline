extends Node
## User-facing options. Kept tiny on purpose: the prototype only needs the
## thermal overlay toggle and the audio levels.

signal changed

var show_thermal_overlay: bool = false
var master_volume_db: float = 0.0


func set_thermal_overlay(p_enabled: bool) -> void:
	if show_thermal_overlay == p_enabled:
		return
	show_thermal_overlay = p_enabled
	changed.emit()


func toggle_thermal_overlay() -> void:
	set_thermal_overlay(not show_thermal_overlay)
