# 前哨站飞镖引导灯分离（ON / OFF）

## 规则依据

《RoboMaster 2026 机甲大师超级对抗赛比赛规则手册 V2.2.0》5.5.1：

> 在前哨站存活的情况下，前哨站的飞镖引导灯常亮，基地的飞镖引导灯熄灭；
> 前哨站被击毁时，前哨站的飞镖引导灯熄灭，基地的飞镖引导灯点亮。

前哨站的飞镖引导灯是 **520 nm 绿色可见光**，在模型里对应材质 `mat_25`。

## 原模型的问题

`assets/OUTPOST.glb` 里绿色引导灯不是独立节点，而是被并进了两个大的多材质网格：

| 网格节点 | primitive | 材质 | 说明 |
|---|---|---|---|
| `0009_1_7.003` | 1 | `mat_25`（绿色自发光） | OUTPOST_1 的引导灯 |
| `0009_1_049` | 0 | `mat_25`（绿色自发光） | OUTPOST_2 的引导灯 |

所以不能在 Godot 里直接 `hide()` 引导灯，只能把整块网格一起隐藏。

## 生成的新文件

`assets/OUTPOST_GUIDE_LIGHT.glb`

- 原两个网格里的绿色 primitive 已移除；
- 新增 4 个独立节点：

```
OUTPOST_1/0009_1_7_003/GUIDE_LIGHT_ON_1
OUTPOST_1/0009_1_7_003/GUIDE_LIGHT_OFF_1
OUTPOST_2/0009_1_049/GUIDE_LIGHT_ON_2
OUTPOST_2/0009_1_049/GUIDE_LIGHT_OFF_2
```

| 节点 | 材质 | 说明 |
|---|---|---|
| `GUIDE_LIGHT_ON_*` | `mat_25`（绿色自发光 520 nm） | 存活状态，常亮 |
| `GUIDE_LIGHT_OFF_*` | `GUIDE_LIGHT_OFF`（暗绿色、无自发光） | 被击毁状态，熄灯 |

`GUIDE_LIGHT_OFF_*` 以自身几何中心缩小到 **97%**，藏在 `GUIDE_LIGHT_ON_*` 内部：

- 默认 ON 可见，OFF 被 ON 挡住，看起来就是“灯亮”；
- 销毁时 `GUIDE_LIGHT_ON_*.hide()`，OFF 就露出来，看起来就是“灯灭”。

这样不需要在场景里手动摆两套模型，也不会出现两层灯重叠闪烁。

## 在 main.tscn 中使用

当前 `main.tscn` 的 `OUTPOST` 实例引用的是 `assets/OUTPOST.glb`：

```
[ext_resource type="PackedScene" uid="uid://c654sgdcu6177" path="res://assets/OUTPOST.glb" id="3_h2yge"]
```

改成：

```
[ext_resource type="PackedScene" uid="uid://bdg6blqh08h83" path="res://assets/OUTPOST_GUIDE_LIGHT.glb" id="3_h2yge"]
```

> 新模型的节点路径和原模型一致，`main.tscn` 里已有的装甲 `Area3D`、`B_*` 可见性等覆盖理论上会保留。
> 改之前建议先备份 `main.tscn`；如果覆盖丢失，重新把装甲 `Area3D` 拖回去即可。

如果不想改 ext_resource，也可以把新 GLB 作为 `OUTPOST` 的兄弟节点实例，但**必须同时隐藏旧 `OUTPOST` 里的绿色 primitive**，否则旧的绿灯还会亮。所以推荐直接替换 ext_resource。

## Outpost.gd 接法

```gdscript
@onready var guide_on_1 = $"空物体/空物体_011/OUTPOST_1/0009_1_7_003/GUIDE_LIGHT_ON_1"
@onready var guide_off_1 = $"空物体/空物体_011/OUTPOST_1/0009_1_7_003/GUIDE_LIGHT_OFF_1"
@onready var guide_on_2 = $"空物体/空物体_011/OUTPOST_2/0009_1_049/GUIDE_LIGHT_ON_2"
@onready var guide_off_2 = $"空物体/空物体_011/OUTPOST_2/0009_1_049/GUIDE_LIGHT_OFF_2"

func _ready() -> void:
	# 默认：亮灯
	_set_guide_light(true)

func _set_guide_light(on: bool) -> void:
	guide_on_1.visible = on
	guide_on_2.visible = on
	# OFF 节点可以一直可见（它藏在 ON 里面），
	# 也可以显式控制；两种都可以。
	guide_off_1.visible = not on
	guide_off_2.visible = not on

func _on_destroyed() -> void:
	...
	_set_guide_light(false)   # 前哨站被击毁，引导灯熄灭
```

如果只想控制当前这一侧的前哨站，保留 `_1` 或 `_2` 其中一组即可。

## 重新生成

```bash
cd /home/chenwx/project
python3 tools/split_outpost_guide_light.py
# 指定输出：
python3 tools/split_outpost_guide_light.py --output assets/OUTPOST_GUIDE_LIGHT.glb
```

脚本只读取 `assets/OUTPOST.glb`，不会修改原件。

## 预览

- `blender/outpost_guide_previews/preview_guide_on.png`
- `blender/outpost_guide_previews/preview_guide_off.png`
