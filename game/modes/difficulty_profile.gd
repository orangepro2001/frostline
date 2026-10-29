class_name DifficultyProfile
extends Resource
## One row of data_src/difficulty.csv.
##
## Difficulty is a set of parameters, not a multiplier on top of one number:
## the prototype reads all of these from here so that adding "extreme night"
## is a data change, not a code change.

@export var id: String = ""
@export var display_name: String = ""
@export_float_0_5 var cooling_rate_mult: float = 1.0
@export_float_0_5 var resource_mult: float = 1.0
@export var forecast_error_c: float = 1.5
@export var event_frequency_mult: float = 1.0
## narrative | standard | harsh | polar_night
@export var save_mode: String = "standard"
