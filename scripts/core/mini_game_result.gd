class_name MiniGameResult
extends Resource

## What a mini-game hands back when a session ends (PLAN.md §6.2).
##
## The hub consumes this to update GameState — a mini-game never writes to
## GameState directly, which keeps "what happened" and "what it means for
## progress" in separate places.
##
## `items_consumed` is one field beyond the three named in §6.2. Dapur spends
## ingredients, and expressing that as a negative count inside `items_produced`
## would have been worse than an explicit field.

@export var game_id: String = ""
@export var level_index: int = 1
@export var rounds_completed: int = 0
@export var coins_earned: int = 0

## item_id -> count added to the inventory.
@export var items_produced: Dictionary = {}

## item_id -> count removed from the inventory.
@export var items_consumed: Dictionary = {}


static func create(game_id_value: String, level_index_value: int) -> MiniGameResult:
	var result: MiniGameResult = MiniGameResult.new()
	result.game_id = game_id_value
	result.level_index = level_index_value
	return result


func add_produced(item_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	items_produced[item_id] = int(items_produced.get(item_id, 0)) + count


func add_consumed(item_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	items_consumed[item_id] = int(items_consumed.get(item_id, 0)) + count


func describe() -> String:
	return "%s L%d: %d rounds, %d coins, produced %s, consumed %s" % [
		game_id, level_index, rounds_completed, coins_earned, items_produced, items_consumed,
	]
