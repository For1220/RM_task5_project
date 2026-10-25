# RoboMaster 2026 仿真客户端
验收视频仅仅演示大致机制，具体细节请见提交的可执行文件
# TCP 图传与相机标准靠近说明

```


scripts/FrameSender.gd
const SEND_HZ: float = 30.0
控制图像发送目标帧率

分辨率在场景文件中：

scenes/infantry.tscn
位置：
[node name="VisionViewport" type="SubViewport" parent="GimbalYaw/GimbalPitch"]
size = Vector2i(640, 360)
render_target_update_mode = 4
```

验收时可修改以靠齐标准，这里由于不知道相机标准是什么于是默认 30HZ+640x360分辨率

# git 说明
第一次上传采用 git LFS 的方法
需要
```
git lfs install
git clone git@github.com:For1220/RM_task5_project.git
cd RM_task5_project
git lfs pull
```
第二次上传时已正确配置 release
# 操作表
- WASD 控制移动
- SPACE/空格 控制跳跃
- 鼠标左键控制瞄准
- R 单击进入暂停/重置比赛页面，在这个页面可以点击重新开始比赛或继续比赛
- P 控制能量机关激活，在有次数的情况下单击可以进入能量机关激活页面
- C 用于切换控制对象，可控制红蓝小兵，点击或按1选择蓝色步兵，按2选择红色步兵
- F 用于使用飞镖，单击唤出飞镖UI，点击可选择飞镖发送模式

# 基础运动说明

瞄准之后单击左键会自动计算重力发射子弹
跳跃速度已经限制为 2.5，经测验不会达到步兵不可达到的敌方

# 局内机制实现

## 前哨站
前哨站中部标靶可旋转，前哨站存活时基地引导灯灭，前哨站引导灯亮。
前哨站被摧毁后在游戏开始时间五分钟内可以重建，步兵占领相应增益点即可。

## 基地
前哨站摧毁之前保持无敌，摧毁后无敌取消。
特定条件下飞镖命中会进入护甲展开形体。

## 能量核心
按 2026赛季 V2.2.0（20260807）规则完成激活后，会获得相应的增益buff，
增益 buff 已做可视化实现。

# 比赛真实性：
- 比例均按照 1：1 的尺寸复现
- 步兵的物理碰撞盒严格小于规则中的步兵最大展开尺寸，且贴图运动位置在碰撞盒之内
- 视觉识别贴图完成配置
- 引导灯状态正确
- 经验机制正确，步兵可以正确获取经验并升级

# 比赛前端 UI
- 小地图上有地标显示，计时器状态正确，整个项目统一调用一个时间来源，HUD 均使用 Snapshot 快照更新
- 步兵朝向与小地图箭头指向匹配
- 配置通知栏目，大部分地图事件均有通知，一定时间内没有新通知，通知栏会隐藏

# 部分验收参考：

- 步兵受攻击有血量变化提示
- 按 F 使用飞镖验收基地护甲展开
- 切换控制角色验收伤害能否正常显示

# 本地通信

## 启动
1. python3 receiver.py
2. Godot F5 运行 main.tscn

在release内
也可以使用：

```bash
./run.sh
```
在release内输入上面指令想要看到py窗口只需新建一个就行。

## 连接状态检查
在 godot 窗口的中央计时器下有本地网络连接状态显示

## 支持
numpy>=1.26
opencv-python>=4.9

## 端口
- 9000：图像通道，Godot -> Python
- 9001：状态通道，Godot -> Python

## 图像帧格式
| 字段 | 类型 | 字节 | 说明 |
|---|---|---|---|
| magic | char[4] | 4 | RMV1 |
| seq | uint32 | 4 | 帧号 |
| ts_us | uint64 | 8 | Unix 微秒 |
| size | uint32 | 4 | JPEG 字节数 |
| payload | bytes | size | JPEG |

端序：大端（big-endian）。

## 状态 JSON
仅仅为一个示例，具体参数请阅读程序

```json
		out.append({
			"id": id,
			"team": parts[0],
			"kind": parts[1],
			"x": map_pos.x,
			"z": map_pos.z,
			"yaw": node3d.global_rotation.y,
			"hp": int(n.get("current_hp")),
			"max_hp": int(n.get("max_hp")),
			"alive": not bool(n.get("is_destroyed")),
			"is_rot": bool(n.get("is_rot")) if n.get("is_rot") != null else false,
			"is_shielded": bool(n.get("is_shielded")) if n.get("is_shielded") != null else false,
			"armor_open": bool(n.get("armor_open")) if n.get("armor_open") != null else false,
			"shield_hp": int(n.get("shield_hp")) if n.get("shield_hp") != null else 0,
			"is_invincible": bool(n.get("is_invincible")) if n.get("is_invincible") != null else false
		})
```

## 排查
- 黑屏：检查 VisionCamera.current、SubViewport update mode、FrameSender 是否找到 Player
- 解码失败：检查 magic、size、端序
- 变慢：降低 send_hz / jpeg_quality，检查丢帧计数

# 未实现的机制
- 等级变化之后的底盘功率，血量等还未实现变化
- 工程兑矿还未实现
- 飞镖机制未仿真，选中之后即显示命中，仅作为验收基地护甲能否正常展开的组建用
- 因为非识别的部分不追求外观，故步兵外观仅使用基本 HBOX 搭建，没有同步替换为开源文件的外观
- 步兵回血的机制没有实现，步兵的血量跟等级挂钩的配置没有实现，现阶段步兵的参数仅作为演示用
- 兑换机制完全没有实现
- 堡垒增益点未配置，仅能通过飞镖演示展开基地护甲。
- 真实环境光照
- 敌方士兵不可见时未隐藏

# 已知问题
- 检测重建的区域使用了多个 box 拼接，极限情况下可能存在压线但没有读条的情况发生
- 步兵的复活除了基础复活时间加上游戏进行中的复活时间之外，未配置兑换复活惩罚
- 灯条不能流动，原因是引用了外部文件，即使在 blender 进行处理也很难做到流动效果
- 通知栏目没有分开红蓝两队进行记录

# 参考文献
- 开源模型贴图（需要自己配置碰撞和运动规则在 godot 下）：https://github.com/Blackjack200/bevy_robomaster_simulator

- UTF-8__RoboMaster 2026 机甲大师高校系列赛机器人制作规范手册V2.0.0（20260626）.pdf

- UTF-8__RoboMaster 2026 机甲大师超级对抗赛比赛规则手册V2.2.0（20260807）.pdf

- RoboMaster_第五次培训_软件开发_官方配图版_v3.pptx

## 辅助 agent 模型
- DeepSeek V4.1 Flash 1017