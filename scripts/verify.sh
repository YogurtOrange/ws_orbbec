#!/usr/bin/env bash
# 安装后验证：包可用性、设备枚举、可选启动冒烟测试。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WS="${ORBBEC_WS:-$(default_ws)}"
ROS_ARG="${ORBBEC_ROS_ARG:-}"
CAMERA="${ORBBEC_CAMERA:-gemini2}"
FULL="${ORBBEC_FULL:-0}"
SYSTEM="${ORBBEC_SYSTEM:-0}"

if ! is_orchestrated && [[ -t 0 ]]; then
  echo "要验证哪个安装？"
  echo "  1) 源码编译的工作空间（$WS/install）"
  echo "  2) apt 二进制安装（/opt/ros）"
  read -r -p "请输入 [1/2]（默认 1）：" _loc || _loc=""
  [[ "${_loc:-1}" == "2" ]] && SYSTEM=1
  read -r -p "是否启动相机节点做冒烟测试（约 20 秒）？[y/N] " _full || _full=""
  [[ "$_full" =~ ^[Yy] ]] && FULL=1
fi

DISTRO="${ROS_ARG:-$(detect_ros_distro)}"
[[ -n "$DISTRO" ]] || die "未检测到 ROS 2 安装"
ros_source "$(ros_setup_file "$DISTRO")"

if [[ "$SYSTEM" == "1" ]]; then
  ok "ROS 2 $DISTRO 环境已加载（二进制安装）"
else
  [[ -f "$WS/install/setup.bash" ]] || die "未找到 $WS/install/setup.bash，请先编译"
  ros_source "$WS/install/setup.bash"
  ok "ROS 2 $DISTRO + 工作空间环境已加载"
fi

ros2 pkg prefix orbbec_camera >/dev/null 2>&1 \
  || die "未找到 orbbec_camera 包，请确认已安装（源码编译需 source $WS/install/setup.bash）"

PREFIX="$(ros2 pkg prefix orbbec_camera)"
ok "软件包：orbbec_camera 可用（$PREFIX，版本 $(orbbec_src_version "$PREFIX/share")）"

# 1. 设备枚举
log "枚举设备：ros2 run orbbec_camera list_devices_node"
DEV_OUT="$(timeout 20 ros2 run orbbec_camera list_devices_node 2>&1 || true)"
printf '%s\n' "$DEV_OUT" | sed 's/^/     /'
if grep -qiE "serial|firmware|pid:|vid:" <<<"$DEV_OUT"; then
  ok "检测到相机设备"
else
  warn "未枚举到相机：请检查 USB3 线缆、供电与 udev 规则（见 docs/05-常见问题.md）"
fi

if [[ "$FULL" != "1" ]]; then
  echo "--------------------------------------------------"
  ok "基础验证完成；重新运行时可选择做启动冒烟测试"
  exit 0
fi

# 2. 启动冒烟测试
LAUNCH="$(orbbec_launch_for "$CAMERA")"
[[ -n "$LAUNCH" ]] || die "未知机型：$CAMERA（可用：gemini2 / gemini2l / gemini330 / gemini435le / femto_bolt / femto_mega / astra2 ...）"
LOG_FILE="$(mktemp -t orbbec_launch_XXXX.log)"
log "启动冒烟测试：ros2 launch orbbec_camera $LAUNCH（日志：$LOG_FILE）"

timeout 30 ros2 launch orbbec_camera "$LAUNCH" >"$LOG_FILE" 2>&1 &
LPID=$!
trap 'kill "$LPID" 2>/dev/null || true' EXIT

for _ in $(seq 1 20); do
  sleep 1
  if ros2 topic list 2>/dev/null | grep -q "^/camera/color/image_raw$"; then break; fi
done

TOPICS="$(ros2 topic list 2>/dev/null || true)"
kill "$LPID" 2>/dev/null || true
wait "$LPID" 2>/dev/null || true
trap - EXIT

if grep -q "^/camera/color/image_raw$" <<<"$TOPICS"; then
  ok "相机节点启动成功，彩色话题已发布"
  grep -E "^/camera/(color|depth|ir)/" <<<"$TOPICS" | sed 's/^/     /' | head -20
else
  warn "未在 20 秒内看到 /camera/color/image_raw，最近日志："
  tail -n 30 "$LOG_FILE" | sed 's/^/     /'
  die "启动冒烟测试失败（参考 docs/05-常见问题.md）"
fi
