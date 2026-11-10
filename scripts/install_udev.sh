#!/usr/bin/env bash
# 安装 Orbbec 相机 udev 规则（必须步骤，否则普通用户无权打开设备）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WS="${ORBBEC_WS:-$(default_ws)}"
DRY_RUN="${ORBBEC_DRY_RUN:-0}"
SYSTEM="${ORBBEC_SYSTEM:-0}"
export DRY_RUN

if ! is_orchestrated && [[ -t 0 && "$DRY_RUN" != "1" ]]; then
  echo "从哪个位置取 udev 规则？"
  echo "  1) 源码编译的工作空间（$WS/install）"
  echo "  2) apt 二进制安装（/opt/ros/*/share）"
  read -r -p "请输入 [1/2]（默认 1）：" _loc || _loc=""
  [[ "${_loc:-1}" == "2" ]] && SYSTEM=1
fi

TARGET=/etc/udev/rules.d/99-obsensor-libusb.rules
SRC_RULE=""
if [[ "$SYSTEM" == "1" ]]; then
  PATH_LIST=(/opt/ros/*/share/orbbec_camera/udev/99-obsensor-libusb.rules)
else
  PATH_LIST=(
    "$WS/install/orbbec_camera/share/orbbec_camera/udev/99-obsensor-libusb.rules"
    "$WS/src/OrbbecSDK_ROS2/orbbec_camera/scripts/99-obsensor-libusb.rules"
  )
fi
for p in "${PATH_LIST[@]}"; do
  if [[ -f "$p" ]]; then SRC_RULE="$p"; break; fi
done
if [[ -z "$SRC_RULE" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    warn "预览：本机暂未找到 99-obsensor-libusb.rules（实际安装后会生成），跳过 udev 步骤"
    exit 0
  fi
  die "未找到 99-obsensor-libusb.rules，请先完成编译/安装或检查源码"
fi

if [[ -f "$TARGET" ]] && cmp -s "$SRC_RULE" "$TARGET"; then
  ok "udev 规则已是最新：$TARGET"
else
  if ! is_orchestrated && [[ "$DRY_RUN" != "1" && -t 0 ]]; then
    read -r -p "将写入 $TARGET（需要 sudo），是否继续？[Y/n] " _ans || _ans=""
    [[ -z "$_ans" || "$_ans" =~ ^[Yy] ]] || { log "已取消"; exit 0; }
  fi
  log "安装 udev 规则：$SRC_RULE -> $TARGET"
  run sudo install -m 644 "$SRC_RULE" "$TARGET"
fi

log "重载 udev 规则 ..."
run sudo udevadm control --reload-rules
run sudo udevadm trigger
if [[ "$DRY_RUN" == "1" ]]; then
  log "预览：以上命令未执行"
else
  ok "udev 规则安装完成，请重新插拔相机后再启动节点"
fi
