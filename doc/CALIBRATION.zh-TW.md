**[English](CALIBRATION.md)** | **[繁體中文](CALIBRATION.zh-TW.md)** | **[简体中文](CALIBRATION.zh-CN.md)** | **[日本語](CALIBRATION.ja.md)**

# RealSense 動態校正工具（Dynamic Calibration Tool）

`devel` 映像檔內建 **Intel RealSense D400 Series Dynamic Calibration
Tool**（`librscalibrationtool`）。本頁說明它的用途、它與 `CAMERA.md` 中晶片上（on-chip）校正的差異，以及如何從容器內執行它。

## 它是什麼（以及它與晶片上校正的差異）

D400 相機有兩種截然不同的校正路徑：

| | 晶片上校正（On-chip calibration） | 動態校正工具（Dynamic Calibration Tool） |
|---|---|---|
| 說明於 | [CAMERA.md](CAMERA.md)（第 5 節） | 本頁 |
| 執行來源 | `realsense-viewer`（內建） | `Intel.Realsense.DynamicCalibrator` |
| 是否需要標靶 | 否 —— 任何有紋理的場景皆可 | 是 —— 需要一張列印（或手機 App 顯示）的標靶 |
| 校正內容 | 僅深度校正（stereo IR 的 rectification） | Rectification + 深度比例（depth scale），**外加 RGB extrinsics**（於具 RGB 的裝置上） |
| 使用時機 | 深度雜訊 / 平面不平整 | 需要一次徹底、以標靶為基礎的重新校正 |

動態校正僅最佳化 **extrinsic**（外參）參數 —— 也就是各成像器（imager）之間的旋轉與平移 —— 而非 intrinsics（焦距、主點與畸變仍維持出廠校正值）。依據 User Guide（v2.11），它提供兩種校正類型、兩種操作模式（有標靶 targeted 與無標靶 target-less）；`Intel.Realsense.DynamicCalibrator` GUI/CLI 執行的是 **targeted**（有標靶）校正：

- **Rectification calibration** —— 重新對齊兩個 IR 成像器的對極幾何（epipolar geometry）（`RotationLeftRight` / `TranslationLeftRight`）；目標與晶片上校正相同，但以標靶為基礎。
- **Depth scale calibration** —— 當光學元件發生位移時，修正絕對深度比例。

D455 上的 Depth<->RGB：targeted 校正**也會重新校正 RGB extrinsics**（`RotationLeftRGB` / `TranslationLeftRGB` —— 也就是彩色感測器相對於左成像器的關係），適用於具 RGB 感測器的裝置（D415/D435/D455）。這正是執行期對齊所依賴的 depth-to-color 關係（`realsense2_camera` 中的 `align_depth.enable:=true`，或 SDK 中的 `rs2::align`），因此重新執行它可修正錯位的 depth<->color 疊圖。Target-less 模式僅校正深度（左/右），**不**校正 RGB，且僅提供 API —— GUI 校正器並未提供此模式。

## 映像檔提供的內容

此工具透過 Intel 官方文件所述的直接 `.deb` 方式（`dpkg -i librscalibrationtool_<ver>_amd64.deb`）安裝於 `devel-base` 階段，Intel 將此方式列為在 Ubuntu 22.04（Humble）與 24.04（Jazzy）上皆受支援。這個由 Intel 託管的單一 `.deb` 是預先編譯的 amd64 二進位檔，沒有 apt 的 `Depends`；它僅連結向前相容的標準函式庫，因此即使 Intel 並未將其編入 noble 的 apt repo 索引，同一個套件仍可在 jammy 與 noble 上安裝並執行。它是 **僅限 amd64** —— Intel 並未提供 ARM64 版本，因此在 ARM64 上會略過安裝，而 multi-arch 映像檔仍可建置成功。

安裝版本：`librscalibrationtool` 2.13.1.0。可執行檔（全部都在 `PATH` 上）：

| 可執行檔 | 用途 |
|---|---|
| `Intel.Realsense.DynamicCalibrator` | 有標靶動態校正（rectification + depth scale + RGB extrinsics），GUI 與 CLI |
| `Intel.Realsense.CustomRW` | 讀取 / 寫入儲存於相機上的校正表 |
| `opencv_interactive-calibration` | OpenCV 互動式校正輔助工具 |

隨附的 API 套件與指南位於
`/usr/share/doc/librscalibrationtool/api/DynamicCalibrationAPI-Linux-2.13.1.0.tar.gz`。

## 先決條件

1. **主機端 udev rules。** 此工具需要對相機的原始 USB 存取權，與 SDK 其餘部分的權限需求相同。在主機上安裝一次即可：

   ```bash
   ./script/install_udev_rules.sh
   ```

   關於為何必須安裝在主機上、而非僅在容器內，請參閱 README 中的「RealSense udev Rules」一節。

2. **一張校正標靶。** 可依文件所述的比例列印官方標靶（連結見下方），或透過 Intel RealSense Dynamic Target 手機 App（iOS / Android）顯示。

3. **GUI 存取。** `devel` 映像檔已包含 X11/Qt/OpenGL 堆疊，且容器以 GUI 模式執行，因此校正器視窗可在主機顯示器上開啟。

## 執行它

```bash
just build    # first time, or after Dockerfile changes
just run      # devel container; GUI + /dev are wired up

# inside the container:
Intel.Realsense.DynamicCalibrator     # interactive GUI calibration
```

將裝置放置在距離標靶 **600--850 mm** 處，並使標靶的條紋在視野中大致垂直；整個過程中都需要相機與標靶之間的相對移動（固定其一，移動另一）。避免反光（陽光、強光、手機螢幕眩光）—— 反光會使標靶無法被偵測。有標靶流程接著會依序執行下列各階段（User Guide 第 4.5.4 節與附錄 B）：

1. **Rectification 階段** —— 即時畫面的中央會疊上一組帶陰影的 **藍色方塊**。每個藍色方塊標記了視野中仍需標靶覆蓋的區域。緩慢移動相機（或標靶），使標靶的黑/白方塊與條紋覆蓋到藍色方塊；已覆蓋的方塊會逐一 **清除**。重複直到全部清除為止。（若開啟了自動曝光搜尋，且標靶短暫遺失，影像會在搜尋時亮<->暗循環 —— 這是正常現象；若始終無法偵測，請重新調整位置以排除反光或距離問題。）中間結果會立即套用到串流。
2. **Scale 階段** —— 自動開始；持續將標靶移到不同、彼此有明顯差異的位置，直到有 **15** 張標靶影像被接受（綠色進度條填滿為止）。
3. **RGB 階段**（僅限具 RGB 的裝置 —— D415/D435/D455）—— 與 scale 階段類似，擷取 15 張標靶影像並校正 depth-to-RGB 的 UV 映射。完成後，左/右深度以及 depth<->RGB 皆已完成校正。

完成後，結果會寫入相機。請使用 `Intel.Realsense.CustomRW` 在校正前/後備份或還原校正表，並在事後驗證深度品質（若不滿意可重新執行）。

## 已知限制：殘餘的 depth<->color 對齊誤差

即使校正成功，depth-to-color 疊圖（`align`）仍會有一些殘餘誤差 —— 在物體邊緣附近最為明顯。已在硬體上驗證：它在 **D455 於約 1--2 m 處明顯可見**，而在 **D435 上則略為存在**。這在很大程度上是 **預期之內且屬幾何性質**，並非校正失敗的徵兆。校正可消除系統性的 extrinsic 偏移，但無法消除：

- **視差 / 遮擋（Parallax / occlusion）** —— 深度（左 IR）與 RGB 屬於不同的光學中心，因此在物體邊界處，一台相機看得到的區域另一台看不到。任何校正都無法對齊該區域 —— 這是純粹的幾何問題，也是邊緣「鑲邊（fringing）」的主因。
- **深度誤差** —— 立體深度誤差大致隨距離平方成長，因此在 1--2 m 處，反投影（deprojection）到彩色影像上的準確度較差（在有雜訊的邊緣與孔洞處更糟）。
- **RGB rolling shutter / 同步** —— 彩色感測器為 rolling-shutter；當相機或場景移動時，它會相對於（全域快門的）深度影格產生位移。

為何 D455 比 D435 更差：**D455 具有 95 mm 的立體基線（stereo baseline），而 D435 為 50 mm**。較寬的基線可提供更佳的長距離深度，但會造成更大的 depth<->RGB 視差，因此殘餘誤差在近/中距離更為明顯。

哪些做法仍有幫助（無法降到零）：

- 依使用情境改用 `align_to depth` 而非 `align_to color`。
- 在對齊 *之前* 套用深度後處理（spatial / temporal / hole-filling）。
- 保持深度/彩色同步並拍攝靜態場景，以避免 rolling-shutter 位移。
- 維持在相機的最佳深度範圍內，使深度盡可能準確。

## 官方參考資料

- 校正總覽（工具、可列印標靶與指南下載）：
  <https://dev.realsenseai.com/docs/calibration/>
- Dynamic Calibration Tool 下載（Windows / Ubuntu 套件）：
  <https://www.intel.com/content/www/us/en/download/645988/29618/intel-realsense-d400-series-dynamic-calibration-tool.html>
- User Guide（PDF）：
  <https://cdrdv2-public.intel.com/840579/RealSense_D400_Dyn_Calib_User_Guide.pdf>
- Programmer's Guide（PDF）：
  <https://cdrdv2-public.intel.com/840422/RealSense_D400_Dyn_Calib_Programmer.pdf>
