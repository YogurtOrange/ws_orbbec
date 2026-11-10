#!/usr/bin/env bash
# 卸载：清理构建产物，可选移除 udev 规则与源码。
# 注意：不处理 apt 安装的二进制包（仓库入口已不提供 apt；
#       如曾用官方单文件脚本装过，请手动执行
#       sudo apt remove ros-humble-orbbec-camera ros-humble-orbbec-description）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WS="${ORBBEC_WS:-$(default_ws)}"
ASSUME_YES="${ORBBEC_ASSUME_YES:-0}"
REMOVE_UDEV="${ORBBEC_REMOVE_UDEV:-0}"
REMOVE_SRC="${ORBBEC_REMOVE_SRC:-0}"
DRY_RUN="${ORBBEC_DRY_RUN:-0}"
export DRY_RUN

if ! is_orchestrated && [[ -t 0 && "$ASSUME_YES" != "1" ]]; then
  echo "请选择清理范围："
  echo "  1) 仅构建产物（build/install/log）"
  echo "  2) 构建产物 + 源码"
  echo "  3) 构建产物 + 源码 + udev 规则"
  echo "  4) 取消"
  read -r -p "请输入 [1/2/3/4]（默认 1）：" _scope || _scope=""
  case "${_scope:-1}" in
    1) ;;
    2) REMOVE_SRC=1 ;;
    3) REMOVE_SRC=1; REMOVE_UDEV=1 ;;
    *) log "已取消"; exit 0 ;;
  esac
fi

confirm() {
  [[ "$ASSUME_YES" == "1" ]] && return 0
  local ans
  read -r -p "$1 [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

TARGETS=()
for d in build install log; do
  [[ -d "$WS/$d" ]] && TARGETS+=("$WS/$d")
done

[[ ${#TARGETS[@]} -gt 0 ]] || log "没有需要清理的构建目录"
if [[ ${#TARGETS[@]} -gt 0 ]]; then
  printf '将删除：\n'
  printf '  %s\n' "${TARGETS[@]}"
  confirm "确认删除以上构建产物？" || die "已取消"
  for t in "${TARGETS[@]}"; do
    run rm -rf "$t"
  done
  ok "构建产物已清理"
fi

if [[ "$REMOVE_UDEV" == "1" ]]; then
  if [[ -f /etc/udev/rules.d/99-obsensor-libusb.rules ]]; then
    confirm "确认删除 udev 规则？" || die "已取消"
    run sudo rm -f /etc/udev/rules.d/99-obsensor-libusb.rules
    run sudo udevadm control --reload-rules
    run sudo udevadm trigger
    ok "udev 规则已删除"
  else
    log "udev 规则不存在，跳过"
  fi
fi

if [[ "$REMOVE_SRC" == "1" ]]; then
  [[ -d "$WS/src/OrbbecSDK_ROS2" ]] || die "源码目录不存在：$WS/src/OrbbecSDK_ROS2"
  confirm "确认删除源码 $WS/src/OrbbecSDK_ROS2（含 .git 记录）？" || die "已取消"
  run rm -rf "$WS/src/OrbbecSDK_ROS2"
  ok "源码已删除"
fi

ok "卸载完成"
