# 快速上手：订阅话题并显示 RGB / 深度

同一份功能分别放在 `python/` 与 `cpp/` 两个目录，演示最基本的用法：订阅 `orbbec_camera`
发布的图像话题，转成 OpenCV 的 BGR 图像，再显示 RGB 与伪彩深度两个窗口。

## Python 版

```bash
# 终端 1：启动相机（按你的机型替换 launch 文件）
source /opt/ros/humble/setup.bash
source ~/ws_orbbec/install/setup.bash
ros2 launch orbbec_camera gemini2.launch.py

# 终端 2：运行示例
~/ws_orbbec/examples/quickstart/python/run.sh
```

窗口中按 `q` 退出。只想看彩色：

```bash
~/ws_orbbec/examples/quickstart/python/run.sh --no-depth
```

### 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--color-topic` | `/camera/color/image_raw` | 彩色图像话题 |
| `--depth-topic` | `/camera/depth/image_raw` | 深度图像话题 |
| `--alpha` | `0.05` | 深度伪彩对比度，毫米值乘以它；太小偏暗，太大易饱和 |
| `--no-depth` | 关闭 | 只订阅并显示彩色 |

话题名随命名空间变化时，直接指定完整话题：

```bash
./python/run.sh --color-topic /cam1/camera/color/image_raw
```

## C++ 版

先编译一次，之后直接运行：

```bash
~/ws_orbbec/examples/quickstart/cpp/build.sh
~/ws_orbbec/examples/quickstart/cpp/run.sh
```

C++ 版用 ROS 2 参数传配置，`build.sh` 已自动 source 环境：

```bash
./cpp/run.sh --ros-args -p alpha:=0.08
./cpp/run.sh --ros-args -p enable_depth:=false
./cpp/run.sh --ros-args -p color_topic:=/cam1/camera/color/image_raw
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `color_topic` | `/camera/color/image_raw` | 彩色图像话题 |
| `depth_topic` | `/camera/depth/image_raw` | 深度图像话题 |
| `alpha` | `0.05` | 深度伪彩对比度 |
| `enable_depth` | `true` | 设为 `false` 只显示彩色 |

C++ 版依赖 `rclcpp`、`sensor_msgs`、`OpenCV` 等，均由安装脚本的依赖清单提供，无需额外安装。

## 数据流

```text
orbbec_camera 节点
  ├─ /camera/color/image_raw  rgb8/bgr8 ─┐
  └─ /camera/depth/image_raw  16UC1(mm) ─┤
                                          ▼
                             消息转 OpenCV 图像
                                          ▼
                       bgr8 / 归一化+伪彩 → cv2.imshow()
```

完整讲解与排错见 [06 快速上手：话题订阅与显示](../../docs/06-快速上手-订阅与显示.md)。
