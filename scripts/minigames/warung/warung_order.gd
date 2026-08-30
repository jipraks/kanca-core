class_name WarungOrder
extends RefCounted

## What one customer asks for (PLAN.md §8.1).
##
## Kept apart from the mini-game scene on purpose: generating an order, speaking
## it, drawing it on the card and checking it are the whole of the learning
## content, and all four should be testable without a 3D scene in the way.

## item_id -> count
var counts: Dictionary = {}

## Which customer is asking, e.g. "cust_ibu". Determines the voice set (§8.1).
var voice_prefix: String = ""


static func create(order_counts: Dictionary, prefix: String) -> WarungOrder:
	var order: WarungOrder = WarungOrder.new()
	order.counts = order_counts.duplicate()
	order.voice_prefix = prefix
	return order


## Builds an order from a level definition. `available` is what is actually on the
## shelf this session, so a customer can never ask for something not stocked.
static func generate(level: Dictionary, available: Array[String], prefix: String, rng: RandomNumberGenerator) -> WarungOrder:
	var pool: Array[String] = available.duplicate()
	if pool.is_empty():
		Log.e("No items available to build an order from", "WarungOrder")
		return WarungOrder.create({"pisang": 1}, prefix)

	var range_raw: Array = level.get("quantity_range", [1, 3]) as Array
	var low: int = maxi(1, int(range_raw[0]) if range_raw.size() > 0 else 1)
	var high: int = maxi(low, int(range_raw[1]) if range_raw.size() > 1 else low)

	var wanted_types: int = mini(maxi(1, int(level.get("item_types_per_order", 1))), pool.size())

	# Shuffle then take, so the same item never appears twice in one order — two
	# rows of the same fruit on the order card would just be confusing.
	RngUtil.shuffle(pool, rng)

	var order_counts: Dictionary = {}
	for i: int in range(wanted_types):
		order_counts[pool[i]] = rng.randi_range(low, high)

	return WarungOrder.create(order_counts, prefix)


## Rows for the order card: icon, dots, numeral (§8.1.4, §3.1).
func to_card_entries() -> Array:
	var entries: Array = []
	for item_id: String in counts:
		entries.append({"item_id": item_id, "count": int(counts[item_id])})
	return entries


## Voice parts, assembled rather than recorded whole (§10.3):
##   [cust_X_open] + "tiga" "pisang" + [cust_X_and] + "satu" "roti" + [cust_X_close]
func to_voice_parts() -> Array[String]:
	var groups: Array = []
	for item_id: String in counts:
		groups.append([
			"num_%d" % int(counts[item_id]),
			ContentDB.get_item_voice_id(item_id),
		])

	var parts: Array[String] = ["%s_open" % voice_prefix]
	parts.append_array(VoiceBank.join_groups(groups, "%s_and" % voice_prefix))
	parts.append("%s_close" % voice_prefix)
	return parts


## True when the tray holds exactly the order: right items, right counts, nothing
## extra. Anything else is simply "not yet" — never a loss (§3.2).
func is_satisfied_by(tray_counts: Dictionary) -> bool:
	for item_id: String in counts:
		if int(tray_counts.get(item_id, 0)) != int(counts[item_id]):
			return false
	for item_id: String in tray_counts:
		if int(tray_counts[item_id]) > 0 and not counts.has(item_id):
			return false
	return true


## True when the tray holds more than was asked for, or something that was not
## asked for at all. Distinguishing "too few" from "too many" matters: glowing the
## shelf helps a child who needs another banana and does nothing for a child who
## already has one too many, who needs to be pointed back at the count (§8.1.8).
func has_surplus(tray_counts: Dictionary) -> bool:
	for item_id: String in tray_counts:
		var held: int = int(tray_counts[item_id])
		if held > int(counts.get(item_id, 0)):
			return true
	return false


func get_item_ids() -> Array[String]:
	var ids: Array[String] = []
	for item_id: String in counts:
		ids.append(item_id)
	return ids


func get_total_count() -> int:
	var total: int = 0
	for item_id: String in counts:
		total += int(counts[item_id])
	return total


func describe() -> String:
	return "%s wants %s" % [voice_prefix, counts]
