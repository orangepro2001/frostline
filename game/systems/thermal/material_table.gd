class_name MaterialTable
extends Resource
## Data-driven material table (generated from data_src/materials.csv by
## tools/tablegen; never edit game/data/*.tres by hand).

@export var materials: Array[MaterialDef] = []


func get_by_id(p_id: int) -> MaterialDef:
	for material: MaterialDef in materials:
		if material.id == p_id:
			return material
	return null


func count() -> int:
	return materials.size()
