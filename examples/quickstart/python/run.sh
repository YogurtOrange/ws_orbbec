#!/usr/bin/env bash
# 一键运行快速上手示例：自动加载 ROS 2 与本工作空间环境
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=/dev/null
source /opt/ros/humble/setup.bash
if [[ -f "$WS_ROOT/install/setup.bash" ]]; then
  # shellcheck source=/dev/null
  source "$WS_ROOT/install/setup.bash"
fi

exec python3 "$SCRIPT_DIR/subscribe_display.py" "$@"
