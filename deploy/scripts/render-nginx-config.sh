#!/usr/bin/env bash
set -euo pipefail

# 使用已登记的数据库 ID 渲染 106 Nginx 正式配置，输出到 staging 文件供 nginx -t 检查。

required=(
  PROJECT_ID ORTHO_DATASET_ID ORTHO_ARTIFACT_ID ORTHO_LAYER_ID
  TILES_DATASET_ID TILES_ARTIFACT_ID TILES_LAYER_ID MINIO_S3_ENDPOINT
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量：${name}" >&2
    exit 2
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="${script_dir}/../nginx/gis-publishing.conf.template"
output="${1:-${script_dir}/../nginx/gis-publishing.conf.staging}"

envsubst '${PROJECT_ID} ${ORTHO_DATASET_ID} ${ORTHO_ARTIFACT_ID} ${ORTHO_LAYER_ID} ${TILES_DATASET_ID} ${TILES_ARTIFACT_ID} ${TILES_LAYER_ID} ${MINIO_S3_ENDPOINT}' \
  < "${template}" > "${output}"

echo "Nginx 配置已渲染：${output}"
echo "下一步必须先备份现有配置，再执行 nginx -t；检查通过后才允许 reload。"
