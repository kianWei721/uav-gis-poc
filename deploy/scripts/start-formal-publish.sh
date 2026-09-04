#!/usr/bin/env bash
set -euo pipefail

# 在 tmux 中启动长耗时上传，SSH 断开后任务仍可继续。
deploy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
session_name="gis-publish-formal"

if tmux has-session -t "${session_name}" 2>/dev/null; then
  echo "上传会话已经存在：${session_name}" >&2
  exit 2
fi

tmux new-session -d -s "${session_name}" "${deploy_dir}/scripts/run-formal-publish.sh"
echo "上传会话已启动：${session_name}"
echo "进度日志：${deploy_dir}/publish.log"
echo "退出码文件：${deploy_dir}/publish.status"
