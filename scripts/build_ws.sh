#!/usr/bin/env bash
# 编译工作空间：colcon build（Release）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WS="${ORBBEC_WS:-$(default_ws)}"
ROS_ARG="${ORBBEC_ROS_ARG:-}"
JOBS="${ORBBEC_JOBS:-}"
DRY_RUN="${ORBBEC_DRY_RUN:-0}"
export DRY_RUN

if ! is_orchestrated && [[ -t 0 && "$DRY_RUN" != "1" && -z "$JOBS" ]]; then
  read -r -p "并行编译任务数（直接回车 = colcon 自动）：" _jobs || _jobs=""
  JOBS="$_jobs"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  [[ -f "$WS/src/OrbbecSDK_ROS2/orbbec_camera/package.xml" ]] \
    || log "预览：源码尚未就绪（实际安装时会先下载/复制）"
else
  [[ -d "$WS" ]] || die "工作空间不存在：$WS"
  [[ -f "$WS/src/OrbbecSDK_ROS2/orbbec_camera/package.xml" ]] \
    || die "未找到源码：$WS/src/OrbbecSDK_ROS2（请先准备源码）"
fi

DISTRO="${ROS_ARG:-$(detect_ros_distro)}"
[[ -n "$DISTRO" ]] || die "未检测到 ROS 2 安装"
ros_source "$(ros_setup_file "$DISTRO")"

ARGS=(build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release)
[[ -n "$JOBS" ]] && ARGS+=(--parallel-workers "$JOBS")

log "开始编译：$WS（ROS 2 $DISTRO）"
cd "$WS"
run colcon "${ARGS[@]}"

[[ -f "$WS/install/orbbec_camera/share/orbbec_camera/package.xml" || "$DRY_RUN" == "1" ]] \
  || die "编译未产出 orbbec_camera，请查看 log/latest_build 下的日志"
if [[ "$DRY_RUN" == "1" ]]; then
  log "预览：以上编译命令未执行"
else
  ok "编译完成：$WS/install"
fi
