#!/usr/bin/env bash
# 安装 OrbbecSDK_ROS2 所需的 apt 依赖（官方 README 清单）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ROS_ARG="${ORBBEC_ROS_ARG:-}"
DRY_RUN="${ORBBEC_DRY_RUN:-0}"
DO_UPDATE=1
[[ "${ORBBEC_NO_UPDATE:-0}" == "1" ]] && DO_UPDATE=0
export DRY_RUN

DISTRO="${ROS_ARG:-$(detect_ros_distro)}"
[[ -n "$DISTRO" ]] || die "未检测到 ROS 2 安装，请先安装 ROS 2 Humble"

mapfile -t PKGS < <(orbbec_deb_packages "$DISTRO")
log "将安装 ${#PKGS[@]} 个依赖（ROS 发行版：$DISTRO）"

MISSING=()
for p in "${PKGS[@]}"; do
  if ! apt-cache show "$p" >/dev/null 2>&1; then
    MISSING+=("$p")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  printf '     缺失：%s\n' "${MISSING[*]}"
  die "apt 源中找不到上述软件包，请确认已添加 ROS 2 apt 源与 Ubuntu universe 源（见 docs/01-环境准备.md）"
fi

if ! is_orchestrated && [[ "$DRY_RUN" != "1" && -t 0 ]]; then
  read -r -p "确认安装以上依赖？[Y/n] " _ans || _ans=""
  [[ -z "$_ans" || "$_ans" =~ ^[Yy] ]] || { log "已取消"; exit 0; }
fi

if [[ "$DO_UPDATE" == "1" ]]; then
  log "更新 apt 索引 ..."
  run sudo apt-get update
fi

log "安装依赖 ..."
run sudo apt-get install -y "${PKGS[@]}"
if [[ "$DRY_RUN" == "1" ]]; then
  log "预览：以上命令未执行"
else
  ok "依赖安装完成"
fi
