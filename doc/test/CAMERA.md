# Testing with a physical RealSense camera

`TEST.md` covers the automatic build-time smoke tests. This page is the manual
procedure for verifying a real Intel RealSense camera through the container.

The container runs `privileged` with `/dev` mounted, so it sees USB devices on
the host. The image ships the ROS 2 wrapper (`realsense2_camera`) plus the
librealsense SDK CLI tools (`rs-enumerate-devices`, `realsense-viewer`, `rs-*`).

## 0. Confirm the host sees the camera

```bash
lsusb | grep -i intel    # e.g. Intel RealSense (8086:0b07)
```

If nothing shows: use a data-capable cable, prefer a USB 3.0 port, and make
sure no other process holds the camera.

## 1. Enter the container

```bash
just build    # first time, or after changes
just run      # interactive shell; ROS is auto-sourced (via ~/.bashrc.d)
```

## 2. Quick check -- is the camera detected (SDK level)

```bash
rs-enumerate-devices        # lists model / serial / firmware
rs-enumerate-devices -s     # short form
```

Passing this confirms the camera, driver, and USB permissions all work.

## 3. ROS 2 integration (the repo's primary use case)

Start the camera node:

```bash
ros2 launch realsense2_camera rs_launch.py
```

In a second shell into the same container (`just exec bash` from the host):

```bash
ros2 topic list                                       # expect /camera/... topics
ros2 topic hz /camera/camera/depth/image_rect_raw     # confirm streaming (Hz)
ros2 topic echo /camera/camera/color/image_raw --once
```

Interactive shells (`just run` and `just exec bash`) auto-source ROS via
`~/.bashrc.d`. Only a non-interactive `just exec <cmd>` (which does not read
`.bashrc`) needs `source /opt/ros/${ROS_DISTRO}/setup.bash` first.

## 4. Visualize (GUI)

```bash
realsense-viewer    # librealsense GUI
rviz2               # ROS 2 visualization
```

The devel image installs `ros-${ROS_DISTRO}-desktop`, so both `realsense-viewer`
and `rviz2` (plus the Qt/OpenGL/X stack they need) are available. The container's
GUI mode + X11 mounts handle the display.

## Troubleshooting

| Symptom | Check |
|---|---|
| `No device detected` | Host `lsusb` sees the camera? cable / USB 3.0 port / not held by another process. Container is `privileged` (default). |
| `ros2: command not found` | Interactive shells auto-source ROS via `~/.bashrc.d`. Only a non-interactive `just exec <cmd>` needs `source /opt/ros/${ROS_DISTRO}/setup.bash` first. |
| `realsense-viewer` will not open (X11) | Host has an X server; `echo $DISPLAY` is set; GUI mode is `[gui] mode = auto` in `config/docker/setup.conf`. |
