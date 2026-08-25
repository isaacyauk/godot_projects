class_name EnemyAction
extends Node

enum Type {CONDITIONAL, CHANCE_BASED}

## How far right of the target an attacking enemy stops when it lunges in.
##
## Sprites are 16px at scale 3, so the two of them together occupy 48px of
## centre-to-centre distance before they overlap. 80 leaves a 32px gap -- close
## enough to read as a hit, far enough that the sprites never intersect.
##
## This was 32 when the viewport was 256x144 and sprites drew at scale 1. If you
## change the viewport or the sprite scale again, this is the number to retune.
const LUNGE_OFFSET := 80.0

@export var intent: Intent
@export var sound: AudioStream
@export var type: Type
@export_range(0.0, 10.0) var chance_weight := 0.0

@onready var accumulated_weight := 0.0

var enemy: BattleEnemy
var target: Node2D


func is_performable() -> bool:
	return false


func perform_action() -> void:
	pass


func update_intent_text() -> void:
	intent.current_text = intent.base_text
