#!/usr/bin/env bash
# =============================================================================
# Orbbec 相机 ROS 2 一键安装（单文件版，官方方式）
#
# 适用：Ubuntu 22.04 + ROS 2 Humble，仅需本文件，无需克隆任何仓库。
# 注意：已克隆本仓库的用户不要用本脚本，请用仓库内 ./scripts/install.sh；
#       若在本仓库目录内运行，脚本会检测到并直接退出。
# 两种安装方式：
#   1) 源码编译：克隆官方 tag（默认 v2.10.7，可选自动获取最新 tag）后 colcon build，可改代码
#   2) apt 二进制：安装官方 deb（2.9.3），速度最快，不可改代码
# 结束时可选择写入 ~/.bashrc，新开终端自动加载，免去每次手动 source。
#
# 用法：bash install_official.sh    （全部交互，无需参数）
# 调试用环境变量：ORBBEC_DRY_RUN=1 / ORBBEC_MODE=source|binary /
#                 ORBBEC_REF=v2.10.7|latest / ORBBEC_ASSUME_YES=1
# =============================================================================

set -euo pipefail

# ---------- 默认值 ----------
WS="${ORBBEC_WS:-$HOME/ws_orbbec}"
MODE="${ORBBEC_MODE:-}"
REF="${ORBBEC_REF:-}"
REF_SET="${ORBBEC_REF_SET:-0}"
GIT_URL="${ORBBEC_GIT_URL:-https://github.com/orbbec/OrbbecSDK_ROS2.git}"
MIRROR_URL="https://gitee.com/orbbecdeveloper/OrbbecSDK_ROS2.git"
DRY_RUN="${ORBBEC_DRY_RUN:-0}"
ASSUME_YES="${ORBBEC_ASSUME_YES:-0}"
DEFAULT_REF="v2.10.7"

# ---------- 日志 ----------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""; C_DIM=""; C_OFF=""
fi
log()  { printf '%s[信息]%s %s\n' "$C_CYAN" "$C_OFF" "$*"; }
ok()   { printf '%s[完成]%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%s[警告]%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
die()  { printf '%s[失败]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# 进度条 + 步骤标题：step_header 2 5 "安装依赖"
step_header() {
  local i="$1" n="$2" title="$3"
  local width=20 filled pct fill="" empty="" j
  filled=$(( i * width / n ))
  pct=$(( i * 100 / n ))
  for (( j = 0; j < width; j++ )); do
    if (( j < filled )); then fill+="█"; else empty+="░"; fi
  done
  printf '\n[%s%s%s%s%s] %3d%%  %s步骤 %s/%s · %s%s\n' \
    "$C_GREEN" "$fill" "$C_DIM" "$empty" "$C_OFF" "$pct" \
    "$C_BOLD$C_CYAN" "$i" "$n" "$title" "$C_OFF"
}

# 顶部横幅：banner "标题"
banner() {
  local line="────────────────────────────────────────────────────────"
  printf '\n%s%s%s\n' "$C_CYAN" "$line" "$C_OFF"
  printf '%s%s%s\n' "$C_BOLD" "$*" "$C_OFF"
  printf '%s%s%s\n' "$C_CYAN" "$line" "$C_OFF"
}

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[演练]%s %s\n' "$C_YELLOW" "$C_OFF" "$*"
  else
    "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# 严格区分两种安装路线：本脚本只服务“没有本仓库”的用户
if [[ -f "$SCRIPT_DIR/scripts/install.sh" && -d "$SCRIPT_DIR/src/OrbbecSDK_ROS2" ]]; then
  die "检测到本脚本位于教程仓库内（$SCRIPT_DIR）。
      已克隆本仓库的用户请在该仓库运行 ./scripts/install.sh，使用仓库内源码编译；
      本脚本（官方方式）只供没有克隆本仓库的用户使用，不做仓库源码编译。"
fi

detect_ros_distro() {
  if [[ -n "${ROS_DISTRO:-}" && -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    echo "$ROS_DISTRO"; return
  fi
  local d
  for d in humble jazzy foxy; do
    [[ -f "/opt/ros/${d}/setup.bash" ]] && { echo "$d"; return; }
  done
  echo ""
}

ros_source() {
  set +u
  # shellcheck disable=SC1090
  source "$1"
  set -u
}

resolve_latest_ref() {
  local url="$1"
  timeout 20 git ls-remote --tags --refs "$url" 2>/dev/null \
    | awk -F/ '{print $NF}' | grep -E '^v[0-9]+\.[0-9]+' | sort -V | tail -1 || true
}

# ---------- ~/.bashrc ----------
BASHRC_BEGIN="# >>> orbbec_camera (ws_orbbec installer) >>>"
BASHRC_END="# <<< orbbec_camera (ws_orbbec installer) <<<"

bashrc_has_block() { grep -qF "$BASHRC_BEGIN" "$HOME/.bashrc" 2>/dev/null; }

# $1 = 工作空间 setup.bash；apt 模式传空（只需 source ROS 环境）
bashrc_block_text() {
  local ws_setup="${1:-}"
  echo "$BASHRC_BEGIN"
  echo "source /opt/ros/${DISTRO}/setup.bash"
  [[ -n "$ws_setup" ]] && echo "source ${ws_setup}"
  echo "$BASHRC_END"
}

# 幂等写入：已有同名块则整体替换，否则追加
bashrc_write() {
  local ws_setup="${1:-}" rc="$HOME/.bashrc" block current tmp
  block="$(bashrc_block_text "$ws_setup")"
  if bashrc_has_block; then
    current="$(awk -v b="$BASHRC_BEGIN" -v e="$BASHRC_END" '
      $0==b {inside=1; print; next}
      $0==e {inside=0; print; next}
      inside {print}
    ' "$rc")"
    if [[ "$current" == "$block" ]]; then
      ok "~/.bashrc 已包含 Orbbec 环境，无需重复写入"
      return 0
    fi
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[演练]%s 将写入 %s：\n' "$C_YELLOW" "$C_OFF" "$rc"
    printf '%s\n' "$block" | sed 's/^/     /'
    return 0
  fi
  touch "$rc"
  if bashrc_has_block; then
    tmp="$(mktemp)"
    awk -v b="$BASHRC_BEGIN" -v e="$BASHRC_END" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      !skip {print}
    ' "$rc" > "$tmp"
    printf '%s\n' "$block" >> "$tmp"
    cat "$tmp" > "$rc"
    rm -f "$tmp"
    ok "已更新 ~/.bashrc 中的 Orbbec 环境"
  else
    printf '\n%s\n' "$block" >> "$rc"
    ok "已写入 ~/.bashrc：新开终端自动加载"
  fi
}

# ---------- 0. 交互选择 ----------
banner "Orbbec 相机 ROS 2 一键安装（单文件版）"

INTERACTIVE=0
if [[ -t 0 && "$ASSUME_YES" != "1" ]]; then INTERACTIVE=1; fi

if [[ -z "$MODE" ]]; then
  if [[ "$INTERACTIVE" == "1" ]]; then
    printf '\n%s两种安装方式的区别：%s\n' "$C_BOLD" "$C_OFF"
    printf '  %s源码编译%s：官方最新 v2.10.7，可改代码/launch；需克隆并编译（约 2-3 分钟）\n' "$C_GREEN" "$C_OFF"
    printf '            安装到 ~/ws_orbbec/install，可随时调整参数\n'
    printf '  %sapt 二进制%s：官方源 2.9.3（比源码版旧），装完即用（约 30 秒）\n' "$C_YELLOW" "$C_OFF"
    printf '            安装到 /opt/ros/humble 系统目录，不能修改代码\n'
    printf '\n%s请选择安装方式：%s\n' "$C_BOLD$C_CYAN" "$C_OFF"
    printf '  %s1)%s 源码编译（推荐）\n' "$C_GREEN" "$C_OFF"
    printf '  %s2)%s apt 二进制\n' "$C_YELLOW" "$C_OFF"
    read -r -p "请输入 [1/2]（默认 1）：" MODE_CHOICE || MODE_CHOICE=""
    case "${MODE_CHOICE:-1}" in
      2) MODE="binary" ;;
      *) MODE="source" ;;
    esac
    echo
  else
    MODE="source"
  fi
fi

case "$MODE" in
  source|binary) ;;
  *) die "无效的安装方式：$MODE" ;;
esac

if [[ "$MODE" == "binary" ]]; then
  TOTAL=4; STEP_UDEV=3; STEP_VERIFY=4
else
  TOTAL=6; STEP_UDEV=5; STEP_VERIFY=6
fi

if [[ "$MODE" == "source" ]]; then
  if [[ "$REF_SET" == "0" ]]; then
    if [[ "$INTERACTIVE" == "1" ]]; then
      printf '\n%s请选择要安装的版本：%s\n' "$C_BOLD$C_CYAN" "$C_OFF"
      printf '  %s1)%s 固定版本 %s（已验证可用，推荐）\n' "$C_GREEN" "$C_OFF" "$DEFAULT_REF"
      printf '  %s2)%s 最新版本（自动获取官方最新 tag，可能不兼容）\n' "$C_CYAN" "$C_OFF"
      read -r -p "请输入 [1/2]（默认 1）：" VER_CHOICE || VER_CHOICE=""
      case "${VER_CHOICE:-1}" in
        2) REF="latest" ;;
        *) REF="$DEFAULT_REF" ;;
      esac
      echo
    else
      REF="$DEFAULT_REF"
    fi
  fi
fi

if [[ "$INTERACTIVE" == "1" ]]; then
  read -r -p "是否先预览安装步骤（只打印命令，不实际安装）？[y/N] " _pv || _pv=""
  [[ "$_pv" =~ ^[Yy] ]] && DRY_RUN=1
  if [[ "$MODE" == "source" ]]; then
    printf '\n%s源码来源：%s\n' "$C_BOLD$C_CYAN" "$C_OFF"
    printf '  %s1)%s GitHub（默认）\n' "$C_GREEN" "$C_OFF"
    printf '  %s2)%s Gitee 镜像（国内更快）\n' "$C_CYAN" "$C_OFF"
    read -r -p "请输入 [1/2]（默认 1）：" _mir || _mir=""
    [[ "${_mir:-1}" == "2" ]] && GIT_URL="$MIRROR_URL"
  fi
  echo
fi

# ---------- 1. 环境自检 ----------
step_header 1 "$TOTAL" "环境自检"
[[ -r /etc/os-release ]] || die "无法读取 /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "22.04" ]] \
  || die "仅支持 Ubuntu 22.04（当前：${PRETTY_NAME:-未知}）"
ok "操作系统：$PRETTY_NAME"

DISTRO="$(detect_ros_distro)"
[[ -n "$DISTRO" ]] || die "未检测到 ROS 2，请先安装 ROS 2 Humble"
[[ "$DISTRO" == "humble" ]] || warn "检测到 ROS 2 $DISTRO，本脚本按 humble 验证，其他版本可能不兼容"
ok "ROS 2 发行版：$DISTRO（/opt/ros/$DISTRO/setup.bash）"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "不支持的架构：$ARCH" ;;
esac
ok "目标架构：$ARCH"

if [[ "$MODE" == "source" ]]; then
  for t in git colcon cmake gcc g++ sudo timeout; do
    command -v "$t" >/dev/null 2>&1 || die "缺少必要工具：$t"
  done
  ok "工具链：git / colcon / cmake / gcc / g++ / sudo 均可用"
else
  for t in sudo timeout; do
    command -v "$t" >/dev/null 2>&1 || die "缺少必要工具：$t"
  done
  ok "工具链：sudo / timeout 可用（apt 安装不需要编译器）"
fi

if lsusb 2>/dev/null | grep -qi "2bc5:"; then
  ok "USB：检测到 Orbbec 设备（VID 2bc5）"
else
  warn "USB：未检测到 Orbbec 设备（VID 2bc5），不影响安装，但最后无法枚举相机"
fi

# ---------- 2. 安装 ----------
if [[ "$MODE" == "binary" ]]; then
  step_header 2 "$TOTAL" "apt 安装官方包"
  log "将安装 ros-$DISTRO-orbbec-camera / ros-$DISTRO-orbbec-description（2.9.3）"
  run sudo apt-get update
  run sudo apt-get install -y "ros-$DISTRO-orbbec-camera" "ros-$DISTRO-orbbec-description"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "预览：以上安装命令未执行"
  else
    ok "apt 包安装完成（版本以 apt 源为准，通常为 2.9.3）"
  fi
  SRC_RULE="/opt/ros/$DISTRO/share/orbbec_camera/udev/99-obsensor-libusb.rules"
else
  step_header 2 "$TOTAL" "安装依赖"
  DEBS=(
    libgflags-dev nlohmann-json3-dev libdw-dev libssl-dev libeigen3-dev
    libopencv-dev libyaml-cpp-dev pkg-config mesa-utils libgl1 libgoogle-glog-dev
    "ros-${DISTRO}-image-transport"
    "ros-${DISTRO}-image-transport-plugins"
    "ros-${DISTRO}-compressed-image-transport"
    "ros-${DISTRO}-image-publisher"
    "ros-${DISTRO}-camera-info-manager"
    "ros-${DISTRO}-diagnostic-updater"
    "ros-${DISTRO}-diagnostic-msgs"
    "ros-${DISTRO}-statistics-msgs"
    "ros-${DISTRO}-xacro"
    "ros-${DISTRO}-backward-ros"
    "ros-${DISTRO}-pluginlib"
    "ros-${DISTRO}-message-filters"
    "ros-${DISTRO}-rclcpp-action"
    "ros-${DISTRO}-geometry-msgs"
    "ros-${DISTRO}-rcl-interfaces"
    "ros-${DISTRO}-rmw"
    "ros-${DISTRO}-ament-index-python"
    "ros-${DISTRO}-launch"
    "ros-${DISTRO}-launch-ros"
    python3-psutil python3-tabulate python3-yaml
  )
  log "将安装 ${#DEBS[@]} 个依赖"
  run sudo apt-get update
  run sudo apt-get install -y "${DEBS[@]}"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "预览：以上安装命令未执行"
  else
    ok "依赖安装完成"
  fi

  # ---------- 3. 克隆官方源码 ----------
  step_header 3 "$TOTAL" "克隆官方源码"
  if [[ "$REF" == "latest" ]]; then
    log "查询最新 tag ..."
    LATEST=""
    for u in "$GIT_URL" "$MIRROR_URL"; do
      LATEST="$(resolve_latest_ref "$u" || true)"
      [[ -n "$LATEST" ]] && { GIT_URL="$u"; break; }
    done
    [[ -n "$LATEST" ]] || die "无法获取最新 tag，请检查网络"
    REF="$LATEST"
    ok "最新版本：$REF"
  fi
  ok "目标版本：$REF"

  SRC="$WS/src/OrbbecSDK_ROS2"
  mkdir -p "$WS/src"
  if [[ -d "$SRC" ]]; then
    BACKUP="$SRC.bak.$(date +%Y%m%d%H%M%S)"
    warn "已存在源码，先备份：$SRC -> $BACKUP"
    run mv "$SRC" "$BACKUP"
  fi

  log "克隆官方仓库：$GIT_URL（$REF）"
  if ! run git clone --depth 1 --branch "$REF" "$GIT_URL" "$SRC"; then
    rm -rf "$SRC"
    warn "克隆失败，尝试 Gitee 镜像：$MIRROR_URL"
    run git clone --depth 1 --branch "$REF" "$MIRROR_URL" "$SRC" \
      || die "克隆失败：请检查网络/代理后重试"
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    ok "预览：源码将来自 $GIT_URL（$REF）"
  else
    ok "源码已就绪：$SRC"
  fi

  # ---------- 4. 编译 ----------
  step_header 4 "$TOTAL" "编译工作空间"
  ros_source "/opt/ros/$DISTRO/setup.bash"
  if [[ "$DRY_RUN" == "1" ]]; then
    run colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
    log "预览：以上编译命令未执行"
  else
    ( cd "$WS" && colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release )
    ok "编译完成：$WS/install"
  fi
  SRC_RULE="$WS/install/orbbec_camera/share/orbbec_camera/udev/99-obsensor-libusb.rules"
fi

# ---------- 5. udev ----------
step_header "$STEP_UDEV" "$TOTAL" "安装 udev 规则"
TARGET=/etc/udev/rules.d/99-obsensor-libusb.rules
if [[ ! -f "$SRC_RULE" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    warn "预览：本机暂未找到 99-obsensor-libusb.rules（实际安装后会生成）"
  else
    die "未找到 99-obsensor-libusb.rules（$SRC_RULE）"
  fi
fi
if [[ -f "$SRC_RULE" ]]; then
  if [[ -f "$TARGET" ]] && cmp -s "$SRC_RULE" "$TARGET"; then
    ok "udev 规则已是最新：$TARGET"
  else
    run sudo install -m 644 "$SRC_RULE" "$TARGET"
    run sudo udevadm control --reload-rules
    run sudo udevadm trigger
    if [[ "$DRY_RUN" == "1" ]]; then
      log "预览：以上命令未执行"
    else
      ok "udev 规则已安装，请重新插拔相机"
    fi
  fi
fi

# ---------- 6. 验证 ----------
step_header "$STEP_VERIFY" "$TOTAL" "验证"
if [[ "$DRY_RUN" == "1" ]]; then
  ok "预览模式：跳过真实验证"
else
  if [[ "$MODE" == "binary" ]]; then
    ros_source "/opt/ros/$DISTRO/setup.bash"
  else
    ros_source "$WS/install/setup.bash"
  fi
  PREFIX="$(ros2 pkg prefix orbbec_camera 2>/dev/null)" \
    || die "未找到 orbbec_camera 包，安装可能失败"
  ok "软件包：orbbec_camera（$PREFIX）"
  log "枚举设备：ros2 run orbbec_camera list_devices_node"
  DEV_OUT="$(timeout 20 ros2 run orbbec_camera list_devices_node 2>&1 || true)"
  printf '%s\n' "$DEV_OUT" | sed 's/^/     /'
  if grep -qiE "serial|firmware|pid:|vid:" <<<"$DEV_OUT"; then
    ok "检测到相机设备"
  else
    warn "未枚举到相机：请检查 USB3 线缆、供电与 udev 规则"
  fi
fi

# ---------- 收尾：写入 ~/.bashrc ----------
log "收尾：配置 ~/.bashrc（免去每次手动 source）"
if [[ "$MODE" == "binary" ]]; then
  BASHRC_SETUP=""
else
  BASHRC_SETUP="$WS/install/setup.bash"
fi
if [[ "$DRY_RUN" == "1" ]]; then
  bashrc_write "$BASHRC_SETUP"
elif [[ "$INTERACTIVE" == "1" ]]; then
  read -r -p "是否写入 ~/.bashrc（以后新开终端自动加载）？[Y/n] " _rc || _rc=""
  if [[ -z "$_rc" || "$_rc" =~ ^[Yy] ]]; then
    bashrc_write "$BASHRC_SETUP"
  else
    log "已跳过；需要时手动 source，或重新运行脚本"
  fi
else
  log "非交互模式：未修改 ~/.bashrc"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  banner "预览结束：未执行任何安装，系统保持原样"
  log "正式安装：bash install_official.sh"
  exit 0
fi

if [[ "$MODE" == "binary" ]]; then
  banner "安装完成（apt 二进制）"
  ok "加载环境：source /opt/ros/$DISTRO/setup.bash"
  log "启动相机：ros2 launch orbbec_camera gemini2.launch.py"
  log "卸载方式：sudo apt remove ros-$DISTRO-orbbec-camera ros-$DISTRO-orbbec-description"
  warn "二进制版不能修改 launch/源码；需要改参数请改用源码编译"
else
  banner "安装完成（源码编译）"
  ok "工作空间：$WS"
  log "加载环境：source $WS/install/setup.bash"
  log "启动相机：ros2 launch orbbec_camera gemini2.launch.py"
  log "查看图像：rqt_image_view  或  rviz2"
fi
