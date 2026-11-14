#!/usr/bin/env bash
# 运行 C++ 示例：自动加载环境，参数原样透传（ROS 参数用 --ros-args -p 指定）
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN="$SCRIPT_DIR/build/subscribe_display"

if [[ ! -x "$BIN" ]]; then
  echo "未找到可执行文件，请先运行: $SCRIPT_DIR/build.sh" >&2
  exit 1
fi

# shellcheck source=/dev/null
source /opt/ros/humble/setup.bash
if [[ -f "$WS_ROOT/install/setup.bash" ]]; then
  # shellcheck source=/dev/null
  source "$WS_ROOT/install/setup.bash"
fi

exec "$BIN" "$@"
