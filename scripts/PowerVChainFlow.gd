extends Node

## 自动把 V-chain 流光材质挂到 POWER_COL/ROOT/FACE_1、FACE_2
## 下面所有 *LEGGING_PROGRESSING 的 MeshInstance3D 上。
##
## 挂载位置：
##   POWER_COL/ROOT/VChainFlow
##
## 注意：
## - 不控制 LEGGING_PROGRESSING 的显示/隐藏。
## - 显示/隐藏继续由 power.gd 的 _show_lit_target/_hide_lit_target 控制。
## - 只在 MatchState.phase_name() == "RUNNING" 时累加 flow_time。

@export var blue_material: ShaderMaterial
@export var red_material: ShaderMaterial

var _flow_time: float = 0.0
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	var root := get_parent()
	if root == null:
		push_warning("VChainFlow: 父节点不存在")
		return

	_apply_to_face(
		root.get_node_or_null("FACE_1"),
		red_material
	)
	_apply_to_face(
		root.get_node_or_null("FACE_2"),
		blue_material
	)

	if _materials.is_empty():
		push_warning("VChainFlow: 没有找到 LEGGING_PROGRESSING 网格，或材质未赋值")


func _process(delta: float) -> void:
	if MatchState.phase_name() != "RUNNING":
		return

	_flow_time += delta

	for material in _materials:
		if material:
			material.set_shader_parameter("flow_time", _flow_time)


func _apply_to_face(face: Node, material: ShaderMaterial) -> void:
	if face == null:
		push_warning("VChainFlow: 找不到 FACE 节点")
		return

	if material == null:
		push_warning("VChainFlow: 材质没有赋值")
		return

	material.set_shader_parameter("active", 1.0)
	material.set_shader_parameter("progress", 1.0)

	var meshes := face.find_children(
		"*LEGGING_PROGRESSING",
		"MeshInstance3D",
		true,
		false
	)

	for mesh in meshes:
		if mesh == null:
			continue

		mesh.material_override = material

		if not _materials.has(material):
			_materials.append(material)
