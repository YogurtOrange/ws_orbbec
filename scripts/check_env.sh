#!/usr/bin/env bash
# 环境自检：Ubuntu 版本、ROS 2 发行版、CPU 架构、工具链、USB 设备与 udev 规则。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FORCE="${ORBBEC_FORCE:-0}"
ROS_ARG="${ORBBEC_ROS_ARG:-}"
ARCH_ARG="${ORBBEC_ARCH:-}"

ERRORS=0
err() { printf '%s[失败]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; ERRORS=$((ERRORS + 1)); }

banner "Orbbec ROS2 环境自检"

# 1. 操作系统
UBU_VER="$(ubuntu_version)"
# 非 22.04 时交互确认（编排模式下由 install.sh 决定）
if [[ "$UBU_VER" != "22.04" && "$FORCE" == "0" ]] && ! is_orchestrated && [[ -t 0 ]]; then
  warn "当前 Ubuntu ${UBU_VER:-未知}，本教程仅在 22.04 上验证"
  read -r -p "仍要继续？[y/N] " _ans || _ans=""
  [[ "$_ans" =~ ^[Yy] ]] && FORCE=1
fi
if [[ "$UBU_VER" == "22.04" ]]; then
  ok "操作系统：Ubuntu $UBU_VER"
elif [[ "$FORCE" == "1" ]]; then
  warn "操作系统为 Ubuntu ${UBU_VER:-未知}，非 22.04，已确认继续"
else
  err "需要 Ubuntu 22.04，当前为 ${UBU_VER:-未知}（交互运行时可选择继续）"
fi
printf '     内核：%s / 机器型号：%s\n' "$(uname -r)" "$(uname -m)"

# 2. ROS 2
DISTRO="${ROS_ARG:-$(detect_ros_distro)}"
if [[ -z "$DISTRO" ]]; then
  err "未找到 /opt/ros/*/setup.bash，请先安装 ROS 2 Humble（见 docs/01-环境准备.md）"
elif [[ ! -f "$(ros_setup_file "$DISTRO")" ]]; then
  err "指定发行版 $DISTRO 未安装：$(ros_setup_file "$DISTRO") 不存在"
else
  ok "ROS 2 发行版：$DISTRO（$(ros_setup_file "$DISTRO")）"
fi

# 3. 目标架构
ARCH="${ARCH_ARG:-$(detect_arch)}"
[[ "$ARCH" == "amd64" || "$ARCH" == "arm64" ]] || err "不支持的架构：$ARCH（仅 amd64 / arm64）"
if [[ -n "$ARCH_ARG" && "$ARCH_ARG" != "$(detect_arch)" ]]; then
  warn "目标架构 $ARCH 与当前机器 $(detect_arch) 不一致，源码构建可能失败"
else
  ok "目标架构：$ARCH"
fi

# 4. 工具链
for cmd in colcon cmake gcc g++ git sudo timeout; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "工具链：$cmd 已安装"
  else
    err "工具链：缺少 $cmd"
  fi
done

# 5. 相机与 udev
if command -v lsusb >/dev/null 2>&1; then
  if lsusb 2>/dev/null | grep -qi "2bc5"; then
    ok "USB：检测到 Orbbec 设备（VID 2bc5）"
    lsusb 2>/dev/null | grep -i "2bc5" | sed 's/^/     /'
  else
    warn "USB：未检测到 Orbbec 设备（VID 2bc5），请确认已插好相机与 USB3 线缆"
  fi
fi

if [[ -f /etc/udev/rules.d/99-obsensor-libusb.rules ]]; then
  ok "udev：规则已安装（/etc/udev/rules.d/99-obsensor-libusb.rules）"
else
  warn "udev：规则未安装，构建后请执行 scripts/install_udev.sh（否则会 Permission denied）"
fi

# 6. 当前工作空间
if [[ -f "$(repo_root)/src/OrbbecSDK_ROS2/orbbec_camera/package.xml" ]]; then
  ok "源码：$(repo_root)/src/OrbbecSDK_ROS2 已就绪"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  die "自检发现 $ERRORS 项问题，请先处理后再安装（参考 docs/05-常见问题.md）"
fi
ok "环境自检通过"
