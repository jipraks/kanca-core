class_name TrayItem
extends Draggable

## One item the child has put on the counter tray (PLAN.md §8.1.6).
##
## Every tray item can be picked back up and dragged off again. Undo has to be
## available at all times — a child who cannot take something back is stuck, and
## being stuck is the thing this design refuses to allow (§3.2).

const TOUCH_SIZE := Vector3(0.38, 0.4, 0.3)

var item_id: String = ""

var _display: Node3D = null


func setup(id: String) -> void:
	item_id = id
	name = "TrayItem_%s" % id

	add_touch_box(TOUCH_SIZE, Vector3(0.0, 0.18, 0.0))

	_display = PlaceholderFactory.build_item_visual(item_id)
	_display.name = "Display"
	add_child(_display)


func get_drag_payload() -> String:
	return item_id


## Settle animation when it lands on the tray.
func play_drop() -> void:
	if _display == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_display, "scale", Vector3(1.2, 0.8, 1.2), 0.07)
	tween.tween_property(_display, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK)


## Slides to a new spot when the tray re-flows around it.
func move_to(target: Vector3, duration: float = 0.14) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", target, duration).set_trans(Tween.TRANS_SINE)
