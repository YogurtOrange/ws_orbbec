#!/usr/bin/env bash
# 编译工作空间：colcon build（Release + symlink），交互选择并行任务数。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WS="${ORBBEC_WS:-$(default_ws)}"
ROS_ARG="${ORBBEC_ROS_ARG:-}"
DRY_RUN="${ORBBEC_DRY_RUN:-0}"
export DRY_RUN

# 并行数：默认推荐值按内存与核数收敛（ARM 低内存板防卡死/OOM），
# 有终端时用菜单选择；预览/非交互模式直接用推荐值。
RECOMMEND="$(suggest_jobs)"
log_build_hardware
if [[ "$DRY_RUN" != "1" && -t 0 && "${ORBBEC_ASSUME_YES:-0}" != "1" ]]; then
  JOBS="$(ask_jobs "$RECOMMEND")"
else
  JOBS="$RECOMMEND"
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
if [[ -n "$JOBS" ]]; then
  ARGS+=(--parallel-workers "$JOBS")
  # 同时限制包级并发（--parallel-workers）与单个包内 make/ninja 的并发，
  # 否则单包编译仍会按全部核数拉起进程，低内存板容易卡死。
  export MAKEFLAGS="-j${JOBS}"
  export CMAKE_BUILD_PARALLEL_LEVEL="$JOBS"
  log "并行编译：$JOBS 个任务"
  [[ "$DRY_RUN" == "1" ]] \
    && log "预览：将额外设置 MAKEFLAGS=-j$JOBS CMAKE_BUILD_PARALLEL_LEVEL=$JOBS"
else
  warn "并行编译：colcon 自动（按 CPU 核数），低内存板建议重新运行并手动指定较小值"
fi

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
