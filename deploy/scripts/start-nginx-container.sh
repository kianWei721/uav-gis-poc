#!/usr/bin/env bash
set -euo pipefail

# 仅在 18082 已释放且 nginx -t 已通过后启动正式发布入口。

container_name="dongming-gis-publisher"
image="ghcr.io/nginx/nginx-unprivileged:1.30.4-alpine"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="${1:-${script_dir}/../nginx/gis-publishing.conf}"
poc_root="${GIS_STATIC_ROOT:?必须设置 GIS_STATIC_ROOT}"
cache_root="${GIS_CACHE_ROOT:?必须设置 GIS_CACHE_ROOT}"

if docker container inspect "${container_name}" >/dev/null 2>&1; then
  echo "容器已存在，拒绝自动覆盖：${container_name}" >&2
  exit 2
fi

if ss -lnt | awk '{print $4}' | grep -qE '(^|:)18082$'; then
  echo "端口 18082 仍被占用；必须先完成 POC 进程备份与停机" >&2
  exit 3
fi

"${script_dir}/validate-nginx-container.sh" "${config}"
mkdir -p "${cache_root}"
chmod 0750 "${cache_root}"

docker run --detach \
  --name "${container_name}" \
  --restart unless-stopped \
  --network host \
  --user "$(id -u):$(id -g)" \
  --read-only \
  --tmpfs /tmp:size=64m,mode=1777 \
  --security-opt no-new-privileges:true \
  --volume "${config}:/etc/nginx/conf.d/default.conf:ro" \
  --volume "${poc_root}:/srv/gis-poc:ro" \
  --volume "${cache_root}:/var/cache/nginx" \
  "${image}"

for _ in $(seq 1 15); do
  if curl --fail --silent http://127.0.0.1:18082/healthz >/dev/null; then
    echo "GIS Nginx 已启动：http://127.0.0.1:18082"
    exit 0
  fi
  sleep 2
done

docker logs --tail 100 "${container_name}" >&2 || true
echo "GIS Nginx 健康检查超时，保留容器供排查" >&2
exit 4
