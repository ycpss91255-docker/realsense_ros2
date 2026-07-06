**[English](CAMERA.md)** | **[繁體中文](CAMERA.zh-TW.md)** | **[简体中文](CAMERA.zh-CN.md)** | **[日本語](CAMERA.ja.md)**

# 使用實體 RealSense 相機進行測試

`TEST.md` 涵蓋建置階段自動執行的煙霧測試（smoke test）。本頁則是透過容器（container）驗證實體 Intel RealSense 相機的手動程序。

容器以 `privileged` 模式執行並掛載 `/dev`，因此能看到主機上的 USB 裝置。此映像檔內含 ROS 2 wrapper（`realsense2_camera`），以及 librealsense SDK 的 CLI 工具（`rs-enumerate-devices`、`realsense-viewer`、`rs-*`）。

## 0. 確認主機能看到相機

```bash
lsusb | grep -i intel    # e.g. Intel RealSense (8086:0b07)
```

若沒有任何輸出：請改用支援資料傳輸的連接線、優先使用 USB 3.0 連接埠，並確認沒有其他程序正佔用相機。

## 1. 進入容器

```bash
just build    # first time, or after changes
just run      # interactive shell; ROS is auto-sourced (via ~/.bashrc.d)
```

## 2. 快速檢查 -- 相機是否被偵測到（SDK 層級）

```bash
rs-enumerate-devices        # lists model / serial / firmware
rs-enumerate-devices -s     # short form
```

通過此步驟即可確認相機、驅動程式與 USB 權限皆正常運作。

## 3. ROS 2 整合（本儲存庫的主要使用情境）

啟動相機節點：

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py
```

在進入同一容器的第二個 shell 中（於主機執行 `just exec bash`）：

```bash
ros2 topic list                                       # expect /camera/... topics
ros2 topic hz /camera/camera/depth/image_rect_raw     # confirm streaming (Hz)
ros2 topic echo /camera/camera/color/image_raw --once
```

互動式 shell（`just run` 與 `just exec bash`）會透過 `~/.bashrc.d` 自動 source ROS。只有非互動式的 `just exec <cmd>`（不會讀取 `.bashrc`）才需要先執行 `source /opt/ros/${ROS_DISTRO}/setup.bash`。

## 4. 視覺化（GUI）

```bash
realsense-viewer    # librealsense GUI
rviz2               # ROS 2 visualization
```

devel 映像檔會安裝 `ros-${ROS_DISTRO}-desktop`，因此 `realsense-viewer` 與 `rviz2`（以及它們所需的 Qt/OpenGL/X 相關套件）皆可使用。容器的 GUI 模式加上 X11 掛載會處理顯示畫面。

## 5. 晶片內校正（on-chip calibration，選用）

D400 系列可從一般場景重新校正其立體深度參數 -- 不需要校正標的物（calibration target）。深度是透過對兩顆 IR 相機進行立體匹配（stereo-matching）計算而得，而原廠參數會隨時間漂移（溫度、機械衝擊、運送、老化），表現為額外的深度雜訊、平面不平整或邊緣雜訊。晶片內校正可修正此漂移。它與韌體更新（firmware update）互相獨立：韌體更新改變的是相機的韌體版本，校正則是調整深度量測參數。在韌體更新後執行一次是不錯的健全性檢查（sanity check）。

請從 `realsense-viewer` 執行：開啟深度感測器的 **More** 選單並選擇 **On-Chip Calibration**，然後對準合適的場景並按下校正。

場景需求：

- 具有紋理、距離 **0.5--2 m**、且 **有效深度像素 > 50%**（避免空白牆面、高反光表面，或任何距離過遠的物體）。
- 「White wall」子模式為例外：**僅**在對準平整的白色牆面並開啟 IR 投影器時才使用。

### 判讀健康檢查分數（health-check score）

校正完成後，viewer 會回報一個健康檢查分數。**重要的是其絕對值** -- 正負號僅代表修正的方向，而非「較好」或「較差」。viewer 的 `if >0.25` 指引指的是 `|health| > 0.25`。

| `|health|` | 意義 | 動作 |
|---|---|---|
| 接近 0（< 0.25） | 已校正良好；本次執行幾乎沒有改變任何東西 | 不需要套用 |
| >= 0.25 | 有明顯漂移；此修正具有意義 | 套用新的校正 |
| 偏大（例如 > 0.75） | 嚴重漂移，或場景不合適 | 先套用，再於更好的場景重新執行以確認 |

因此 `-0.45` 的分數即 `|0.45| > 0.25`：偵測到有意義的漂移，建議套用新的校正。負號**不**代表校正失敗。套用後，請在 `realsense-viewer` 中檢查深度影像（平面更平整、雜訊更少）；為求保險，可在不同場景重新執行 -- 分數回到接近 0 表示校正已收斂。

## 疑難排解

| 症狀 | 檢查項目 |
|---|---|
| `No device detected` | 主機的 `lsusb` 是否看到相機？連接線／USB 3.0 連接埠／未被其他程序佔用。容器為 `privileged`（預設）。 |
| `ros2: command not found` | 互動式 shell 會透過 `~/.bashrc.d` 自動 source ROS。只有非互動式的 `just exec <cmd>` 需要先執行 `source /opt/ros/${ROS_DISTRO}/setup.bash`。 |
| `realsense-viewer` 無法開啟（X11） | 主機有 X server；`echo $DISPLAY` 有設定值；GUI 模式在 `config/docker/setup.conf` 中為 `[gui] mode = auto`。 |
