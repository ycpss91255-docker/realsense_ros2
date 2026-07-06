**[English](CALIBRATION.md)** | **[繁體中文](CALIBRATION.zh-TW.md)** | **[简体中文](CALIBRATION.zh-CN.md)** | **[日本語](CALIBRATION.ja.md)**

# RealSense 动态标定工具

`devel` 镜像自带 **Intel RealSense D400 Series Dynamic Calibration
Tool**（`librscalibrationtool`）。本页说明该工具的用途、它与 `CAMERA.md` 中的片上标定（on-chip calibration）有何不同，以及如何在容器中运行它。

## 它是什么（以及与片上标定有何不同）

D400 相机有两条不同的标定路径：

| | 片上标定（On-chip calibration） | 动态标定工具（Dynamic Calibration Tool） |
|---|---|---|
| 说明位置 | [CAMERA.md](CAMERA.md)（第 5 节） | 本页 |
| 运行来源 | `realsense-viewer`（内置） | `Intel.Realsense.DynamicCalibrator` |
| 是否需要标靶 | 否 —— 任何有纹理的场景即可 | 是 —— 需要打印的（或手机 App 显示的）标靶 |
| 标定内容 | 仅深度校正（立体 IR） | 校正 + 深度尺度，**外加 RGB 设备上的 RGB 外参（extrinsics）** |
| 何时使用 | 深度噪声 / 平面不平整时 | 需要一次彻底的、基于标靶的重新标定时 |

动态标定仅优化 **外参（extrinsic）** 参数 —— 即两个成像器之间的旋转与平移 —— 而非内参（焦距、主点和畸变保持出厂标定值）。根据用户指南（v2.11），它在两种工作模式（有标靶和无标靶）下提供两种标定类型；`Intel.Realsense.DynamicCalibrator` 的 GUI/CLI 运行 **有标靶（targeted）** 标定：

- **校正标定（Rectification calibration）** —— 重新对齐两个 IR 成像器的对极几何（`RotationLeftRight` / `TranslationLeftRight`）；目标与片上标定相同，但基于标靶。
- **深度尺度标定（Depth scale calibration）** —— 当光学元件发生位移时，校正绝对深度尺度。

D455 上的 Depth<->RGB：有标靶标定 **还会重新标定 RGB 外参**（`RotationLeftRGB` / `TranslationLeftRGB` —— 彩色传感器相对于左成像器的关系），适用于带有 RGB 传感器的设备（D415/D435/D455）。这正是运行时对齐所依赖的深度到彩色的关系（`realsense2_camera` 中的 `align_depth.enable:=true`，或 SDK 中的 `rs2::align`），因此重新运行它可以修复错位的 depth<->color 叠加。无标靶模式仅标定深度（左/右），**不** 标定 RGB，且仅提供 API —— GUI 标定器不提供该模式。

## 镜像提供了什么

该工具在 `devel-base` 阶段通过 Intel 官方文档记载的直接 `.deb` 方式（`dpkg -i librscalibrationtool_<ver>_amd64.deb`）安装，Intel 将该方式列为在 Ubuntu 22.04（Humble）和 24.04（Jazzy）上均受支持。这个由 Intel 托管的单一 `.deb` 是一个预编译的 amd64 二进制文件，没有 apt `Depends`；它仅链接向前兼容的标准库，因此即便 Intel 未将其编入 noble apt 仓库的索引，同一个软件包也能在 jammy 和 noble 上安装并运行。它是 **仅 amd64** 的 —— Intel 未提供 ARM64 构建，因此在 ARM64 上会跳过安装，多架构镜像仍能构建成功。

已安装版本：`librscalibrationtool` 2.13.1.0。可执行文件（均在 `PATH` 中）：

| 可执行文件 | 用途 |
|---|---|
| `Intel.Realsense.DynamicCalibrator` | 有标靶动态标定（校正 + 深度尺度 + RGB 外参），GUI 和 CLI |
| `Intel.Realsense.CustomRW` | 读取 / 写入存储在相机上的标定表 |
| `opencv_interactive-calibration` | OpenCV 交互式标定辅助工具 |

随附的 API 软件包和指南位于
`/usr/share/doc/librscalibrationtool/api/DynamicCalibrationAPI-Linux-2.13.1.0.tar.gz`。

## 前置条件

1. **主机 udev 规则。** 该工具需要对相机进行原始 USB 访问，与 SDK 其余部分的权限要求相同。在主机上安装一次即可：

   ```bash
   ./script/install_udev_rules.sh
   ```

   关于为何必须安装在主机上而不仅仅在容器内，请参见 README 中的 "RealSense udev Rules" 章节。

2. **一个标定标靶。** 要么按文档记载的比例打印官方标靶（链接见下），要么通过 Intel RealSense Dynamic Target 手机 App（iOS / Android）显示它。

3. **GUI 访问。** `devel` 镜像已包含 X11/Qt/OpenGL 栈，且容器以 GUI 模式运行，因此标定器窗口可以在主机显示器上打开。

## 运行它

```bash
just build    # first time, or after Dockerfile changes
just run      # devel container; GUI + /dev are wired up

# inside the container:
Intel.Realsense.DynamicCalibrator     # interactive GUI calibration
```

将设备放置在距标靶 **600--850 mm** 处，使标靶的条纹在视野中大致竖直；整个过程中需要相机与标靶之间的相对运动（固定其一，移动另一）。避免反光（阳光、强光、手机屏幕眩光）—— 它们会导致标靶无法被检测到。有标靶流程随后按顺序运行以下阶段（用户指南第 4.5.4 节和附录 B）：

1. **校正阶段（Rectification phase）** —— 一组带阴影的 **蓝色方块** 叠加在实时视图中央。每个蓝色方块标记了视野中仍需标靶覆盖的一个区域。缓慢移动相机（或标靶），使标靶的黑/白方块和条纹与蓝色方块重叠；被覆盖的方块会逐个 **清除**。重复直到全部清除。（如果开启了自动曝光搜索且标靶短暂丢失，图像会在搜索时明<->暗循环 —— 这是预期现象；如果始终检测不到，请重新定位以修复反光或距离问题。）中间结果会立即应用到数据流上。
2. **尺度阶段（Scale phase）** —— 自动开始；持续将标靶重新定位到不同且各异的位置，直到接受 **15** 张标靶图像（一条绿色进度条填满完成）。
3. **RGB 阶段（RGB phase）**（仅限 RGB 设备 —— D415/D435/D455）—— 与尺度阶段类似，它捕获 15 张标靶图像并标定深度到 RGB 的 UV 映射。完成后，左/右深度和 depth<->RGB 均已完成标定。

完成后，结果会写入相机。使用 `Intel.Realsense.CustomRW` 在标定前后备份或恢复标定表，并在之后验证深度质量（若不满意则重新运行）。

## 已知局限：残余的 depth<->color 对齐误差

即使标定成功，深度到彩色的叠加（`align`）仍存在一些残余误差 —— 在物体边缘附近最为明显。已在硬件上验证：它在 **D455 上于 ~1--2 m 处明显可见**，在 **D435 上略有出现**。这在很大程度上是 **预期的且属于几何性的**，并非标定失败的迹象。标定消除了系统性的外参偏移；但它无法消除：

- **视差 / 遮挡（Parallax / occlusion）** —— 深度（左 IR）和 RGB 是不同的光学中心，因此在物体边界处，一台相机能看到另一台看不到的部分。任何标定都无法对齐该区域 —— 这是纯粹的几何问题，也是边缘 "条纹（fringing）" 的主要成因。
- **深度误差（Depth error）** —— 立体深度误差大致随距离的平方增长，因此在 1--2 m 处，反投影到彩色图像的准确度较低（在有噪声的边缘和空洞处更差）。
- **RGB 卷帘快门 / 同步（RGB rolling shutter / sync）** —— 彩色传感器是卷帘快门；当相机或场景运动时，它会相对于（全局快门的）深度帧发生偏移。

为何 D455 比 D435 更差：**D455 的立体基线为 95 mm，而 D435 为 50 mm**。更宽的基线带来更好的远距离深度，但会造成更大的 depth<->RGB 视差，因此残余在近/中距离更明显。

哪些做法仍有帮助（无法降到零）：

- 根据用例，尝试使用 `align_to depth` 而非 `align_to color`。
- 在对齐 *之前* 应用深度后处理（空间 / 时间 / 空洞填充）。
- 保持深度/彩色同步并拍摄静态场景，以避免卷帘快门偏移。
- 保持在相机的最佳深度范围内，使深度尽可能准确。

## 官方参考资料

- 标定概述（工具、可打印标靶及指南下载）：
  <https://dev.realsenseai.com/docs/calibration/>
- 动态标定工具下载（Windows / Ubuntu 软件包）：
  <https://www.intel.com/content/www/us/en/download/645988/29618/intel-realsense-d400-series-dynamic-calibration-tool.html>
- 用户指南（PDF）：
  <https://cdrdv2-public.intel.com/840579/RealSense_D400_Dyn_Calib_User_Guide.pdf>
- 编程指南（PDF）：
  <https://cdrdv2-public.intel.com/840422/RealSense_D400_Dyn_Calib_Programmer.pdf>
