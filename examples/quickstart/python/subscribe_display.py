#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Orbbec 相机 ROS 2 话题订阅与显示入门示例。

数据流：
    orbbec_camera 节点
      -> /camera/color/image_raw (sensor_msgs/Image, rgb8/bgr8)
      -> /camera/depth/image_raw (sensor_msgs/Image, 16UC1, 单位 mm)
      -> rclpy 订阅 -> 转 BGR / 深度转伪彩 -> OpenCV 窗口显示
"""

import argparse
import sys

import cv2
import rclpy
from cv_bridge import CvBridge, CvBridgeError
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node
from sensor_msgs.msg import Image


class QuickViewer(Node):
    def __init__(self, args):
        super().__init__("orbbec_quick_viewer")
        self.bridge = CvBridge()
        self.alpha = args.alpha

        self.create_subscription(Image, args.color_topic, self.on_color, 10)
        if not args.no_depth:
            self.create_subscription(Image, args.depth_topic, self.on_depth, 10)

        self.get_logger().info(f"订阅彩色: {args.color_topic}")
        if not args.no_depth:
            self.get_logger().info(f"订阅深度: {args.depth_topic}")
        self.get_logger().info("按 q 退出")

    def on_color(self, msg):
        try:
            # 会自动把 rgb8 / bgr8 / 其他常见编码统一转成 bgr8
            frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")
        except CvBridgeError as exc:
            self.get_logger().error(f"彩色转换失败: {exc}")
            return
        self._show("RGB", frame)

    def on_depth(self, msg):
        try:
            if msg.encoding in ("rgb8", "bgr8"):
                # depth_colorizer_mode 非 none 时，深度话题直接发布伪彩图，直接显示
                frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")
            else:
                # 原始深度是 16UC1、单位毫米，直接当 8 位显示几乎全黑，需先压缩到 0~255
                depth = self.bridge.imgmsg_to_cv2(
                    msg, desired_encoding="passthrough"
                )
                frame = cv2.convertScaleAbs(depth, alpha=self.alpha)
                frame = cv2.applyColorMap(frame, cv2.COLORMAP_JET)
                frame[depth == 0] = (0, 0, 0)  # 0 表示无效深度，置黑
                h, w = depth.shape[:2]
                cv2.putText(
                    frame,
                    f"{int(depth[h // 2, w // 2])} mm",
                    (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.8,
                    (255, 255, 255),
                    2,
                )
        except CvBridgeError as exc:
            self.get_logger().error(f"深度转换失败: {exc}")
            return
        self._show("Depth", frame)

    def _show(self, window, frame):
        cv2.imshow(window, frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            self.get_logger().info("收到 q，退出")
            rclpy.shutdown()


def main():
    parser = argparse.ArgumentParser(description="Orbbec RGB / Depth 订阅显示示例")
    parser.add_argument(
        "--color-topic", default="/camera/color/image_raw", help="彩色图像话题"
    )
    parser.add_argument(
        "--depth-topic", default="/camera/depth/image_raw", help="深度图像话题"
    )
    parser.add_argument(
        "--alpha",
        type=float,
        default=0.05,
        help="深度转伪彩的对比度系数：毫米值乘以它，越大越亮（默认 0.05，约覆盖 0~5 米）",
    )
    parser.add_argument("--no-depth", action="store_true", help="只显示彩色")
    args, ros_args = parser.parse_known_args()

    rclpy.init(args=[sys.argv[0]] + ros_args)
    node = QuickViewer(args)
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
