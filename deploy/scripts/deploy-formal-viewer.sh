#!/usr/bin/env bash
set -euo pipefail

# 将正式动态 XYZ 验收页部署到发布服务器的只读 Nginx 挂载目录。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deploy_dir="$(cd "${script_dir}/.." && pwd)"
source_file="${1:-${deploy_dir}/viewer/viewer-full.html}"
target_file="${GIS_VIEWER_TARGET:?必须设置 GIS_VIEWER_TARGET}"
local_base_url="${GIS_LOCAL_BASE_URL:-http://127.0.0.1:18082}"

required=(ORTHO_LAYER_ID TILES_LAYER_ID TEST_TILE_Z TEST_TILE_X TEST_TILE_Y)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量：${name}" >&2
    exit 2
  fi
done
backup_dir="${deploy_dir}/backups/viewer-$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="${backup_dir}/viewer-full.html"
restore_needed=1

restore_on_error() {
  code=$?
  if [[ "${restore_needed}" -eq 1 && -f "${backup_file}" ]]; then
    cp -p "${backup_file}" "${target_file}"
    echo "验收页部署失败，已恢复旧页面：${backup_file}" >&2
  fi
  exit "${code}"
}
trap restore_on_error ERR

if [[ ! -f "${source_file}" ]]; then
  echo "缺少正式验收页：${source_file}" >&2
  exit 2
fi
if [[ ! -f "${target_file}" ]]; then
  echo "缺少待替换的现有验收页：${target_file}" >&2
  exit 3
fi

mkdir -p "${backup_dir}"
cp -p "${target_file}" "${backup_file}"
install -m 0644 "${source_file}" "${target_file}"

# 静态源码必须使用正式动态路由，并且不能退回单图预览方案。
grep -Fq 'Cesium.UrlTemplateImageryProvider' "${target_file}"
grep -Fq '/gis/raster/' "${target_file}"
grep -Fq '/gis/3d/' "${target_file}"
if grep -Fq 'SingleTileImageryProvider' "${target_file}"; then
  echo "验收页仍包含 SingleTileImageryProvider，拒绝发布" >&2
  exit 4
fi

curl --fail --silent --show-error --output /dev/null \
  "${local_base_url%/}/viewer-full.html"
curl --fail --silent --show-error --output /dev/null \
  "${local_base_url%/}/gis/raster/${ORTHO_LAYER_ID}/${TEST_TILE_Z}/${TEST_TILE_X}/${TEST_TILE_Y}.png"
curl --fail --silent --show-error --output /dev/null \
  "${local_base_url%/}/gis/3d/${TILES_LAYER_ID}/tileset.json"

restore_needed=0
trap - ERR
echo "formal_viewer_deploy=OK"
echo "backup_file=${backup_file}"
