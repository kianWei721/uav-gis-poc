#!/usr/bin/env bash
set -euo pipefail

# 使用与正式运行相同的固定镜像执行 nginx -t，不占用宿主端口。

image="ghcr.io/nginx/nginx-unprivileged:1.30.4-alpine"
config="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../nginx" && pwd)/gis-publishing.conf}"

if [[ ! -f "${config}" ]]; then
  echo "缺少已渲染的 Nginx 配置：${config}" >&2
  exit 2
fi

docker pull "${image}"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --read-only \
  --tmpfs /tmp:size=64m,mode=1777 \
  --tmpfs /var/cache/nginx:size=16m,mode=1777 \
  --security-opt no-new-privileges:true \
  --volume "${config}:/etc/nginx/conf.d/default.conf:ro" \
  "${image}" nginx -t
