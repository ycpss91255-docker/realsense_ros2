**[English](CAMERA.md)** | **[繁體中文](CAMERA.zh-TW.md)** | **[简体中文](CAMERA.zh-CN.md)** | **[日本語](CAMERA.ja.md)**

# 使用物理 RealSense 相机进行测试

`TEST.md` 涵盖了构建时的自动化冒烟测试（smoke test）。本页则是通过容器验证真实 Intel RealSense 相机的手动流程。

容器以 `privileged`（特权模式）运行并挂载了 `/dev`，因此可以看到主机上的 USB 设备。该镜像内置了 ROS 2 封装（`realsense2_camera`）以及 librealsense SDK 的 CLI 工具（`rs-enumerate-devices`、`realsense-viewer`、`rs-*`）。

## 0. 确认主机能看到相机

```bash
lsusb | grep -i intel    # e.g. Intel RealSense (8086:0b07)
```

如果没有任何显示：请使用支持数据传输的线缆，优先选择 USB 3.0 端口，并确保没有其他进程占用相机。

## 1. 进入容器

```bash
just build    # first time, or after changes
just run      # interactive shell; ROS is auto-sourced (via ~/.bashrc.d)
```

## 2. 快速检查 —— 相机是否被检测到（SDK 层级）

```bash
rs-enumerate-devices        # lists model / serial / firmware
rs-enumerate-devices -s     # short form
```

通过这一步即可确认相机、驱动和 USB 权限都正常工作。

## 3. ROS 2 集成（本仓库的主要用例）

启动相机节点：

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py
```

在进入同一容器的第二个 shell 中（从主机执行 `just exec bash`）：

```bash
ros2 topic list                                       # expect /camera/... topics
ros2 topic hz /camera/camera/depth/image_rect_raw     # confirm streaming (Hz)
ros2 topic echo /camera/camera/color/image_raw --once
```

交互式 shell（`just run` 和 `just exec bash`）会通过 `~/.bashrc.d` 自动 source ROS。只有非交互式的 `just exec <cmd>`（不会读取 `.bashrc`）才需要先执行 `source /opt/ros/${ROS_DISTRO}/setup.bash`。

## 4. 可视化（GUI）

```bash
realsense-viewer    # librealsense GUI
rviz2               # ROS 2 visualization
```

devel 镜像安装了 `ros-${ROS_DISTRO}-desktop`，因此 `realsense-viewer` 和 `rviz2`（以及它们所需的 Qt/OpenGL/X 栈）都可用。容器的 GUI 模式 + X11 挂载会负责处理显示。

## 5. 芯片内标定（On-chip calibration，可选）

D400 系列可以从普通场景中重新标定其立体深度参数 —— 无需标定标靶。深度是通过对两个 IR 相机进行立体匹配（stereo-matching）计算得到的，而出厂参数会随时间漂移（温度、机械冲击、运输、老化），表现为额外的深度噪声、平面不平整或边缘噪声。芯片内标定可以纠正这种漂移。它独立于固件更新：固件更新改变的是相机的固件版本，而标定调整的是深度测量参数。在固件更新后运行一次是很好的健全性检查（sanity check）。

从 `realsense-viewer` 中运行：打开深度传感器的 **More** 菜单并选择 **On-Chip Calibration**，然后对准一个合适的场景并按下标定。

场景要求：

- 有纹理，距离 **0.5--2 m**，且拥有 **> 50% 的有效深度像素**（避免空白墙面、高反光表面或过远的物体）。
- "White wall" 子模式是例外：**仅**在对准平坦白墙且开启 IR 投影器时使用。

### 解读健康检查（health-check）分数

标定后，viewer 会报告一个健康检查分数。**关键在于它的绝对值** —— 符号只表示修正的方向，并不代表"更好"或"更差"。viewer 的 `if >0.25` 指引意思是 `|health| > 0.25`。

| `|health|` | 含义 | 操作 |
|---|---|---|
| 接近 0（< 0.25） | 已经标定良好；本次运行几乎没有改变任何东西 | 无需应用 |
| >= 0.25 | 存在明显漂移；此修正有意义 | 应用新的标定 |
| 较大（例如 > 0.75） | 严重漂移，或场景不合适 | 应用后，在更好的场景上重新运行以确认 |

因此，`-0.45` 的分数即 `|0.45| > 0.25`：检测到了有意义的漂移，建议应用新的标定。负号**不**代表标定失败。应用后，请在 `realsense-viewer` 中检查深度图像（平面更平整、噪声更少）；为保险起见，可在不同场景上重新运行 —— 分数重新接近 0 表示标定已经收敛。

## 疑难排解

| 症状 | 检查项 |
|---|---|
| `No device detected` | 主机 `lsusb` 能看到相机吗？线缆 / USB 3.0 端口 / 未被其他进程占用。容器为 `privileged`（默认）。 |
| `ros2: command not found` | 交互式 shell 会通过 `~/.bashrc.d` 自动 source ROS。只有非交互式的 `just exec <cmd>` 才需要先执行 `source /opt/ros/${ROS_DISTRO}/setup.bash`。 |
| `realsense-viewer` 无法打开（X11） | 主机有 X server；`echo $DISPLAY` 已设置；`config/docker/setup.conf` 中 GUI 模式为 `[gui] mode = auto`。 |
