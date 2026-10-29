class_name DifficultyTable
extends Resource
## Data-driven difficulty table (generated from data_src/difficulty.csv).

@export var profiles: Array[DifficultyProfile] = []


func get_by_id(p_id: String) -> DifficultyProfile:
	for profile: DifficultyProfile in profiles:
		if profile.id == p_id:
			return profile
	return null
