class_name FuelDef
extends Resource
## One row of data_src/fuels.csv.

@export var id: String = ""
@export var display_name: String = ""
@export var heat_value_kj_per_kg: float = 0.0
@export var mass_kg: float = 0.0
@export var burn_minutes: float = 0.0
@export var ignition_temp_c: float = 0.0
@export var note: String = ""


## Total energy released by one unit of this fuel, in kilojoules.
func total_energy_kj() -> float:
	return heat_value_kj_per_kg * mass_kg
