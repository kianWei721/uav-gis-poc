#!/usr/bin/env bash
set -euo pipefail

# 发布参数由环境变量传入；MinIO 凭据仅从服务器本地 .env 读取。
deploy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${deploy_dir}/titiler/.env"
log_file="${deploy_dir}/publish.log"
status_file="${deploy_dir}/publish.status"

if [[ ! -f "${env_file}" ]]; then
  echo "MinIO 环境文件不存在：${env_file}" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "${env_file}"
set +a

required=(
  PROJECT_ID ORTHO_DATASET_ID ORTHO_ARTIFACT_ID
  TILES_DATASET_ID TILES_ARTIFACT_ID COG_SOURCE TILES_SOURCE
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量：${name}" >&2
    exit 3
  fi
done

rm -f "${status_file}"
set +e
"${deploy_dir}/scripts/publish-existing-assets.sh" >"${log_file}" 2>&1
code=$?
set -e
printf '%s\n' "${code}" >"${status_file}"
exit "${code}"
