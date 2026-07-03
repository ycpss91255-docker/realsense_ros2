**[English](../README.md)** | **[繁體中文](README.zh-TW.md)** | **[简体中文](README.zh-CN.md)** | **[日本語](README.ja.md)**

# Intel RealSense Docker コンテナ（ROS 2）

[![CI](https://github.com/ycpss91255-docker/realsense_ros2/actions/workflows/main.yaml/badge.svg)](https://github.com/ycpss91255-docker/realsense_ros2/actions/workflows/main.yaml) [![License](https://img.shields.io/badge/License-Apache--2.0-blue?style=flat-square)](../LICENSE)

## TL;DR

コンテナ化された ROS 2 RealSense カメラ **アプリ**：`runtime` イメージのデフォルト CMD がカメラノードを launch し、リアルタイムの **RGB + Depth** トピックを配信します。apt から `realsense2-camera` と `realsense2-description` をインストールし（これにより `librealsense2` が依存関係として推移的に取り込まれます）、USB アクセス用の udev ルールを同梱します。マルチディストロ（Humble + Jazzy）、マルチアーキ（x86_64 + ARM64 / Raspberry Pi）。

```bash
./script/install_udev_rules.sh      # once on the host (physical camera)
just build && just run -t runtime    # build + launch the camera app
# -> logs show "RealSense Node Is Up!" and depth/color streaming
```

> `just run` 単体は **devel** 開発シェルを開くだけでカメラアプリではありません -- `just run -t runtime` を使ってください。RGB-D ストリームの確認は [クイックスタート](#クイックスタート) を参照。

---

## 目次

- [概要](#概要)
- [機能](#機能)
- [前提条件](#prerequisites)
- [クイックスタート](#クイックスタート)
- [使い方](#使い方)
- [マルチマシン](#multi-machine-ros-2)
- [アンインストール / クリーンアップ](#uninstall--cleanup)
- [設定](#設定)
- [アーキテクチャ](#アーキテクチャ)
- [Smoke Tests](#smoke-tests)
- [ディレクトリ構成](#ディレクトリ構成)

---

## 概要

Intel RealSense 深度カメラ向けに、再現可能な ROS 2 環境を提供します。CI は **ROS 2 Humble（Ubuntu 22.04）と Jazzy（Ubuntu 24.04）の両方** でイメージをビルドし、それぞれ対応する `ros-<distro>-realsense2-camera` と `ros-<distro>-realsense2-description` パッケージを ROS 2 apt リポジトリからインストールします（`librealsense2` ライブラリはその依存関係として推移的に取り込まれます）。さらに上流の udev ルールを焼き込んでいるため、USB デバイスがコンテナ内で正しい権限のもとで起動します。マルチアーキテクチャのベースイメージは x86_64 と ARM64（Raspberry Pi、Jetson CPU モード）をサポートします。

## 機能

- **マルチディストロ**：CI が単一の Dockerfile から ROS 2 Humble（Ubuntu 22.04）と Jazzy（Ubuntu 24.04）をビルド
- **Apt ベースのインストール**：ROS 2 apt リポジトリから `realsense2-camera` と `realsense2-description`（`librealsense2` は推移的に取り込まれる）
- **Smoke Test**：Bats テストがビルド時に自動実行され、環境を検証
- **Docker Compose**：単一の `compose.yaml` で全ターゲットを管理
- **udev ルール**：RealSense USB デバイスアクセス用に事前設定済み
- **マルチアーキテクチャ**：x86_64 と ARM64（RPi、Jetson CPU モード）をサポート

## Prerequisites

ユーザーのエントリポイントは `just` で、これが Docker を駆動します。以下をホストに一度だけインストールしてください：

- **Docker Engine + Compose plugin。** ラッパーは `docker compose` を呼び出すため、
  Compose plugin が必要です。公式の便利スクリプトは Engine + Buildx + Compose を
  まとめてインストールします：

  ```bash
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"   # log out/in so docker runs without sudo
  ```

  `docker compose version` で確認してください。（ディストロのパッケージ単体では
  Compose が欠けることがあります -- 例：`docker-compose-v2` なしの `docker.io` では
  `docker: unknown command: docker compose` になります。）

- **just**（コマンドランナー）。ビルド済みバイナリを `~/.local/bin` へ、sudo 不要：

  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/.local/bin
  ```

  `~/.local/bin` が `PATH` にあることを確認し、`just --version` で確認してください。
  `just` をインストールしたくない場合のために、各レシピには生のフォールバック
  （`./script/<verb>.sh`）も用意されています。

- **（実機カメラ）ホストの udev ルール。** USB 経由で実機の RealSense を使うには、
  付属のルールをホストにインストールします（[RealSense udev ルール](#realsense-udev-rules) を参照）：

  ```bash
  ./script/install_udev_rules.sh
  ```

  これがないと、コンテナ内の非 root ユーザーは raw USB ノードを開けず、SDK がカメラを
  誤検出します -- 例：USB 3 デバイスが USB 2.1 として列挙される（"Reduced
  performance expected"）。

## クイックスタート

```bash
# 1. Build (default: ROS 2 Humble)
just build

# 2. (physical camera) install the host udev rules once
./script/install_udev_rules.sh

# 3. Launch the camera app. The `runtime` service's default command is
#    `ros2 launch realsense2_camera rs_align_depth_launch.py`; foreground shows the node logs:
just run -t runtime
#    ...or detached:
just run -d -t runtime
```

### See the RGB-D data

**CLI** -- カラー + Depth トピックが配信されているか確認します（インタラクティブな exec には `ros2` があります）：

```bash
just exec -t runtime bash -ic 'ros2 topic hz /camera/camera/color/image_raw'
just exec -t runtime bash -ic 'ros2 topic hz /camera/camera/depth/image_rect_raw'
```

**Visual** -- `rqt` で画像ストリームを表示します（`devel` イメージには `rqt_image_view` が同梱）：

```bash
just run -t devel
# inside the container:
ros2 launch realsense2_camera rs_align_depth_launch.py &     # start the camera
ros2 run rqt_image_view rqt_image_view           # pick color/image_raw and depth/image_rect_raw
```

> `-t` なしの `just run` は **devel** 開発シェルを開くだけでカメラアプリではありません -- アプリには
> `just run -t runtime` を使ってください。カメラの調整は launch 引数を渡すことで行います。例：
> `just run -t runtime ros2 launch realsense2_camera rs_launch.py pointcloud.enable:=true`、
> あるいはコマンドを丸ごと上書きします。低レベルの等価コマンドは [使い方](#使い方) を参照。

## 使い方

### ランタイム

ユーザーのエントリポイントは `just` です（リポジトリルートの `justfile` は base
サブツリーへのシンボリックリンク）。各レシピは `script/` 配下のラッパースクリプトに
1:1 で転送され、引数はそのまま渡されます。`--` 区切りは不要です。

```bash
just build                       # ビルド（デフォルト：devel）
just build test                  # devel-test ゲートをビルド
just run                         # 起動（例：just run -d）
just exec                        # 実行中のコンテナに入る
just stop                        # コンテナを停止・削除
just setup                       # setup.conf から .env + compose.yaml を再生成

docker compose build runtime     # 同等の低レベルコマンド
docker compose up runtime        # 起動
docker compose exec runtime bash # 実行中のコンテナに入る
```

### ROS 2 ディストロの選択

`just build` は Dockerfile のデフォルト（Humble / Ubuntu 22.04 jammy）を使用します。
CI は `.github/workflows/main.yaml` の `call-docker-build` マトリクスを通じて
Humble と Jazzy の両方を自動的にビルドします。ローカルで Jazzy をビルドするには、
対応する build-arg を `docker compose` 経由で渡します：

```bash
docker compose build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg ROS_TAG=ros-base \
  --build-arg UBUNTU_CODENAME=noble \
  runtime
```

### Smoke tests（test ステージ）

Smoke tests はビルド時に自動実行されます。テスト失敗時はビルドも失敗します。
`devel-test` ステージは lint（ShellCheck + Hadolint）と bats スイートを実行し、
`runtime-test` ステージはインストール済みの `realsense2_camera` ライブラリに対して
ldd 解決チェックを実行します。

```bash
just build test
# または
docker compose --profile test build test
```

## Multi-machine (ROS 2)

ROS 2 には master がありません——同じ **DDS domain** 上のノードは LAN 越しに
自動的に互いを発見するため、設定すべき `ROS_MASTER_URI` / `ROS_IP` はありません。
すべてのマシンで一致させる必要がある唯一の値は domain ID で、これはデプロイ
ごとのランタイム値なので **`.env`**（手動で書く workload overlay——`env_file:
- .env` で注入され、`just run` だけで適用され、再生成されず、git で無視される）
に置きます。マシン固有／ビルドパラメータ（GPU、privileged、マウント）は
`config/docker/setup.conf` に残します。

この repo はすでに `[network] mode = host` を出荷しているため、DDS の発見
（multicast）とトラフィックはホストの実インターフェースを使い——他のマシン
から到達できます。

**カメラ側のマシン（例：Raspberry Pi）：** `.env` に追記します

```ini
ROS_DOMAIN_ID=0    # any 0..101; MUST be identical on every machine
```

そして追加のフラグなしで起動します——compose が `.env` を注入します：

```bash
just run -t runtime
```

**もう一方のマシン：** 同じ domain を設定して購読します（任意の ROS 2 環境）：

```bash
export ROS_DOMAIN_ID=0
ros2 topic hz /camera/camera/color/image_raw   # auto-discovered, no master
```

> **要件：** 両マシンが同じサブネット上にあること；`[network] mode = host`
> （ここでのデフォルト）；そして `ROS_LOCALHOST_ONLY` が未設定または `0`
> （デフォルト——`1` にすると DDS が loopback に閉じ込められ、マシン間の発見が
> ブロックされます）。
>
> **帯域幅：** raw image topic は重いです。制約のあるリンクでは DDS の
> best-effort QoS がフレームを落とすことがあり、30 Hz のソースが約 10 Hz で
> 届くことがあります。フルレートが必要なら `compressed` image transport か
> より低いプロファイルを使ってください。

Raspberry Pi 5（カメラ）とホストの両方を `ROS_DOMAIN_ID=0` にして検証済み：
`/camera/camera/color/image_raw` はホスト上で自動発見されました（直結リンクで
約 10 Hz、上述のとおり best-effort QoS によりフレームが落ちます）。

## Uninstall / Cleanup

```bash
just stop      # stop and remove the running containers
just prune     # remove this repo's images + dangling build cache (see `just prune -h`)
```

リポジトリがホストに配置したものを完全に削除するには：

- **イメージ / ビルドキャッシュ：** `just prune`（特定のイメージは `docker image rm <tag>`）。
- **ホストの udev ルール**（インストールした場合のみ）：

  ```bash
  sudo rm -f /etc/udev/rules.d/99-realsense-libusb.rules
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```

- **リポジトリ：** クローンしたディレクトリを削除します。

## 設定

### 設定サーフェス（setup.conf）

実際の設定サーフェスは `config/docker/setup.conf` です。`just setup` がそこから
`.env` と `compose.yaml` を生成するため、`.env` は生成された成果物であり、手で
編集すべきではありません。`setup.conf` を編集（または `just setup-tui`）してから
`just setup` を再実行してください。

`setup.conf` はセクションに分かれています -- `[image]`、`[build]`、`[deploy]`、
`[gui]`、`[network]`、`[security]`、`[resources]`、`[environment]`、`[tmpfs]`、
`[devices]`、`[volumes]`。たとえば `[deploy]` セクションは GPU ランタイムキー
（`gpu_mode`、`gpu_count`、`gpu_capabilities`、`gpu_runtime`）を持ち、`[image]` は
リテラルな `image_name` キーではなく命名規則からイメージ名を導出します。

### RealSense udev ルール

udev ルールはコンテナ内だけでなく **ホスト** にインストールする必要があります。
コンテナには `udevd` がなく、デバイスノードの権限は `/dev` bind mount で共有される
ホストの `devtmpfs` inode 上にあるため、イメージに焼き込まれたルールだけでは機能
しません。ホストのルールがないと、コンテナ内の非 root ユーザーは raw USB ノードを
開けず、SDK がカメラを誤検出します（USB 2.0、`Product Line not supported` を報告、
またはファームウェア更新に失敗）。[IntelRealSense/librealsense#12022](https://github.com/IntelRealSense/librealsense/issues/12022)
を参照してください。

付属スクリプトでホストに一度だけインストールします（`sudo` を使用）：

```bash
./script/install_udev_rules.sh
```

スクリプトは `config/realsense/99-realsense-libusb.rules` を `/etc/udev/rules.d/`
にコピーして udev をリロードします。その後カメラを再接続してください。コンテナ自体は
`privileged` モードで実行され、`/dev` がマウントされます。

## アーキテクチャ

### Docker ビルドステージ図

```mermaid
graph TD
    EXT1["test-tools image\n(ghcr test-tools or test-tools:local)"]
    EXT2["ros:humble-ros-base-jammy\nor ros:jazzy-ros-base-noble"]

    EXT1 --> ttstage["test-tools-stage"]

    EXT2 --> sys["sys"]

    sys --> develbase["devel-base"]
    develbase --> devel["devel\n(shipped)"]
    devel --> develtest["devel-test (ephemeral)\nlint + bats /smoke_test/"]

    sys --> runtimebase["runtime-base"]
    runtimebase --> runtime["runtime\n(shipped)\nrealsense2_camera + udev rules"]
    runtime --> runtimetest["runtime-test (ephemeral)\nldd-resolution smoke"]

    ttstage --> develtest
```

### ステージ説明

| ステージ | FROM | 用途 |
|----------|------|------|
| `test-tools-stage` | `${TEST_TOOLS_IMAGE}`（マルチアーキの ghcr test-tools、または `test-tools:local`） | ShellCheck + Hadolint + Bats、出荷しない |
| `sys` | `ros:<distro>-ros-base-<codename>`（humble-jammy / jazzy-noble） | 共通ベース：ユーザー、ロケール、タイムゾーン（base v0.41.0 build contract） |
| `devel-base` | `sys` | 開発ツール + ROS 2 desktop + RealSense パッケージ + Dynamic Calibration Tool（amd64） |
| `devel` | `devel-base` | 出荷する開発イメージ（デフォルト CMD `bash`） |
| `devel-test` | `devel` + `test-tools-stage` | Lint + smoke tests、ビルド後に破棄（一時的） |
| `runtime-base` | `sys` | 最小ベース（`sudo`、`tini`） |
| `runtime` | `runtime-base` | 出荷するランタイムイメージ：RealSense パッケージ + udev ルール（デフォルト CMD `ros2 launch realsense2_camera rs_align_depth_launch.py`） |
| `runtime-test` | `runtime` | `realsense2_camera` ライブラリに対する ldd 解決 smoke、ビルド後に破棄（一時的） |

## Smoke Tests

ビルド時の自動テストは [TEST.md](test/TEST.md)、実機カメラでのテストは [CAMERA.md](CAMERA.md)、動的キャリブレーションツールは [CALIBRATION.md](CALIBRATION.md) を参照。

## ディレクトリ構成

```text
realsense_ros2/
├── Dockerfile                   # マルチステージビルド
├── LICENSE
├── README.md
├── justfile -> .base/script/docker/justfile        # シンボリックリンク（ユーザーエントリポイント）
├── .hadolint.yaml -> .base/.hadolint.yaml          # シンボリックリンク
├── .base/                       # base サブツリー（読み取り専用；v0.41.0）
├── script/
│   ├── entrypoint.sh            # コンテナエントリポイント（リポジトリ所有）
│   ├── install_udev_rules.sh    # ホストに RealSense udev ルールをインストール（リポジトリ所有）
│   ├── build.sh -> ../.base/script/docker/wrapper/build.sh   # シンボリックリンク
│   ├── run.sh   -> ../.base/script/docker/wrapper/run.sh     # シンボリックリンク
│   ├── exec.sh  -> ../.base/script/docker/wrapper/exec.sh    # シンボリックリンク
│   ├── stop.sh  -> ../.base/script/docker/wrapper/stop.sh    # シンボリックリンク
│   ├── prune.sh -> ../.base/script/docker/wrapper/prune.sh   # シンボリックリンク
│   ├── setup.sh -> ../.base/script/docker/wrapper/setup.sh   # シンボリックリンク
│   ├── setup_tui.sh -> ../.base/script/docker/wrapper/setup_tui.sh  # シンボリックリンク
│   └── hooks/                   # pre/ + post/ ラッパーフック
├── config/
│   ├── docker/
│   │   └── setup.conf           # 設定サーフェス（.env/compose.yaml はここから生成）
│   └── realsense/
│       └── 99-realsense-libusb.rules  # RealSense udev ルール
├── doc/
│   ├── README.zh-TW.md          # 繁体字中国語
│   ├── README.zh-CN.md          # 簡体字中国語
│   ├── README.ja.md             # 日本語
│   ├── adr/                     # アーキテクチャ決定記録（ADR）
│   ├── CAMERA.md               # 実機カメラでの手動テスト
│   ├── CALIBRATION.md          # 動的キャリブレーションツール解説
│   ├── changelog/CHANGELOG.md
│   └── test/
│       └── TEST.md             # ビルド時の自動 smoke テスト
├── .github/workflows/
│   └── main.yaml                # CI（base の再利用可能な build/release ワーカーを呼び出す）
└── test/
    └── smoke/                   # リポジトリ所有の bats テスト
        └── ros_env.bats         # （ヘルパーと追加の .bats は .base/test/smoke/ から）
```
