# 代码语言
## GimbalYaw
Y轴是现实中的竖直方向，这个模块可以实现绕Y轴转动，相当于左右看。
## Mesh
### CylinderMesh 圆柱体
- top radius 顶部半径
- bottom radius 底部半径
- height 高度
### rotation
`event.rotation.y` 鼠标向下移是正数，向上移是负数
`pitch.rotation.x` ，X正方向旋转是低头向下，想要向下转动摄像头需要让这个值变大。
也就是说，只要把鼠标输入的 `event.rotation.y` 乘上sensitivity加到 `pitch.rotation.x` 里面就好了。
### margin
物理外扩距离。

## @onready var
场景加载完毕后获取子节点的调用，可从左侧文件树中查看
## Input.get_vector 
获得键盘的输入，映射成一个2D的向量
## global_basis
包含三个向量的基座，表示物体自身的坐标系和指向哪里。
`global` 表示全局坐标，相对于整个世界的原点。
`-global_basis.z` 表示机器的前方

## _ unhandled_input 
 一个 Godot 系统自带的函数。
 Godot 处理输入的流程是**有优先级**的，就像公司里处理投诉一样：
- **UI 优先**：如果有 UI（比如设置菜单的按钮），UI 会先拦截鼠标点击。
-  **`_input()` 其次**：如果 UI 没有拦截，会传递给 `_input()`。
- **`_unhandled_input()` 兜底**：如果 `_input()` 没管，最后才会传到 `_unhandled_input()`。

对于射击游戏来说，**用 `_unhandled_input` 是最完美的**。因为当你以后在屏幕上加 HUD、设置菜单时，你点击按钮就不会导致底层的枪管乱转或开枪。

### clamp
限制俯仰视角角度(,deg_to_rad(),deg_to_rad())

## Area3D
声明这是一个监测区域而不是物理体

## `PhysicsRayQueryParameters3D.create`
拉出一条物理直线由起点指向终点，能检测这个射线经过的目标，是扫掠检测的核心角色。

## is_action_(_ just _ ) _ pressed
区别：加了just之后就只在按下的一瞬间检测。

## extends
决定脚本挂载在哪个类型的节点上，具有该类型的能力，属性等。（例如：characterBody3D,Node3D)

## control
所有 UI 节点的基类，定义了一个矩形区域，提供了做UI的基础能力：
- **位置与大小**（Position, Size）
    
- **锚点与边距**（Anchors, Margins，用来做屏幕适配）
    
- **鼠标交互**（Mouse Filter，决定鼠标能不能穿过它）
    
- **焦点系统**（获得/失去焦点）
## Panel
用来在界面上画出一个实心的方块背景,带颜色的背景板或者

## .poll()
调用 `connect_to_host` 的时候，其会立刻返回，在后台默默连接。
`.poll()` 相当于去访问连接状态信息然后更新 `get_status()` 的返回值，例如，从 `STATUS_CONNECTING` 变成 `STATUS_CONNECTED`。

## .append()
把当前的东西加到某一个 Array 的后面，相当于C++ vector里面的push_back

## .emit(xxx)
用于对 signal 类的处理，其他人可以监听这个发送的 signal 信号

## floori,ceili
向下取整和向上取整
## get_viewport()
获取当前节点所在的视口，通常为主游戏窗口
## set_input_as_handle()
标记该输入事件为已处理，按键传统（需要设计节点树的层次）

## layout.grow
#### 1. 水平方向：`grow_horizontal`

|参数值|检查器显示|含义（固定哪边，向哪边变长）|
|---|---|---|
|**0**|**Begin** (或 **Left**)|**固定右边界**，向左生长。|
|**1**|**End** (或 **Right**)|**固定左边界**，向右生长。|
|**2**|**Both**|**固定中心**，向左右两边同时生长。|

#### 2. 垂直方向：`grow_vertical`

|参数值|检查器显示|含义（固定哪边，向哪边变长）|
|---|---|---|
|**0**|**Begin** (或 **Top**)|**固定下边界**，向上生长。|
|**1**|**End** (或 **Bottom**)|**固定上边界**，向下生长。|
|**2**|**Both**|**固定中心**，向上下两边同时生长。|
## find_child("",0/1,0/1)
第一个双引号支持模糊搜索，用 `*` 来模糊，第二个参数表示是否开启递归查找，第三个参数表示是否只查找属于当前场景的节点
## roundf
对浮点数四舍五入

## get(key,default)
	return key?key:default
# 关键部分
## 非阻塞发送
`put_partial_data`：缓冲区如果能接受的话，就发送数据，这样能保证程序正常进行。
## 引用传递
例如，a=StyleBoxFlat.new，创建一个 新的容器，然后 add_theme_stylebox_override("target",container)
## 内存与释放
子弹多次创建未销毁会积累卡死程序，由于子弹弹速很快，可以+时间生命检测。
## 能量核心组件
face_1是红色，face_2是蓝色
- target_i_legging：激活状态的过渡灯条
- target_i_padding：大能量机关已激活状态的靶边缘
- target_i_completed：激活状态的靶心
- target_i_legging_progress：正在激活状态的流动状过渡灯条
- target_i_active：大小能量机关的激活中标靶形状
- target_i_activated：小能量机关已激活后靶边缘
- R_padding：中心R标的底座
- R_powered：中心R标非未激活状态的点亮状态
- R_unpowered：中心R标未激活状态的非点亮状态
- 