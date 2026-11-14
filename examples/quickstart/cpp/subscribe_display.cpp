// Orbbec 相机 ROS 2 话题订阅与显示入门示例（C++ 版）。
//
// 数据流：
//   orbbec_camera 节点
//     -> /camera/color/image_raw (sensor_msgs/Image, rgb8/bgr8)
//     -> /camera/depth/image_raw (sensor_msgs/Image, 16UC1, 单位 mm)
//     -> rclcpp 订阅 -> 转 BGR / 深度转伪彩 -> OpenCV 窗口显示

#include <string>

#include <cv_bridge/cv_bridge.h>
#include <opencv2/opencv.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/image_encodings.hpp>
#include <sensor_msgs/msg/image.hpp>

class QuickViewer : public rclcpp::Node {
 public:
  QuickViewer() : Node("orbbec_quick_viewer") {
    color_topic_ = declare_parameter<std::string>("color_topic", "/camera/color/image_raw");
    depth_topic_ = declare_parameter<std::string>("depth_topic", "/camera/depth/image_raw");
    alpha_ = declare_parameter<double>("alpha", 0.05);
    enable_depth_ = declare_parameter<bool>("enable_depth", true);

    color_sub_ = create_subscription<sensor_msgs::msg::Image>(
        color_topic_, rclcpp::QoS(10),
        [this](const sensor_msgs::msg::Image::ConstSharedPtr& msg) { on_color(msg); });
    if (enable_depth_) {
      depth_sub_ = create_subscription<sensor_msgs::msg::Image>(
          depth_topic_, rclcpp::QoS(10),
          [this](const sensor_msgs::msg::Image::ConstSharedPtr& msg) { on_depth(msg); });
    }

    RCLCPP_INFO(get_logger(), "订阅彩色: %s", color_topic_.c_str());
    if (enable_depth_) {
      RCLCPP_INFO(get_logger(), "订阅深度: %s", depth_topic_.c_str());
    }
    RCLCPP_INFO(get_logger(), "按 q 退出");
  }

 private:
  void on_color(const sensor_msgs::msg::Image::ConstSharedPtr& msg) {
    cv::Mat frame;
    try {
      // 会自动把 rgb8 / bgr8 / 其他常见编码统一转成 bgr8
      frame = cv_bridge::toCvCopy(msg, sensor_msgs::image_encodings::BGR8)->image;
    } catch (const cv_bridge::Exception& e) {
      RCLCPP_ERROR(get_logger(), "彩色转换失败: %s", e.what());
      return;
    }
    show("RGB", frame);
  }

  void on_depth(const sensor_msgs::msg::Image::ConstSharedPtr& msg) {
    cv::Mat frame;
    try {
      if (msg->encoding == sensor_msgs::image_encodings::RGB8 ||
          msg->encoding == sensor_msgs::image_encodings::BGR8) {
        // depth_colorizer_mode 非 none 时，深度话题直接发布伪彩图，直接显示
        frame = cv_bridge::toCvCopy(msg, sensor_msgs::image_encodings::BGR8)->image;
      } else {
        // 原始深度是 16UC1、单位毫米，直接当 8 位显示几乎全黑，需先压缩到 0~255
        const cv::Mat depth = cv_bridge::toCvCopy(msg)->image;
        cv::convertScaleAbs(depth, frame, alpha_);
        cv::applyColorMap(frame, frame, cv::COLORMAP_JET);
        frame.setTo(cv::Scalar(0, 0, 0), depth == 0);  // 0 表示无效深度，置黑
        if (depth.type() == CV_16U) {
          const int cx = depth.cols / 2;
          const int cy = depth.rows / 2;
          const int distance = depth.at<uint16_t>(cy, cx);
          cv::putText(frame, std::to_string(distance) + " mm", cv::Point(10, 30),
                      cv::FONT_HERSHEY_SIMPLEX, 0.8, cv::Scalar(255, 255, 255), 2);
        }
      }
    } catch (const cv_bridge::Exception& e) {
      RCLCPP_ERROR(get_logger(), "深度转换失败: %s", e.what());
      return;
    }
    show("Depth", frame);
  }

  void show(const std::string& window, const cv::Mat& frame) {
    cv::imshow(window, frame);
    if ((cv::waitKey(1) & 0xFF) == 'q') {
      RCLCPP_INFO(get_logger(), "收到 q，退出");
      rclcpp::shutdown();
    }
  }

  std::string color_topic_;
  std::string depth_topic_;
  double alpha_ = 0.05;
  bool enable_depth_ = true;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr color_sub_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr depth_sub_;
};

int main(int argc, char** argv) {
  rclcpp::init(argc, argv);
  auto node = std::make_shared<QuickViewer>();
  try {
    rclcpp::spin(node);
  } catch (const std::exception& e) {
    RCLCPP_ERROR(node->get_logger(), "%s", e.what());
  }
  if (rclcpp::ok()) {
    rclcpp::shutdown();
  }
  cv::destroyAllWindows();
  return 0;
}
