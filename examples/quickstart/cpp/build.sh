#!/usr/bin/env bash
# 编译 C++ 示例：自动加载 ROS 2 与本工作空间环境
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=/dev/null
source /opt/ros/humble/setup.bash
if [[ -f "$WS_ROOT/install/setup.bash" ]]; then
  # shellcheck source=/dev/null
  source "$WS_ROOT/install/setup.bash"
fi

cmake -S "$SCRIPT_DIR" -B "$SCRIPT_DIR/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$SCRIPT_DIR/build" -j"$(nproc)"

echo "编译完成: $SCRIPT_DIR/build/subscribe_display"
