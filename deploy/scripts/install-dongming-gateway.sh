#!/usr/bin/env bash
set -euo pipefail

# 在东明 HTTPS server 块中安装正式 GIS 路由；必须以 root 执行。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nginx_config="${NGINX_CONFIG:-/etc/nginx/nginx.conf}"
locations_source="${1:-${script_dir}/../nginx/dongming-gateway-gis.conf}"
locations_target="${GIS_NGINX_LOCATIONS_TARGET:-/etc/nginx/dongming-gis-formal.locations}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_config="${nginx_config}.bak_gis_formal_${timestamp}"
backup_locations="${locations_target}.bak_${timestamp}"
candidate="$(mktemp /etc/nginx/nginx.conf.gis-staging.XXXXXX)"
changed=0
locations_existed=0

required=(
  PUBLIC_GIS_HOST PUBLIC_GIS_PORT ORTHO_LAYER_ID TILES_LAYER_ID
  TEST_TILE_Z TEST_TILE_X TEST_TILE_Y TILES_SMOKE_PATH
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量：${name}" >&2
    exit 2
  fi
done
public_base="https://${PUBLIC_GIS_HOST}:${PUBLIC_GIS_PORT}"

rollback_on_error() {
  code=$?
  rm -f "${candidate}"
  if [[ "${changed}" -eq 1 ]]; then
    cp -p "${backup_config}" "${nginx_config}"
    if [[ "${locations_existed}" -eq 1 ]]; then
      cp -p "${backup_locations}" "${locations_target}"
    else
      rm -f "${locations_target}"
    fi
    nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1 || true
    echo "东明 Nginx 安装失败，已恢复原配置：${backup_config}" >&2
  fi
  exit "${code}"
}
trap rollback_on_error ERR

wait_https() {
  for _ in $(seq 1 15); do
    if curl --fail --silent --show-error --output /dev/null "$@"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "必须以 root 执行" >&2
  exit 2
fi
if [[ ! -f "${nginx_config}" || ! -f "${locations_source}" ]]; then
  echo "缺少 Nginx 主配置或 GIS location 文件" >&2
  exit 3
fi
if grep -q 'dongming-gis-formal.locations\|location /gis/raster/\|location /gis/3d/' "${nginx_config}"; then
  echo "正式 GIS 路由已经存在，拒绝重复写入" >&2
  exit 4
fi
if ! grep -qE '^[[:space:]]*location /gis-demo/ \{' "${nginx_config}"; then
  echo "未找到已验证的 /gis-demo/ 锚点，拒绝修改" >&2
  exit 5
fi

cp -p "${nginx_config}" "${backup_config}"
if [[ -f "${locations_target}" ]]; then
  locations_existed=1
  cp -p "${locations_target}" "${backup_locations}"
fi
install -o root -g root -m 0644 "${locations_source}" "${locations_target}"

awk '
  /^[[:space:]]*location \/gis-demo\/ \{/ && !inserted {
    print "        include /etc/nginx/dongming-gis-formal.locations;"
    print ""
    inserted=1
  }
  { print }
  END { if (!inserted) exit 20 }
' "${nginx_config}" >"${candidate}"

nginx -t -c "${candidate}"
install -o root -g root -m 0644 "${candidate}" "${nginx_config}"
changed=1
nginx -t
nginx -s reload

wait_https \
  --resolve "${PUBLIC_GIS_HOST}:${PUBLIC_GIS_PORT}:127.0.0.1" \
  "${public_base}/gis/raster/${ORTHO_LAYER_ID}/${TEST_TILE_Z}/${TEST_TILE_X}/${TEST_TILE_Y}.png"
wait_https \
  --resolve "${PUBLIC_GIS_HOST}:${PUBLIC_GIS_PORT}:127.0.0.1" \
  "${public_base}/gis/3d/${TILES_LAYER_ID}/tileset.json"
wait_https \
  --header 'Range: bytes=0-99' \
  --resolve "${PUBLIC_GIS_HOST}:${PUBLIC_GIS_PORT}:127.0.0.1" \
  "${public_base}/gis/3d/${TILES_LAYER_ID}/${TILES_SMOKE_PATH#/}"

changed=0
trap - ERR
rm -f "${candidate}"
echo "dongming_gateway=OK"
echo "nginx_backup=${backup_config}"
