class_name FuelTable
extends Resource
## Data-driven fuel table (generated from data_src/fuels.csv).

@export var fuels: Array[FuelDef] = []


func get_by_id(p_id: String) -> FuelDef:
	for fuel: FuelDef in fuels:
		if fuel.id == p_id:
			return fuel
	return null
