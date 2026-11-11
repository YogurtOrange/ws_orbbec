#!/usr/bin/env bash
# Orbbec ROS2 相机 SDK 一键安装入口（Ubuntu 22.04 + ROS 2 Humble）
# 仅用于“已克隆本仓库”的用户：使用仓库内 src/OrbbecSDK_ROS2 源码编译。
# 没有本仓库请改用 install_official.sh（源码克隆 或 apt 二进制）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# 所有配置均由交互式选择产生；ORBBEC_* 仅用于内部编排与调试，不作为对外用法
WS="${ORBBEC_WS:-}"
CAMERA="${ORBBEC_CAMERA:-gemini2}"
ARCH="${ORBBEC_ARCH:-}"
ROS_ARG="${ORBBEC_ROS_ARG:-}"
ASSUME_YES="${ORBBEC_ASSUME_YES:-0}"
DRY_RUN="${ORBBEC_DRY_RUN:-0}"
SKIP_DEPS="${ORBBEC_SKIP_DEPS:-0}"
SKIP_UDEV="${ORBBEC_SKIP_UDEV:-0}"
SKIP_VERIFY="${ORBBEC_SKIP_VERIFY:-0}"
FORCE="${ORBBEC_FORCE:-0}"
NO_UPDATE="${ORBBEC_NO_UPDATE:-0}"

PREVIEW=0
if [[ -t 0 && "$ASSUME_YES" != "1" ]]; then
  while true; do
    printf '\n%s请选择操作%s（当前已在本仓库内，将使用本仓库源码编译）：\n' "$C_BOLD$C_BLUE" "$C_OFF"
    printf '  %s1)%s 源码编译：使用本仓库内已配置源码（推荐，v2.10.7，编译无需联网）\n' "$C_GREEN" "$C_OFF"
    printf '  %s2)%s 预览安装步骤（只打印将执行的命令，不实际安装）\n' "$C_BLUE" "$C_OFF"
    read -r -p "请输入 [1/2]（默认 1）：" CHOICE || CHOICE=""
    case "${CHOICE:-1}" in
      1) break ;;
      2) PREVIEW=1; break ;;
      *) echo "无效输入，请重新选择。"; continue ;;
    esac
  done
  echo
else
  log "非交互模式：使用源码编译（仓库内源码）"
fi

# 预览模式：只演练命令，跳过需要真实环境的验证
if [[ "$PREVIEW" == "1" ]]; then
  DRY_RUN=1
  SKIP_VERIFY=1
fi

export DRY_RUN
ARCH="${ARCH:-$(detect_arch)}"

# 固定根目录：无论本仓库放在哪里，源码一律安装到 ~/ws_orbbec
[[ -z "$WS" ]] && WS="$(default_ws)"

# 子脚本统一读取 ORBBEC_* 环境变量，不再接受命令行参数
export ORBBEC_ORCHESTRATED=1
export ORBBEC_WS="$WS"
export ORBBEC_ROS_ARG="$ROS_ARG"
export ORBBEC_ARCH="$ARCH"
export ORBBEC_CAMERA="$CAMERA"
export ORBBEC_DRY_RUN="$DRY_RUN"
export ORBBEC_ASSUME_YES="$ASSUME_YES"
export ORBBEC_NO_UPDATE="$NO_UPDATE"
export ORBBEC_FORCE="$FORCE"
export ORBBEC_SYSTEM=0

TARGET_REF="$(orbbec_src_version "$(repo_root)/src/OrbbecSDK_ROS2")"
TARGET_REF="${TARGET_REF:-跟随仓库源码}"

banner "Orbbec ROS2 一键安装（仓库入口）"
log "模式：仓库源码编译    架构：$ARCH    目标版本：$TARGET_REF"
log "工作空间：$WS"
if [[ "$PREVIEW" == "1" ]]; then
  warn "预览模式：只打印将执行的命令，不会修改系统"
fi

# ---------- 1. 环境自检 ----------
step_header 1 5 "环境自检"
"$SCRIPT_DIR/check_env.sh" || die "环境自检未通过"

# ---------- 2. 依赖 ----------
step_header 2 5 "安装依赖"
if [[ "$SKIP_DEPS" == "1" ]]; then
  warn "已跳过依赖安装"
else
  "$SCRIPT_DIR/install_deps.sh"
fi

# ---------- 3. 准备源码 ----------
step_header 3 5 "准备源码"
SRC_PKG="$WS/src/OrbbecSDK_ROS2"
# 严格使用本仓库源码：工作空间里没有就复制仓库里的，绝不回退到官方克隆
REPO_SRC="$(repo_root)/src/OrbbecSDK_ROS2"
if [[ -f "$REPO_SRC/orbbec_camera/package.xml" ]]; then
  if [[ -f "$SRC_PKG/orbbec_camera/package.xml" ]]; then
    ok "使用工作空间内源码：$SRC_PKG（版本 $(orbbec_src_version "$SRC_PKG")）"
  else
    mkdir -p "$WS/src"
    log "复制本仓库源码 -> $SRC_PKG"
    run cp -a "$REPO_SRC" "$SRC_PKG"
  fi
elif [[ -f "$SRC_PKG/orbbec_camera/package.xml" ]]; then
  ok "使用工作空间内源码：$SRC_PKG（版本 $(orbbec_src_version "$SRC_PKG")）"
else
  die "本仓库缺少源码：$REPO_SRC（请重新克隆本仓库；本入口不会从官方仓库下载源码）"
fi

# ---------- 4. 编译 ----------
step_header 4 5 "编译工作空间"
"$SCRIPT_DIR/build_ws.sh"

# ---------- 5. udev + 验证 ----------
step_header 5 5 "udev 与验证"
if [[ "$SKIP_UDEV" == "1" ]]; then
  warn "已跳过 udev 规则安装，普通用户可能无权打开相机"
else
  "$SCRIPT_DIR/install_udev.sh"
fi

if [[ "$SKIP_VERIFY" == "1" ]]; then
  if [[ "$PREVIEW" == "1" ]]; then
    warn "预览模式：跳过真实验证（仅演练）"
  else
    warn "已跳过验证"
  fi
else
  "$SCRIPT_DIR/verify.sh"
fi

# ---------- 收尾：写入 ~/.bashrc（可选） ----------
log "收尾：配置 ~/.bashrc（免去每次手动 source）"
DISTRO="${DISTRO:-$(detect_ros_distro)}"
[[ -n "$DISTRO" ]] || DISTRO="humble"
if [[ "$DRY_RUN" == "1" ]]; then
  orbbec_bashrc_write "$DISTRO" "$WS/install/setup.bash"
elif [[ -t 0 && "$ASSUME_YES" != "1" ]]; then
  read -r -p "是否写入 ~/.bashrc（以后新开终端自动加载）？[Y/n] " _rc || _rc=""
  if [[ -z "$_rc" || "$_rc" =~ ^[Yy] ]]; then
    orbbec_bashrc_write "$DISTRO" "$WS/install/setup.bash"
  else
    log "已跳过；需要时手动 source，或重新运行安装脚本"
  fi
else
  log "非交互模式：未修改 ~/.bashrc"
fi

if [[ "$PREVIEW" == "1" ]]; then
  banner "预览结束：未执行任何安装，系统保持原样"
  log "正式安装：./scripts/install.sh"
  exit 0
fi

LAUNCH="$(orbbec_launch_for "$CAMERA")"
[[ -n "$LAUNCH" ]] || LAUNCH="<机型>.launch.py"
banner "安装完成"
ok "工作空间：$WS"
log "加载环境：source $WS/install/setup.bash"
log "启动相机：ros2 launch orbbec_camera $LAUNCH"
log "查看图像：rqt_image_view  或  rviz2"

banner "致谢"
log "感谢使用本仓库的一键安装脚本"
log "仓库地址：https://github.com/YogurtOrange/ws_orbbec"
log "如果对你有帮助，欢迎 Star、提 Issue 或提交 PR"
log "详细文档：$(repo_root)/docs（遇到问题先看 05-常见问题.md）"
