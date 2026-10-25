# 五等分灯臂（大能量机关激活进度）

原 `POWER_COL.glb` 每根灯臂的中部灯条由 `LEGGING_1 / LEGGING_2 / LEGGING_3` 三段组成。
本工具把同一段灯条表面按长度重新裁成 **5 等分**，生成独立模型，**不修改任何原件**。

## 生成的文件

| 文件 | 内容 |
|---|---|
| `assets/POWER_LEGGING5_FACE2.glb` | 蓝方 5 根灯臂，每根 5 段，材质 `BLUE_EMISSION.001` |
| `assets/POWER_LEGGING5_FACE1.glb` | 红方 5 根灯臂，每根 5 段，材质 `RED_EMISSION.001` |
| `tools/make_legging5.py` | 生成脚本，只读取 `blender/POWER_COL.glb` |
| `blender/legging5_previews/` | 预览图（全部点亮 / 3/5 进度） |

原件 `assets/POWER.glb`、`blender/POWER_COL.glb`、`main.tscn`、`scripts/power.gd` 均未改动。

## 几何数据

- 灯条总长：约 **386～388 mm**（各臂略有差异）
- 每段长度：约 **77.1～77.7 mm**
- 5 段首尾相接，切面处在同一平面内（间隙 0）
- 灯条宽度、厚度、所在表面均直接沿用原 `LEGGING_1/2/3` 的三角形
- 材质直接复制 `blender/POWER_COL.glb` 里 `LEGGING_1` 实际使用的材质
  （`BLUE_EMISSION.001` / `RED_EMISSION.001`，没有 `KHR_materials_emissive_strength`），
  与场景自带三段灯条完全一致（emission energy = 1.0）
- 默认沿靶面法线抬高 **0.5 mm**，避免与旧三段重叠时 Z-fighting；可用 `--offset 0` 取消

## 在 main.tscn 中使用

1. 选中 `POWER_COL` → 右键“可编辑子节点”（已开启）。
2. 把 `FACE_2` 下原有的 `FACE_2_TARGET_1..5_LEGGING_1/2/3` 取消 `Visible`（保留原件，只做覆盖）。
   - `LEGGING_PROGRESSING` 是流动箭头叠加层，可保留。
3. 把 `assets/POWER_LEGGING5_FACE2.glb` 拖到 `POWER_COL/ROOT/FACE_2` 下，Transform 保持 identity。
4. 蓝方用 `FACE2`，红方用 `FACE1`（挂在 `FACE_1` 下）。

节点结构：

```
FACE_2
└─ POWER_LEGGING5_FACE2      (glTF 根)
   └─ POWER_LEGGING5_FACE2   (Godot 导入包装节点)
      ├─ TARGET_1
      │  ├─ TARGET_1_SEG_1
      │  ├─ TARGET_1_SEG_2
      │  ├─ TARGET_1_SEG_3
      │  ├─ TARGET_1_SEG_4
      │  └─ TARGET_1_SEG_5
      ├─ TARGET_2 ...
      └─ TARGET_5 ...
```

## 进度控制示例

大能量机关激活到第 n 组时，显示每根灯臂的前 n/5 段：

```gdscript
@onready var face_2 = $FACE_2

var legging5: Array = []   # legging5[k][s]

func _ready() -> void:
	for k in range(1, 6):
		var row: Array = []
		for s in range(1, 6):
			row.append(face_2.find_child("TARGET_%d_SEG_%d" % [k, s], true, false))
		legging5.append(row)
	set_rune_progress(0)

# n = 0..5
func set_rune_progress(n: int) -> void:
	for k in range(5):
		for s in range(5):
			var node = legging5[k][s]
			if node:
				node.visible = s < n
```

- 未激活 / IDLE：`set_rune_progress(0)`
- 已激活 1 组：`set_rune_progress(1)`
- 已激活 3 组：`set_rune_progress(3)`
- 全部 5 组：`set_rune_progress(5)`

## 重新生成

```bash
cd /home/chenwx/project
python3 tools/make_legging5.py
# 不抬高：
python3 tools/make_legging5.py --offset 0
```

脚本按每根灯臂的径向方向取 `LEGGING_1/2/3` 的并集长度，等分成 5 段后对各三角形做平面裁剪，
因此切面不是简单套一个 Box，而是严格沿原曲面的等分线切开。
