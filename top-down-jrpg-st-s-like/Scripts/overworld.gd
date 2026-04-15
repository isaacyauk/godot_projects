extends Node2D

func _ready() -> void:
	if GameState.world_map_position != Vector2.ZERO:
		$PlayerCharacter.position = GameState.world_map_position
