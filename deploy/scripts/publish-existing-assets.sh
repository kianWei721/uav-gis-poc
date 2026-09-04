#!/usr/bin/env bash
set -euo pipefail

# 将已经验证成功的 COG 和 3D Tiles 发布到全新的 MinIO 对象前缀。
# 同尺寸对象会跳过，大小冲突则拒绝覆盖，便于中断后安全重试。

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${GIS_DEPLOY_ENV:-${script_dir}/../titiler/.env}"
if [[ -f "${env_file}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${env_file}"
  set +a
fi

required=(
  MINIO_S3_ENDPOINT MINIO_ACCESS_KEY MINIO_SECRET_KEY
  PROJECT_ID ORTHO_DATASET_ID ORTHO_ARTIFACT_ID
  TILES_DATASET_ID TILES_ARTIFACT_ID COG_SOURCE TILES_SOURCE
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量：${name}" >&2
    exit 2
  fi
done

deploy_dir="$(cd "${script_dir}/.." && pwd)"
python_bin="${deploy_dir}/.venv/bin/python"
python_script="${script_dir}/publish_existing_assets.py"
if [[ ! -x "${python_bin}" ]]; then
  echo "MinIO SDK 虚拟环境不存在：${python_bin}" >&2
  exit 3
fi

exec "${python_bin}" "${python_script}"
