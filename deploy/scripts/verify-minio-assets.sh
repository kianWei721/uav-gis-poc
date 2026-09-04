#!/usr/bin/env bash
set -euo pipefail

# 在切换正式端口前，直接验证 MinIO Range 和现有 TiTiler 对 COG 的读取能力。
required=(
  MINIO_URL GIS_BUCKET PROJECT_ID ORTHO_DATASET_ID ORTHO_ARTIFACT_ID
  TILES_DATASET_ID TILES_ARTIFACT_ID TILES_SOURCE
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量：${name}" >&2
    exit 2
  fi
done

cog_url="${MINIO_URL%/}/${GIS_BUCKET}/${PROJECT_ID}/${ORTHO_DATASET_ID}/${ORTHO_ARTIFACT_ID}/ortho/result.cog.tif"
tiles_base="${MINIO_URL%/}/${GIS_BUCKET}/${PROJECT_ID}/${TILES_DATASET_ID}/${TILES_ARTIFACT_ID}/3dtiles"
tiles_source="${TILES_SOURCE}"
titiler_base_url="${TITILER_BASE_URL:-http://127.0.0.1:8000}"
titiler_python="${TITILER_PYTHON:-python3}"
info_file="$(mktemp)"
trap 'rm -f -- "${info_file}"' EXIT

first_b3dm="$(find "${tiles_source}" -type f -name '*.b3dm' -print -quit)"
if [[ -z "${first_b3dm}" ]]; then
  echo "本地 3D Tiles 中未找到 B3DM" >&2
  exit 2
fi
relative_b3dm="${first_b3dm#${tiles_source}/}"

curl --fail --silent --show-error --output /dev/null \
  --header 'Range: bytes=0-99' \
  --write-out 'cog_range_http=%{http_code} bytes=%{size_download} type=%{content_type}\n' \
  "${cog_url}"

curl --fail --silent --show-error --output /dev/null \
  --header 'Range: bytes=0-99' \
  --write-out 'b3dm_range_http=%{http_code} bytes=%{size_download} type=%{content_type}\n' \
  "${tiles_base}/${relative_b3dm}"

curl --fail --silent --show-error --get \
  --data-urlencode "url=${cog_url}" \
  --output "${info_file}" \
  "${titiler_base_url%/}/cog/info"

"${titiler_python}" - "${info_file}" <<'PY'
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as stream:
    info = json.load(stream)
print('titiler_cog_info=OK')
print('titiler_size=' + 'x'.join(str(value) for value in (info['width'], info['height'])))
print('titiler_crs=' + str(info.get('crs')))
PY
