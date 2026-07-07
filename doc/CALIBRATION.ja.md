**[English](CALIBRATION.md)** | **[繁體中文](CALIBRATION.zh-TW.md)** | **[简体中文](CALIBRATION.zh-CN.md)** | **[日本語](CALIBRATION.ja.md)**

# RealSense Dynamic Calibration Tool

`devel` イメージには **Intel RealSense D400 Series Dynamic Calibration
Tool**（`librscalibrationtool`）が同梱されています。このページでは、このツールが何をするのか、`CAMERA.md` の on-chip calibration（オンチップ校正）とどう異なるのか、そしてコンテナから実行する方法を説明します。

## 概要 (オンチップキャリブレーションとの違い)

D400 カメラには、明確に異なる 2 つの校正経路があります。

| | On-chip calibration | Dynamic Calibration Tool |
|---|---|---|
| 記載場所 | [CAMERA.md](CAMERA.md)（section 5） | このページ |
| 実行元 | `realsense-viewer`（組み込み） | `Intel.Realsense.DynamicCalibrator` |
| ターゲットの要否 | 不要 -- テクスチャのあるシーンなら何でも可 | 必要 -- 印刷した（またはスマートフォンアプリの）ターゲット |
| 校正対象 | Depth の rectification（矯正）のみ（ステレオ IR） | Rectification + depth scale、**さらに RGB デバイスでは RGB extrinsics** |
| 使うべき場面 | Depth ノイズ / 平面が平坦でない場合 | 徹底したターゲットベースの再校正が必要な場合 |

Dynamic calibration が最適化するのは **extrinsic**（外部）パラメータのみ、つまりイメージャ間の回転と並進であり、intrinsics（内部パラメータ：focal length、principal point、distortion は工場校正値のまま）は対象外です。User Guide（v2.11）によれば、2 つの動作モード（targeted と target-less）で 2 種類の校正を提供します。`Intel.Realsense.DynamicCalibrator` の GUI/CLI は **targeted** 校正を実行します。

- **Rectification calibration** -- 2 つの IR イメージャのエピポーラ幾何を再整列します
  （`RotationLeftRight` / `TranslationLeftRight`）。on-chip calibration と同じ目的ですが、
  ターゲットベースで行います。
- **Depth scale calibration** -- 光学素子がずれた際に、絶対的な depth scale を
  補正します。

D455 における Depth<->RGB：targeted 校正は、RGB センサーを備えるデバイス（D415/D435/D455）では **RGB extrinsics も再校正します**（`RotationLeftRGB` / `TranslationLeftRGB` -- 左イメージャに対する color センサーの関係）。これはまさに、ランタイムの alignment（位置合わせ）が依存する depth-to-color の関係（`realsense2_camera` の `align_depth.enable:=true`、または SDK の `rs2::align`）であり、再実行することで depth<->color のオーバーレイのずれが修正されます。Target-less モードは depth（left/right）のみを校正し、RGB は **校正しません**。また API 専用であり、GUI の校正ツールでは提供されません。

## イメージが提供するもの

このツールは `devel-base` ステージにおいて、Intel が公式に文書化している直接 `.deb` 方式（`dpkg -i librscalibrationtool_<ver>_amd64.deb`）でインストールされます。Intel はこの方式を Ubuntu 22.04（Humble）と 24.04（Jazzy）の両方でサポート対象として挙げています。Intel がホストするこの単一の `.deb` は、apt の `Depends` を持たないプリコンパイル済み amd64 バイナリです。前方互換性のある標準ライブラリのみをリンクしているため、Intel が noble の apt リポジトリでインデックス化していなくても、同じパッケージが jammy と noble の両方でインストール・実行できます。これは **amd64 専用** です -- Intel は ARM64 ビルドを提供していないため、ARM64 ではインストールがスキップされ、マルチアーキテクチャのイメージも引き続きビルドできます。

インストールされるバージョン：`librscalibrationtool` 2.13.1.0。実行ファイル（すべて `PATH` 上）：

| Executable | Purpose |
|---|---|
| `Intel.Realsense.DynamicCalibrator` | Targeted dynamic calibration（rectification + depth scale + RGB extrinsics）、GUI と CLI |
| `Intel.Realsense.CustomRW` | カメラに保存された校正テーブルの読み取り / 書き込み |
| `opencv_interactive-calibration` | OpenCV のインタラクティブ校正ヘルパー |

同梱の API パッケージとガイドは
`/usr/share/doc/librscalibrationtool/api/DynamicCalibrationAPI-Linux-2.13.1.0.tar.gz` にあります。

## 前提条件

1. **Host udev rules.** このツールはカメラへの raw USB アクセスを必要とします。これは
   SDK の他の部分と同じ権限要件です。ホスト上で一度だけインストールしてください。

   ```bash
   ./script/install_udev_rules.sh
   ```

   なぜこれがコンテナ内だけでなくホスト上で必要なのかは、README の
   "RealSense udev Rules" セクションを参照してください。

2. **A calibration target.** 公式ターゲットを文書化されたスケールで印刷するか
   （リンクは下記）、Intel RealSense Dynamic Target スマートフォンアプリ
   （iOS / Android）で表示します。

3. **GUI access.** `devel` イメージには X11/Qt/OpenGL スタックがすでに含まれており、
   コンテナは GUI モードで動作するため、校正ツールのウィンドウをホストの
   ディスプレイに開くことができます。

## 実行方法

```bash
just build    # first time, or after Dockerfile changes
just run      # devel container; GUI + /dev are wired up

# inside the container:
Intel.Realsense.DynamicCalibrator     # interactive GUI calibration
```

デバイスをターゲットから **600--850 mm** の位置に置き、視野内でターゲットのバーがおおよそ垂直になるようにします。処理全体を通してカメラとターゲット間の相対的な動きが必要です（片方を固定し、もう片方を動かす）。反射（日光、明るい照明、スマートフォン画面のグレア）は避けてください -- ターゲットが検出されなくなります。targeted フローでは、次のフェーズが順番に実行されます（User Guide の section 4.5.4 および Appendix B）。

1. **Rectification phase** -- ライブビューの中央に、陰影の付いた **青い正方形** の
   ブロックが重ね表示されます。各青い正方形は、まだターゲットのカバーが必要な視野の領域を
   示します。ターゲットの黒／白の正方形とバーが青い正方形に重なるように、カメラ（または
   ターゲット）をゆっくり動かします。カバーされた正方形は 1 つずつ **消えて** いきます。
   すべて消えるまで繰り返します。（auto-exposure サーチが有効でターゲットが一時的に
   見失われると、サーチ中に映像が明<->暗と切り替わります -- これは想定内です。まったく
   検出されない場合は、反射や距離を直すために位置を調整してください。）中間結果はただちに
   ストリームに適用されます。
2. **Scale phase** -- 自動的に開始します。**15** 枚のターゲット画像が受理される
   （緑のプログレスバーが完了まで満たされる）まで、ターゲットを異なる別々の位置へ
   移動し続けます。
3. **RGB phase**（RGB デバイスのみ -- D415/D435/D455）-- scale phase と同様に、
   15 枚のターゲット画像を取り込み、depth-to-RGB の UV マッピングを校正します。この後、
   left/right depth と depth<->RGB の両方が校正されます。

完了すると、結果がカメラに書き込まれます。前後の校正テーブルのバックアップや復元には `Intel.Realsense.CustomRW` を使い、その後 depth の品質を確認してください（満足できない場合は再実行）。

## 既知の制限: depth<->color アライメントの残差誤差

校正が成功した後でも、depth-to-color のオーバーレイ（`align`）には多少の残差があります -- 物体のエッジ付近で最も目立ちます。ハードウェアで検証済み：**D455 では ~1--2 m で明確に目立ち**、**D435 ではわずかに現れます**。これは主に **想定内かつ幾何学的なもの** であり、校正が失敗したことを示すものではありません。校正は系統的な extrinsic のオフセットを除去しますが、次のものは除去できません。

- **Parallax / occlusion**（視差 / オクルージョン）-- depth（left IR）と RGB は
  光学中心が異なるため、物体の境界では一方のカメラが見えるものをもう一方は見られません。
  その領域はどんな校正でも整列できません -- これは純粋な幾何であり、エッジの
  「フリンジ（縁取り）」の主な原因です。
- **Depth error** -- ステレオ depth 誤差はおおよそ距離の 2 乗で増大するため、1--2 m では
  color 画像への deprojection（逆投影）の精度が下がります（ノイズの多いエッジや穴で
  より悪化します）。
- **RGB rolling shutter / sync** -- color センサーは rolling-shutter 方式です。カメラや
  シーンの動きがあると、（global な）depth フレームに対して相対的にずれます。

D455 が D435 より悪い理由：**D455 のステレオ baseline は 95 mm で、D435 の 50 mm に対して広い** ためです。baseline が広いほど長距離の depth は良くなりますが、depth<->RGB の parallax が大きくなるため、近距離／中距離で残差がより目立ちます。

依然として役立つこと（ゼロにはなりません）：

- ユースケースに応じて、`align_to color` の代わりに `align_to depth` を試す。
- 整列の *前* に depth の後処理（spatial / temporal / hole-filling）を適用する。
- depth/color を同期させ、静止したシーンを撮影して rolling-shutter のずれを避ける。
- カメラの最適な depth 範囲内に収め、depth をできるだけ正確にする。

## 公式リファレンス

- Calibration overview（tool, printable target, and guide downloads）：
  <https://dev.realsenseai.com/docs/calibration/>
- Dynamic Calibration Tool download（Windows / Ubuntu packages）：
  <https://www.intel.com/content/www/us/en/download/645988/29618/intel-realsense-d400-series-dynamic-calibration-tool.html>
- User Guide（PDF）：
  <https://cdrdv2-public.intel.com/840579/RealSense_D400_Dyn_Calib_User_Guide.pdf>
- Programmer's Guide（PDF）：
  <https://cdrdv2-public.intel.com/840422/RealSense_D400_Dyn_Calib_Programmer.pdf>
