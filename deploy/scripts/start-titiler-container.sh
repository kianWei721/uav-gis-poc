#!/usr/bin/env bash
set -euo pipefail

# 不依赖 Docker Compose，按固定镜像启动正式 TiTiler。

container_name="dongming-gis-titiler"
image="ghcr.io/developmentseed/titiler:2.2.1@sha256:bf753ccf0fe0f231bc51a0ddbaebf7c0c82253a26db8ab25d1c30ea417e704ff"
env_file="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../titiler" && pwd)/.env}"

if [[ ! -f "${env_file}" ]]; then
  echo "缺少 TiTiler 环境文件：${env_file}" >&2
  exit 2
fi

mode="$(stat -c '%a' "${env_file}")"
if (( 8#${mode} & 8#077 )); then
  echo "环境文件权限必须为 600 或更严格：${env_file}" >&2
  exit 3
fi

set -a
# shellcheck disable=SC1090
source "${env_file}"
set +a

for name in MINIO_ACCESS_KEY MINIO_SECRET_KEY MINIO_S3_ENDPOINT; do
  if [[ -z "${!name:-}" ]]; then
    echo "环境文件缺少变量：${name}" >&2
    exit 4
  fi
done

if docker container inspect "${container_name}" >/dev/null 2>&1; then
  echo "容器已存在，拒绝自动覆盖：${container_name}" >&2
  exit 5
fi

if ss -lnt | awk '{print $4}' | grep -qE '(^|:)18081$'; then
  echo "端口 18081 已被占用，拒绝启动 TiTiler" >&2
  exit 6
fi

docker pull "${image}"
docker run --detach \
  --name "${container_name}" \
  --restart unless-stopped \
  --read-only \
  --tmpfs /tmp:size=1g,mode=1777 \
  --security-opt no-new-privileges:true \
  --publish 127.0.0.1:18081:8000 \
  --env AWS_ACCESS_KEY_ID="${MINIO_ACCESS_KEY}" \
  --env AWS_SECRET_ACCESS_KEY="${MINIO_SECRET_KEY}" \
  --env AWS_REGION="${MINIO_REGION:-us-east-1}" \
  --env AWS_S3_ENDPOINT="${MINIO_S3_ENDPOINT}" \
  --env AWS_HTTPS=NO \
  --env AWS_VIRTUAL_HOSTING=FALSE \
  --env CPL_VSIL_CURL_ALLOWED_EXTENSIONS=.tif,.tiff \
  --env GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR \
  --env GDAL_HTTP_MULTIRANGE=YES \
  --env GDAL_HTTP_MERGE_CONSECUTIVE_RANGES=YES \
  --env GDAL_CACHEMAX=512 \
  --env VSI_CACHE=TRUE \
  --env VSI_CACHE_SIZE=50000000 \
  "${image}" \
  uvicorn titiler.application.main:app --host 0.0.0.0 --port 8000 --workers 2

for _ in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:18081/healthz >/dev/null; then
    echo "TiTiler 已启动：http://127.0.0.1:18081"
    exit 0
  fi
  sleep 2
done

docker logs --tail 100 "${container_name}" >&2 || true
echo "TiTiler 健康检查超时，保留容器供排查" >&2
exit 7
