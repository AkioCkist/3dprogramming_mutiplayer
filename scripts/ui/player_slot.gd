extends Panel
class_name PlayerSlotPanel

## Reflect player name
@export var player_name := "Player":
	set(value):
		%PlayerName.text = value
		player_name = value

## Reflect player color
@export var player_color := Color.WHITE:
	set(value):
		%PlayerName.modulate = value
		player_color = value

## Store player network ID
var player_id: int = 0
