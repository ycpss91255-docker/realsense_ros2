**[English](CAMERA.md)** | **[繁體中文](CAMERA.zh-TW.md)** | **[简体中文](CAMERA.zh-CN.md)** | **[日本語](CAMERA.ja.md)**

# 物理的な RealSense カメラを使ったテスト

`TEST.md` はビルド時の自動スモークテストを扱います。このページは、コンテナを通して実際の Intel RealSense カメラを検証するための手動手順です。

コンテナは `/dev` をマウントした状態で `privileged` として動作するため、ホスト上の USB デバイスを認識できます。イメージには ROS 2 ラッパー（`realsense2_camera`）に加えて、librealsense SDK の CLI ツール（`rs-enumerate-devices`、`realsense-viewer`、`rs-*`）が同梱されています。

## 0. ホストがカメラを認識していることを確認する

```bash
lsusb | grep -i intel    # e.g. Intel RealSense (8086:0b07)
```

何も表示されない場合: データ通信対応のケーブルを使用し、できれば USB 3.0 ポートを選び、他のプロセスがカメラを占有していないことを確認してください。

## 1. コンテナに入る

```bash
just build    # first time, or after changes
just run      # interactive shell; ROS is auto-sourced (via ~/.bashrc.d)
```

## 2. クイックチェック -- カメラが検出されているか（SDK レベル）

```bash
rs-enumerate-devices        # lists model / serial / firmware
rs-enumerate-devices -s     # short form
```

これに合格すれば、カメラ、ドライバ、USB のパーミッションがすべて正しく機能していることが確認できます。

## 3. ROS 2 統合（本リポジトリの主なユースケース）

カメラノードを起動します:

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py
```

同じコンテナへの 2 つ目のシェル（ホストから `just exec bash`）で:

```bash
ros2 topic list                                       # expect /camera/... topics
ros2 topic hz /camera/camera/depth/image_rect_raw     # confirm streaming (Hz)
ros2 topic echo /camera/camera/color/image_raw --once
```

インタラクティブシェル（`just run` および `just exec bash`）は `~/.bashrc.d` を介して ROS を自動的に source します。`.bashrc` を読み込まない非インタラクティブな `just exec <cmd>` の場合のみ、先に `source /opt/ros/${ROS_DISTRO}/setup.bash` を実行する必要があります。

## 4. 可視化（GUI）

```bash
realsense-viewer    # librealsense GUI
rviz2               # ROS 2 visualization
```

devel イメージには `ros-${ROS_DISTRO}-desktop` がインストールされているため、`realsense-viewer` と `rviz2`（およびそれらが必要とする Qt/OpenGL/X スタック）の両方が利用できます。コンテナの GUI モードと X11 マウントがディスプレイを処理します。

## 5. オンチップキャリブレーション（任意）

D400 シリーズは、通常のシーンからステレオ深度パラメータを再キャリブレーションできます -- キャリブレーションターゲットは不要です。深度は 2 つの IR カメラのステレオマッチングによって計算され、工場出荷時のパラメータは時間とともにドリフト（温度、機械的衝撃、輸送、経年劣化）します。これは深度ノイズの増加、平面が平らにならない、エッジがノイズだらけになるといった形で現れます。オンチップキャリブレーションはそのドリフトを補正します。これはファームウェアの更新とは独立しています: ファームウェアはカメラのファームウェアバージョンを変更し、キャリブレーションは深度測定パラメータを調整します。ファームウェア更新後に一度実行しておくと、良い健全性チェックになります。

`realsense-viewer` から実行します: 深度センサーの **More** メニューを開いて **On-Chip Calibration** を選び、適切なシーンに向けて calibrate を押します。

シーンの要件:

- テクスチャがあり、**0.5--2 m** 離れていて、**> 50% valid depth pixels**（無地の壁、反射の強い表面、遠すぎるものは避ける）。
- 「White wall」サブモードは例外です: IR プロジェクターをオンにして平らな白い壁に向ける場合に **のみ** 使用してください。

### ヘルスチェックスコアの読み方

キャリブレーション後、ビューアはヘルスチェックスコアを報告します。**重要なのはその絶対値です** -- 符号は補正の方向を表しているだけで、「良い」「悪い」を示すものではありません。ビューアの `if >0.25` というガイダンスは `|health| > 0.25` を意味します。

| `|health|` | 意味 | 対応 |
|---|---|---|
| 0 に近い (< 0.25) | すでに十分にキャリブレーションされている。この実行ではほとんど変化しなかった | 適用する必要なし |
| >= 0.25 | 顕著なドリフト。補正には意味がある | 新しいキャリブレーションを適用する |
| 大きい (e.g. > 0.75) | 大きなドリフト、または不適切なシーン | 適用し、より良いシーンで再実行して確認する |

したがって `-0.45` というスコアは `|0.45| > 0.25` であり: 意味のあるドリフトが検出されたため、新しいキャリブレーションの適用が推奨されます。負の符号はキャリブレーションが失敗したことを **意味しません**。適用後、`realsense-viewer` で深度画像を確認してください（平面がより平らになり、ノイズが減る）。念のため、別のシーンで再実行してください -- スコアが再び 0 付近に戻れば、キャリブレーションが収束したことを意味します。

## トラブルシューティング

| 症状 | 確認事項 |
|---|---|
| `No device detected` | ホストの `lsusb` はカメラを認識していますか? ケーブル / USB 3.0 ポート / 他のプロセスに占有されていないか。コンテナは `privileged`（デフォルト）です。 |
| `ros2: command not found` | インタラクティブシェルは `~/.bashrc.d` を介して ROS を自動 source します。非インタラクティブな `just exec <cmd>` の場合のみ、先に `source /opt/ros/${ROS_DISTRO}/setup.bash` が必要です。 |
| `realsense-viewer` が開かない (X11) | ホストに X サーバーがある; `echo $DISPLAY` が設定されている; `config/docker/setup.conf` で GUI モードが `[gui] mode = auto` になっている。 |
