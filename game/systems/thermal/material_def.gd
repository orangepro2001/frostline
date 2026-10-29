class_name MaterialDef
extends Resource
## One row of data_src/materials.csv.
##
## The coefficients are lumped per 0.5 m grid cell (see
## native/src/thermal/thermal_core.h): conductance is W/K per shared edge and
## capacity is J/K for the whole cell.

@export var id: int = 0
@export var id_name: String = ""
@export var conductance_w_per_k: float = 0.0
@export var heat_capacity_j_per_k: float = 1.0
@export var surface_coef_w_per_k: float = 0.0
@export var blocks_wind: bool = false
