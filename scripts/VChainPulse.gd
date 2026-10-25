extends Node3D

## 单个 V 形发光脉冲。
##
## 挂载位置：
##   LEGGING_PROGRESSING/VChainPulses/V01 ...
##
## 默认路径已按 FACE_2_TARGET_1_LEGGING_PROGRESSING 的局部平面设置：
##   长轴方向约为本地 (1, 0, -1)
##   V 平面由 VShape 节点负责旋转对齐。
##
## 多个 VChainPulse 使用相同 duration，通过 phase 错开位置，
## 形成“一串 V 形整体沿灯条移动”的效果。

# +d 是靠近机构的一端，-d 是远端
@export var travel_start: Vector3 = Vector3(0.10, 0.0, -0.10)
@export var travel_end: Vector3 = Vector3(-0.10, 0.0, 0.10)

## 走得比之前快：3.0 → 1.2 秒走完整段。
@export_range(0.05, 10.0, 0.05)
var duration: float = 1.2

@export_range(0.0, 1.0, 0.001)
var phase: float = 0.0

@export var loop: bool = true

var _tween: Tween


func _ready() -> void:
	position = travel_start
	_start_tween()


## 重新开始动画，例如靶形重新出现时可以调用。
func restart() -> void:
	_start_tween()


func _start_tween() -> void:
	if _tween:
		_tween.kill()

	position = travel_start

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_LINEAR)

	if loop:
		_tween.set_loops()
	else:
		_tween.set_loops(1)

	# 用 phase 错开多个 V 的出发时间
	if phase > 0.0:
		_tween.tween_interval(duration * phase)

	_tween.tween_property(
		self,
		"position",
		travel_end,
		duration
	).from(travel_start)
