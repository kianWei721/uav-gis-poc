#!/usr/bin/env bash
set -euo pipefail

# 将两个 POC Python 端口原子切换为正式 TiTiler 与 Nginx。
deploy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
required=(
  COG_POC_ROOT TILES_POC_ROOT PROJECT_ID ORTHO_DATASET_ID ORTHO_ARTIFACT_ID
  ORTHO_LAYER_ID TILES_LAYER_ID TEST_TILE_Z TEST_TILE_X TEST_TILE_Y
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量：${name}" >&2
    exit 2
  fi
done
staging_config="${deploy_dir}/nginx/gis-publishing.conf.staging"
formal_config="${deploy_dir}/nginx/gis-publishing.conf"
backup_dir="${deploy_dir}/backups/$(date -u +%Y%m%dT%H%M%SZ)"
cog_poc_command="python3 -m http.server 18081 --bind 0.0.0.0 --directory ${COG_POC_ROOT}"
tiles_poc_command="python3 -m http.server 18082 --bind 0.0.0.0 --directory ${TILES_POC_ROOT}"
rollback_needed=1

restart_poc() {
  docker rm -f dongming-gis-publisher >/dev/null 2>&1 || true
  docker rm -f dongming-gis-titiler >/dev/null 2>&1 || true
  if ! ss -lnt | awk '{print $4}' | grep -qE '(^|:)18081$'; then
    nohup bash -lc "${cog_poc_command}" >"${deploy_dir}/poc-18081.log" 2>&1 &
  fi
  if ! ss -lnt | awk '{print $4}' | grep -qE '(^|:)18082$'; then
    nohup bash -lc "${tiles_poc_command}" >"${deploy_dir}/poc-18082.log" 2>&1 &
  fi
  sleep 2
}

rollback_on_error() {
  code=$?
  if [[ "${rollback_needed}" -eq 1 ]]; then
    echo "正式服务切换失败，正在恢复两个 POC 端口" >&2
    restart_poc
  fi
  exit "${code}"
}
trap rollback_on_error ERR

if [[ ! -f "${staging_config}" ]]; then
  echo "缺少已验证的正式 Nginx 配置：${staging_config}" >&2
  exit 2
fi
if docker container inspect dongming-gis-titiler >/dev/null 2>&1 ||
   docker container inspect dongming-gis-publisher >/dev/null 2>&1; then
  echo "正式容器已经存在，拒绝重复切换" >&2
  exit 3
fi

mkdir -p "${backup_dir}"
ps -eo pid,ppid,lstart,args >"${backup_dir}/processes-before.txt"
ss -lntp >"${backup_dir}/ports-before.txt"
if [[ -f "${formal_config}" ]]; then
  cp -p "${formal_config}" "${backup_dir}/gis-publishing.conf"
fi
install -m 0640 "${staging_config}" "${formal_config}"

cog_pid="$(pgrep -f "^${cog_poc_command}$" || true)"
tiles_pid="$(pgrep -f "^${tiles_poc_command}$" || true)"
if [[ -z "${cog_pid}" || -z "${tiles_pid}" ]]; then
  echo "未找到两个预期的 POC 进程，拒绝切换" >&2
  exit 4
fi

kill -TERM ${cog_pid}
for _ in $(seq 1 10); do
  if ! ss -lnt | awk '{print $4}' | grep -qE '(^|:)18081$'; then
    break
  fi
  sleep 1
done
if ss -lnt | awk '{print $4}' | grep -qE '(^|:)18081$'; then
  echo "POC 18081 未能正常停止" >&2
  exit 5
fi

"${deploy_dir}/scripts/start-titiler-container.sh"

cog_url="s3://gis-published/${PROJECT_ID}/${ORTHO_DATASET_ID}/${ORTHO_ARTIFACT_ID}/ortho/result.cog.tif"
curl --fail --silent --show-error --get \
  --data-urlencode "url=${cog_url}" \
  --output "${backup_dir}/titiler-info.json" \
  http://127.0.0.1:18081/cog/info
curl --fail --silent --show-error --output "${backup_dir}/sample-tile.png" \
  --get --data-urlencode "url=${cog_url}" \
  "http://127.0.0.1:18081/cog/tiles/WebMercatorQuad/${TEST_TILE_Z}/${TEST_TILE_X}/${TEST_TILE_Y}.png"
test "$(stat -c '%s' "${backup_dir}/sample-tile.png")" -gt 100

kill -TERM ${tiles_pid}
for _ in $(seq 1 10); do
  if ! ss -lnt | awk '{print $4}' | grep -qE '(^|:)18082$'; then
    break
  fi
  sleep 1
done
if ss -lnt | awk '{print $4}' | grep -qE '(^|:)18082$'; then
  echo "POC 18082 未能正常停止" >&2
  exit 6
fi

"${deploy_dir}/scripts/start-nginx-container.sh" "${formal_config}"

curl --fail --silent --show-error --output /dev/null \
  "http://127.0.0.1:18082/gis/raster/${ORTHO_LAYER_ID}/${TEST_TILE_Z}/${TEST_TILE_X}/${TEST_TILE_Y}.png"
curl --fail --silent --show-error --output /dev/null \
  "http://127.0.0.1:18082/gis/3d/${TILES_LAYER_ID}/tileset.json"

rollback_needed=0
trap - ERR
echo "formal_switch=OK"
echo "backup_dir=${backup_dir}"
docker ps --filter name=dongming-gis --format '{{.Names}}|{{.Status}}|{{.Image}}'
