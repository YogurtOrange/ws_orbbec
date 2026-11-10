#!/usr/bin/env bash
# Orbbec ROS2 安装教程公共库：日志/进度条/横幅、环境探测、依赖清单、机型映射、~/.bashrc 写入。
# 用法：source "$SCRIPT_DIR/lib/common.sh"

if [[ -n "${ORBBEC_COMMON_LOADED:-}" ]]; then
  return 0
fi
ORBBEC_COMMON_LOADED=1

# ---------- 日志 ----------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_DIM=""; C_OFF=""
fi

log()  { printf '%s[信息]%s %s\n' "$C_BLUE"   "$C_OFF" "$*"; }
ok()   { printf '%s[完成]%s %s\n' "$C_GREEN"  "$C_OFF" "$*"; }
warn() { printf '%s[警告]%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%s[失败]%s %s\n' "$C_RED"    "$C_OFF" "$*" >&2; exit 1; }

# ---------- 进度显示 ----------
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
    "$C_BOLD$C_BLUE" "$i" "$n" "$title" "$C_OFF"
}

# 顶部横幅：banner "标题"
banner() {
  local line="────────────────────────────────────────────────────────"
  printf '\n%s%s%s\n' "$C_BLUE" "$line" "$C_OFF"
  printf '%s%s%s\n' "$C_BOLD" "$*" "$C_OFF"
  printf '%s%s%s\n' "$C_BLUE" "$line" "$C_OFF"
}

# 演练模式（DRY_RUN=1 时只打印命令）
run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s[演练]%s %s\n' "$C_YELLOW" "$C_OFF" "$*"
  else
    "$@"
  fi
}

# 编排模式：install.sh 通过环境变量向子脚本传配置，子脚本不再接受命令行参数
is_orchestrated() { [[ "${ORBBEC_ORCHESTRATED:-0}" == "1" ]]; }

# ---------- 路径 ----------
# 本仓库根目录：scripts/lib/ 的上两级
repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd -P; }

# 固定的工作空间根目录：仓库入口与官方单文件安装统一使用 ~/ws_orbbec
default_ws() { echo "$HOME/ws_orbbec"; }

orbbec_src_version() {
  local p="$1/orbbec_camera/package.xml"
  if [[ -f "$p" ]]; then
    sed -n 's:.*<version>[[:space:]]*\([^<]*\)</version>.*:\1:p' "$p" | head -1
  fi
  return 0
}

# ---------- 环境探测 ----------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "unknown" ;;
  esac
}

detect_ros_distro() {
  if [[ -n "${ROS_DISTRO:-}" && -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    echo "$ROS_DISTRO"
    return
  fi
  local d
  for d in humble jazzy foxy; do
    if [[ -f "/opt/ros/${d}/setup.bash" ]]; then
      echo "$d"
      return
    fi
  done
  echo ""
}

ros_setup_file() { echo "/opt/ros/${1}/setup.bash"; }

# ROS 的 setup.bash 不是 set -u 安全的，source 时临时关闭 nounset
ros_source() {
  local f="$1"
  [[ -f "$f" ]] || die "环境脚本不存在：$f"
  set +u
  # shellcheck disable=SC1090
  source "$f"
  local rc=$?
  set -u
  return "$rc"
}

# ---------- 官方依赖清单（v2.10.7） ----------
# 来源：https://github.com/orbbec/OrbbecSDK_ROS2/blob/v2-main/README_CN.MD
# 同时按 orbbec_camera/package.xml 补齐 v2.10.x 新增依赖
orbbec_deb_packages() {
  local d="${1:-humble}"
  cat <<EOF
libgflags-dev
nlohmann-json3-dev
libdw-dev
libssl-dev
libeigen3-dev
libopencv-dev
libyaml-cpp-dev
pkg-config
mesa-utils
libgl1
libgoogle-glog-dev
ros-${d}-image-transport
ros-${d}-image-transport-plugins
ros-${d}-compressed-image-transport
ros-${d}-image-publisher
ros-${d}-camera-info-manager
ros-${d}-diagnostic-updater
ros-${d}-diagnostic-msgs
ros-${d}-statistics-msgs
ros-${d}-xacro
ros-${d}-backward-ros
ros-${d}-pluginlib
ros-${d}-message-filters
ros-${d}-rclcpp-action
ros-${d}-geometry-msgs
ros-${d}-rcl-interfaces
ros-${d}-rmw
ros-${d}-ament-index-python
ros-${d}-launch
ros-${d}-launch-ros
python3-psutil
python3-tabulate
python3-yaml
EOF
}

# ---------- 机型 -> launch 文件 ----------
orbbec_launch_for() {
  case "${1,,}" in
    gemini2|gemini_2)            echo "gemini2.launch.py" ;;
    gemini2l|gemini_2_l)         echo "gemini2L.launch.py" ;;
    gemini210|gemini_210)        echo "gemini210.launch.py" ;;
    gemini305|gemini_305)        echo "gemini305.launch.py" ;;
    gemini330|gemini_330|gemini_330_series) echo "gemini_330_series.launch.py" ;;
    gemini435|gemini435le|gemini_435_le)    echo "gemini435_le.launch.py" ;;
    gemini345|gemini_345)        echo "gemini345.launch.py" ;;
    femto|femto_bolt|femtobolt)  echo "femto_bolt.launch.py" ;;
    femto_mega|femtomega)        echo "femto_mega.launch.py" ;;
    astra2|astra_2)              echo "astra2.launch.py" ;;
    astra|astra_plus)            echo "astra.launch.py" ;;
    dabai_dcw2|dabai)            echo "dabai_dcw2.launch.py" ;;
    lidar)                       echo "lidar.launch.py" ;;
    *)                           echo "" ;;
  esac
}

# ---------- 通用小工具 ----------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1（$2）"
}

# 读取 Ubuntu 版本号，如 22.04
ubuntu_version() { awk -F'"' '/^VERSION_ID=/{print $2}' /etc/os-release 2>/dev/null; }

# ---------- ~/.bashrc 环境变量 ----------
ORBBEC_BASHRC_BEGIN="# >>> orbbec_camera (ws_orbbec installer) >>>"
ORBBEC_BASHRC_END="# <<< orbbec_camera (ws_orbbec installer) <<<"

# $1=ROS 发行版；$2=工作空间 setup.bash（本库仅服务仓库源码安装，两行都写）
orbbec_bashrc_text() {
  local distro="$1" ws_setup="${2:-}"
  echo "$ORBBEC_BASHRC_BEGIN"
  echo "source /opt/ros/${distro}/setup.bash"
  [[ -n "$ws_setup" ]] && echo "source ${ws_setup}"
  echo "$ORBBEC_BASHRC_END"
}

bashrc_has_block() { grep -qF "$ORBBEC_BASHRC_BEGIN" "$HOME/.bashrc" 2>/dev/null; }

# 幂等写入：已有同名块则整体替换，否则追加到末尾
orbbec_bashrc_write() {
  local distro="$1" ws_setup="${2:-}" rc="$HOME/.bashrc" block current tmp
  block="$(orbbec_bashrc_text "$distro" "$ws_setup")"
  if bashrc_has_block; then
    current="$(awk -v b="$ORBBEC_BASHRC_BEGIN" -v e="$ORBBEC_BASHRC_END" '
      $0==b {inside=1; print; next}
      $0==e {inside=0; print; next}
      inside {print}
    ' "$rc")"
    if [[ "$current" == "$block" ]]; then
      ok "~/.bashrc 已包含 Orbbec 环境，无需重复写入"
      return 0
    fi
  fi
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s[演练]%s 将写入 %s：\n' "$C_YELLOW" "$C_OFF" "$rc"
    printf '%s\n' "$block" | sed 's/^/     /'
    return 0
  fi
  touch "$rc"
  if bashrc_has_block; then
    tmp="$(mktemp)"
    awk -v b="$ORBBEC_BASHRC_BEGIN" -v e="$ORBBEC_BASHRC_END" '
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
